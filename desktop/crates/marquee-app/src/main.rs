// No console window in release builds on Windows.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

//! Marquee for Windows: a tray app with global shortcuts and the Marquee window. Capture,
//! recording and the clipboard are added phase by phase (see desktop/README.md).

mod actions;
mod shortcuts;
mod tray;
mod window;

use std::path::PathBuf;
use std::sync::Mutex;

use marquee_core::prefs::Preferences;
use marquee_core::shortcuts::Action;
use serde::Serialize;
use tauri::{AppHandle, Manager, RunEvent, State};
use tauri_plugin_autostart::ManagerExt;

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

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
fn window_material(app: AppHandle) -> &'static str {
    app.try_state::<window::Material>().map_or("none", |m| *m.0.lock().unwrap())
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
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .plugin(shortcuts::plugin())
        .invoke_handler(tauri::generate_handler![
            get_prefs,
            set_prefs,
            list_actions,
            perform,
            app_version,
            window_material,
            take_pending
        ])
        .setup(|app| {
            let config_dir = app.path().app_config_dir()?;
            let prefs_path = config_dir.join("settings.json");
            let prefs = Preferences::load(&prefs_path);
            app.manage(AppState { prefs: Mutex::new(prefs), prefs_path });
            tray::install(app.handle())?;
            if let Err(message) = shortcuts::register_all(app.handle()) {
                eprintln!("Marquee: {message}");
            }
            window::show_main(app.handle(), None);
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
