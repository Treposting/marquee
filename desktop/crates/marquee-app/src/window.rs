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
