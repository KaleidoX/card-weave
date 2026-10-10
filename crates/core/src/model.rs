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
#[serde(rename_all = "snake_case")]
pub enum Calendar {
    Gregorian,
    ChineseLunar,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ContactDate {
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
    #[serde(default)]
    pub family_name: String,
    #[serde(default)]
    pub phones: Vec<LabeledValue>,
    #[serde(default)]
    pub emails: Vec<LabeledValue>,
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
        if self.version != 1 {
            return Err(Error::Invalid("unsupported contact version"));
        }
        text(&self.display_name, 1024, true)?;
        for name in [&self.given_name, &self.family_name, &self.organization] {
            text(name, 1024, false)?;
        }
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
        if self.dates.len() > 32 {
            return Err(Error::Invalid("at most 32 dates"));
        }
        for date in &self.dates {
            text(&date.label, 128, true)?;
            if !(1..=12).contains(&date.month)
                || date.year.is_some_and(|y| !(1..=9999).contains(&y))
            {
                return Err(Error::Invalid("date month/year bounds"));
            }
            let max_day = match date.calendar {
                Calendar::ChineseLunar => 30,
                Calendar::Gregorian => {
                    if date.is_leap_month {
                        return Err(Error::Invalid("Gregorian date cannot have leap month"));
                    }
                    match date.month {
                        4 | 6 | 9 | 11 => 30,
                        2 => {
                            if date
                                .year
                                .is_none_or(|y| y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))
                            {
                                29
                            } else {
                                28
                            }
                        }
                        _ => 31,
                    }
                }
            };
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
