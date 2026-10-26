//! The Marquee window: Home, Library, Clipboard, Colors and Settings, drawn by `ui/`.

use std::sync::Mutex;

use marquee_core::shortcuts::Action;
use tauri::{AppHandle, Emitter, Manager, Runtime, WebviewUrl, WebviewWindowBuilder};

/// The backdrop behind the window's web content: "mica", "acrylic" or "none" (solid). The page
/// asks for it on load and draws a solid background when there's none.
#[derive(Default)]
pub struct Material(pub Mutex<&'static str>);

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
    // Mica shows the desktop's tint through the window, like Windows 11's own apps.
    #[cfg(windows)]
    let builder = builder.transparent(true);
    let window = builder.build()?;
    let material = backdrop(&window);
    app.manage(Material::default());
    *app.state::<Material>().0.lock().unwrap() = material;
    Ok(window)
}

/// Mica on Windows 11, acrylic on Windows 10, otherwise nothing.
#[allow(unused_variables)]
fn backdrop<R: Runtime>(window: &tauri::WebviewWindow<R>) -> &'static str {
    #[cfg(windows)]
    {
        if window_vibrancy::apply_mica(window, None).is_ok() {
            return "mica";
        }
        if window_vibrancy::apply_acrylic(window, Some((32, 32, 36, 160))).is_ok() {
            return "acrylic";
        }
    }
    "none"
}
