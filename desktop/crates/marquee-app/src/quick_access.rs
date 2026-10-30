//! Quick Access: after a capture, a small stack of thumbnails in the bottom-left corner of the
//! display (ui/quick-access.html), with Copy, Save, Open and Close. It hides on its own after
//! Settings → "Hide thumbnail after", and can be tucked against the screen's edge.

use std::sync::Mutex;

use serde::Serialize;
use tauri::{
    AppHandle, Emitter, LogicalSize, Manager, PhysicalPosition, State, WebviewUrl, WebviewWindowBuilder,
};

use crate::library::ItemInfo;
use crate::AppState;

const LABEL: &str = "quick-access";
/// The window's width in logical pixels; its height follows the stack.
pub const WIDTH: f64 = 268.0;
/// How much stays on screen when it's tucked away.
const TUCKED: f64 = 26.0;
const MARGIN: f64 = 14.0;
const MAX_ITEMS: usize = 4;

#[derive(Default)]
pub struct QuickAccess {
    state: Mutex<Stack>,
}

#[derive(Default)]
struct Stack {
    items: Vec<ItemInfo>,
    tucked: bool,
    /// Where the last capture was, to pick its display.
    anchor: Option<(f64, f64)>,
    height: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    items: Vec<ItemInfo>,
    tucked: bool,
    /// Seconds before a thumbnail hides; 0 means never.
    timeout: u32,
}

/// Shows a new capture on top of the stack.
pub fn show(app: &AppHandle, item: ItemInfo, anchor: Option<(i32, i32)>) {
    let qa = app.state::<QuickAccess>();
    {
        let mut stack = qa.state.lock().unwrap();
        stack.items.insert(0, item);
        stack.items.truncate(MAX_ITEMS);
        stack.tucked = false;
        if let Some((x, y)) = anchor {
            stack.anchor = Some((x as f64, y as f64));
        }
    }
    if app.get_webview_window(LABEL).is_none() {
        // The page asks for the stack when it loads, then lays itself out.
        let built = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::App("quick-access.html".into()))
            .title("Marquee Quick Access")
            .inner_size(WIDTH, 120.0)
            .decorations(false)
            .resizable(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .focused(false)
            .visible(false)
            .build();
        match built {
            Ok(window) => crate::window::round_corners(&window),
            Err(e) => eprintln!("Marquee: couldn't open Quick Access: {e}"),
        }
    } else {
        let _ = app.emit_to(LABEL, "quick-access-changed", ());
    }
}

/// Removes a deleted capture from the stack.
pub fn forget(app: &AppHandle, id: &str) {
    if let Some(qa) = app.try_state::<QuickAccess>() {
        qa.state.lock().unwrap().items.retain(|i| i.item.id != id);
        let _ = app.emit_to(LABEL, "quick-access-changed", ());
    }
}

pub fn forget_all(app: &AppHandle) {
    if let Some(qa) = app.try_state::<QuickAccess>() {
        qa.state.lock().unwrap().items.clear();
        let _ = app.emit_to(LABEL, "quick-access-changed", ());
    }
}

#[tauri::command]
pub fn quick_access_items(qa: State<QuickAccess>, app_state: State<AppState>) -> Snapshot {
    let stack = qa.state.lock().unwrap();
    Snapshot {
        items: stack.items.clone(),
        tucked: stack.tucked,
        timeout: app_state.prefs.lock().unwrap().overlay_timeout,
    }
}

#[tauri::command]
pub fn quick_access_dismiss(app: AppHandle, qa: State<QuickAccess>, id: String) {
    qa.state.lock().unwrap().items.retain(|i| i.item.id != id);
    let _ = app.emit_to(LABEL, "quick-access-changed", ());
}

#[tauri::command]
pub fn quick_access_tuck(app: AppHandle, qa: State<QuickAccess>, tucked: bool) {
    let height = {
        let mut stack = qa.state.lock().unwrap();
        stack.tucked = tucked;
        stack.height
    };
    place(&app, &qa, height);
}

/// The page's height after it laid out the stack: size and place the window, or hide it when
/// the stack is empty.
#[tauri::command]
pub fn quick_access_layout(app: AppHandle, qa: State<QuickAccess>, height: f64) {
    qa.state.lock().unwrap().height = height;
    place(&app, &qa, height);
}

fn place(app: &AppHandle, qa: &State<QuickAccess>, height: f64) {
    let Some(window) = app.get_webview_window(LABEL) else { return };
    let (empty, tucked, anchor) = {
        let stack = qa.state.lock().unwrap();
        (stack.items.is_empty(), stack.tucked, stack.anchor)
    };
    if empty || height < 1.0 {
        let _ = window.hide();
        return;
    }
    let monitor = anchor
        .and_then(|(x, y)| app.monitor_from_point(x, y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let _ = window.set_size(LogicalSize::new(WIDTH, height));
    if let Some(monitor) = monitor {
        let scale = monitor.scale_factor();
        let area = monitor.work_area();
        let x = if tucked {
            area.position.x as f64 - (WIDTH - TUCKED) * scale
        } else {
            area.position.x as f64 + MARGIN * scale
        };
        let y = area.position.y as f64 + area.size.height as f64 - (height + MARGIN) * scale;
        let _ = window.set_position(PhysicalPosition::new(x as i32, y as i32));
    }
    let _ = window.show();
}
