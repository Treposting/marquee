//! Runs an action from the tray, a shortcut or the window. Actions that haven't reached
//! Windows yet open the window on Home, which says they're coming.

use marquee_core::shortcuts::Action;
use tauri::AppHandle;

use crate::capture::{self, Target};
use crate::window;

/// Whether the action works yet on this platform.
pub fn is_available(action: Action) -> bool {
    matches!(
        action,
        Action::AllInOne
            | Action::CaptureArea
            | Action::CaptureWindow
            | Action::CaptureFullscreen
            | Action::CaptureTimed
            | Action::Measure
            | Action::ClipboardHistory
    )
}

pub fn perform(app: &AppHandle, action: Action) {
    match action {
        Action::AllInOne => capture::run(app, Target::AllInOne),
        Action::CaptureArea => capture::run(app, Target::Area),
        Action::CaptureFullscreen => capture::run(app, Target::FullScreen),
        Action::CaptureWindow => capture::run(app, Target::Window),
        Action::CaptureTimed => capture::run(app, Target::Timed),
        Action::Measure => capture::run(app, Target::Measure),
        Action::ClipboardHistory => crate::clipboard::toggle_panel(app),
        _ => window::show_main(app, Some(action)),
    }
}
