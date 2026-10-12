use crate::{Error, Result};
use lfs_storage::{OpenDalTransport, Options, S3Credentials, WebdavCredentials};
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, time::Duration};

/// Persist only environment variable names, never credential values.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Backend {
    Fs {
        root: PathBuf,
    },
    Webdav {
        endpoint: String,
        #[serde(default)]
        directory: String,
        username_env: Option<String>,
        password_env: Option<String>,
        bearer_env: Option<String>,
        #[serde(default)]
        allow_loopback_http: bool,
    },
    S3 {
        endpoint: String,
        region: String,
        bucket: String,
        access_key_env: String,
        secret_key_env: String,
        session_token_env: Option<String>,
        #[serde(default)]
        allow_loopback_http: bool,
    },
}
fn secret(name: &str) -> Result<String> {
    if name.is_empty()
        || name.len() > 128
        || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
    {
        return Err(Error::Invalid(
            "invalid credential environment variable name",
        ));
    }
    std::env::var(name)
        .ok()
        .filter(|s| !s.is_empty() && s.len() <= 16384)
        .ok_or(Error::Invalid(
            "credential environment variable missing or invalid",
        ))
}
impl Backend {
    pub fn connect(&self) -> Result<OpenDalTransport> {
        let options = |allow_loopback_http| Options {
            timeout: Duration::from_secs(15),
            allow_loopback_http,
        };
        let result = match self {
            Self::Fs { root } => OpenDalTransport::fs(root, Options::default()),
            Self::Webdav {
                endpoint,
                directory,
                username_env,
                password_env,
                bearer_env,
                allow_loopback_http,
            } => {
                let credentials = match (username_env, password_env, bearer_env) {
                    (Some(user), Some(pass), None) => WebdavCredentials::Basic {
                        username: secret(user)?,
                        password: secret(pass)?,
                    },
                    (None, None, Some(token)) => WebdavCredentials::Bearer(secret(token)?),
                    _ => {
                        return Err(Error::Invalid(
                            "choose Basic or Bearer environment credentials",
                        ));
                    }
                };
                OpenDalTransport::webdav_with_directory(
                    endpoint,
                    directory,
                    credentials,
                    options(*allow_loopback_http),
                )
            }
            Self::S3 {
                endpoint,
                region,
                bucket,
                access_key_env,
                secret_key_env,
                session_token_env,
                allow_loopback_http,
            } => OpenDalTransport::s3(
                endpoint,
                region,
                bucket,
                S3Credentials {
                    access_key_id: secret(access_key_env)?,
                    secret_access_key: secret(secret_key_env)?,
                    session_token: session_token_env
                        .as_ref()
                        .map(|name| secret(name))
                        .transpose()?,
                },
                options(*allow_loopback_http),
            ),
        };
        result.map_err(|e| Error::Sdk(lfs_sqlite::Error::Network(e)))
    }
}
