//! Screenshots: the full screen, the front window and the self-timer. What happens after a
//! capture follows Settings → After capture: copy it, save it, play the shutter sound. Area
//! selection, a window picker and the Quick Access thumbnail come next (desktop/README.md).

use std::borrow::Cow;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

use arboard::{Clipboard, ImageData};
use marquee_core::prefs::Preferences;
use tauri::{AppHandle, Manager};
use tauri_plugin_notification::NotificationExt;
use xcap::image::RgbaImage;
use xcap::{Monitor, Window};

use crate::{sound, window, AppState};

#[derive(Debug, Clone, Copy)]
pub enum Target {
    /// The display under the pointer.
    FullScreen,
    /// The window in front (not Marquee's own, the taskbar or a minimized one).
    Window,
    /// The full screen after 5 seconds.
    Timed,
}

/// Ignores a second request while a capture is under way (a held-down shortcut, a double click).
static BUSY: AtomicBool = AtomicBool::new(false);

pub fn run(app: &AppHandle, target: Target) {
    if BUSY.swap(true, Ordering::SeqCst) {
        return;
    }
    // Take the point now: the pointer chooses the display, wherever it moves during the delay.
    let point = app.cursor_position().ok().map(|p| (p.x as i32, p.y as i32));
    let was_showing = window::hide_main(app);
    let app = app.clone();
    thread::spawn(move || {
        let delay = match target {
            Target::Timed => Duration::from_secs(5),
            // Give our window time to leave the screen before it's captured.
            _ if was_showing => Duration::from_millis(300),
            _ => Duration::ZERO,
        };
        thread::sleep(delay);
        let result = match target {
            Target::FullScreen | Target::Timed => capture_screen(point),
            Target::Window => capture_window(),
        };
        match result {
            Ok(image) => {
                if let Err(message) = deliver(&app, &image) {
                    notify(&app, "Couldn't finish the screenshot", &message);
                }
            }
            Err(message) => notify(&app, "Couldn't take the screenshot", &message),
        }
        BUSY.store(false, Ordering::SeqCst);
    });
}

fn capture_screen(point: Option<(i32, i32)>) -> Result<RgbaImage, String> {
    let monitor = match point.and_then(|(x, y)| Monitor::from_point(x, y).ok()) {
        Some(monitor) => monitor,
        None => {
            let monitors = Monitor::all().map_err(|e| e.to_string())?;
            let primary = monitors.iter().position(|m| m.is_primary().unwrap_or(false)).unwrap_or(0);
            monitors.into_iter().nth(primary).ok_or("No display was found.")?
        }
    };
    monitor.capture_image().map_err(|e| e.to_string())
}

fn capture_window() -> Result<RgbaImage, String> {
    let own = std::process::id();
    let windows = Window::all().map_err(|e| e.to_string())?;
    // Front to back. The focused window wins; from the tray menu that's the taskbar, which
    // has no title, so the topmost real window is used instead.
    let usable: Vec<&Window> = windows
        .iter()
        .filter(|w| {
            !w.is_minimized().unwrap_or(true)
                && w.pid().map(|pid| pid != own).unwrap_or(false)
                && w.title().map(|t| !t.trim().is_empty()).unwrap_or(false)
                && w.width().unwrap_or(0) >= 40
                && w.height().unwrap_or(0) >= 40
        })
        .collect();
    let window = usable
        .iter()
        .find(|w| w.is_focused().unwrap_or(false))
        .or_else(|| usable.first())
        .ok_or("There's no window to capture. Open one and try again.")?;
    window.capture_image().map_err(|e| e.to_string())
}

/// Copies and/or saves a new screenshot, plays the shutter and says what happened.
fn deliver(app: &AppHandle, image: &RgbaImage) -> Result<(), String> {
    let prefs = app.state::<AppState>().prefs.lock().unwrap().clone();
    if prefs.play_sound {
        sound::shutter();
    }
    // Until the Quick Access thumbnail arrives, a screenshot that's neither copied nor saved
    // would be lost, so it's copied.
    let copy = prefs.copy_after_capture || !prefs.save_after_capture;
    if copy {
        copy_image(image)?;
    }
    let saved = if prefs.save_after_capture { Some(save_image(app, &prefs, image)?) } else { None };

    let (title, body) = match (&saved, copy) {
        (Some(path), true) => ("Screenshot copied and saved", file_label(path)),
        (Some(path), false) => ("Screenshot saved", file_label(path)),
        (None, _) => ("Screenshot copied", "Paste it anywhere with Ctrl+V.".to_string()),
    };
    notify(app, title, &body);
    Ok(())
}

fn copy_image(image: &RgbaImage) -> Result<(), String> {
    let data = ImageData {
        width: image.width() as usize,
        height: image.height() as usize,
        bytes: Cow::Borrowed(image.as_raw()),
    };
    Clipboard::new()
        .and_then(|mut clipboard| clipboard.set_image(data))
        .map_err(|e| format!("Couldn't copy it to the clipboard: {e}"))
}

fn save_image(app: &AppHandle, prefs: &Preferences, image: &RgbaImage) -> Result<PathBuf, String> {
    let dir = save_folder(app, prefs);
    std::fs::create_dir_all(&dir).map_err(|e| format!("Couldn't create {}: {e}", dir.display()))?;
    let path = marquee_core::capture::unique_path(&dir, chrono::Local::now().naive_local());
    image.save(&path).map_err(|e| format!("Couldn't save {}: {e}", path.display()))?;
    Ok(path)
}

/// Where screenshots are saved: the chosen folder, or Pictures\Marquee.
pub fn save_folder(app: &AppHandle, prefs: &Preferences) -> PathBuf {
    prefs.save_folder.clone().unwrap_or_else(|| {
        let pictures = app.path().picture_dir().or_else(|_| app.path().home_dir()).unwrap_or_default();
        pictures.join("Marquee")
    })
}

fn file_label(path: &std::path::Path) -> String {
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let folder = path.parent().map(|p| p.display().to_string()).unwrap_or_default();
    format!("{name} in {folder}")
}

fn notify(app: &AppHandle, title: &str, body: &str) {
    if let Err(e) = app.notification().builder().title(title).body(body).show() {
        eprintln!("Marquee: {title}: {body} ({e})");
    }
}
