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

#[test]
fn reference_date_uses_requested_calendar_and_validates_input() {
    let host = Host::new();
    let date = |calendar, year, month, day| -> Value {
        serde_json::from_str(
            &host.execute(
                json!({
                    "action": "calendar_date", "calendar": calendar,
                    "year": year, "month": month, "day": day,
                })
                .to_string(),
            ),
        )
        .unwrap()
    };
    assert_eq!(
        date("gregorian", 2026, 10, 12)["data"],
        json!({
            "year":2026,"month":10,"day":12,"is_leap_month":false
        })
    );
    assert_eq!(
        date("chinese_lunar", 2025, 1, 29)["data"],
        json!({
            "year":2025,"month":1,"day":1,"is_leap_month":false
        })
    );
    assert_eq!(date("chinese_lunar", 2025, 1, 28)["data"]["year"], 2024);
    assert_eq!(
        date("chinese_lunar", 2025, 7, 25)["data"],
        json!({
            "year":2025,"month":6,"day":1,"is_leap_month":true
        })
    );
    assert_eq!(date("gregorian", 2025, 2, 29)["ok"], false);
    assert_eq!(date("chinese_lunar", 1800, 1, 1)["ok"], false);
}
