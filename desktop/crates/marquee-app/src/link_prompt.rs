//! After Copy Text finds links: a small panel near the bottom of the screen that says what
//! was copied and offers to open each link (ui/link-prompt.html). Enter opens the first, Esc
//! closes it, and it closes by itself when you click elsewhere or leave it for a while. The
//! page can only open the links stored here, by index.

use std::sync::Mutex;

use marquee_core::recognized;
use serde::Serialize;
use tauri::{
    AppHandle, Emitter, LogicalSize, Manager, PhysicalPosition, State, WebviewUrl, WebviewWindowBuilder,
};
use url::Url;

use crate::platform;

const LABEL: &str = "link-prompt";
/// Logical width of the window; the card inside leaves room for its shadow.
const WIDTH: f64 = 460.0;

#[derive(Default)]
pub struct LinkPromptState(Mutex<Option<Prompt>>);

struct Prompt {
    links: Vec<Url>,
    summary: String,
    from_code: bool,
    /// Where the pointer was, to choose the display.
    point: Option<(f64, f64)>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptInfo {
    links: Vec<LinkInfo>,
    summary: String,
    from_code: bool,
}

#[derive(Serialize)]
pub struct LinkInfo {
    text: String,
    email: bool,
}

/// Builds the hidden window ahead of time, so the prompt appears at once.
pub fn prewarm(app: &AppHandle) {
    if app.get_webview_window(LABEL).is_some() {
        return;
    }
    let built = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::App("link-prompt.html".into()))
        .title("Open link")
        .inner_size(WIDTH, 220.0)
        .decorations(false)
        .transparent(true)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .focused(false)
        .visible(false)
        .build();
    let Ok(window) = built else { return };
    let handle = window.clone();
    window.on_window_event(move |event| {
        if let tauri::WindowEvent::Focused(false) = event {
            let _ = handle.hide();
        }
    });
}

pub fn show(app: &AppHandle, links: Vec<Url>, summary: String, from_code: bool) {
    let point = app.cursor_position().ok().map(|p| (p.x, p.y));
    *app.state::<LinkPromptState>().0.lock().unwrap() = Some(Prompt { links, summary, from_code, point });
    prewarm(app);
    // The page renders, measures itself and calls link_prompt_layout, which shows the window.
    let _ = app.emit_to(LABEL, "link-prompt-show", ());
}

#[tauri::command]
pub fn link_prompt_info(state: State<LinkPromptState>) -> Option<PromptInfo> {
    let prompt = state.0.lock().unwrap();
    let prompt = prompt.as_ref()?;
    Some(PromptInfo {
        links: prompt
            .links
            .iter()
            .map(|u| LinkInfo { text: recognized::display_text(u), email: u.scheme() == "mailto" })
            .collect(),
        summary: prompt.summary.clone(),
        from_code: prompt.from_code,
    })
}

/// Sizes the window to the page's content (logical pixels), places it low and centered on
/// the display that was in use, and shows it with the keyboard.
#[tauri::command]
pub fn link_prompt_layout(app: AppHandle, state: State<LinkPromptState>, height: f64) {
    let Some(window) = app.get_webview_window(LABEL) else { return };
    let point = state.0.lock().unwrap().as_ref().and_then(|p| p.point);
    let monitor = point
        .and_then(|(x, y)| app.monitor_from_point(x, y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let _ = window.set_size(LogicalSize::new(WIDTH, height));
    if let Some(monitor) = monitor {
        let scale = monitor.scale_factor();
        let area = monitor.work_area();
        let (w, h) = (WIDTH * scale, height * scale);
        let _ = window.set_position(PhysicalPosition::new(
            (area.position.x as f64 + (area.size.width as f64 - w) / 2.0) as i32,
            (area.position.y as f64 + area.size.height as f64 - h - 40.0 * scale) as i32,
        ));
    }
    let _ = window.show();
    let _ = window.set_focus();
}

#[tauri::command]
pub fn link_prompt_open(app: AppHandle, state: State<LinkPromptState>, index: usize) -> Result<(), String> {
    let url = state
        .0
        .lock()
        .unwrap()
        .as_ref()
        .and_then(|p| p.links.get(index).cloned())
        .ok_or("That link is gone.")?;
    link_prompt_close(app);
    platform::open_url(url.as_str())
}

#[tauri::command]
pub fn link_prompt_close(app: AppHandle) {
    if let Some(window) = app.get_webview_window(LABEL) {
        let _ = window.hide();
    }
}
