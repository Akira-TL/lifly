use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use opaque_ke::{
    ClientLogin, ClientLoginFinishParameters, ClientRegistration,
    ClientRegistrationFinishParameters, CredentialFinalization, CredentialRequest,
    CredentialResponse, RegistrationRequest, RegistrationResponse, RegistrationUpload,
    ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup,
};
use opaque_ke::{CipherSuite, Ristretto255, TripleDh};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256, Sha512};

pub const PROTOCOL: &str = "opaque-rfc9807";
pub const PROTOCOL_VERSION: u64 = 1;

struct LiflyCipherSuite;

impl CipherSuite for LiflyCipherSuite {
    type OprfCs = Ristretto255;
    type KeyExchange = TripleDh<Ristretto255, Sha512>;
    type Ksf = argon2::Argon2<'static>;
}

#[derive(Debug, Deserialize)]
pub struct HelperRequest {
    pub protocol: String,
    pub protocol_version: u64,
    pub operation: String,
    #[serde(default)]
    pub identifier: Option<String>,
    #[serde(default)]
    pub password: Option<String>,
    #[serde(default)]
    pub client_request: Option<String>,
    #[serde(default)]
    pub client_state: Option<String>,
    #[serde(default)]
    pub server_response: Option<String>,
    #[serde(default)]
    pub server_state: Option<String>,
    #[serde(default)]
    pub client_upload: Option<String>,
    #[serde(default)]
    pub credential_record: Option<String>,
    #[serde(default)]
    pub client_finish: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct RegistrationServerState {
    kind: String,
    identifier_hash: String,
}

pub fn handle_json(input: &str, server_setup_path: &Path) -> Result<Value> {
    let request: HelperRequest = serde_json::from_str(input).context("invalid helper request JSON")?;
    handle_request(request, server_setup_path)
}

pub fn handle_request(request: HelperRequest, server_setup_path: &Path) -> Result<Value> {
    validate_protocol(&request)?;
    match request.operation.as_str() {
        "client_registration_start" => client_registration_start(&request),
        "client_registration_finish" => client_registration_finish(&request),
        "client_login_start" => client_login_start(&request),
        "client_login_finish" => client_login_finish(&request),
        "registration_start" => server_registration_start(&request, server_setup_path),
        "registration_finish" => server_registration_finish(&request),
        "login_start" => server_login_start(&request, server_setup_path),
        "login_finish" => server_login_finish(&request),
        other => bail!("unsupported OPAQUE operation: {other}"),
    }
}

pub fn default_server_setup_path() -> Result<PathBuf> {
    if let Ok(value) = std::env::var("LIFLY_OPAQUE_SERVER_SETUP_PATH") {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            return Ok(PathBuf::from(trimmed));
        }
    }
    if let Ok(value) = std::env::var("XDG_STATE_HOME") {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            return Ok(PathBuf::from(trimmed).join("lifly/opaque-server-setup.bin"));
        }
    }
    let home = std::env::var("HOME").context("HOME is required for OPAQUE server setup storage")?;
    Ok(PathBuf::from(home).join(".local/state/lifly/opaque-server-setup.bin"))
}

fn validate_protocol(request: &HelperRequest) -> Result<()> {
    if request.protocol != PROTOCOL || request.protocol_version != PROTOCOL_VERSION {
        bail!("unsupported OPAQUE protocol/version")
    }
    Ok(())
}

fn client_registration_start(request: &HelperRequest) -> Result<Value> {
    let password = required(&request.password, "password")?;
    let started = ClientRegistration::<LiflyCipherSuite>::start(&mut OsRng, password.as_bytes())
        .context("OPAQUE client registration start failed")?;
    Ok(json!({
        "client_request": encode(started.message.serialize().as_slice()),
        "client_state": encode(started.state.serialize().as_slice()),
    }))
}

fn client_registration_finish(request: &HelperRequest) -> Result<Value> {
    let password = required(&request.password, "password")?;
    let state = ClientRegistration::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.client_state,
        "client_state",
    )?)?)
    .context("invalid OPAQUE client registration state")?;
    let response = RegistrationResponse::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.server_response,
        "server_response",
    )?)?)
    .context("invalid OPAQUE registration response")?;
    let finished = state
        .finish(
            &mut OsRng,
            password.as_bytes(),
            response,
            ClientRegistrationFinishParameters::default(),
        )
        .context("OPAQUE client registration finish failed")?;
    Ok(json!({
        "client_message": encode(finished.message.serialize().as_slice()),
        "export_key": encode(finished.export_key.as_slice()),
    }))
}

fn client_login_start(request: &HelperRequest) -> Result<Value> {
    let password = required(&request.password, "password")?;
    let started = ClientLogin::<LiflyCipherSuite>::start(&mut OsRng, password.as_bytes())
        .context("OPAQUE client login start failed")?;
    Ok(json!({
        "client_request": encode(started.message.serialize().as_slice()),
        "client_state": encode(started.state.serialize().as_slice()),
    }))
}

fn client_login_finish(request: &HelperRequest) -> Result<Value> {
    let password = required(&request.password, "password")?;
    let state = ClientLogin::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.client_state,
        "client_state",
    )?)?)
    .context("invalid OPAQUE client login state")?;
    let response = CredentialResponse::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.server_response,
        "server_response",
    )?)?)
    .context("invalid OPAQUE credential response")?;
    let finished = state
        .finish(
            &mut OsRng,
            password.as_bytes(),
            response,
            ClientLoginFinishParameters::default(),
        )
        .context("OPAQUE client login finish failed")?;
    Ok(json!({
        "client_message": encode(finished.message.serialize().as_slice()),
        "export_key": encode(finished.export_key.as_slice()),
    }))
}

