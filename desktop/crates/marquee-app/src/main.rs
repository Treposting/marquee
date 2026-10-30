// No console window in release builds on Windows.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

//! Marquee for Windows: a tray app with global shortcuts, screenshots and the Marquee window.
//! The rest (area capture, clipboard, recording…) is added phase by phase (desktop/README.md).

mod actions;
mod annotate;
mod capture;
mod clipboard;
mod library;
mod pin;
mod platform;
mod previews;
mod quick_access;
mod shortcuts;
mod sound;
mod tray;
mod updater;
mod window;

use std::path::PathBuf;
use std::sync::Mutex;

use marquee_core::prefs::Preferences;
use marquee_core::shortcuts::Action;
use serde::Serialize;
use tauri::{AppHandle, Manager, RunEvent, State};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_dialog::DialogExt;

/// Added to the command line Windows uses to start Marquee at sign-in.
const AUTOSTART_FLAG: &str = "--autostart";

/// Settings and where they're saved.
pub struct AppState {
    pub prefs: Mutex<Preferences>,
    pub prefs_path: PathBuf,
}

/// One action as the window shows it.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ActionInfo {
    id: &'static str,
    title: &'static str,
    category: marquee_core::shortcuts::Category,
    shortcut: Option<String>,
    available: bool,
}

#[tauri::command]
fn get_prefs(state: State<AppState>) -> Preferences {
    state.prefs.lock().unwrap().clone()
}

/// Saves settings and applies the ones that act outside the window (shortcuts, launch at login).
/// Returns an error message for a shortcut that couldn't be registered.
#[tauri::command]
fn set_prefs(app: AppHandle, state: State<AppState>, prefs: Preferences) -> Result<(), String> {
    prefs.save(&state.prefs_path).map_err(|e| format!("Couldn't save settings: {e}"))?;
    let launch = prefs.launch_at_login;
    *state.prefs.lock().unwrap() = prefs;
    let autolaunch = app.autolaunch();
    let result = if launch { autolaunch.enable() } else { autolaunch.disable() };
    if let Err(e) = result {
        eprintln!("Marquee: launch at login: {e}");
    }
    let registered = shortcuts::register_all(&app);
    tray::refresh(&app);
    registered
}

#[tauri::command]
fn list_actions(state: State<AppState>) -> Vec<ActionInfo> {
    let prefs = state.prefs.lock().unwrap();
    Action::ALL
        .into_iter()
        .map(|a| ActionInfo {
            id: a.id(),
            title: a.title(),
            category: a.category(),
            shortcut: prefs.shortcut(a),
            available: actions::is_available(a),
        })
        .collect()
}

#[tauri::command]
fn perform(app: AppHandle, id: String) -> Result<(), String> {
    let action = Action::from_id(&id).ok_or_else(|| format!("Unknown action {id}"))?;
    actions::perform(&app, action);
    Ok(())
}

/// The folder screenshots are saved to, for Settings to show.
#[tauri::command]
fn save_folder(app: AppHandle, state: State<AppState>) -> String {
    let prefs = state.prefs.lock().unwrap().clone();
    capture::save_folder(&app, &prefs).display().to_string()
}

/// Lets the user pick the save folder and stores it. Returns the new folder, or None if they
/// cancelled. Async so the folder dialog doesn't block the window.
#[tauri::command]
async fn choose_save_folder(app: AppHandle) -> Result<Option<String>, String> {
    let state = app.state::<AppState>();
    let current = capture::save_folder(&app, &state.prefs.lock().unwrap().clone());
    let picked =
        app.dialog().file().set_title("Save screenshots to").set_directory(&current).blocking_pick_folder();
    let Some(path) = picked.and_then(|p| p.into_path().ok()) else { return Ok(None) };
    let mut prefs = state.prefs.lock().unwrap().clone();
    prefs.save_folder = Some(path.clone());
    prefs.save(&state.prefs_path).map_err(|e| format!("Couldn't save settings: {e}"))?;
    *state.prefs.lock().unwrap() = prefs;
    Ok(Some(path.display().to_string()))
}

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

