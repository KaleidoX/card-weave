use card_weave_app_host::Host;
use serde_json::{Value, json};

#[test]
fn calendar_query_needs_no_book_and_rejects_unsupported_year() {
    let host = Host::new();
    let response = |year| -> Value {
        serde_json::from_str(
            &host.execute(
                json!({"action":"calendar_options", "calendar":"chinese_lunar","year":year})
                    .to_string(),
            ),
        )
        .unwrap()
    };
    let r = response(Some(2025));
    assert_eq!(r["ok"], true);
    assert_eq!(
        r["data"]["months"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|m| m["is_leap_month"] == true)
            .count(),
        1
    );
    assert_eq!(response(None)["data"]["year_specific"], false);
    assert_eq!(response(Some(1900))["ok"], false);
}
