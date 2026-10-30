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

/// A selection from the overlay, clamped to an image of `width` × `height` pixels. None when
/// nothing is left (a click without a drag, or a selection off the edge).
pub fn clamp_rect(x: i64, y: i64, w: i64, h: i64, width: u32, height: u32) -> Option<(u32, u32, u32, u32)> {
    let (left, top) = (x.max(0), y.max(0));
    let right = (x + w).min(width as i64);
    let bottom = (y + h).min(height as i64);
    (right - left >= 2 && bottom - top >= 2)
        .then(|| (left as u32, top as u32, (right - left) as u32, (bottom - top) as u32))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    fn at() -> NaiveDateTime {
        NaiveDate::from_ymd_opt(2026, 10, 30).unwrap().and_hms_opt(14, 3, 22).unwrap()
    }

    #[test]
    fn rects_are_clamped_to_the_image() {
        assert_eq!(clamp_rect(10, 20, 100, 50, 1920, 1080), Some((10, 20, 100, 50)));
        assert_eq!(clamp_rect(-5, -5, 20, 20, 1920, 1080), Some((0, 0, 15, 15)));
        assert_eq!(clamp_rect(1900, 1070, 100, 100, 1920, 1080), Some((1900, 1070, 20, 10)));
        assert_eq!(clamp_rect(10, 10, 1, 40, 1920, 1080), None);
        assert_eq!(clamp_rect(2000, 10, 50, 50, 1920, 1080), None);
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
