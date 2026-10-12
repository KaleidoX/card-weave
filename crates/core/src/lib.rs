pub mod backend;
mod calendar;
pub use calendar::{CalendarMonth, CalendarOptions, calendar_options};
mod model;
use lfs_protocol::OpId;
use lfs_sqlite::{Baseline, Column, ColumnType, Identity, Schema, Sdk, Table, Value};
pub use lfs_sqlite::{Cancellation, SyncLimits, Transport};
pub use model::{
    Calendar, Contact, ContactData, ContactDate, DateKind, LabeledValue, MAX_DOCUMENT_BYTES,
};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{Read, Write},
    path::Path,
};

pub type Result<T> = std::result::Result<T, Error>;
#[derive(Debug)]
pub enum Error {
    Invalid(&'static str),
    NotFound,
    EditStale,
    Conflict,
    Io(std::io::Error),
    Json(serde_json::Error),
    Sdk(lfs_sqlite::Error),
}
impl Error {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Invalid(_) | Self::Json(_) => "invalid_input",
            Self::NotFound => "not_found",
            Self::EditStale => "edit_stale",
            Self::Conflict => "conflict_requires_resolution",
            Self::Io(_) => "io_error",
            Self::Sdk(e) => match e {
                lfs_sqlite::Error::ConflictRequiresResolution { .. } => {
                    "conflict_requires_resolution"
                }
                lfs_sqlite::Error::DatabaseInUse => "database_in_use",
                lfs_sqlite::Error::IdentityMismatch => "identity_mismatch",
                lfs_sqlite::Error::Busy | lfs_sqlite::Error::SyncInProgress => "busy",
                lfs_sqlite::Error::Network(_) => "network_error",
                _ => "sdk_error",
            },
        }
    }
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Invalid(message) => write!(f, "{message}"),
            _ => write!(f, "{}", self.code()),
        }
    }
}
impl std::error::Error for Error {}
impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}
impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Self::Json(e)
    }
}
impl From<lfs_sqlite::Error> for Error {
    fn from(e: lfs_sqlite::Error) -> Self {
        Self::Sdk(e)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub version: u32,
    pub dataset: String,
    pub device: String,
    pub incarnation: String,
}
impl Config {
    fn identity(&self) -> Identity {
        Identity {
            dataset: self.dataset.clone(),
            device: self.device.clone(),
            incarnation: self.incarnation.clone(),
        }
    }
}
fn random_id() -> Result<String> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| Error::Invalid("OS randomness unavailable"))?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
fn schema() -> Schema {
    Schema {
        version: 1,
        tables: vec![Table {
            id: 1,
            name: "contacts".into(),
            columns: ["id", "display_name", "document"]
                .map(|name| Column {
                    name: name.into(),
                    kind: ColumnType::Text,
                    nullable: false,
                })
                .to_vec(),
        }],
    }
}
pub fn read_bounded(path: &Path, limit: usize) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    fs::File::open(path)?
        .take(limit as u64 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > limit {
        return Err(Error::Invalid("input file exceeds size limit"));
    }
    Ok(bytes)
}
fn row(id: &str, data: &ContactData) -> Result<Vec<Value>> {
    data.validate()?;
    Ok(vec![
        Value::Text(id.into()),
        Value::Text(data.display_name.clone()),
        Value::Text(serde_json::to_string(data)?),
    ])
}
fn decode(row: &[Value], has_conflict: bool) -> Result<Contact> {
    let [Value::Text(id), Value::Text(name), Value::Text(document)] = row else {
        return Err(Error::Invalid("invalid stored contact row"));
    };
    let data = ContactData::from_json(document.as_bytes())?;
    if &data.display_name != name {
        return Err(Error::Invalid("inconsistent stored contact name"));
    }
    Ok(Contact {
        id: id.clone(),
        data,
        has_conflict,
    })
}
fn valid_key(id: &str) -> Result<()> {
    if id.len() != 32
        || !id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(Error::Invalid(
            "contact ID must be 32 lowercase hex characters",
        ));
    }
    Ok(())
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VersionId {
    pub dataset: String,
    pub device: String,
    pub incarnation: String,
    pub seq: String,
    pub index: u32,
    pub schema: u32,
}
impl From<OpId> for VersionId {
    fn from(v: OpId) -> Self {
        Self {
            dataset: v.dataset,
            device: v.device,
            incarnation: v.incarnation,
            seq: v.seq.to_string(),
            index: v.index,
            schema: v.schema,
        }
    }
}
impl VersionId {
    fn operation(&self) -> Result<OpId> {
        let seq: u64 = self
            .seq
            .parse()
            .map_err(|_| Error::Invalid("invalid version sequence"))?;
        if seq.to_string() != self.seq {
            return Err(Error::Invalid("noncanonical version sequence"));
        }
        Ok(OpId {
            dataset: self.dataset.clone(),
            device: self.device.clone(),
            incarnation: self.incarnation.clone(),
            seq,
            index: self.index,
            schema: self.schema,
        })
    }
}
#[derive(Debug, Serialize)]
pub struct Candidate {
    pub version: VersionId,
    pub contact: Option<Contact>,
}
#[derive(Debug, Serialize)]
pub struct ContactConflict {
    pub id: String,
    pub candidates: Vec<Candidate>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Resolution {
    pub observed: Vec<VersionId>,
    #[serde(deserialize_with = "Option::deserialize")]
    pub contact: Option<ContactData>,
}
#[derive(Debug, Serialize)]
pub struct SyncStatus {
    pub protocol_healthy: bool,
    pub settled: bool,
    pub pending_outbox: usize,
    pub conflict_count: usize,
    pub stopped_streams: usize,
    pub discovery_incomplete: bool,
    pub outstanding_objects: usize,
    pub inbox_states: std::collections::BTreeMap<String, usize>,
    pub last_sync_failed: bool,
}
#[derive(Debug, Serialize)]
pub struct SyncOutcome {
    pub uploaded: usize,
    pub downloaded: usize,
    pub complete_scan: bool,
    pub status: SyncStatus,
}

pub struct AddressBook {
    sdk: Sdk,
    config: Config,
}
impl AddressBook {
    /// Creates a new owned directory. Existing directories are never overwritten.
    pub fn init(home: &Path, dataset: Option<String>) -> Result<Self> {
        let config = Config {
            version: 1,
            dataset: dataset.unwrap_or(random_id()?),
            device: random_id()?,
            incarnation: random_id()?,
        };
        config.identity().validate().map_err(Error::Invalid)?;
        fs::create_dir(home)?;
        let result = (|| {
            let sdk = Sdk::open(
                home.join("contacts.sqlite"),
                config.identity(),
                schema(),
                Baseline::Reject,
            )?;
            let mut file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(home.join("identity.json"))?;
            file.write_all(&serde_json::to_vec_pretty(&config)?)?;
            file.sync_all()?;
            Ok(Self { sdk, config })
        })();
        if result.is_err() {
            let _ = fs::remove_dir_all(home);
        }
        result
    }
    pub fn open(home: &Path) -> Result<Self> {
        let config: Config =
            serde_json::from_slice(&read_bounded(&home.join("identity.json"), 4096)?)?;
        if config.version != 1 || !home.join("contacts.sqlite").is_file() {
            return Err(Error::Invalid(
                "incomplete address book or unsupported config",
            ));
        }
        config.identity().validate().map_err(Error::Invalid)?;
        let sdk = Sdk::open(
            home.join("contacts.sqlite"),
            config.identity(),
            schema(),
            Baseline::Reject,
        )?;
        Ok(Self { sdk, config })
    }
    pub fn config(&self) -> &Config {
        &self.config
    }
    pub fn create(&mut self, data: ContactData) -> Result<Contact> {
        let id = random_id()?;
        let values = row(&id, &data)?;
        self.sdk
            .write_transaction(|w| w.execute("INSERT INTO contacts VALUES (?1,?2,?3)", &values))?;
        Ok(Contact {
            id,
            data,
            has_conflict: false,
        })
    }
    pub fn get(&mut self, id: &str) -> Result<Option<Contact>> {
        valid_key(id)?;
        let conflict = self.sdk.list_conflicts()?.iter().any(|c| c.key == id);
        let rows = self.sdk.read(|r| {
            r.query(
                "SELECT id,display_name,document FROM contacts WHERE id=?1",
                &[Value::Text(id.into())],
            )
        })?;
        rows.first().map(|r| decode(r, conflict)).transpose()
    }
    pub fn list(&mut self, search: &str, limit: u32, offset: u32) -> Result<Vec<Contact>> {
        if search.len() > 1024 || limit == 0 || limit > 500 {
            return Err(Error::Invalid("search/limit bounds (1..500)"));
        }
        let conflicts = self.sdk.list_conflicts()?;
        let needle = search.to_lowercase();
        let mut matches = Vec::new();
        let mut skipped = 0;
        for page in 0..1563 {
            let rows = self.sdk.read(|r| r.query("SELECT id,display_name,document FROM contacts ORDER BY display_name,id LIMIT 64 OFFSET ?1", &[Value::Integer(page * 64)]))?;
            if rows.is_empty() {
                return Ok(matches);
            }
            for values in rows {
                let mut contact = decode(&values, false)?;
                let data = &contact.data;
                let found = [
                    &data.display_name,
                    &data.given_name,
                    &data.family_name,
                    &data.organization,
                    &data.notes,
                ]
                .iter()
                .any(|s| s.to_lowercase().contains(&needle))
                    || data
                        .phones
                        .iter()
                        .chain(&data.emails)
                        .any(|v| v.value.to_lowercase().contains(&needle));
                if !found {
                    continue;
                }
                if skipped < offset {
                    skipped += 1;
                    continue;
                }
                contact.has_conflict = conflicts.iter().any(|c| c.key == contact.id);
                matches.push(contact);
                if matches.len() == limit as usize {
                    return Ok(matches);
                }
            }
        }
        Err(Error::Invalid("search scan exceeds 100032 contacts"))
    }

