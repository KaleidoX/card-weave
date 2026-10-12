use card_weave_app_host::Host;
use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};
fn command(host: &Host, value: Value) -> Value {
    serde_json::from_str(&host.execute(value.to_string())).unwrap()
}
#[test]
fn public_host_serializes_identity_mutations_and_cancel_before_network() {
    let path = std::env::temp_dir().join(format!(
        "cardweave-host-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let host = Host::new();
    let opened: Value =
        serde_json::from_str(&host.initialize(path.display().to_string(), true, None)).unwrap();
    assert_eq!(opened["ok"], true);
    assert_eq!(
        command(&host, json!({"action":"identity"}))["data"],
        opened["data"]
    );
    assert_eq!(
        command(
            &host,
            json!({"action":"validate_contact","contact":{"version":2,"display_name":"Import fixture","dates":[{"kind":"birthday","label":"","calendar":"gregorian","year":null,"month":2,"day":29,"is_leap_month":false}]}})
        )["data"],
        true
    );
    assert_eq!(
        command(
            &host,
            json!({"action":"validate_contact","contact":{"version":2,"display_name":""}})
        )["ok"],
        false
    );
    assert_eq!(
        command(&host, json!({"action":"status"}))["data"]["pending_outbox"],
        0
    );
    let saved = command(
        &host,
        json!({"action":"create","contact":{"version":2,"display_name":"Host fixture"}}),
    );
    assert_eq!(saved["ok"], true);
    assert_eq!(
        command(&host, json!({"action":"status"}))["data"]["pending_outbox"],
        1
    );
    assert!(host.begin_sync());
    assert!(!host.begin_sync());
    host.cancel();
    let response:Value=serde_json::from_str(&host.synchronize(json!({"type":"webdav","endpoint":"https://localhost:1/","username":"synthetic","password":"secret-not-in-error"}).to_string())).unwrap();
    assert_eq!(response["error"]["code"], "cancelled");
    assert!(!response.to_string().contains("secret-not-in-error"));
    assert_eq!(
        command(&host, json!({"action":"status"}))["data"]["pending_outbox"],
        1
    );
    assert_eq!(command(&host, json!({"action":"close"}))["ok"], true);
    std::fs::remove_dir_all(path).unwrap();
}
