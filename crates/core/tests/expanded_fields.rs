use card_weave_core::{AddressBook, ContactData};
use serde_json::json;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn optional_fields_preserve_legacy_document_and_guarded_edits() {
    let path = std::env::temp_dir().join(format!(
        "cw-expanded-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let mut book = AddressBook::init(&path, None).unwrap();
    let old = ContactData::from_json(br#"{"version":2,"display_name":"Legacy","given_name":"","family_name":"","phones":[],"emails":[],"organization":"","notes":"","dates":[]}"#).unwrap();
    let created = book.create(old.clone()).unwrap();
    let before = book.status().unwrap().pending_outbox;
    let encoded = serde_json::to_value(&old).unwrap();
    for field in [
        "name_prefix",
        "name_suffix",
        "phonetic_family_name",
        "phonetic_middle_name",
        "phonetic_given_name",
        "nickname",
        "job_title",
        "website",
        "addresses",
        "instant_messages",
        "relations",
    ] {
        assert!(encoded.get(field).is_none());
    }
    book.save_guarded(&created.id, &old, Some(old.clone()))
        .unwrap();
    assert_eq!(book.status().unwrap().pending_outbox, before);
    let mut extended = encoded.clone();
    extended["nickname"] = json!("New nickname");
    extended["addresses"] = json!([{"label":"住宅","value":"Address fixture"}]);
    let extended = ContactData::from_json(&serde_json::to_vec(&extended).unwrap()).unwrap();
    book.save_guarded(&created.id, &old, Some(extended.clone()))
        .unwrap();
    let pending = book.status().unwrap().pending_outbox;
    let mut oversized = extended.clone();
    oversized.addresses = vec![
        card_weave_core::LabeledValue {
            label: "住宅".into(),
            value: "a".repeat(4096),
        };
        16
    ];
    assert!(
        book.save_guarded(&created.id, &extended, Some(oversized))
            .is_err()
    );
    assert_eq!(book.get(&created.id).unwrap().unwrap().data, extended);
    assert_eq!(book.status().unwrap().pending_outbox, pending);
    assert_eq!(
        book.save_guarded(&created.id, &old, Some(old.clone()))
            .unwrap_err()
            .code(),
        "edit_stale"
    );
    assert_eq!(book.status().unwrap().pending_outbox, pending);
    book.close().unwrap();
    let mut book = AddressBook::open(&path).unwrap();
    assert_eq!(book.get(&created.id).unwrap().unwrap().data, extended);
    book.save_guarded(&created.id, &extended, Some(old.clone()))
        .unwrap();
    assert_eq!(
        serde_json::to_value(book.get(&created.id).unwrap().unwrap().data).unwrap(),
        encoded
    );
    book.close().unwrap();
    std::fs::remove_dir_all(path).unwrap();
}
