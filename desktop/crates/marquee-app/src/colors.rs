//! The color picker's results: copying a picked color in the chosen format, and the history
//! the Colors page shows (`app_data/colors.json`). Picking itself happens on the capture
//! overlay (ui/color.js).

use std::path::PathBuf;
use std::sync::Mutex;

use arboard::Clipboard;
use marquee_core::colors::{ColorHistory, Rgb};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};

use crate::AppState;

pub struct ColorState {
    history: Mutex<ColorHistory>,
    path: PathBuf,
}

/// A color as the Colors page shows it.
#[derive(Serialize)]
pub struct ColorInfo {
    hex: String,
    rgb: String,
    hsl: String,
    /// In the format chosen in Settings, which is what clicking it copies.
    text: String,
}

pub fn init(app: &AppHandle) -> tauri::Result<()> {
    let path = app.path().app_data_dir()?.join("colors.json");
    let history = ColorHistory::load(&path).unwrap_or_default();
    app.manage(ColorState { history: Mutex::new(history), path });
    Ok(())
}

fn copy_text(app: &AppHandle, color: Rgb) -> Result<String, String> {
    let format = app.state::<AppState>().prefs.lock().unwrap().color_format;
    let text = color.format(format);
    Clipboard::new()
        .and_then(|mut c| c.set_text(text.clone()))
        .map_err(|e| format!("Couldn't copy it: {e}"))?;
    Ok(text)
}

fn changed(app: &AppHandle, state: &ColorState, history: &ColorHistory) {
    if let Err(e) = history.save(&state.path) {
        eprintln!("Marquee: couldn't save colors: {e}");
    }
    let _ = app.emit("colors-changed", ());
}

/// A color picked on screen: keep it and copy it. Returns what was copied.
pub fn picked(app: &AppHandle, color: Rgb) -> Result<String, String> {
    let state = app.state::<ColorState>();
    {
        let mut history = state.history.lock().unwrap();
        history.add(color);
        changed(app, &state, &history);
    }
    copy_text(app, color)
}

fn parse(hex: &str) -> Result<Rgb, String> {
    Rgb::parse_hex(hex).ok_or_else(|| "That isn't a color.".into())
}

#[tauri::command]
pub fn colors_list(app: AppHandle, state: State<ColorState>) -> Vec<ColorInfo> {
    let format = app.state::<AppState>().prefs.lock().unwrap().color_format;
    let history = state.history.lock().unwrap();
    history
        .colors
        .iter()
        .map(|c| {
            let (h, s, l) = c.color.hsl();
            ColorInfo {
                hex: c.color.hex(),
                rgb: format!("{}, {}, {}", c.color.r, c.color.g, c.color.b),
                hsl: format!("{h}°, {s}%, {l}%"),
                text: c.color.format(format),
            }
        })
        .collect()
}

#[tauri::command]
pub fn color_copy(app: AppHandle, hex: String) -> Result<String, String> {
    copy_text(&app, parse(&hex)?)
}

#[tauri::command]
pub fn color_delete(app: AppHandle, state: State<ColorState>, hex: String) -> Result<(), String> {
    let mut history = state.history.lock().unwrap();
    history.remove(parse(&hex)?);
    changed(&app, &state, &history);
    Ok(())
}

#[tauri::command]
pub fn colors_clear(app: AppHandle, state: State<ColorState>) {
    let mut history = state.history.lock().unwrap();
    history.clear();
    changed(&app, &state, &history);
}
