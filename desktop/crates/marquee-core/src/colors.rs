//! Picked colors: the formats they're copied in and the history of the last 48, like the
//! macOS app's color picker.

use std::fs;
use std::io;
use std::path::Path;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// How many picked colors are kept.
pub const HISTORY_LIMIT: usize = 48;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

/// How a color is copied.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ColorFormat {
    #[default]
    Hex,
    Rgb,
    Hsl,
}

impl Rgb {
    /// "#FFCF1A" or "FFCF1A"; three-digit shorthand works too.
    pub fn parse_hex(text: &str) -> Option<Rgb> {
        let hex = text.trim().trim_start_matches('#');
        let expanded: String = match hex.len() {
            3 => hex.chars().flat_map(|c| [c, c]).collect(),
            6 => hex.to_string(),
            _ => return None,
        };
        let value = u32::from_str_radix(&expanded, 16).ok()?;
        Some(Rgb { r: (value >> 16) as u8, g: (value >> 8) as u8, b: value as u8 })
    }

    pub fn hex(self) -> String {
        format!("#{:02X}{:02X}{:02X}", self.r, self.g, self.b)
    }

    /// Hue in degrees, saturation and lightness in percent, rounded.
    pub fn hsl(self) -> (u32, u32, u32) {
        let (r, g, b) = (self.r as f64 / 255.0, self.g as f64 / 255.0, self.b as f64 / 255.0);
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let l = (max + min) / 2.0;
        let d = max - min;
        if d == 0.0 {
            return (0, 0, (l * 100.0).round() as u32);
        }
        let s = d / (1.0 - (2.0 * l - 1.0).abs());
        let h = if max == r {
            60.0 * (((g - b) / d).rem_euclid(6.0))
        } else if max == g {
            60.0 * ((b - r) / d + 2.0)
        } else {
            60.0 * ((r - g) / d + 4.0)
        };
        ((h.round() as u32) % 360, (s * 100.0).round() as u32, (l * 100.0).round() as u32)
    }

    pub fn format(self, format: ColorFormat) -> String {
        match format {
            ColorFormat::Hex => self.hex(),
            ColorFormat::Rgb => format!("rgb({}, {}, {})", self.r, self.g, self.b),
            ColorFormat::Hsl => {
                let (h, s, l) = self.hsl();
                format!("hsl({h}, {s}%, {l}%)")
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PickedColor {
    pub color: Rgb,
    pub date: DateTime<Utc>,
}

/// Newest first, no duplicates, at most `HISTORY_LIMIT`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ColorHistory {
    pub colors: Vec<PickedColor>,
}

impl ColorHistory {
    pub fn load(path: &Path) -> io::Result<ColorHistory> {
        match fs::read(path) {
            Ok(data) => serde_json::from_slice(&data).map_err(io::Error::other),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(ColorHistory::default()),
            Err(e) => Err(e),
        }
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec(self).map_err(io::Error::other)?)?;
        fs::rename(tmp, path)
    }

    /// Adds a color at the top; picking it again moves it there.
    pub fn add(&mut self, color: Rgb) {
        self.colors.retain(|c| c.color != color);
        self.colors.insert(0, PickedColor { color, date: Utc::now() });
        self.colors.truncate(HISTORY_LIMIT);
    }

    pub fn remove(&mut self, color: Rgb) {
        self.colors.retain(|c| c.color != color);
    }

    pub fn clear(&mut self) {
        self.colors.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const YELLOW: Rgb = Rgb { r: 255, g: 207, b: 26 };

    #[test]
    fn formats() {
        assert_eq!(YELLOW.format(ColorFormat::Hex), "#FFCF1A");
        assert_eq!(YELLOW.format(ColorFormat::Rgb), "rgb(255, 207, 26)");
        assert_eq!(YELLOW.format(ColorFormat::Hsl), "hsl(47, 100%, 55%)");
        assert_eq!(Rgb { r: 128, g: 128, b: 128 }.format(ColorFormat::Hsl), "hsl(0, 0%, 50%)");
        assert_eq!(Rgb { r: 0, g: 0, b: 255 }.hsl(), (240, 100, 50));
        assert_eq!(Rgb { r: 255, g: 0, b: 128 }.hsl(), (330, 100, 50));
    }

    #[test]
    fn parses_hex() {
        assert_eq!(Rgb::parse_hex("#FFCF1A"), Some(YELLOW));
        assert_eq!(Rgb::parse_hex("fff"), Some(Rgb { r: 255, g: 255, b: 255 }));
        assert_eq!(Rgb::parse_hex("#12345"), None);
        assert_eq!(Rgb::parse_hex("zzzzzz"), None);
    }

    #[test]
    fn history_is_newest_first_without_duplicates() {
        let mut h = ColorHistory::default();
        h.add(YELLOW);
        h.add(Rgb { r: 0, g: 0, b: 0 });
        h.add(YELLOW);
        assert_eq!(h.colors.len(), 2);
        assert_eq!(h.colors[0].color, YELLOW);
        for i in 0..60 {
            h.add(Rgb { r: i, g: 1, b: 2 });
        }
        assert_eq!(h.colors.len(), HISTORY_LIMIT);
        h.remove(Rgb { r: 59, g: 1, b: 2 });
        assert_eq!(h.colors[0].color, Rgb { r: 58, g: 1, b: 2 });
    }

    #[test]
    fn round_trip() {
        let dir = std::env::temp_dir().join(format!("marquee-colors-{}", uuid::Uuid::new_v4()));
        let path = dir.join("colors.json");
        let mut h = ColorHistory::default();
        h.add(YELLOW);
        h.save(&path).unwrap();
        assert_eq!(ColorHistory::load(&path).unwrap(), h);
        assert!(ColorHistory::load(&dir.join("none.json")).unwrap().colors.is_empty());
        fs::remove_dir_all(dir).unwrap();
    }
}
