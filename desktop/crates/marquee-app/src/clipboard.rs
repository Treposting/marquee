//! Clipboard history on Windows: watches the clipboard, stores what's copied in marquee-core's
//! `History` (images as PNG files), and serves the Clipboard page and the Clipboard History
//! panel (ui/clipboard-panel.html), which pastes into the app you were using.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicIsize, AtomicU32, Ordering};
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use arboard::{Clipboard, ImageData};
use marquee_core::clip::{ClipFilter, ClipItem, ClipKind};
use marquee_core::history::{self, History};
use serde::Serialize;
use tauri::{
    AppHandle, Emitter, LogicalSize, Manager, PhysicalPosition, State, WebviewUrl, WebviewWindowBuilder,
};
use uuid::Uuid;
use xcap::image::RgbaImage;

use crate::{platform, AppState};

const PANEL: &str = "clipboard-panel";
/// The panel's height in logical pixels; it spans the width of the display.
const PANEL_HEIGHT: f64 = 300.0;

pub struct ClipState {
    history: Mutex<History>,
    dir: PathBuf,
}

/// The clipboard change we made ourselves (copying from history), so it isn't stored again.
static OWN_CHANGE: AtomicU32 = AtomicU32::new(0);
/// The window that was in front when the panel opened, to paste into.
static PASTE_TARGET: AtomicIsize = AtomicIsize::new(0);

/// An item as the pages show it.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipInfo {
    #[serde(flatten)]
    item: ClipItem,
    /// Full path of the image file, for image items.
    image_path: Option<String>,
}

impl ClipState {
    fn history_path(&self) -> PathBuf {
        self.dir.join("history.json")
    }

    fn images_dir(&self) -> PathBuf {
        self.dir.join("images")
    }

    fn save(&self, history: &History) {
        if let Err(e) = history.save(&self.history_path()) {
            eprintln!("Marquee: couldn't save clipboard history: {e}");
        }
    }

    fn delete_images(&self, names: &[String]) {
        for name in names {
            let _ = std::fs::remove_file(self.images_dir().join(name));
        }
    }
}

pub fn init(app: &AppHandle) -> tauri::Result<()> {
    let dir = app.path().app_data_dir()?.join("Clipboard");
    let history = History::load(&dir.join("history.json")).unwrap_or_else(|e| {
        eprintln!("Marquee: couldn't read clipboard history, starting fresh: {e}");
        History::default()
    });
    app.manage(ClipState { history: Mutex::new(history), dir });

    let app = app.clone();
    thread::spawn(move || watch(app));
    Ok(())
}

/// Checks the clipboard's change counter a few times a second and stores what's new.
fn watch(app: AppHandle) {
    let mut last = platform::clipboard_sequence();
    loop {
        thread::sleep(Duration::from_millis(300));
        let sequence = platform::clipboard_sequence();
        if sequence == last {
            continue;
        }
        last = sequence;
        if sequence == OWN_CHANGE.load(Ordering::SeqCst) {
            continue;
        }
        // Let the copying app finish writing every format before reading.
        thread::sleep(Duration::from_millis(60));
        if record(&app) {
            let _ = app.emit("clipboard-changed", ());
        }
    }
}

