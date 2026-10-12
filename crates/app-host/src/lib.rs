use card_weave_core::{
    AddressBook, Calendar, Cancellation, ContactData, Error, Resolution, calendar_date,
    calendar_options,
};
use lfs_sqlite::NetworkError;
use lfs_storage::{OpenDalTransport, Options, S3Credentials, WebdavCredentials};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    path::Path,
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum Command {
    CalendarDate {
        calendar: Calendar,
        year: u16,
        month: u8,
        day: u8,
    },
    CalendarOptions {
        calendar: Calendar,
        year: Option<u16>,
    },
    Identity,
    List {
        search: String,
        offset: u32,
    },
    Get {
        id: String,
    },
    Create {
        contact: ContactData,
    },
    Save {
        id: String,
        expected: ContactData,
        contact: Box<ContactData>,
    },
    Delete {
        id: String,
        expected: ContactData,
    },
    Status,
    Conflicts,
    Resolve {
        id: String,
        resolution: Resolution,
    },
    Close,
}
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum SyncConfig {
    Webdav {
        endpoint: String,
        username: String,
        password: String,
    },
    S3 {
        endpoint: String,
        region: String,
        bucket: String,
        access_key: String,
        secret_key: String,
        session_token: Option<String>,
    },
}
impl SyncConfig {
    fn connect(self) -> Result<OpenDalTransport, Error> {
        let options = Options::default();
        let result = match self {
            Self::Webdav {
                endpoint,
                username,
                password,
            } => OpenDalTransport::webdav(
                &endpoint,
                WebdavCredentials::Basic { username, password },
                options,
            ),
            Self::S3 {
                endpoint,
                region,
                bucket,
                access_key,
                secret_key,
                session_token,
            } => OpenDalTransport::s3(
                &endpoint,
                &region,
                &bucket,
                S3Credentials {
                    access_key_id: access_key,
                    secret_access_key: secret_key,
                    session_token,
                },
                options,
            ),
        };
        result.map_err(|e| Error::Sdk(lfs_sqlite::Error::Network(e)))
    }
}
fn encode<T: serde::Serialize>(value: T) -> Result<Value, Error> {
    Ok(serde_json::to_value(value)?)
}
fn reply(result: Result<Value, Error>) -> String {
    match result {
        Ok(data) => json!({"ok":true,"data":data}),
        Err(error) => {
            let code = match &error {
                Error::Sdk(lfs_sqlite::Error::Network(NetworkError::Auth)) => "authentication",
                Error::Sdk(lfs_sqlite::Error::Network(NetworkError::Cancelled)) => "cancelled",
                Error::Sdk(lfs_sqlite::Error::Network(NetworkError::Unsupported)) => "unsupported",
                Error::Sdk(lfs_sqlite::Error::Network(NetworkError::Corrupt)) => "remote_corrupt",
                Error::Sdk(lfs_sqlite::Error::Network(NetworkError::RateLimit)) => "rate_limit",
                _ => error.code(),
            };
            json!({"ok":false,"error":{"code":code}})
        }
    }
    .to_string()
}

pub struct Host {
    book: Mutex<Option<AddressBook>>,
    cancellation: Mutex<Option<Cancellation>>,
    syncing: AtomicBool,
    runtime: tokio::runtime::Runtime,
}
impl Host {
    pub fn new() -> Self {
        Self {
            book: Mutex::new(None),
            cancellation: Mutex::new(None),
            syncing: AtomicBool::new(false),
            runtime: tokio::runtime::Runtime::new().expect("async runtime"),
        }
    }
    pub fn initialize(&self, path: String, create: bool, dataset: Option<String>) -> String {
        reply((|| {
            let mut state = self
                .book
                .lock()
                .map_err(|_| Error::Invalid("host unavailable"))?;
            if state.is_some() {
                return Err(Error::Invalid("already open"));
            }
            let book = if create {
                AddressBook::init(Path::new(&path), dataset)?
            } else {
                AddressBook::open(Path::new(&path))?
            };
            let identity = encode(book.config())?;
            *state = Some(book);
            Ok(identity)
        })())
    }
    pub fn cancel(&self) {
        if let Ok(active) = self.cancellation.lock()
            && let Some(token) = active.as_ref()
        {
            token.cancel();
        }
    }
    pub fn execute(&self, request: String) -> String {
        reply((|| {
            if request.len() > 300_000 {
                return Err(Error::Invalid("request too large"));
            }
            let command: Command = serde_json::from_str(&request)?;
            if let Command::CalendarDate {
                ref calendar,
                year,
                month,
                day,
            } = command
            {
                return encode(calendar_date(calendar, year, month, day)?);
            }
            if let Command::CalendarOptions { ref calendar, year } = command {
                return encode(calendar_options(calendar, year)?);
            }
            if matches!(
                command,
                Command::Create { .. }
                    | Command::Save { .. }
                    | Command::Delete { .. }
                    | Command::Resolve { .. }
                    | Command::Close
            ) {
                self.cancel();
            }
            let mut state = self
                .book
                .lock()
                .map_err(|_| Error::Invalid("host unavailable"))?;
            let book = state.as_mut().ok_or(Error::Invalid("not open"))?;
            match command {
                Command::CalendarOptions { .. } | Command::CalendarDate { .. } => unreachable!(),
                Command::Identity => encode(book.config()),
                Command::List { search, offset } => encode(book.list(&search, 50, offset)?),
                Command::Get { id } => encode(book.get(&id)?),
                Command::Create { contact } => encode(book.create(contact)?),
                Command::Save {
                    id,
                    expected,
                    contact,
                } => encode(book.save_guarded(&id, &expected, Some(*contact))?),
                Command::Delete { id, expected } => {
                    encode(book.save_guarded(&id, &expected, None)?)
                }
                Command::Status => encode(book.status()?),
                Command::Conflicts => encode(book.conflicts()?),
                Command::Resolve { id, resolution } => {
                    book.resolve(&id, resolution)?;
                    encode(book.conflicts()?)
                }
                Command::Close => {
                    book.close()?;
                    *state = None;
                    Ok(Value::Null)
                }
            }
        })())
    }
    pub fn begin_sync(&self) -> bool {
        let Ok(mut active) = self.cancellation.lock() else {
            return false;
        };
        if self.syncing.swap(true, Ordering::AcqRel) {
            return false;
        }
        *active = Some(Cancellation::default());
        true
    }
    pub fn synchronize(&self, configuration: String) -> String {
        let result = (|| {
            let token = self
                .cancellation
                .lock()
                .map_err(|_| Error::Invalid("host unavailable"))?
                .clone()
                .ok_or(Error::Invalid("sync not started"))?;
            if configuration.len() > 65536 {
                return Err(Error::Invalid("config too large"));
            }
            let config: SyncConfig = serde_json::from_str(&configuration)?;
            let transport = config.connect()?;
            let mut state = self
                .book
                .lock()
                .map_err(|_| Error::Invalid("host unavailable"))?;
            let book = state.as_mut().ok_or(Error::Invalid("not open"))?;
            encode(self.runtime.block_on(book.sync(&transport, &token))?)
        })();
        if let Ok(mut token) = self.cancellation.lock() {
            *token = None;
        }
        self.syncing.store(false, Ordering::Release);
        reply(result)
    }
}
impl Default for Host {
    fn default() -> Self {
        Self::new()
    }
}
impl Drop for Host {
    fn drop(&mut self) {
        self.cancel();
        if let Ok(Some(book)) = self.book.get_mut() {
            let _ = book.close();
        }
    }
}
