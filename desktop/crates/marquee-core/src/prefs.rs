//! Settings, with the same defaults as the macOS app. Stored as JSON in the app's config folder.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::shortcuts::Action;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Preferences {
    // After capture
    pub show_overlay: bool,
    /// Seconds before the Quick Access thumbnail hides; 0 means never.
    pub overlay_timeout: u32,
    pub copy_after_capture: bool,
    pub save_after_capture: bool,
    pub save_folder: Option<PathBuf>,
    // General
    pub play_sound: bool,
    pub copy_paste_sound: bool,
    pub launch_at_login: bool,
    pub auto_check_updates: bool,
    // Clipboard
    pub history_limit: usize,
    pub auto_paste: bool,
    pub monitor_paused: bool,
    pub link_previews: bool,
    /// Executable names whose copies are never stored.
    pub ignored_apps: Vec<String>,
    // Recording
    pub record_fps: u32,
    pub record_show_cursor: bool,
    pub record_audio: bool,
    pub record_microphone: bool,
    pub record_countdown_seconds: u32,
    // Measure
    pub measure_tolerance: u32,
    // Color picker
    pub color_format: crate::colors::ColorFormat,
    /// Action id → accelerator. Missing actions use their default; an empty string means none.
    pub shortcuts: BTreeMap<String, String>,
}

impl Default for Preferences {
    fn default() -> Self {
        Preferences {
            show_overlay: true,
            overlay_timeout: 20,
            copy_after_capture: true,
            save_after_capture: false,
            save_folder: None,
            play_sound: true,
            copy_paste_sound: true,
            launch_at_login: false,
            auto_check_updates: true,
            history_limit: 500,
            auto_paste: true,
            monitor_paused: false,
            link_previews: true,
            ignored_apps: DEFAULT_IGNORED_APPS.iter().map(|s| s.to_string()).collect(),
            record_fps: 30,
            record_show_cursor: true,
            record_audio: false,
            record_microphone: false,
            record_countdown_seconds: 3,
            measure_tolerance: 12,
            color_format: crate::colors::ColorFormat::Hex,
            shortcuts: BTreeMap::new(),
        }
    }
}

/// Password managers whose copies are never stored, like on macOS.
pub const DEFAULT_IGNORED_APPS: &[&str] = &[
    "1Password.exe",
    "Bitwarden.exe",
    "KeePass.exe",
    "KeePassXC.exe",
    "Dashlane.exe",
    "NordPass.exe",
    "Enpass.exe",
    "LastPass.exe",
    "ProtonPass.exe",
];

impl Preferences {
    /// Loads settings; a missing or unreadable file gives the defaults.
    pub fn load(path: &Path) -> Preferences {
        fs::read(path).ok().and_then(|data| serde_json::from_slice(&data).ok()).unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec_pretty(self).map_err(io::Error::other)?)?;
        fs::rename(tmp, path)
    }

    /// The accelerator for an action, or None if it has none.
    pub fn shortcut(&self, action: Action) -> Option<String> {
        match self.shortcuts.get(action.id()) {
            Some(s) if s.is_empty() => None,
            Some(s) => Some(s.clone()),
            None => action.default_shortcut().map(str::to_string),
        }
    }

    pub fn is_ignored(&self, app_id: &str) -> bool {
        self.ignored_apps.iter().any(|a| a.eq_ignore_ascii_case(app_id))
    }

    pub fn history_limit(&self) -> usize {
        self.history_limit.max(10)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_macos() {
        let p = Preferences::default();
        assert_eq!(p.overlay_timeout, 20);
        assert_eq!(p.history_limit, 500);
        assert!(p.is_ignored("1password.exe"));
    }

    #[test]
    fn shortcuts_fall_back_to_defaults_and_can_be_cleared() {
        let mut p = Preferences::default();
        assert_eq!(p.shortcut(Action::AllInOne).as_deref(), Some("Ctrl+Alt+Shift+A"));
        assert_eq!(p.shortcut(Action::Measure), None);
        p.shortcuts.insert("allInOne".into(), String::new());
        p.shortcuts.insert("measure".into(), "Ctrl+Alt+M".into());
        assert_eq!(p.shortcut(Action::AllInOne), None);
        assert_eq!(p.shortcut(Action::Measure).as_deref(), Some("Ctrl+Alt+M"));
    }

    #[test]
    fn partial_files_keep_other_defaults() {
        let p: Preferences = serde_json::from_str(r#"{"historyLimit": 50}"#).unwrap();
        assert_eq!(p.history_limit, 50);
        assert!(p.show_overlay);
        assert_eq!(Preferences { history_limit: 3, ..p }.history_limit(), 10);
    }
}
