use card_weave_core::{AddressBook, ContactData};
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn public_lifecycle_rejects_second_owner_and_preserves_pending() {
    let home = std::env::temp_dir().join(format!(
        "card-weave-api-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let mut book = AddressBook::init(&home, None).unwrap();
    assert!(matches!(AddressBook::open(&home), Err(e) if e.code() == "database_in_use"));
    let data = ContactData::from_json(br#"{"version":2,"display_name":"Fixture"}"#).unwrap();
    let contact = book.create(data).unwrap();
    let identity = serde_json::to_value(book.config()).unwrap();
    let pending = book.status().unwrap().pending_outbox;
    assert_eq!(pending, 1);
    book.close().unwrap();
    let mut reopened = AddressBook::open(&home).unwrap();
    assert_eq!(serde_json::to_value(reopened.config()).unwrap(), identity);
    assert_eq!(reopened.get(&contact.id).unwrap(), Some(contact));
    assert_eq!(reopened.status().unwrap().pending_outbox, pending);
    reopened.close().unwrap();
    std::fs::remove_dir_all(home).unwrap();
}
