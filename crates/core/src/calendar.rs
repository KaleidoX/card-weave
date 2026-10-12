use crate::{Calendar, Error, Result};
use chinese_lunisolar_calendar::{
    LunarMonth, LunisolarYear, MAX_YEAR_IN_SOLAR_CALENDAR, MIN_YEAR_IN_SOLAR_CALENDAR, SolarYear,
};
use serde::Serialize;

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct CalendarMonth {
    pub month: u8,
    pub is_leap_month: bool,
    pub days: u8,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct CalendarOptions {
    pub min_year: u16,
    pub max_year: u16,
    pub year_specific: bool,
    pub months: Vec<CalendarMonth>,
}

pub fn calendar_options(calendar: &Calendar, year: Option<u16>) -> Result<CalendarOptions> {
    let lunar = *calendar == Calendar::ChineseLunar;
    let (min_year, max_year) = if lunar {
        (MIN_YEAR_IN_SOLAR_CALENDAR, MAX_YEAR_IN_SOLAR_CALENDAR)
    } else {
        (1, 9999)
    };
    if year.is_some_and(|y| !(min_year..=max_year).contains(&y)) {
        return Err(Error::Invalid("calendar year outside supported range"));
    }
    let lunar_year = if lunar {
        year.map(|y| LunisolarYear::from_solar_year(SolarYear::from_u16(y)))
            .transpose()
            .map_err(|_| Error::Invalid("unsupported lunar year"))?
    } else {
        None
    };
    let mut months = Vec::with_capacity(24);
    for month in 1..=12 {
        for is_leap_month in [false, true] {
            let days = if lunar {
                match lunar_year {
                    Some(y) => {
                        let m = LunarMonth::from_u8_with_leap(month, is_leap_month)
                            .map_err(|_| Error::Invalid("invalid lunar month"))?;
                        let Some(days) = y.get_total_days_in_a_month(m) else {
                            continue;
                        };
                        days
                    }
                    None => 30,
                }
            } else {
                if is_leap_month {
                    continue;
                }
                match month {
                    4 | 6 | 9 | 11 => 30,
                    2 => {
                        if year.is_none_or(|y| y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) {
                            29
                        } else {
                            28
                        }
                    }
                    _ => 31,
                }
            };
            months.push(CalendarMonth {
                month,
                is_leap_month,
                days,
            });
        }
    }
    Ok(CalendarOptions {
        min_year,
        max_year,
        year_specific: year.is_some(),
        months,
    })
}
