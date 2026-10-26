//! Runs an action from the tray, a shortcut or the window. Each feature arrives in a later
//! phase; until then the window opens on Home and says what's coming.

use marquee_core::shortcuts::Action;
use tauri::AppHandle;

use crate::window;

/// Whether the action works yet on this platform.
pub fn is_available(_action: Action) -> bool {
    // Phase 2 onward: capture, clipboard, tools and recording.
    false
}

pub fn perform(app: &AppHandle, action: Action) {
    if !is_available(action) {
        window::show_main(app, Some(action));
    }
}
