use std::path::Path;

use lifly_opaque_helper::handle_json;
use serde_json::{json, Value};
use tempfile::TempDir;

fn invoke(setup: &Path, request: Value) -> Value {
    handle_json(&request.to_string(), setup).expect("helper operation must succeed")
}

fn field(value: &Value, name: &str) -> String {
    value[name]
        .as_str()
        .unwrap_or_else(|| panic!("missing {name}"))
        .to_string()
}

#[test]
fn registration_and_login_reproduce_export_key_without_exposing_password() {
    let temp = TempDir::new().unwrap();
    let setup = temp.path().join("server-setup.bin");
    let identifier = "+8613800138000";
    let password = "demo-password-安全";

    let client_start = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "client_registration_start",
            "password": password,
        }),
    );
    assert!(!client_start.to_string().contains(password));

    let server_start = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "registration_start",
            "identifier": identifier,
            "client_request": field(&client_start, "client_request"),
        }),
    );
    let client_finish = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "client_registration_finish",
            "password": password,
            "client_state": field(&client_start, "client_state"),
            "server_response": field(&server_start, "server_response"),
        }),
    );
    assert!(!client_finish.to_string().contains(password));
    let registration_export_key = field(&client_finish, "export_key");

    let server_finish = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "registration_finish",
            "identifier": identifier,
            "server_state": field(&server_start, "server_state"),
            "client_upload": field(&client_finish, "client_message"),
        }),
    );
    let credential_record = field(&server_finish, "credential_record");

    let login_client_start = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "client_login_start",
            "password": password,
        }),
    );
    let login_server_start = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "login_start",
            "identifier": identifier,
            "credential_record": credential_record,
            "client_request": field(&login_client_start, "client_request"),
        }),
    );
    let login_client_finish = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "client_login_finish",
            "password": password,
            "client_state": field(&login_client_start, "client_state"),
            "server_response": field(&login_server_start, "server_response"),
        }),
    );
    assert_eq!(registration_export_key, field(&login_client_finish, "export_key"));

    let login_server_finish = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "login_finish",
            "identifier": identifier,
            "server_state": field(&login_server_start, "server_state"),
            "client_finish": field(&login_client_finish, "client_message"),
        }),
    );
    assert_eq!(login_server_finish["authenticated"], true);
    assert!(setup.exists());
}

#[cfg(unix)]
#[test]
fn persisted_setup_does_not_change_existing_parent_permissions() {
    use std::os::unix::fs::PermissionsExt;

    let temp = TempDir::new().unwrap();
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o755)).unwrap();
    let setup = temp.path().join("setup.bin");
    let before = std::fs::metadata(temp.path()).unwrap().permissions().mode() & 0o777;

    let client = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "client_registration_start",
            "password": "permission-test",
        }),
    );
    let _ = invoke(
        &setup,
        json!({
            "protocol": "opaque-rfc9807",
            "protocol_version": 1,
            "operation": "registration_start",
            "identifier": "+8613800138000",
            "client_request": field(&client, "client_request"),
        }),
    );

    let after = std::fs::metadata(temp.path()).unwrap().permissions().mode() & 0o777;
    let setup_mode = std::fs::metadata(&setup).unwrap().permissions().mode() & 0o777;
    assert_eq!(after, before);
    assert_eq!(setup_mode, 0o600);
}
