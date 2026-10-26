//! The tray icon and its menu, the Windows counterpart of the macOS menu bar menu.

use marquee_core::shortcuts::{Action, Category};
use tauri::image::Image;
use tauri::menu::{IsMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, Wry};

use crate::{actions, window, AppState};

pub fn install(app: &AppHandle) -> tauri::Result<()> {
    let size = 32;
    let icon = Image::new_owned(marquee_icon::rgba(size, marquee_icon::Style::App), size, size);
    TrayIconBuilder::with_id("main")
        .icon(icon)
        .tooltip("Marquee")
        .menu(&menu(app)?)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => window::show_main(app, None),
            "quit" => app.exit(0),
            id => {
                if let Some(action) = Action::from_id(id) {
                    actions::perform(app, action);
                }
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                window::show_main(tray.app_handle(), None);
            }
        })
        .build(app)?;
    Ok(())
}

/// Rebuilds the menu so it shows the current shortcuts.
pub fn refresh(app: &AppHandle) {
    if let (Some(tray), Ok(menu)) = (app.tray_by_id("main"), menu(app)) {
        let _ = tray.set_menu(Some(menu));
    }
}

fn menu(app: &AppHandle) -> tauri::Result<Menu<Wry>> {
    let prefs = app.state::<AppState>().prefs.lock().unwrap().clone();
    let item = |action: Action| {
        let accel = prefs.shortcut(action);
        MenuItem::with_id(app, action.id(), action.title(), true, accel.as_deref())
    };

    let all_in_one = item(Action::AllInOne)?;
    let capture: Vec<MenuItem<Wry>> = Action::ALL
        .into_iter()
        .filter(|a| a.category() == Category::Capture && *a != Action::AllInOne)
        .map(item)
        .collect::<Result<_, _>>()?;
    let capture_refs: Vec<&dyn IsMenuItem<Wry>> = capture.iter().map(|i| i as &dyn IsMenuItem<Wry>).collect();
    let capture_menu = Submenu::with_items(app, "Capture", true, &capture_refs)?;
    let record_area = item(Action::RecordArea)?;
    let record_screen = item(Action::RecordScreen)?;
    let measure = item(Action::Measure)?;
    let color = item(Action::PickColor)?;
    let clipboard = item(Action::ClipboardHistory)?;
    let open = MenuItem::with_id(app, "open", "Open Marquee", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Marquee", true, None::<&str>)?;
    let separator = || PredefinedMenuItem::separator(app);

    Menu::with_items(
        app,
        &[
            &all_in_one,
            &capture_menu,
            &separator()?,
            &record_area,
            &record_screen,
            &separator()?,
            &measure,
            &color,
            &clipboard,
            &separator()?,
            &open,
            &quit,
        ],
    )
}