/// The page the window should open on, if something asked for one; asking clears it.
#[tauri::command]
fn take_page(app: AppHandle) -> Option<&'static str> {
    app.try_state::<window::PendingPage>().and_then(|p| p.0.lock().unwrap().take())
}

/// The action the page should explain, if any; asking clears it.
#[tauri::command]
fn take_pending(app: AppHandle) -> Option<&'static str> {
    app.try_state::<window::Pending>().and_then(|p| p.0.lock().unwrap().take())
}

fn main() {
    let app = tauri::Builder::default()
        // A second launch shows the running copy's window instead.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| window::show_main(app, None)))
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec![AUTOSTART_FLAG]),
        ))
        .plugin(shortcuts::plugin())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            get_prefs,
            set_prefs,
            list_actions,
            perform,
            app_version,
            take_pending,
            take_page,
            save_folder,
            choose_save_folder,
            capture::overlay_info,
            capture::overlay_windows,
            capture::overlay_frame,
            capture::overlay_ready,
            capture::overlay_finish,
            library::library_list,
            library::library_copy,
            library::library_save,
            library::library_open,
            library::library_reveal,
            library::library_delete,
            library::library_clear,
            quick_access::quick_access_items,
            quick_access::quick_access_dismiss,
            quick_access::quick_access_tuck,
            quick_access::quick_access_layout,
            clipboard::clip_list,
            clipboard::clip_copy,
            clipboard::clip_paste,
            clipboard::clip_pin,
            clipboard::clip_delete,
            clipboard::clip_clear,
            clipboard::clip_ignore_app,
            clipboard::clip_categories,
            clipboard::clip_category_add,
            clipboard::clip_category_update,
            clipboard::clip_category_delete,
            clipboard::clip_set_category,
            clipboard::clip_close_panel,
            annotate::annotate_image,
            annotate::annotate_export,
            annotate::annotate_ready,
            annotate::library_annotate,
            pin::pin_info,
            pin::pin_ready,
            pin::pin_action,
            pin::pin_zoom,
            pin::pin_menu,
            pin::library_pin,
            updater::update_status,
            updater::update_check,
            updater::update_install,
            updater::update_open_page
        ])
        .setup(|app| {
            let config_dir = app.path().app_config_dir()?;
            let prefs_path = config_dir.join("settings.json");
            let prefs = Preferences::load(&prefs_path);
            let launch_at_login = prefs.launch_at_login;
            app.manage(AppState { prefs: Mutex::new(prefs), prefs_path });
            // Rewrite the startup entry each launch: it then carries the current path and the
            // flag below, even if it was made by an older version or before a reinstall.
            if launch_at_login {
                if let Err(e) = app.autolaunch().enable() {
                    eprintln!("Marquee: launch at login: {e}");
                }
            }
            app.manage(capture::Session::default());
            app.manage(quick_access::QuickAccess::default());
            app.manage(pin::Pins::default());
            app.on_menu_event(|app, event| pin::menu_event(app, &event));
            library::init(app.handle())?;
            clipboard::init(app.handle())?;
            updater::init(app.handle());
            tray::install(app.handle())?;
            // Load the windows that appear on a shortcut now, so they open instantly later.
            capture::prewarm(app.handle());
            quick_access::prewarm(app.handle());
            clipboard::prewarm(app.handle());
            if let Err(message) = shortcuts::register_all(app.handle()) {
                eprintln!("Marquee: {message}");
            }
            // Started by Windows at sign-in: stay in the tray. Opened by you: show the window.
            if !std::env::args().any(|a| a == AUTOSTART_FLAG) {
                window::show_main(app.handle(), None);
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building Marquee");

    app.run(|_app, event| {
        // Closing the window keeps Marquee running in the tray; Quit in the tray menu exits.
        if let RunEvent::ExitRequested { api, code: None, .. } = event {
            api.prevent_exit();
        }
    });
}
