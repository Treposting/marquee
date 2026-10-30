//! Screenshots: an area, a window, the full screen and the self-timer. Every capture goes into
//! the Library; the rest follows Settings → After capture: copy it, save it, play the shutter
//! sound and show the Quick Access thumbnail (or a notification when that's off).
//!
//! Area and window captures freeze the display under the pointer first, then show that frame
//! in an opaque, full-screen overlay window (ui/overlay.html) to select from. What you select
//! is exactly what was on screen, and the overlay needs no transparency.

use std::borrow::Cow;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use arboard::{Clipboard, ImageData};
use marquee_core::prefs::Preferences;
use serde::{Deserialize, Serialize};
use tauri::{
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, State, WebviewUrl, WebviewWindowBuilder,
};
use tauri_plugin_notification::NotificationExt;
use xcap::image::{imageops, RgbaImage};
use xcap::{Monitor, Window};

use crate::{annotate, library, pin, quick_access, sound, window, AppState};

const OVERLAY: &str = "overlay";
const COUNTDOWN: &str = "countdown";
const TIMER_SECONDS: u32 = 5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    /// Drag over part of the display under the pointer (Space switches to picking a window).
    Area,
    /// Click a window to capture it (Space switches to dragging an area).
    Window,
    /// All-in-One: a toolbar from the start and an editable selection; actions use the full
    /// screen until something is selected.
    AllInOne,
    /// The display under the pointer.
    FullScreen,
    /// The full screen after 5 seconds.
    Timed,
    /// Measure: distances to edges, element sizes and guides over the frozen display.
    Measure,
}

/// Ignores a second request while a capture is under way (a held-down shortcut, a double click,
/// a shortcut pressed while the overlay is up).
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
        if target == Target::Timed {
            countdown(&app, point, TIMER_SECONDS);
        } else if was_showing {
            // Give our window time to leave the screen before it's captured.
            thread::sleep(Duration::from_millis(200));
        }
        match target {
            Target::FullScreen | Target::Timed => finish(
                &app,
                capture_monitor(point).and_then(|m| m.capture_image().map_err(|e| e.to_string())),
                point,
            ),
            Target::Area | Target::Window | Target::AllInOne | Target::Measure => {
                if let Err(message) = open_overlay(&app, point, target) {
                    finish(&app, Err(message), point);
                }
            }
        }
    });
}

/// Shows a small 5-4-3-2-1 countdown in the middle of the display that will be captured, and
/// returns once it has run out and left the screen. It never takes the keyboard, so you can
/// keep working in the app you're capturing.
fn countdown(app: &AppHandle, point: Option<(i32, i32)>, seconds: u32) {
    let shown = capture_monitor(point).ok().and_then(|monitor| {
        let scale = monitor.scale_factor().unwrap_or(1.0) as f64;
        let side = 150.0;
        let (mx, my) = (monitor.x().unwrap_or(0) as f64, monitor.y().unwrap_or(0) as f64);
        let (mw, mh) = (monitor.width().unwrap_or(0) as f64, monitor.height().unwrap_or(0) as f64);
        let url = WebviewUrl::App(format!("countdown.html?s={seconds}").into());
        let window = WebviewWindowBuilder::new(app, COUNTDOWN, url)
            .title("Marquee self-timer")
            .inner_size(side, side)
            .decorations(false)
            .resizable(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .focused(false)
            .background_color(tauri::window::Color(29, 29, 31, 255))
            .build()
            .ok()?;
        window::round_corners(&window);
        let _ = window.set_position(PhysicalPosition::new(
            (mx + (mw - side * scale) / 2.0) as i32,
            (my + (mh - side * scale) / 2.0) as i32,
        ));
        Some(window)
    });
    thread::sleep(Duration::from_secs(seconds as u64));
    if let Some(window) = shown {
        let _ = window.destroy();
        // Let it leave the screen before the capture.
        thread::sleep(Duration::from_millis(200));
    }
}

/// Delivers a capture or reports why there isn't one, and frees the way for the next.
fn finish(app: &AppHandle, result: Result<RgbaImage, String>, point: Option<(i32, i32)>) {
    match result {
        Ok(image) => {
            if let Err(message) = deliver(app, &image, point) {
                notify(app, "Couldn't finish the screenshot", &message);
            }
        }
        Err(message) => notify(app, "Couldn't take the screenshot", &message),
    }
    BUSY.store(false, Ordering::SeqCst);
}

fn capture_monitor(point: Option<(i32, i32)>) -> Result<Monitor, String> {
    if let Some(monitor) = point.and_then(|(x, y)| Monitor::from_point(x, y).ok()) {
        return Ok(monitor);
    }
    let monitors = Monitor::all().map_err(|e| e.to_string())?;
    let primary = monitors.iter().position(|m| m.is_primary().unwrap_or(false)).unwrap_or(0);
    monitors.into_iter().nth(primary).ok_or_else(|| "No display was found.".to_string())
}

// MARK: Overlay

/// A window the overlay can highlight, in the frozen frame's pixels.
#[derive(Debug, Clone, Serialize)]
pub struct WindowRect {
    id: u32,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

/// The frozen display while the overlay is open.
pub struct Frozen {
    image: RgbaImage,
    /// The display's top-left corner on the desktop, in physical pixels.
    origin: (i32, i32),
    /// Listed the first time they're needed (picking a window), not before the overlay shows.
    windows: Option<Vec<WindowRect>>,
    mode: Target,
    /// Where the capture started, for placing Quick Access on the same display.
    point: Option<(i32, i32)>,
}

#[derive(Default)]
pub struct Session(Mutex<Option<Frozen>>);

/// What the overlay page needs before it draws.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OverlayInfo {
    width: u32,
    height: u32,
    /// "area", "window" or "aio" (All-in-One): what the overlay starts in.
    mode: &'static str,
}

/// The overlay's answer.
#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Selection {
    /// A rectangle in the frozen frame's pixels. With `copy` (All-in-One's Copy), it's only
    /// copied to the clipboard and kept in the Library; with `pin` (All-in-One's Pin), it's
    /// kept in the Library and pinned where it was on screen; with `annotate`, it's kept in the
    /// Library and opened in the editor.
    Area {
        x: i64,
        y: i64,
        width: i64,
        height: i64,
        #[serde(default)]
        copy: bool,
        #[serde(default)]
        pin: bool,
        #[serde(default)]
        annotate: bool,
    },
    Window {
        id: u32,
    },
    /// All-in-One's gear: open Settings.
    Settings,
    Cancel,
}

