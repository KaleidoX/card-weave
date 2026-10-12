use card_weave_core::{AddressBook, ContactData};
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn stale_edit_and_delete_preserve_newer_document_and_outbox() {
    let path = std::env::temp_dir().join(format!(
        "card-weave-guard-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let mut book = AddressBook::init(&path, None).unwrap();
    let original = ContactData::from_json(br#"{"version":2,"display_name":"Original","phones":[{"label":"work","value":"123"}],"dates":[{"kind":"birthday","label":"birthday","calendar":"chinese_lunar","year":null,"month":4,"day":15,"is_leap_month":true}]}"#).unwrap();
    assert!(
        !serde_json::to_value(&original)
            .unwrap()
            .as_object()
            .unwrap()
            .contains_key("middle_name")
    );
    let contact = book.create(original.clone()).unwrap();
    let mut newer = original.clone();
    newer.display_name = "Newer".into();
    newer.middle_name = "MiddleOnly".into();
    book.save_guarded(&contact.id, &original, Some(newer.clone()))
        .unwrap();
    assert_eq!(book.list("MiddleOnly", 10, 0).unwrap().len(), 1);
    let pending = book.status().unwrap().pending_outbox;
    for replacement in [Some(original.clone()), None] {
        assert_eq!(
            book.save_guarded(&contact.id, &original, replacement)
                .unwrap_err()
                .code(),
            "edit_stale"
        );
        assert_eq!(book.get(&contact.id).unwrap().unwrap().data, newer);
        assert_eq!(book.status().unwrap().pending_outbox, pending);
    }
    book.close().unwrap();
    let mut book = AddressBook::open(&path).unwrap();
    assert_eq!(book.get(&contact.id).unwrap().unwrap().data, newer);
    book.save_guarded(&contact.id, &newer, None).unwrap();
    assert!(book.get(&contact.id).unwrap().is_none());
    assert_eq!(
        book.save_guarded(&contact.id, &newer, Some(newer.clone()))
            .unwrap_err()
            .code(),
        "edit_stale"
    );
    book.close().unwrap();
    std::fs::remove_dir_all(path).unwrap();
}
