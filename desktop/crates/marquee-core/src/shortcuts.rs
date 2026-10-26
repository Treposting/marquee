//! Actions that can have a global shortcut. Only All-in-One and Clipboard History have one out
//! of the box, like on macOS. Both use Ctrl+Alt+Shift: Ctrl+Shift+V (the closest match for ⇧⌘V)
//! already means "paste as plain text" in many Windows apps.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Action {
    AllInOne,
    CaptureArea,
    CaptureWindow,
    CaptureFullscreen,
    CaptureTimed,
    CaptureText,
    CaptureScrolling,
    RecordArea,
    RecordScreen,
    Measure,
    PickColor,
    ClipboardHistory,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Category {
    Capture,
    Record,
    Tools,
    Clipboard,
}

impl Action {
    pub const ALL: [Action; 12] = [
        Action::AllInOne,
        Action::CaptureArea,
        Action::CaptureWindow,
        Action::CaptureFullscreen,
        Action::CaptureTimed,
        Action::CaptureText,
        Action::CaptureScrolling,
        Action::RecordArea,
        Action::RecordScreen,
        Action::Measure,
        Action::PickColor,
        Action::ClipboardHistory,
    ];

    pub fn id(self) -> &'static str {
        match self {
            Action::AllInOne => "allInOne",
            Action::CaptureArea => "captureArea",
            Action::CaptureWindow => "captureWindow",
            Action::CaptureFullscreen => "captureFullscreen",
            Action::CaptureTimed => "captureTimed",
            Action::CaptureText => "captureText",
            Action::CaptureScrolling => "captureScrolling",
            Action::RecordArea => "recordArea",
            Action::RecordScreen => "recordScreen",
            Action::Measure => "measure",
            Action::PickColor => "pickColor",
            Action::ClipboardHistory => "clipboardHistory",
        }
    }

    pub fn from_id(id: &str) -> Option<Action> {
        Action::ALL.into_iter().find(|a| a.id() == id)
    }

    pub fn title(self) -> &'static str {
        match self {
            Action::AllInOne => "All-in-One",
            Action::CaptureArea => "Capture Area",
            Action::CaptureWindow => "Capture Window",
            Action::CaptureFullscreen => "Capture Full Screen",
            Action::CaptureTimed => "Capture Full Screen in 5 Seconds",
            Action::CaptureText => "Capture Text (OCR)",
            Action::CaptureScrolling => "Capture Scrolling",
            Action::RecordArea => "Record Area",
            Action::RecordScreen => "Record Screen",
            Action::Measure => "Measure",
            Action::PickColor => "Pick Color",
            Action::ClipboardHistory => "Clipboard History",
        }
    }

    pub fn category(self) -> Category {
        match self {
            Action::RecordArea | Action::RecordScreen => Category::Record,
            Action::Measure | Action::PickColor => Category::Tools,
            Action::ClipboardHistory => Category::Clipboard,
            _ => Category::Capture,
        }
    }

    /// Accelerator in the form the global-shortcut plugin parses.
    pub fn default_shortcut(self) -> Option<&'static str> {
        match self {
            Action::AllInOne => Some("Ctrl+Alt+Shift+A"),
            Action::ClipboardHistory => Some("Ctrl+Alt+Shift+V"),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_round_trip_and_only_two_defaults() {
        for a in Action::ALL {
            assert_eq!(Action::from_id(a.id()), Some(a));
        }
        let defaults = Action::ALL.iter().filter(|a| a.default_shortcut().is_some()).count();
        assert_eq!(defaults, 2);
    }
}