/// Creates the overlay window once, hidden, so a capture only has to show it: building a new
/// WebView2 window for every capture took most of a second.
pub fn prewarm(app: &AppHandle) {
    if app.get_webview_window(OVERLAY).is_some() {
        return;
    }
    let built = WebviewWindowBuilder::new(app, OVERLAY, WebviewUrl::App("overlay.html".into()))
        .title("Marquee capture")
        .decorations(false)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(false)
        .focused(false)
        .visible(false)
        .background_color(tauri::window::Color(0, 0, 0, 255))
        .build();
    match built {
        Ok(overlay) => {
            // If the overlay is closed without answering (Alt+F4), end the session; the next
            // capture builds a new one.
            let handle = app.clone();
            overlay.on_window_event(move |event| {
                if let tauri::WindowEvent::Destroyed = event {
                    if let Some(session) = handle.try_state::<Session>() {
                        if session.0.lock().unwrap().take().is_some() {
                            BUSY.store(false, Ordering::SeqCst);
                        }
                    }
                }
            });
        }
        Err(e) => eprintln!("Marquee: couldn't prepare the capture overlay: {e}"),
    }
}

fn open_overlay(app: &AppHandle, point: Option<(i32, i32)>, mode: Target) -> Result<(), String> {
    let monitor = capture_monitor(point)?;
    let image = monitor.capture_image().map_err(|e| e.to_string())?;
    let origin = (monitor.x().unwrap_or(0), monitor.y().unwrap_or(0));
    let (width, height) = (image.width(), image.height());
    *app.state::<Session>().0.lock().unwrap() = Some(Frozen { image, origin, windows: None, mode, point });

    let fresh = app.get_webview_window(OVERLAY).is_none();
    prewarm(app);
    let overlay = app.get_webview_window(OVERLAY).ok_or("Couldn't open the capture overlay.")?;
    // Exactly over the display: Windows then treats it as full screen and keeps the taskbar
    // behind it, with no slow switch to fullscreen mode.
    let _ = overlay.set_position(PhysicalPosition::new(origin.0, origin.1));
    let _ = overlay.set_size(PhysicalSize::new(width, height));
    // A page that just loaded asks for the session itself; a waiting one is told to start.
    if !fresh {
        let _ = overlay.emit("overlay-start", ());
    }
    Ok(())
}