fn server_registration_start(request: &HelperRequest, setup_path: &Path) -> Result<Value> {
    let identifier = required(&request.identifier, "identifier")?;
    let client_request = RegistrationRequest::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.client_request,
        "client_request",
    )?)?)
    .context("invalid OPAQUE registration request")?;
    let setup = load_or_create_server_setup(setup_path)?;
    let started = ServerRegistration::<LiflyCipherSuite>::start(
        &setup,
        client_request,
        identifier.as_bytes(),
    )
    .context("OPAQUE server registration start failed")?;
    let state = RegistrationServerState {
        kind: "registration-v1".to_string(),
        identifier_hash: identifier_hash(identifier),
    };
    Ok(json!({
        "server_response": encode(started.message.serialize().as_slice()),
        "server_state": encode(serde_json::to_vec(&state)?.as_slice()),
    }))
}

fn server_registration_finish(request: &HelperRequest) -> Result<Value> {
    let identifier = required(&request.identifier, "identifier")?;
    let state_bytes = decode(required(&request.server_state, "server_state")?)?;
    let state: RegistrationServerState = serde_json::from_slice(&state_bytes)
        .context("invalid OPAQUE registration server state")?;
    if state.kind != "registration-v1" || state.identifier_hash != identifier_hash(identifier) {
        bail!("OPAQUE registration server state does not match identifier")
    }
    let upload = RegistrationUpload::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.client_upload,
        "client_upload",
    )?)?)
    .context("invalid OPAQUE registration upload")?;
    let password_file = ServerRegistration::<LiflyCipherSuite>::finish(upload);
    Ok(json!({
        "credential_record": encode(password_file.serialize().as_slice()),
    }))
}

fn server_login_start(request: &HelperRequest, setup_path: &Path) -> Result<Value> {
    let identifier = required(&request.identifier, "identifier")?;
    let credential_request = CredentialRequest::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.client_request,
        "client_request",
    )?)?)
    .context("invalid OPAQUE credential request")?;
    let password_file = match request.credential_record.as_deref().filter(|value| !value.is_empty()) {
        Some(value) => Some(
            ServerRegistration::<LiflyCipherSuite>::deserialize(&decode(value)?)
                .context("invalid OPAQUE credential record")?,
        ),
        None => None,
    };
    let setup = load_or_create_server_setup(setup_path)?;
    let started = ServerLogin::<LiflyCipherSuite>::start(
        &mut OsRng,
        &setup,
        password_file,
        credential_request,
        identifier.as_bytes(),
        ServerLoginParameters::default(),
    )
    .context("OPAQUE server login start failed")?;
    Ok(json!({
        "server_response": encode(started.message.serialize().as_slice()),
        "server_state": encode(started.state.serialize().as_slice()),
    }))
}

fn server_login_finish(request: &HelperRequest) -> Result<Value> {
    let state = ServerLogin::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.server_state,
        "server_state",
    )?)?)
    .context("invalid OPAQUE server login state")?;
    let finish = CredentialFinalization::<LiflyCipherSuite>::deserialize(&decode(required(
        &request.client_finish,
        "client_finish",
    )?)?)
    .context("invalid OPAQUE client finalization")?;
    let authenticated = state
        .finish(finish, ServerLoginParameters::default())
        .is_ok();
    Ok(json!({"authenticated": authenticated}))
}

fn load_or_create_server_setup(path: &Path) -> Result<ServerSetup<LiflyCipherSuite>> {
    match fs::read(path) {
        Ok(bytes) => ServerSetup::<LiflyCipherSuite>::deserialize(&bytes)
            .context("invalid persisted OPAQUE server setup"),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            let setup = ServerSetup::<LiflyCipherSuite>::new(&mut OsRng);
            persist_server_setup(path, setup.serialize().as_slice())?;
            Ok(setup)
        }
        Err(error) => Err(error).with_context(|| format!("failed to read {}", path.display())),
    }
}

fn persist_server_setup(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow!("OPAQUE setup path has no parent"))?;
    let created_parent = !parent.exists();
    fs::create_dir_all(parent)
        .with_context(|| format!("failed to create {}", parent.display()))?;
    if created_parent {
        set_private_directory_permissions(parent)?;
    }
    let temp = path.with_extension("tmp");
    fs::write(&temp, bytes).with_context(|| format!("failed to write {}", temp.display()))?;
    set_private_file_permissions(&temp)?;
    fs::rename(&temp, path).with_context(|| format!("failed to persist {}", path.display()))?;
    set_private_file_permissions(path)?;
    Ok(())
}

#[cfg(unix)]
fn set_private_directory_permissions(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_private_directory_permissions(_path: &Path) -> Result<()> {
    Ok(())
}

#[cfg(unix)]
fn set_private_file_permissions(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_private_file_permissions(_path: &Path) -> Result<()> {
    Ok(())
}

fn required<'a>(value: &'a Option<String>, name: &str) -> Result<&'a str> {
    value
        .as_deref()
        .filter(|item| !item.is_empty())
        .ok_or_else(|| anyhow!("missing {name}"))
}

fn encode(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn decode(value: &str) -> Result<Vec<u8>> {
    URL_SAFE_NO_PAD
        .decode(value)
        .with_context(|| "invalid base64url OPAQUE payload")
}

fn identifier_hash(identifier: &str) -> String {
    encode(Sha256::digest(identifier.as_bytes()).as_slice())
}
