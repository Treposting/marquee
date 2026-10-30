//! The Library page and the files behind it (marquee-core's `Library`), plus what you can do
//! with a capture from the Library or Quick Access: copy, save, open, show in folder, delete.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

use chrono::Utc;
use marquee_core::library::{Library, LibraryItem};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use xcap::image::{imageops, RgbaImage};

use crate::capture;

pub struct LibraryState(pub Mutex<Library>);

/// A library item as the pages show it, with the paths of its files.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ItemInfo {
    #[serde(flatten)]
    pub item: LibraryItem,
    pub path: String,
    pub thumb: String,
}

pub fn init(app: &AppHandle) -> tauri::Result<()> {
    let dir = app.path().app_data_dir()?.join("Library");
    app.manage(LibraryState(Mutex::new(Library::load(&dir))));
    Ok(())
}

fn info(library: &Library, item: &LibraryItem) -> ItemInfo {
    ItemInfo {
        item: item.clone(),
        path: library.image_path(item).display().to_string(),
        thumb: library.thumb_path(item).display().to_string(),
    }
}

/// Keeps a new capture: the PNG, a thumbnail up to 480 pixels on its long side, and the index.
pub fn store(app: &AppHandle, image: &RgbaImage) -> Result<ItemInfo, String> {
    let state = app.state::<LibraryState>();
    let item = LibraryItem::new(image.width(), image.height(), Utc::now());
    let (path, thumb_path) = {
        let library = state.0.lock().unwrap();
        std::fs::create_dir_all(library.dir()).map_err(|e| format!("Couldn't create the library: {e}"))?;
        (library.image_path(&item), library.thumb_path(&item))
    };
    image.save(&path).map_err(|e| format!("Couldn't keep the screenshot: {e}"))?;
    let scale = (480.0 / image.width().max(image.height()) as f32).min(1.0);
    let (w, h) =
        (((image.width() as f32 * scale) as u32).max(1), ((image.height() as f32 * scale) as u32).max(1));
    imageops::thumbnail(image, w, h)
        .save(&thumb_path)
        .map_err(|e| format!("Couldn't keep the thumbnail: {e}"))?;

    let mut library = state.0.lock().unwrap();
    library.add(item.clone()).map_err(|e| format!("Couldn't update the library: {e}"))?;
    let info = info(&library, &item);
    drop(library);
    let _ = app.emit("library-changed", ());
    Ok(info)
}

fn path_of(state: &State<LibraryState>, id: &str) -> Result<PathBuf, String> {
    let library = state.0.lock().unwrap();
    let item = library.get(id).ok_or("That screenshot is no longer in the library.")?;
    Ok(library.image_path(item))
}

/// Copies a library item into the save folder under the usual name. Returns where it went.
pub fn save_copy(app: &AppHandle, path: &Path) -> Result<PathBuf, String> {
    let prefs = app.state::<crate::AppState>().prefs.lock().unwrap().clone();
    let dir = capture::save_folder(app, &prefs);
    std::fs::create_dir_all(&dir).map_err(|e| format!("Couldn't create {}: {e}", dir.display()))?;
    let dest = marquee_core::capture::unique_path(&dir, chrono::Local::now().naive_local());
    std::fs::copy(path, &dest).map_err(|e| format!("Couldn't save {}: {e}", dest.display()))?;
    Ok(dest)
}

#[tauri::command]
pub fn library_list(state: State<LibraryState>) -> Vec<ItemInfo> {
    let library = state.0.lock().unwrap();
    library.items().iter().map(|item| info(&library, item)).collect()
}

#[tauri::command]
pub async fn library_copy(state: State<'_, LibraryState>, id: String) -> Result<(), String> {
    let path = path_of(&state, &id)?;
    let image =
        xcap::image::open(&path).map_err(|e| format!("Couldn't open the screenshot: {e}"))?.to_rgba8();
    capture::copy_image(&image)
}

#[tauri::command]
pub async fn library_save(
    app: AppHandle,
    state: State<'_, LibraryState>,
    id: String,
) -> Result<String, String> {
    let path = path_of(&state, &id)?;
    save_copy(&app, &path).map(|p| p.display().to_string())
}

#[tauri::command]
pub fn library_open(state: State<LibraryState>, id: String) -> Result<(), String> {
    open_path(&path_of(&state, &id)?, false)
}

#[tauri::command]
pub fn library_reveal(state: State<LibraryState>, id: String) -> Result<(), String> {
    open_path(&path_of(&state, &id)?, true)
}

#[tauri::command]
pub fn library_delete(app: AppHandle, state: State<LibraryState>, id: String) -> Result<(), String> {
    state.0.lock().unwrap().remove(&id).map_err(|e| format!("Couldn't delete it: {e}"))?;
    crate::quick_access::forget(&app, &id);
    let _ = app.emit("library-changed", ());
    Ok(())
}

#[tauri::command]
pub fn library_clear(app: AppHandle, state: State<LibraryState>) -> Result<(), String> {
    state.0.lock().unwrap().clear().map_err(|e| format!("Couldn't clear the library: {e}"))?;
    crate::quick_access::forget_all(&app);
    let _ = app.emit("library-changed", ());
    Ok(())
}

/// Opens a file in its default app, or shows it selected in its folder.
fn open_path(path: &Path, reveal: bool) -> Result<(), String> {
    let mut command;
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command = Command::new("explorer");
        if reveal {
            // explorer wants the quotes inside the argument: /select,"C:\…\file.png"
            command.raw_arg(format!("/select,\"{}\"", path.display()));
        } else {
            command.arg(path);
        }
    }
    #[cfg(target_os = "macos")]
    {
        command = Command::new("open");
        if reveal {
            command.arg("-R");
        }
        command.arg(path);
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        command = Command::new("xdg-open");
        command.arg(if reveal { path.parent().unwrap_or(path) } else { path });
    }
    command.spawn().map(|_| ()).map_err(|e| format!("Couldn't open it: {e}"))
}