/// Normal windows on the frozen display, front to back, in the frame's pixels.
fn visible_windows(origin: (i32, i32), width: u32, height: u32) -> Vec<WindowRect> {
    let own = std::process::id();
    let Ok(windows) = Window::all() else { return Vec::new() };
    windows
        .iter()
        .filter(|w| {
            !w.is_minimized().unwrap_or(true)
                && w.pid().map(|pid| pid != own).unwrap_or(false)
                && w.title().map(|t| !t.trim().is_empty()).unwrap_or(false)
        })
        .filter_map(|w| {
            let rect = WindowRect {
                id: w.id().ok()?,
                x: w.x().ok()? - origin.0,
                y: w.y().ok()? - origin.1,
                width: w.width().ok()?,
                height: w.height().ok()?,
            };
            let on_screen = rect.x < width as i32
                && rect.y < height as i32
                && rect.x + rect.width as i32 > 0
                && rect.y + rect.height as i32 > 0;
            (on_screen && rect.width >= 40 && rect.height >= 40).then_some(rect)
        })
        .collect()
}

#[tauri::command]
pub fn overlay_info(session: State<Session>) -> Option<OverlayInfo> {
    let frozen = session.0.lock().unwrap();
    let frozen = frozen.as_ref()?;
    Some(OverlayInfo {
        width: frozen.image.width(),
        height: frozen.image.height(),
        mode: match frozen.mode {
            Target::Window => "window",
            Target::AllInOne => "aio",
            Target::Measure => "measure",
            _ => "area",
        },
    })
}

/// The windows the overlay can highlight. Asked for after the overlay is showing.
#[tauri::command]
pub async fn overlay_windows(app: AppHandle) -> Vec<WindowRect> {
    let Some((origin, width, height)) = app
        .state::<Session>()
        .0
        .lock()
        .unwrap()
        .as_ref()
        .map(|f| (f.origin, f.image.width(), f.image.height()))
    else {
        return Vec::new();
    };
    let windows = visible_windows(origin, width, height);
    if let Some(frozen) = app.state::<Session>().0.lock().unwrap().as_mut() {
        frozen.windows = Some(windows.clone());
    }
    windows
}

/// The frozen frame as raw RGBA bytes, sent without JSON encoding.
#[tauri::command]
pub fn overlay_frame(session: State<Session>) -> tauri::ipc::Response {
    let frozen = session.0.lock().unwrap();
    let bytes = frozen.as_ref().map(|f| f.image.as_raw().clone()).unwrap_or_default();
    tauri::ipc::Response::new(bytes)
}

/// The page has drawn the frame: show the overlay and give it the keyboard.
#[tauri::command]
pub fn overlay_ready(app: AppHandle) {
    if let Some(overlay) = app.get_webview_window(OVERLAY) {
        let _ = overlay.show();
        let _ = overlay.set_focus();
    }
}

#[tauri::command]
pub fn overlay_finish(app: AppHandle, selection: Selection) {
    let frozen = app.try_state::<Session>().and_then(|s| s.0.lock().unwrap().take());
    // Hidden, not closed: the next capture reuses it.
    if let Some(overlay) = app.get_webview_window(OVERLAY) {
        let _ = overlay.hide();
    }
    let Some(frozen) = frozen else { return };
    thread::spawn(move || {
        let result = match selection {
            Selection::Cancel => {
                BUSY.store(false, Ordering::SeqCst);
                return;
            }
            Selection::Settings => {
                BUSY.store(false, Ordering::SeqCst);
                window::show_page(&app, "settings");
                return;
            }
            Selection::Area { x, y, width, height, copy: true, .. } => {
                match crop(&frozen, x, y, width, height).and_then(|image| copy_only(&app, &image)) {
                    Ok(()) => {}
                    Err(message) => notify(&app, "Couldn't copy the screenshot", &message),
                }
                BUSY.store(false, Ordering::SeqCst);
                return;
            }
            Selection::Area { x, y, width, height, pin: true, .. } => {
                let pinned = crop(&frozen, x, y, width, height).and_then(|image| {
                    let info = library::store(&app, &image)?;
                    let at = (frozen.origin.0 + x.max(0) as i32, frozen.origin.1 + y.max(0) as i32);
                    pin::open(&app, &info.item.id, Some(at))
                });
                if let Err(message) = pinned {
                    notify(&app, "Couldn't pin the screenshot", &message);
                }
                BUSY.store(false, Ordering::SeqCst);
                return;
            }
            Selection::Area { x, y, width, height, annotate: true, .. } => {
                let opened = crop(&frozen, x, y, width, height).and_then(|image| {
                    let info = library::store(&app, &image)?;
                    annotate::open(&app, &info.item.id)
                });
                if let Err(message) = opened {
                    notify(&app, "Couldn't open the screenshot for annotating", &message);
                }
                BUSY.store(false, Ordering::SeqCst);
                return;
            }
            Selection::Area { x, y, width, height, .. } => crop(&frozen, x, y, width, height),
            Selection::Window { id } => {
                // Let the overlay leave the screen, then capture the window itself, which leaves
                // out anything overlapping it. Fall back to the frozen frame.
                thread::sleep(Duration::from_millis(120));
                capture_window_by_id(id).or_else(|_| {
                    let rect =
                        frozen.windows.iter().flatten().find(|w| w.id == id).ok_or("That window is gone.")?;
                    crop(&frozen, rect.x as i64, rect.y as i64, rect.width as i64, rect.height as i64)
                })
            }
        };
        finish(&app, result, frozen.point);
    });
}