/// Stores the clipboard's current content, unless history is paused, the content is marked
/// private, or it comes from an ignored app. Returns whether history changed.
fn record(app: &AppHandle) -> bool {
    let prefs = app.state::<AppState>().prefs.lock().unwrap().clone();
    if prefs.monitor_paused || platform::is_private() {
        return false;
    }
    let source = platform::source_app();
    if source.as_ref().is_some_and(|s| prefs.is_ignored(&s.id)) {
        return false;
    }
    let Ok(mut clipboard) = Clipboard::new() else { return false };
    let state = app.state::<ClipState>();
    let limit = prefs.history_limit();

    let files: Vec<String> = clipboard
        .get()
        .file_list()
        .unwrap_or_default()
        .into_iter()
        .map(|p| p.display().to_string())
        .collect();
    let removed = if !files.is_empty() {
        state.history.lock().unwrap().add_files(&files, source.as_ref(), limit)
    } else if let Some(text) = clipboard.get_text().ok().filter(|t| !t.trim().is_empty()) {
        state.history.lock().unwrap().add_text(&text, source.as_ref(), limit)
    } else if let Ok(image) = clipboard.get_image() {
        let hash = history::hash(&image.bytes);
        if state.history.lock().unwrap().contains(&hash) {
            state.history.lock().unwrap().add_image(hash, String::new(), source.as_ref(), limit)
        } else {
            let Some(name) = save_image(&state.images_dir(), &image) else { return false };
            state.history.lock().unwrap().add_image(hash, name, source.as_ref(), limit)
        }
    } else {
        return false;
    };
    let removed: Vec<String> = removed.into_iter().filter(|n| !n.is_empty()).collect();
    state.delete_images(&removed);
    let history = state.history.lock().unwrap();
    state.save(&history);
    true
}

fn save_image(dir: &Path, image: &ImageData) -> Option<String> {
    let rgba = RgbaImage::from_raw(image.width as u32, image.height as u32, image.bytes.to_vec())?;
    std::fs::create_dir_all(dir).ok()?;
    let name = format!("{}.png", Uuid::new_v4());
    rgba.save(dir.join(&name)).ok()?;
    Some(name)
}

/// Puts a history item back on the clipboard, without storing it again.
fn write(state: &ClipState, item: &ClipItem) -> Result<(), String> {
    let mut clipboard = Clipboard::new().map_err(|e| e.to_string())?;
    let result = match item.kind {
        ClipKind::Text | ClipKind::Link => clipboard.set_text(item.text.clone().unwrap_or_default()),
        ClipKind::File => clipboard.set().file_list(item.file_paths.as_deref().unwrap_or_default()),
        ClipKind::Image => {
            let name = item.image_name.as_deref().ok_or("That image is missing.")?;
            let image = xcap::image::open(state.images_dir().join(name))
                .map_err(|e| format!("Couldn't open the image: {e}"))?
                .to_rgba8();
            let data = ImageData {
                width: image.width() as usize,
                height: image.height() as usize,
                bytes: image.into_raw().into(),
            };
            clipboard.set_image(data)
        }
    };
    OWN_CHANGE.store(platform::clipboard_sequence(), Ordering::SeqCst);
    result.map_err(|e| format!("Couldn't copy it: {e}"))
}

fn parse_id(id: &str) -> Result<Uuid, String> {
    Uuid::parse_str(id).map_err(|_| "Unknown item.".to_string())
}

fn changed(app: &AppHandle, state: &ClipState, history: &History) {
    state.save(history);
    let _ = app.emit("clipboard-changed", ());
}

// MARK: Commands

#[tauri::command]
pub fn clip_list(state: State<ClipState>, filter: String, query: String) -> Vec<ClipInfo> {
    let filter = match filter.as_str() {
        "text" => ClipFilter::Text,
        "links" => ClipFilter::Links,
        "images" => ClipFilter::Images,
        "files" => ClipFilter::Files,
        "pinned" => ClipFilter::Pinned,
        _ => ClipFilter::All,
    };
    let images = state.images_dir();
    let history = state.history.lock().unwrap();
    history
        .matching(filter, &query)
        .into_iter()
        .map(|item| ClipInfo {
            item: item.clone(),
            image_path: item.image_name.as_ref().map(|n| images.join(n).display().to_string()),
        })
        .collect()
}

#[tauri::command]
pub async fn clip_copy(app: AppHandle, state: State<'_, ClipState>, id: String) -> Result<(), String> {
    let id = parse_id(&id)?;
    let item = state.history.lock().unwrap().get(id).cloned().ok_or("That item is gone.")?;
    write(&state, &item)?;
    let mut history = state.history.lock().unwrap();
    history.touch(id);
    changed(&app, &state, &history);
    Ok(())
}

