//! Pinned screenshots: borderless windows that float above everything else. Drag to move,
//! scroll to change opacity, Ctrl+scroll to zoom, double-click or Esc to close, right-click
//! for a menu (ui/pin.html). Every pin shows a Library item.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;

use serde::Serialize;
use tauri::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, State, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder,
};

use crate::library::{self, LibraryState};
use crate::{annotate, capture};

static NEXT: AtomicU32 = AtomicU32::new(1);

/// Which Library item each pin window shows, by window label.
#[derive(Default)]
pub struct Pins(Mutex<HashMap<String, String>>);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PinInfo {
    id: String,
    path: String,
    width: u32,
    height: u32,
}

/// Pins a Library item. `at` is the top-left corner in physical pixels, e.g. where the area
/// was on screen; otherwise the pin opens in the middle of the display under the pointer.
pub fn open(app: &AppHandle, id: &str, at: Option<(i32, i32)>) -> Result<(), String> {
    let (width, height) = {
        let state = app.state::<LibraryState>();
        let library = state.0.lock().unwrap();
        let item = library.get(id).ok_or("That screenshot is no longer in the library.")?;
        (item.width, item.height)
    };
    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten())
        .ok_or("No display found.")?;
    let area = monitor.work_area();
    // Shown at its real size, unless that doesn't fit in most of the screen.
    let fit = (area.size.width as f64 * 0.8 / width as f64)
        .min(area.size.height as f64 * 0.8 / height as f64)
        .min(1.0);
    let size = PhysicalSize::new(
        ((width as f64 * fit).round() as u32).max(40),
        ((height as f64 * fit).round() as u32).max(40),
    );
    let position = at.map(|(x, y)| PhysicalPosition::new(x, y)).unwrap_or_else(|| {
        PhysicalPosition::new(
            area.position.x + (area.size.width as i32 - size.width as i32) / 2,
            area.position.y + (area.size.height as i32 - size.height as i32) / 2,
        )
    });

    let label = format!("pin-{}", NEXT.fetch_add(1, Ordering::SeqCst));
    app.state::<Pins>().0.lock().unwrap().insert(label.clone(), id.to_string());
    let window = WebviewWindowBuilder::new(app, label.clone(), WebviewUrl::App("pin.html".into()))
        .title("Pinned screenshot")
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .visible(false)
        .build()
        .map_err(|e| format!("Couldn't pin it: {e}"))?;
    let _ = window.set_size(size);
    let _ = window.set_position(position);
    let handle = app.clone();
    window.on_window_event(move |event| {
        if let tauri::WindowEvent::Destroyed = event {
            handle.state::<Pins>().0.lock().unwrap().remove(&label);
        }
    });
    Ok(())
}

fn pinned_id(pins: &State<Pins>, window: &WebviewWindow) -> Result<String, String> {
    pins.0.lock().unwrap().get(window.label()).cloned().ok_or_else(|| "This pin is gone.".into())
}

#[tauri::command]
pub fn pin_info(
    window: WebviewWindow,
    pins: State<Pins>,
    library: State<LibraryState>,
) -> Result<PinInfo, String> {
    let id = pinned_id(&pins, &window)?;
    let library = library.0.lock().unwrap();
    let item = library.get(&id).ok_or("That screenshot is no longer in the library.")?;
    Ok(PinInfo {
        path: library.image_path(item).display().to_string(),
        width: item.width,
        height: item.height,
        id,
    })
}

/// The page has the image: show the pin.
#[tauri::command]
pub fn pin_ready(window: WebviewWindow) {
    let _ = window.show();
    let _ = window.set_focus();
}