/// Measure's Ctrl+S: the screen with the measurements drawn on it, as a PNG request body.
/// Ends the session and delivers it like any screenshot (Library, Quick Access…).
#[tauri::command]
pub async fn overlay_capture(app: AppHandle, request: tauri::ipc::Request<'_>) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(bytes) = request.body() else { return Err("No image.".into()) };
    let image =
        image::load_from_memory(bytes).map_err(|e| format!("Couldn't read the image: {e}"))?.to_rgba8();
    let frozen = app.try_state::<Session>().and_then(|s| s.0.lock().unwrap().take());
    if let Some(overlay) = app.get_webview_window(OVERLAY) {
        let _ = overlay.hide();
    }
    let point = frozen.and_then(|f| f.point);
    thread::spawn(move || finish(&app, Ok(image), point));
    Ok(())
}

/// Measure's Ctrl+C: puts a measurement like "140 × 48" on the clipboard.
#[tauri::command]
pub fn overlay_copy_text(text: String) -> Result<(), String> {
    Clipboard::new()
        .and_then(|mut clipboard| clipboard.set_text(text))
        .map_err(|e| format!("Couldn't copy it: {e}"))
}

fn crop(frozen: &Frozen, x: i64, y: i64, width: i64, height: i64) -> Result<RgbaImage, String> {
    let (w, h) = (frozen.image.width(), frozen.image.height());
    let (x, y, width, height) = marquee_core::capture::clamp_rect(x, y, width, height, w, h)
        .ok_or("The selection was too small. Drag to select an area.")?;
    Ok(imageops::crop_imm(&frozen.image, x, y, width, height).to_image())
}

fn capture_window_by_id(id: u32) -> Result<RgbaImage, String> {
    let windows = Window::all().map_err(|e| e.to_string())?;
    let window = windows.iter().find(|w| w.id().ok() == Some(id)).ok_or("That window is gone.")?;
    window.capture_image().map_err(|e| e.to_string())
}

// MARK: After capture

/// Keeps a new screenshot in the Library, copies and/or saves it, plays the shutter, then
/// shows it in Quick Access (or says what happened in a notification).
fn deliver(app: &AppHandle, image: &RgbaImage, point: Option<(i32, i32)>) -> Result<(), String> {
    let prefs = app.state::<AppState>().prefs.lock().unwrap().clone();
    if prefs.play_sound {
        sound::shutter();
    }
    let item = library::store(app, image)?;
    // Without Quick Access, a screenshot that's neither copied nor saved would be easy to miss
    // (it's only in the Library), so it's copied.
    let copy = prefs.copy_after_capture || (!prefs.save_after_capture && !prefs.show_overlay);
    if copy {
        copy_image(image)?;
    }
    let saved = if prefs.save_after_capture {
        Some(library::save_copy(app, std::path::Path::new(&item.path))?)
    } else {
        None
    };

    if prefs.show_overlay {
        quick_access::show(app, item, point);
        return Ok(());
    }
    let (title, body) = match (&saved, copy) {
        (Some(path), true) => ("Screenshot copied and saved", file_label(path)),
        (Some(path), false) => ("Screenshot saved", file_label(path)),
        (None, _) => ("Screenshot copied", "Paste it anywhere with Ctrl+V.".to_string()),
    };
    notify(app, title, &body);
    Ok(())
}

/// All-in-One's Copy: straight to the clipboard (and the Library), with the shutter and a
/// short notification instead of Quick Access.
fn copy_only(app: &AppHandle, image: &RgbaImage) -> Result<(), String> {
    if app.state::<AppState>().prefs.lock().unwrap().play_sound {
        sound::shutter();
    }
    library::store(app, image)?;
    copy_image(image)?;
    notify(app, "Copied to the clipboard", "Paste it anywhere with Ctrl+V.");
    Ok(())
}

pub fn copy_image(image: &RgbaImage) -> Result<(), String> {
    let data = ImageData {
        width: image.width() as usize,
        height: image.height() as usize,
        bytes: Cow::Borrowed(image.as_raw()),
    };
    Clipboard::new()
        .and_then(|mut clipboard| clipboard.set_image(data))
        .map_err(|e| format!("Couldn't copy it to the clipboard: {e}"))
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
