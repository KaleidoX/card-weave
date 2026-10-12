use card_weave_app_host::Host;
use card_weave_core::{AddressBook, Cancellation, ContactData, Resolution};
use lfs_storage::{OpenDalTransport, Options};
use serde_json::{Value, json};
fn root(label: &str) -> std::path::PathBuf {
    std::env::temp_dir().join(format!(
        "cw-directory-{label}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ))
}
fn command(host: &Host, input: Value) -> Value {
    serde_json::from_str(&host.execute(input.to_string())).unwrap()
}
fn data(name: &str) -> ContactData {
    ContactData::from_json(
        json!({"version":2,"display_name":name})
            .to_string()
            .as_bytes(),
    )
    .unwrap()
}
#[test]
fn directory_pages_jump_to_unloaded_sections_and_reject_stale_snapshots() {
    let path = root("host");
    let host = Host::new();
    let opened: Value =
        serde_json::from_str(&host.initialize(path.display().to_string(), true, None)).unwrap();
    assert_eq!(opened["ok"], true);
    for i in 0..101 {
        assert_eq!(
            command(
                &host,
                json!({"action":"create","contact":data(&format!("Alice {i:03}"))})
            )["ok"],
            true
        );
    }
    let z = command(&host, json!({"action":"create","contact":data("张三")}))["data"].clone();
    let first = command(
        &host,
        json!({"action":"directory","group":null,"revision":null,"offset":0}),
    )["data"]
        .clone();
    assert_eq!(first["total"], 102);
    assert_eq!(first["entries"].as_array().unwrap().len(), 50);
    assert_eq!(
        first["sections"],
        json!([{"initial":"A","offset":0,"count":101},{"initial":"Z","offset":101,"count":1}])
    );
    let last = command(
        &host,
        json!({"action":"directory","group":null,"revision":first["revision"],"offset":101}),
    );
    assert_eq!(last["data"]["entries"][0]["id"], z["id"]);
    let mut renamed = z["data"].clone();
    renamed["display_name"] = json!("李四");
    assert_eq!(
        command(
            &host,
            json!({"action":"save","id":z["id"],"expected":z["data"],"contact":renamed})
        )["ok"],
        true
    );
    assert_eq!(
        command(
            &host,
            json!({"action":"directory","group":null,"revision":first["revision"],"offset":50})
        )["error"]["code"],
        "edit_stale"
    );
    let refreshed = command(
        &host,
        json!({"action":"directory","group":null,"revision":null,"offset":101}),
    );
    assert_eq!(refreshed["data"]["sections"][1]["initial"], "L");
    assert_eq!(refreshed["data"]["entries"][0]["display_name"], "李四");
    command(&host, json!({"action":"close"}));
    drop(host);
    std::fs::remove_dir_all(path).unwrap();
}
#[tokio::test]
async fn names_follow_writes_sync_delete_and_reopen_without_changing_documents() {
    let root = root("sync");
    std::fs::create_dir(&root).unwrap();
    let mut a = AddressBook::init(&root.join("a"), None).unwrap();
    let mut b = AddressBook::init(&root.join("b"), Some(a.config().dataset.clone())).unwrap();
    std::fs::create_dir(root.join("remote")).unwrap();
    let remote = OpenDalTransport::fs(root.join("remote"), Options::default()).unwrap();
    let mut explicit = data("单先生");
    explicit.phonetic_family_name = "Shan".into();
    let contact = a.create(explicit.clone()).unwrap();
    a.create(data("123 fixture")).unwrap();
    assert_eq!(
        a.directory(None)
            .unwrap()
            .sections
            .iter()
            .map(|s| s.initial.as_str())
            .collect::<Vec<_>>(),
        ["S", "#"]
    );
    a.sync(&remote, &Cancellation::default()).await.unwrap();
    b.sync(&remote, &Cancellation::default()).await.unwrap();
    assert_eq!(b.directory(None).unwrap().sections[0].initial, "S");
    assert_eq!(b.get(&contact.id).unwrap().unwrap().data, explicit);
    b.update(&contact.id, data("赵先生")).unwrap();
    let changed = data("王先生");
    a.update(&contact.id, changed.clone()).unwrap();
    assert_eq!(a.directory(None).unwrap().sections[0].initial, "W");
    a.sync(&remote, &Cancellation::default()).await.unwrap();
    b.sync(&remote, &Cancellation::default()).await.unwrap();
    let conflicted = b.directory(None).unwrap();
    let summary = conflicted
        .entries
        .iter()
        .find(|c| c.id == contact.id)
        .unwrap();
    assert!(summary.has_conflict);
    assert_eq!(
        summary.display_name,
        b.get(&contact.id).unwrap().unwrap().data.display_name
    );
    let observed = b
        .conflicts()
        .unwrap()
        .into_iter()
        .find(|c| c.id == contact.id)
        .unwrap()
        .candidates
        .into_iter()
        .map(|c| c.version)
        .collect();
    b.resolve(
        &contact.id,
        Resolution {
            observed,
            contact: Some(changed.clone()),
        },
    )
    .unwrap();
    assert_eq!(b.directory(None).unwrap().sections[0].initial, "W");
    assert!(!b.directory(None).unwrap().entries[0].has_conflict);
    b.sync(&remote, &Cancellation::default()).await.unwrap();
    a.sync(&remote, &Cancellation::default()).await.unwrap();
    a.save_guarded(&contact.id, &changed, None).unwrap();
    a.sync(&remote, &Cancellation::default()).await.unwrap();
    b.sync(&remote, &Cancellation::default()).await.unwrap();
    assert_eq!(b.directory(None).unwrap().entries.len(), 1);
    b.close().unwrap();
    let mut b = AddressBook::open(&root.join("b")).unwrap();
    assert_eq!(b.directory(None).unwrap().sections[0].initial, "#");
    b.close().unwrap();
    a.close().unwrap();
    drop((a, b));
    std::fs::remove_dir_all(root).unwrap();
}
