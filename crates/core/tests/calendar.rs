use card_weave_core::{Calendar, ContactData, calendar_options};
use serde_json::json;

#[test]
fn official_lunar_months_and_boundaries() {
    // HKO Gregorian-Lunar tables: 2023e.pdf, 2025e.pdf, 2033e.pdf.
    for (year, leap) in [(2023, 2), (2025, 6), (2033, 11)] {
        let result = calendar_options(&Calendar::ChineseLunar, Some(year)).unwrap();
        assert!(result.year_specific);
        assert_eq!(result.months.len(), 13);
        let m = result.months.iter().find(|m| m.is_leap_month).unwrap();
        assert_eq!(m.month, leap);
        assert_eq!(m.days, 29);
    }
    let ordinary = calendar_options(&Calendar::ChineseLunar, Some(2024)).unwrap();
    assert_eq!(ordinary.months.len(), 12);
    assert!(ordinary.months.iter().all(|m| !m.is_leap_month));
    assert_eq!(ordinary.months[0].days, 29);
    for year in [1901, 2100] {
        let r = calendar_options(&Calendar::ChineseLunar, Some(year)).unwrap();
        assert_eq!(r.months.iter().filter(|m| !m.is_leap_month).count(), 12);
        assert!(r.months.iter().all(|m| [29, 30].contains(&m.days)));
    }
    for year in [0, 1900, 2101, 9999] {
        assert!(calendar_options(&Calendar::ChineseLunar, Some(year)).is_err());
    }
}

#[test]
fn unknown_year_preserves_month_identity_without_inventing_a_year() {
    let r = calendar_options(&Calendar::ChineseLunar, None).unwrap();
    assert!(!r.year_specific);
    assert_eq!(r.months.len(), 24);
    assert!(r.months.iter().all(|m| m.days == 30));
    assert!(r.months.iter().any(|m| m.month == 12 && m.is_leap_month));
    assert_eq!(
        calendar_options(&Calendar::Gregorian, None).unwrap().months[1].days,
        29
    );
}

#[test]
fn contact_validation_uses_the_same_calendar_contract() {
    let base = json!({"version":2,"display_name":"Calendar fixture","dates":[{
        "kind":"birthday","label":"","calendar":"chinese_lunar",
        "year":2025,"month":6,"day":29,"is_leap_month":true
    }]});
    let valid =
        |v: &serde_json::Value| ContactData::from_json(&serde_json::to_vec(v).unwrap()).is_ok();
    assert!(valid(&base));
    let mut date = base.clone();
    date["dates"][0]["day"] = json!(30);
    assert!(!valid(&date));
    date["dates"][0]["year"] = serde_json::Value::Null;
    assert!(valid(&date));
    date["dates"][0]["year"] = json!(2024);
    assert!(!valid(&date));
    date["dates"][0]["is_leap_month"] = json!(false);
    date["dates"][0]["month"] = json!(1);
    assert!(!valid(&date));
    date["dates"][0]["day"] = json!(29);
    assert!(valid(&date));
}
