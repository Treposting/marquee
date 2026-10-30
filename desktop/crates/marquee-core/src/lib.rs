//! Platform-independent logic for Marquee on Windows and Linux: clipboard history, settings,
//! shortcuts, the capture library and file names, the shutter sound and small helpers, ported from the macOS
//! app so both behave the same.

pub mod age;
pub mod capture;
pub mod clip;
pub mod colors;
pub mod history;
pub mod library;
pub mod linkmeta;
pub mod prefs;
pub mod shortcuts;
pub mod sound;
pub mod update;
