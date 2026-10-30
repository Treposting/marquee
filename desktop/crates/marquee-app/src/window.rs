//! The Marquee window: Home, Library, Clipboard, Colors and Settings, drawn by `ui/`.

use std::sync::Mutex;

use marquee_core::shortcuts::Action;
use tauri::{AppHandle, Emitter, Manager, Runtime, WebviewUrl, WebviewWindowBuilder};

/// An action that isn't available yet, waiting to be explained by a page still loading.
#[derive(Default)]
pub struct Pending(pub Mutex<Option<&'static str>>);

/// Shows the window, creating it the first time. With an action, Home explains when it arrives.
pub fn show_main<R: Runtime>(app: &AppHandle<R>, pending: Option<Action>) {
    if let Some(action) = pending {
        app.manage(Pending::default());
        *app.state::<Pending>().0.lock().unwrap() = Some(action.title());
    }
    let window = match app.get_webview_window("main") {
        Some(window) => window,
        None => match build(app) {
            Ok(window) => window,
            Err(e) => {
                eprintln!("Marquee: couldn't open the window: {e}");
                return;
            }
        },
    };
    let _ = window.unminimize();
    let _ = window.show();
    let _ = window.set_focus();
    // A page that's already loaded hears about it right away; a new one asks on load.
    if pending.is_some() {
        let _ = window.emit("coming-soon", ());
    }
}

/// Shows the window on one of its pages ("home", "library", "clipboard", "colors", "settings").
pub fn show_page<R: Runtime>(app: &AppHandle<R>, page: &'static str) {
    app.manage(PendingPage::default());
    *app.state::<PendingPage>().0.lock().unwrap() = Some(page);
    show_main(app, None);
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.emit("show-page", page);
    }
}

/// A page to open, waiting for a window that's still loading.
#[derive(Default)]
pub struct PendingPage(pub Mutex<Option<&'static str>>);

/// Hides the window if it's on screen, so a capture doesn't include it. Returns whether it was.
pub fn hide_main<R: Runtime>(app: &AppHandle<R>) -> bool {
    let Some(window) = app.get_webview_window("main") else { return false };
    let showing = window.is_visible().unwrap_or(false) && !window.is_minimized().unwrap_or(false);
    if showing {
        let _ = window.hide();
    }
    showing
}

/// Rounded corners for Marquee's small borderless windows (Quick Access, the self-timer), as
/// Windows 11 draws them for normal windows. Does nothing on Windows 10 or other systems.
#[allow(unused_variables)]
pub fn round_corners<R: Runtime>(window: &tauri::WebviewWindow<R>) {
    #[cfg(windows)]
    if let Ok(hwnd) = window.hwnd() {
        use windows_sys::Win32::Graphics::Dwm::{
            DwmSetWindowAttribute, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND,
        };
        let preference = DWMWCP_ROUND;
        // SAFETY: a valid window handle, and a pointer to a value of the size we pass.
        unsafe {
            DwmSetWindowAttribute(
                hwnd.0 as _,
                DWMWA_WINDOW_CORNER_PREFERENCE as u32,
                (&preference as *const i32).cast(),
                std::mem::size_of::<i32>() as u32,
            );
        }
    }
}

fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<tauri::WebviewWindow<R>> {
    let builder = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
        .title("Marquee")
        .inner_size(1040.0, 700.0)
        .min_inner_size(760.0, 520.0)
        .center()
        .visible(false);
    // Opaque on purpose: a transparent WebView2 window with Mica or acrylic behind it kept the
    // compositor busy enough to slow the whole system and leave a second cursor on screen.
    builder.build()
}
