//! Updates from GitHub Releases. With Settings → Check for updates automatically on, Marquee
//! looks for a newer `windows-v…` release shortly after it starts and then every hour; a new
//! version gets one notification, a tray item and a badge in the window. Installing downloads
//! the setup program, checks its size and GitHub's SHA-256, runs it in passive mode (it closes
//! Marquee, updates it and starts it again) and quits.

use std::io::Read;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use chrono::{DateTime, Utc};
use marquee_core::history;
use marquee_core::update::{self, Release, Version};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_notification::NotificationExt;
use ureq::tls::{TlsConfig, TlsProvider};
use ureq::Agent;

use crate::{tray, window, AppState};

const RELEASES: &str = "https://api.github.com/repos/Treposting/marquee/releases?per_page=30";
const FIRST_CHECK: Duration = Duration::from_secs(30);
const INTERVAL: Duration = Duration::from_secs(60 * 60);
const MAX_INSTALLER: u64 = 300 * 1024 * 1024;

#[derive(Default)]
pub struct UpdateState(Mutex<Inner>);

#[derive(Default)]
struct Inner {
    available: Option<Release>,
    checking: bool,
    installing: bool,
    last_checked: Option<DateTime<Utc>>,
    error: Option<String>,
    /// The version the user was already notified about, so it's announced once.
    notified: Option<Version>,
}

/// What the window shows.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    current: String,
    available: Option<AvailableInfo>,
    checking: bool,
    installing: bool,
    last_checked: Option<DateTime<Utc>>,
    error: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AvailableInfo {
    version: String,
    notes: String,
    page_url: String,
    /// False when this copy wasn't installed by the setup program (e.g. the .msi), so the
    /// window offers the download page instead of installing in place.
    can_install: bool,
}

pub fn init(app: &AppHandle) {
    app.manage(UpdateState::default());
    let app = app.clone();
    thread::spawn(move || {
        thread::sleep(FIRST_CHECK);
        loop {
            if app.state::<AppState>().prefs.lock().unwrap().auto_check_updates {
                let _ = check(&app, false);
            }
            thread::sleep(INTERVAL);
        }
    });
}

fn current_version(app: &AppHandle) -> Version {
    Version::parse(&app.package_info().version.to_string()).unwrap_or(Version(0, 0, 0))
}

/// The newer version, if one was found; for the tray menu.
pub fn available_version(app: &AppHandle) -> Option<String> {
    let state = app.try_state::<UpdateState>()?;
    let inner = state.0.lock().unwrap();
    inner.available.as_ref().map(|r| r.version.to_string())
}

fn status(app: &AppHandle) -> Status {
    let state = app.state::<UpdateState>();
    let inner = state.0.lock().unwrap();
    Status {
        current: app.package_info().version.to_string(),
        available: inner.available.as_ref().map(|r| AvailableInfo {
            version: r.version.to_string(),
            notes: r.notes.clone(),
            page_url: r.page_url.clone(),
            can_install: installed_by_setup(),
        }),
        checking: inner.checking,
        installing: inner.installing,
        last_checked: inner.last_checked,
        error: inner.error.clone(),
    }
}

fn changed(app: &AppHandle) {
    let _ = app.emit("update-changed", ());
    tray::refresh(app);
}

/// Asks GitHub for the releases. `manual` checks report errors; automatic ones stay quiet.
fn check(app: &AppHandle, manual: bool) -> Result<(), String> {
    let state = app.state::<UpdateState>();
    {
        let mut inner = state.0.lock().unwrap();
        if inner.checking || inner.installing {
            return Ok(());
        }
        inner.checking = true;
        inner.error = None;
    }
    changed(app);
    let result = fetch_releases().map(|releases| update::newer_than(releases, current_version(app)));
    let announce = {
        let mut inner = state.0.lock().unwrap();
        inner.checking = false;
        inner.last_checked = Some(Utc::now());
        match &result {
            Ok(found) => {
                inner.available = found.clone();
                let version = found.as_ref().map(|r| r.version);
                let new = version.is_some() && version != inner.notified;
                if new {
                    inner.notified = version;
                }
                version.filter(|_| new && !manual)
            }
            Err(e) => {
                if manual {
                    inner.error = Some(e.clone());
                }
                None
            }
        }
    };
    changed(app);
    if let Some(version) = announce {
        let _ = app
            .notification()
            .builder()
            .title(format!("Marquee {version} is available"))
            .body("Open Marquee from the tray to see what's new and update.")
            .show();
    }
    result.map(|_| ())
}

fn agent(redirects: u32, timeout: Duration) -> Agent {
    Agent::config_builder()
        .max_redirects(redirects)
        .http_status_as_error(false)
        .timeout_global(Some(timeout))
        .user_agent(concat!("Marquee-Windows/", env!("CARGO_PKG_VERSION")))
        .tls_config(TlsConfig::builder().provider(TlsProvider::NativeTls).build())
        .build()
        .into()
}

