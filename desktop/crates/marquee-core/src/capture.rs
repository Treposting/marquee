//! Names and places for saved captures, matching the macOS app: "Marquee 2026-10-30 at
//! 14.03.22.png", with " (2)", " (3)"… when a file of that name already exists.

use std::path::{Path, PathBuf};

use chrono::NaiveDateTime;

pub fn file_name(at: NaiveDateTime, suffix: &str) -> String {
    format!("Marquee {}{suffix}.png", at.format("%Y-%m-%d at %H.%M.%S"))
}

/// A path in `dir` that doesn't exist yet.
pub fn unique_path(dir: &Path, at: NaiveDateTime) -> PathBuf {
    let mut path = dir.join(file_name(at, ""));
    let mut n = 2;
    while path.exists() {
        path = dir.join(file_name(at, &format!(" ({n})")));
        n += 1;
    }
    path
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    fn at() -> NaiveDateTime {
        NaiveDate::from_ymd_opt(2026, 10, 30).unwrap().and_hms_opt(14, 3, 22).unwrap()
    }

    #[test]
    fn names_match_macos() {
        assert_eq!(file_name(at(), ""), "Marquee 2026-10-30 at 14.03.22.png");
        assert_eq!(file_name(at(), " (2)"), "Marquee 2026-10-30 at 14.03.22 (2).png");
    }

    #[test]
    fn unique_path_skips_existing_files() {
        let dir = std::env::temp_dir().join(format!("marquee-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let first = unique_path(&dir, at());
        assert_eq!(first.file_name().unwrap(), "Marquee 2026-10-30 at 14.03.22.png");
        std::fs::write(&first, b"x").unwrap();
        let second = unique_path(&dir, at());
        assert_eq!(second.file_name().unwrap(), "Marquee 2026-10-30 at 14.03.22 (2).png");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
