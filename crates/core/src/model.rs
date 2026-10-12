use crate::{Error, Result};
use serde::{Deserialize, Serialize};

pub const MAX_DOCUMENT_BYTES: usize = 64 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LabeledValue {
    pub label: String,
    pub value: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Relation {
    pub label: String,
    pub value: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_contact_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Calendar {
    Gregorian,
    ChineseLunar,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DateKind {
    Birthday,
    Anniversary,
    Other,
    Custom,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ContactDate {
    pub kind: DateKind,
    pub label: String,
    pub calendar: Calendar,
    pub year: Option<u16>,
    pub month: u8,
    pub day: u8,
    pub is_leap_month: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ContactData {
    pub version: u32,
    pub display_name: String,
    #[serde(default)]
    pub given_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub middle_name: String,
    #[serde(default)]
    pub family_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name_prefix: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name_suffix: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub phonetic_family_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub phonetic_middle_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub phonetic_given_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub nickname: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub job_title: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub website: String,
    #[serde(default)]
    pub phones: Vec<LabeledValue>,
    #[serde(default)]
    pub emails: Vec<LabeledValue>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub addresses: Vec<LabeledValue>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub instant_messages: Vec<LabeledValue>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub relations: Vec<Relation>,
    #[serde(default)]
    pub organization: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub dates: Vec<ContactDate>,
}

fn text(value: &str, max: usize, required: bool) -> Result<()> {
    if value.len() > max || value.contains('\0') || (required && value.trim().is_empty()) {
        return Err(Error::Invalid("text bounds"));
    }
    Ok(())
}

impl ContactData {
    pub fn from_json(bytes: &[u8]) -> Result<Self> {
        if bytes.len() > MAX_DOCUMENT_BYTES {
            return Err(Error::Invalid("contact exceeds 64 KiB"));
        }
        let data: Self = serde_json::from_slice(bytes)
            .map_err(|_| Error::Invalid("invalid contact JSON or unknown fields"))?;
        data.validate()?;
        Ok(data)
    }

    pub fn validate(&self) -> Result<()> {
        if self.version != 2 {
            return Err(Error::Invalid("unsupported contact version"));
        }
        text(&self.display_name, 1024, true)?;
        for name in [
            &self.given_name,
            &self.middle_name,
            &self.family_name,
            &self.organization,
            &self.name_prefix,
            &self.name_suffix,
            &self.phonetic_family_name,
            &self.phonetic_middle_name,
            &self.phonetic_given_name,
            &self.nickname,
            &self.job_title,
        ] {
            text(name, 1024, false)?;
        }
        text(&self.website, 4096, false)?;
        text(&self.notes, 32768, false)?;
        for items in [&self.phones, &self.emails] {
            if items.len() > 32 {
                return Err(Error::Invalid("at most 32 phone/email entries"));
            }
            for item in items {
                text(&item.label, 128, false)?;
                text(&item.value, 1024, true)?;
            }
        }
        for (items, max_value) in [(&self.addresses, 4096), (&self.instant_messages, 1024)] {
            if items.len() > 32 {
                return Err(Error::Invalid("at most 32 entries per field"));
            }
            for item in items {
                text(&item.label, 128, true)?;
                text(&item.value, max_value, true)?;
            }
        }
        if self.relations.len() > 32 {
            return Err(Error::Invalid("at most 32 relations"));
        }
        let mut targets = std::collections::BTreeSet::new();
        for relation in &self.relations {
            text(&relation.label, 128, true)?;
            text(&relation.value, 1024, true)?;
            if let Some(id) = &relation.target_contact_id {
                crate::valid_key(id)?;
                if !targets.insert((&relation.label, id)) {
                    return Err(Error::Invalid("duplicate relation"));
                }
            }
        }
        if self.dates.len() > 32 {
            return Err(Error::Invalid("at most 32 dates"));
        }
        let mut birthdays = [false; 2];
        for date in &self.dates {
            text(&date.label, 128, date.kind == DateKind::Custom)?;
            if date.kind == DateKind::Birthday {
                let index = match date.calendar {
                    Calendar::Gregorian => 0,
                    Calendar::ChineseLunar => 1,
                };
                if birthdays[index] {
                    return Err(Error::Invalid("at most one birthday per calendar"));
                }
                birthdays[index] = true;
            }
            let options = crate::calendar_options(&date.calendar, date.year)?;
            let max_day = options
                .months
                .iter()
                .find(|m| m.month == date.month && m.is_leap_month == date.is_leap_month)
                .ok_or(Error::Invalid(
                    "month does not exist in selected calendar year",
                ))?
                .days;
            if date.day == 0 || date.day > max_day {
                return Err(Error::Invalid("date day bounds"));
            }
        }
        if serde_json::to_vec(self)?.len() > MAX_DOCUMENT_BYTES {
            return Err(Error::Invalid("contact exceeds 64 KiB"));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct Contact {
    pub id: String,
    pub data: ContactData,
    pub has_conflict: bool,
}
