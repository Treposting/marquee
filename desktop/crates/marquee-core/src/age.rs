//! "Just now", "5 min ago", "2 hr ago", "Yesterday", "3 days ago", then the date. Ported from
//! the macOS app's `CopiedAge`.

use chrono::{DateTime, Local, TimeZone, Utc};

pub fn copied_age(date: DateTime<Utc>, now: DateTime<Utc>) -> String {
    copied_age_in(date, now, &Local)
}

/// Same as [`copied_age`], with days counted in `tz` (for tests).
pub fn copied_age_in<Tz: TimeZone>(date: DateTime<Utc>, now: DateTime<Utc>, tz: &Tz) -> String
where
    Tz::Offset: std::fmt::Display,
{
    let seconds = (now - date).num_seconds().max(0);
    match seconds {
        0..=59 => "Just now".into(),
        60..=3599 => format!("{} min ago", seconds / 60),
        3600..=86_399 => format!("{} hr ago", seconds / 3600),
        _ => {
            let day = |d: DateTime<Utc>| d.with_timezone(tz).date_naive();
            let days = (day(now) - day(date)).num_days();
            if days <= 1 {
                "Yesterday".into()
            } else if days < 7 {
                format!("{days} days ago")
            } else {
                date.with_timezone(tz).format("%b %-d").to_string()
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Duration, Utc as UtcTz};

    #[test]
    fn ages() {
        let now = UtcTz.with_ymd_and_hms(2026, 10, 26, 15, 0, 0).unwrap();
        let ago = |s: i64| copied_age_in(now - Duration::seconds(s), now, &UtcTz);
        assert_eq!(ago(10), "Just now");
        assert_eq!(ago(5 * 60), "5 min ago");
        assert_eq!(ago(2 * 3600), "2 hr ago");
        assert_eq!(ago(26 * 3600), "Yesterday");
        assert_eq!(ago(3 * 86_400), "3 days ago");
        assert_eq!(ago(20 * 86_400), "Oct 6");
        assert_eq!(copied_age_in(now + Duration::seconds(30), now, &UtcTz), "Just now");
    }
}