fn fetch_releases() -> Result<Vec<Release>, String> {
    let offline = |e: ureq::Error| format!("Couldn't reach GitHub: {e}");
    let mut response = agent(3, Duration::from_secs(15))
        .get(RELEASES)
        .header("Accept", "application/vnd.github+json")
        .call()
        .map_err(offline)?;
    if !response.status().is_success() {
        return Err(format!("GitHub answered {}. Try again later.", response.status()));
    }
    let body = response.body_mut().with_config().limit(8 * 1024 * 1024).read_to_string().map_err(offline)?;
    update::parse_releases(&body).map_err(|e| format!("Couldn't read GitHub's answer: {e}"))
}

/// True when this copy lives where the setup program installs it (per user, under
/// %LOCALAPPDATA%), so running a newer setup program replaces it.
fn installed_by_setup() -> bool {
    let (Ok(exe), Some(local)) = (std::env::current_exe(), std::env::var_os("LOCALAPPDATA")) else {
        return false;
    };
    exe.starts_with(PathBuf::from(local))
}

/// Downloads the installer, following redirects only to GitHub's hosts, and reports progress.
fn download(app: &AppHandle, installer: &update::Installer) -> Result<PathBuf, String> {
    let failed = |e: ureq::Error| format!("The download failed: {e}");
    let agent = agent(0, Duration::from_secs(15 * 60));
    let mut url = installer.url.clone();
    let mut response = None;
    for _ in 0..5 {
        if !update::is_trusted_download(&url) {
            return Err("The download pointed somewhere other than GitHub, so Marquee stopped.".into());
        }
        let r = agent.get(&url).call().map_err(failed)?;
        if r.status().is_redirection() {
            let location =
                r.headers().get("location").and_then(|v| v.to_str().ok()).ok_or("Bad redirect.")?;
            url = url::Url::parse(&url).and_then(|u| u.join(location)).map_err(|e| e.to_string())?.into();
            continue;
        }
        if !r.status().is_success() {
            return Err(format!("GitHub answered {} to the download.", r.status()));
        }
        response = Some(r);
        break;
    }
    let mut response = response.ok_or("Too many redirects.")?;
    let total = installer.size.max(1);
    let mut reader = response.body_mut().with_config().limit(MAX_INSTALLER).reader();
    let mut bytes = Vec::with_capacity(installer.size as usize);
    let mut chunk = vec![0; 256 * 1024];
    let mut last = 0;
    loop {
        let n = reader.read(&mut chunk).map_err(|e| format!("The download failed: {e}"))?;
        if n == 0 {
            break;
        }
        bytes.extend_from_slice(&chunk[..n]);
        let percent = (bytes.len() as u64 * 100 / total).min(100);
        if percent != last {
            last = percent;
            let _ = app.emit("update-progress", percent);
        }
    }
    if installer.size > 0 && bytes.len() as u64 != installer.size {
        return Err("The download was incomplete. Try again.".into());
    }
    if let Some(expected) = &installer.sha256 {
        if &history::hash(&bytes) != expected {
            return Err(
                "The download didn't match the release's checksum, so Marquee didn't install it.".into()
            );
        }
    }
    let dir = std::env::temp_dir().join("Marquee update");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let file_name = std::path::Path::new(&installer.name).file_name().ok_or("Bad installer name.")?;
    let path = dir.join(file_name);
    std::fs::write(&path, bytes).map_err(|e| format!("Couldn't save the update: {e}"))?;
    Ok(path)
}

// MARK: Commands

#[tauri::command]
pub fn update_status(app: AppHandle) -> Status {
    status(&app)
}

#[tauri::command]
pub async fn update_check(app: AppHandle) -> Status {
    let _ = check(&app, true);
    status(&app)
}

/// Downloads and runs the new setup program, then quits so it can replace Marquee.
#[tauri::command]
pub async fn update_install(app: AppHandle, state: State<'_, UpdateState>) -> Result<(), String> {
    let release = {
        let mut inner = state.0.lock().unwrap();
        if inner.installing {
            return Ok(());
        }
        let release = inner.available.clone().ok_or("There's no update to install.")?;
        inner.installing = true;
        inner.error = None;
        release
    };
    changed(&app);
    let result = (|| {
        let installer = release.installer.as_ref().ok_or("This release has no installer.")?;
        let path = download(&app, installer)?;
        // /P: passive (progress only, closes a running Marquee); /R: start Marquee again after.
        Command::new(&path).args(["/P", "/R"]).spawn().map_err(|e| format!("Couldn't start the update: {e}"))
    })();
    match result {
        Ok(_) => {
            app.exit(0);
            Ok(())
        }
        Err(e) => {
            let mut inner = state.0.lock().unwrap();
            inner.installing = false;
            inner.error = Some(e.clone());
            drop(inner);
            changed(&app);
            Err(e)
        }
    }
}

/// Opens the new release's page in the browser.
#[tauri::command]
pub fn update_open_page(state: State<UpdateState>) -> Result<(), String> {
    let url = state.0.lock().unwrap().available.as_ref().map(|r| r.page_url.clone()).ok_or("No update.")?;
    if !url.starts_with("https://github.com/") {
        return Err("That isn't a GitHub page.".into());
    }
    Command::new("explorer").arg(&url).spawn().map(|_| ()).map_err(|e| format!("Couldn't open the page: {e}"))
}

/// Opens the window on the update page (from the tray).
pub fn show(app: &AppHandle) {
    window::show_page(app, "update");
}