    fn writable(&mut self, id: &str) -> Result<()> {
        valid_key(id)?;
        if self.sdk.list_conflicts()?.iter().any(|c| c.key == id) {
            return Err(Error::Conflict);
        }
        if self.get(id)?.is_none() {
            return Err(Error::NotFound);
        }
        Ok(())
    }
    pub fn update(&mut self, id: &str, data: ContactData) -> Result<Contact> {
        self.writable(id)?;
        let values = row(id, &data)?;
        self.sdk.write_transaction(|w| {
            w.execute(
                "UPDATE contacts SET display_name=?2,document=?3 WHERE id=?1",
                &values,
            )
        })?;
        self.get(id)?.ok_or(Error::NotFound)
    }
    pub fn delete(&mut self, id: &str) -> Result<()> {
        self.writable(id)?;
        self.sdk.write_transaction(|w| {
            w.execute(
                "DELETE FROM contacts WHERE id=?1",
                &[Value::Text(id.into())],
            )
        })?;
        Ok(())
    }
    /// Atomically compares the observed full document before replacing or deleting it.
    pub fn save_guarded(
        &mut self,
        id: &str,
        expected: &ContactData,
        replacement: Option<ContactData>,
    ) -> Result<Option<Contact>> {
        self.writable(id).map_err(|error| match error {
            Error::NotFound => Error::EditStale,
            other => other,
        })?;
        expected.validate()?;
        let expected = serde_json::to_string(expected)?;
        let values = replacement.as_ref().map(|data| row(id, data)).transpose()?;
        let (changed, _) = self.sdk.write_transaction(|w| {
            let current = w.query(
                "SELECT document FROM contacts WHERE id=?1",
                &[Value::Text(id.into())],
            )?;
            if current.first().and_then(|r| r.first()) != Some(&Value::Text(expected.clone())) {
                return Ok(false);
            }
            match &values {
                Some(values) => {
                    w.execute(
                        "UPDATE contacts SET display_name=?2,document=?3 WHERE id=?1",
                        values,
                    )?;
                }
                None => {
                    w.execute(
                        "DELETE FROM contacts WHERE id=?1",
                        &[Value::Text(id.into())],
                    )?;
                }
            }
            Ok(true)
        })?;
        if !changed {
            return Err(Error::EditStale);
        }
        self.get(id)
    }

