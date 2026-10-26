//! Global shortcuts, registered from the user's settings.

use std::collections::HashMap;
use std::sync::Mutex;

use marquee_core::shortcuts::Action;
use tauri::plugin::TauriPlugin;
use tauri::{AppHandle, Manager, Runtime, Wry};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

use crate::{actions, AppState};

/// Which action each registered shortcut runs, by the shortcut's id.
#[derive(Default)]
struct Registered(Mutex<HashMap<u32, Action>>);

pub fn plugin() -> TauriPlugin<Wry> {
    tauri_plugin_global_shortcut::Builder::new()
        .with_handler(|app, shortcut, event| {
            if event.state() != ShortcutState::Pressed {
                return;
            }
            let action =
                app.try_state::<Registered>().and_then(|r| r.0.lock().unwrap().get(&shortcut.id()).copied());
            if let Some(action) = action {
                actions::perform(app, action);
            }
        })
        .build()
}

/// Replaces every registered shortcut with the ones in settings. Keeps going past a shortcut
/// that fails (taken by another app, or not a valid key) and reports the first failure.
pub fn register_all<R: Runtime>(app: &AppHandle<R>) -> Result<(), String> {
    if app.try_state::<Registered>().is_none() {
        app.manage(Registered::default());
    }
    let prefs = app.state::<AppState>().prefs.lock().unwrap().clone();
    let manager = app.global_shortcut();
    manager.unregister_all().map_err(|e| e.to_string())?;
    let registered = app.state::<Registered>();
    let mut map = registered.0.lock().unwrap();
    map.clear();

    let mut first_error = None;
    for action in Action::ALL {
        let Some(text) = prefs.shortcut(action) else { continue };
        let result = text
            .parse::<Shortcut>()
            .map_err(|e| e.to_string())
            .and_then(|shortcut| manager.register(shortcut).map(|_| shortcut).map_err(|e| e.to_string()));
        match result {
            Ok(shortcut) => {
                map.insert(shortcut.id(), action);
            }
            Err(e) => {
                first_error.get_or_insert(format!("{text} for {} couldn't be set: {e}", action.title()));
            }
        }
    }
    first_error.map_or(Ok(()), Err)
}
