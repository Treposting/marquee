//! The annotation editor (ui/annotate.html): arrows, shapes, pen, highlight, text, numbered
//! steps and redaction over a Library item. The page draws everything and sends the finished
//! PNG back to copy it, save it or pin it; saved and pinned results join the Library.

use std::sync::atomic::{AtomicU32, Ordering};

use tauri::ipc::{InvokeBody, Request, Response};
use tauri::{AppHandle, LogicalSize, Manager, WebviewUrl, WebviewWindowBuilder};

use crate::library::{self, LibraryState};
use crate::{capture, pin};

static NEXT: AtomicU32 = AtomicU32::new(1);
/// Room for the toolbar above the image, in logical pixels.
const CHROME: f64 = 72.0;

/// Opens an editor window for a Library item, sized to show it whole when it fits.
pub fn open(app: &AppHandle, id: &str) -> Result<(), String> {
    let (width, height) = {
        let state = app.state::<LibraryState>();
        let library = state.0.lock().unwrap();
        let item = library.get(id).ok_or("That screenshot is no longer in the library.")?;
        (item.width as f64, item.height as f64)
    };
    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let (scale, max_w, max_h) = monitor
        .map(|m| {
            let s = m.scale_factor();
            let area = m.work_area().size;
            (s, area.width as f64 / s * 0.9, area.height as f64 / s * 0.9)
        })
        .unwrap_or((1.0, 1400.0, 900.0));
    let (image_w, image_h) = (width / scale, height / scale);
    let fit = ((max_w - 48.0) / image_w).min((max_h - CHROME - 48.0) / image_h).min(1.0);
    let size = LogicalSize::new(
        (image_w * fit + 48.0).clamp(820.0, max_w.max(820.0)),
        (image_h * fit + CHROME + 48.0).clamp(560.0, max_h.max(560.0)),
    );

    let label = format!("annotate-{}", NEXT.fetch_add(1, Ordering::SeqCst));
    let url = format!("annotate.html?id={id}");
    let window = WebviewWindowBuilder::new(app, label, WebviewUrl::App(url.into()))
        .title("Annotate – Marquee")
        .inner_size(size.width, size.height)
        .min_inner_size(720.0, 480.0)
        .center()
        .visible(false)
        .build()
        .map_err(|e| format!("Couldn't open the editor: {e}"))?;
    let _ = window.set_focus();
    Ok(())
}

/// The original PNG, sent as raw bytes so the page can draw and export it.
#[tauri::command]
pub async fn annotate_image(app: AppHandle, id: String) -> Result<Response, String> {
    let path = library::path_of_id(&app, &id)?;
    std::fs::read(&path).map(Response::new).map_err(|e| format!("Couldn't open the screenshot: {e}"))
}

/// The finished image: the PNG is the request body, the `x-action` header says copy, save or
/// pin. Returns a short message for the editor to show.
#[tauri::command]
pub async fn annotate_export(app: AppHandle, request: Request<'_>) -> Result<String, String> {
    let InvokeBody::Raw(bytes) = request.body() else { return Err("No image.".into()) };
    let action = request.headers().get("x-action").and_then(|v| v.to_str().ok()).unwrap_or("copy");
    let image =
        image::load_from_memory(bytes).map_err(|e| format!("Couldn't read the image: {e}"))?.to_rgba8();
    match action {
        "copy" => capture::copy_image(&image).map(|_| "Copied to the clipboard".into()),
        "save" => {
            let info = library::store(&app, &image)?;
            let dest = library::save_copy(&app, std::path::Path::new(&info.path))?;
            Ok(format!("Saved to {}", dest.parent().map(|d| d.display().to_string()).unwrap_or_default()))
        }
        "pin" => {
            let info = library::store(&app, &image)?;
            pin::open(&app, &info.item.id, None).map(|_| "Pinned".into())
        }
        _ => Err("Unknown action.".into()),
    }
}

/// The editor has drawn the image: show its window.
#[tauri::command]
pub fn annotate_ready(window: tauri::WebviewWindow) {
    let _ = window.show();
    let _ = window.set_focus();
}

#[tauri::command]
pub async fn library_annotate(app: AppHandle, id: String) -> Result<(), String> {
    open(&app, &id)
}