    pub fn conflicts(&mut self) -> Result<Vec<ContactConflict>> {
        self.sdk
            .list_conflicts()?
            .into_iter()
            .map(|conflict| {
                let candidates = conflict
                    .heads
                    .into_iter()
                    .map(|h| {
                        Ok(Candidate {
                            version: h.id.into(),
                            contact: h.row.as_ref().map(|r| decode(r, true)).transpose()?,
                        })
                    })
                    .collect::<Result<Vec<_>>>()?;
                Ok(ContactConflict {
                    id: conflict.key,
                    candidates,
                })
            })
            .collect()
    }
    pub fn resolve(&mut self, id: &str, resolution: Resolution) -> Result<()> {
        valid_key(id)?;
        if resolution.observed.is_empty() || resolution.observed.len() > 1000 {
            return Err(Error::Invalid("observed versions required (max 1000)"));
        }
        let parents = resolution
            .observed
            .iter()
            .map(VersionId::operation)
            .collect::<Result<Vec<_>>>()?;
        let row = resolution
            .contact
            .as_ref()
            .map(|data| row(id, data))
            .transpose()?;
        self.sdk.resolve(1, id, parents, row)?;
        Ok(())
    }
    pub fn status(&mut self) -> Result<SyncStatus> {
        let s = self.sdk.status()?;
        let conflict_count = self.sdk.list_conflicts()?.len();
        let mut inbox_states = std::collections::BTreeMap::new();
        for item in &s.inbox {
            *inbox_states.entry(format!("{:?}", item.state)).or_insert(0) += 1;
        }
        Ok(SyncStatus {
            protocol_healthy: s.healthy(),
            settled: s.healthy() && s.pending_outbox == 0 && conflict_count == 0,
            pending_outbox: s.pending_outbox,
            conflict_count,
            stopped_streams: s.stopped_streams,
            discovery_incomplete: s.discovery_incomplete,
            outstanding_objects: s.outstanding_objects,
            inbox_states,
            last_sync_failed: s.last_sync_error.is_some(),
        })
    }
    pub async fn sync(
        &mut self,
        transport: &impl Transport,
        cancellation: &Cancellation,
    ) -> Result<SyncOutcome> {
        let report = self
            .sdk
            .sync_once(transport, cancellation, SyncLimits::default())
            .await?;
        let mut status = self.status()?;
        status.settled &= report.complete_scan;
        Ok(SyncOutcome {
            uploaded: report.uploaded,
            downloaded: report.downloaded,
            complete_scan: report.complete_scan,
            status,
        })
    }
    pub fn close(&mut self) -> Result<()> {
        self.sdk.close()?;
        Ok(())
    }
}
