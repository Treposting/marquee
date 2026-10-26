//! Platform-independent logic for Marquee on Windows and Linux: clipboard history, settings,
//! shortcuts and small helpers, ported from the macOS app so both behave the same.

pub mod age;
pub mod clip;
pub mod history;
pub mod prefs;
pub mod shortcuts;