/// Copies an item, closes the panel and pastes into the app that was in front (or just leaves
/// it on the clipboard, when "Paste into the app you were using" is off).
#[tauri::command]
pub async fn clip_paste(app: AppHandle, state: State<'_, ClipState>, id: String) -> Result<(), String> {
    clip_copy(app.clone(), state, id).await?;
    if let Some(panel) = app.get_webview_window(PANEL) {
        let _ = panel.hide();
    }
    if app.state::<AppState>().prefs.lock().unwrap().auto_paste {
        platform::paste_into(PASTE_TARGET.load(Ordering::SeqCst));
    }
    Ok(())
}

#[tauri::command]
pub fn clip_pin(app: AppHandle, state: State<ClipState>, id: String) -> Result<(), String> {
    let mut history = state.history.lock().unwrap();
    history.toggle_pin(parse_id(&id)?);
    changed(&app, &state, &history);
    Ok(())
}

#[tauri::command]
pub fn clip_delete(app: AppHandle, state: State<ClipState>, id: String) -> Result<(), String> {
    let mut history = state.history.lock().unwrap();
    let removed = history.remove(parse_id(&id)?);
    state.delete_images(&removed);
    changed(&app, &state, &history);
    Ok(())
}

/// Clears history; pinned items stay.
#[tauri::command]
pub fn clip_clear(app: AppHandle, state: State<ClipState>) {
    let mut history = state.history.lock().unwrap();
    let removed = history.clear(true);
    state.delete_images(&removed);
    changed(&app, &state, &history);
}

#[tauri::command]
pub fn clip_close_panel(app: AppHandle) {
    if let Some(panel) = app.get_webview_window(PANEL) {
        let _ = panel.hide();
    }
}

// MARK: Panel

/// Creates the (hidden) panel ahead of time, so the shortcut opens it at once.
pub fn prewarm(app: &AppHandle) {
    if app.get_webview_window(PANEL).is_some() {
        return;
    }
    let built = WebviewWindowBuilder::new(app, PANEL, WebviewUrl::App("clipboard-panel.html".into()))
        .title("Marquee clipboard history")
        .decorations(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .focused(false)
        .visible(false)
        .build();
    let Ok(panel) = built else { return };
    crate::window::round_corners(&panel);
    // Clicking elsewhere closes it, like a menu.
    let handle = panel.clone();
    panel.on_window_event(move |event| {
        if let tauri::WindowEvent::Focused(false) = event {
            let _ = handle.hide();
        }
    });
}

/// Opens the Clipboard History panel along the bottom of the display under the pointer, or
/// closes it if it's open.
pub fn toggle_panel(app: &AppHandle) {
    if let Some(panel) = app.get_webview_window(PANEL) {
        if panel.is_visible().unwrap_or(false) {
            let _ = panel.hide();
            return;
        }
    }
    PASTE_TARGET.store(platform::foreground_window(), Ordering::SeqCst);
    prewarm(app);
    let Some(panel) = app.get_webview_window(PANEL) else { return };
    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    if let Some(monitor) = monitor {
        let scale = monitor.scale_factor();
        let area = monitor.work_area();
        let margin = 12.0 * scale;
        let width = (area.size.width as f64 - 2.0 * margin) / scale;
        let _ = panel.set_size(LogicalSize::new(width, PANEL_HEIGHT));
        let _ = panel.set_position(PhysicalPosition::new(
            (area.position.x as f64 + margin) as i32,
            (area.position.y as f64 + area.size.height as f64 - PANEL_HEIGHT * scale - margin) as i32,
        ));
    }
    let _ = panel.emit("clipboard-panel-open", ());
    let _ = panel.show();
    let _ = panel.set_focus();
}