/// Copy, Save, Annotate or Close, from the pin's menu and keys. Returns a short message.
#[tauri::command]
pub async fn pin_action(
    app: AppHandle,
    window: WebviewWindow,
    pins: State<'_, Pins>,
    action: String,
) -> Result<String, String> {
    let id = pinned_id(&pins, &window)?;
    match action.as_str() {
        "copy" => {
            let path = library::path_of_id(&app, &id)?;
            let image = xcap::image::open(&path).map_err(|e| format!("Couldn't open it: {e}"))?.to_rgba8();
            capture::copy_image(&image).map(|_| "Copied".into())
        }
        "save" => {
            let path = library::path_of_id(&app, &id)?;
            library::save_copy(&app, &path).map(|_| "Saved".into())
        }
        "annotate" => annotate::open(&app, &id).map(|_| String::new()),
        "close" => {
            pins.0.lock().unwrap().remove(window.label());
            let _ = window.close();
            Ok(String::new())
        }
        _ => Err("Unknown action.".into()),
    }
}

/// Zooms the pin by `factor` around its center, keeping it between 40 pixels and the display.
#[tauri::command]
pub fn pin_zoom(window: WebviewWindow, factor: f64) -> Result<(), String> {
    let size = window.inner_size().map_err(|e| e.to_string())?;
    let position = window.outer_position().map_err(|e| e.to_string())?;
    let limit = window
        .current_monitor()
        .ok()
        .flatten()
        .map(|m| (m.size().width as f64, m.size().height as f64))
        .unwrap_or((4000.0, 4000.0));
    let (w, h) = (size.width as f64, size.height as f64);
    let factor = factor.clamp(40.0 / w.min(h), (limit.0 / w).min(limit.1 / h));
    let (nw, nh) = ((w * factor).round(), (h * factor).round());
    let _ = window.set_size(PhysicalSize::new(nw as u32, nh as u32));
    let _ = window.set_position(PhysicalPosition::new(
        position.x + ((w - nw) / 2.0) as i32,
        position.y + ((h - nh) / 2.0) as i32,
    ));
    Ok(())
}

/// The pin's right-click menu, as a native menu so it isn't cut off by a small pin. Its
/// items are "pin:<action>:<window label>"; `menu_event` handles them.
#[tauri::command]
pub fn pin_menu(app: AppHandle, window: WebviewWindow) -> Result<(), String> {
    let label = window.label();
    let item = |action: &str, title: &str, accel: Option<&str>| {
        MenuItem::with_id(&app, format!("pin:{action}:{label}"), title, true, accel)
    };
    let build = || -> tauri::Result<Menu<tauri::Wry>> {
        let opacity = Submenu::with_items(
            &app,
            "Opacity",
            true,
            &[
                &item("opacity-100", "100%", None)?,
                &item("opacity-75", "75%", None)?,
                &item("opacity-50", "50%", None)?,
                &item("opacity-25", "25%", None)?,
            ],
        )?;
        Menu::with_items(
            &app,
            &[
                &item("copy", "Copy", Some("Ctrl+C"))?,
                &item("save", "Save", Some("Ctrl+S"))?,
                &item("annotate", "Annotate", None)?,
                &PredefinedMenuItem::separator(&app)?,
                &opacity,
                &item("zoom-in", "Zoom In", Some("Ctrl+="))?,
                &item("zoom-out", "Zoom Out", Some("Ctrl+-"))?,
                &PredefinedMenuItem::separator(&app)?,
                &item("close", "Close", Some("Esc"))?,
            ],
        )
    };
    let menu = build().map_err(|e| e.to_string())?;
    window.popup_menu(&menu).map_err(|e| e.to_string())
}

/// Runs a pin menu item. The page does the work, so keys and the menu behave the same.
pub fn menu_event(app: &AppHandle, event: &MenuEvent) {
    let Some(rest) = event.id().as_ref().strip_prefix("pin:") else { return };
    let Some((action, label)) = rest.split_once(':') else { return };
    let _ = app.emit_to(label, "pin-command", action.to_string());
}

#[tauri::command]
pub async fn library_pin(app: AppHandle, id: String) -> Result<(), String> {
    open(&app, &id, None)
}
