//! Previews for clipboard cards, made in the background after an item is stored: the title
//! and image of a copied link (only from public addresses, when Settings → Clipboard → Show
//! previews for copied links is on), and a thumbnail of a copied image file.

use std::net::ToSocketAddrs;
use std::path::Path;
use std::thread;
use std::time::Duration;

use marquee_core::linkmeta::{self, PageInfo};
use tauri::{AppHandle, Emitter, Manager};
use ureq::tls::{TlsConfig, TlsProvider};
use ureq::Agent;
use url::Url;
use uuid::Uuid;

use crate::clipboard::ClipState;

/// Thumbnails are at most this wide or tall, in pixels.
const THUMB: u32 = 480;
const MAX_PAGE: u64 = 1024 * 1024;
const MAX_IMAGE: u64 = 8 * 1024 * 1024;
const MAX_FILE: u64 = 64 * 1024 * 1024;
const IMAGE_EXTENSIONS: [&str; 8] = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "ico", "jfif"];

/// Looks up a link's title and image, then updates the item with `content_hash`.
pub fn link(app: &AppHandle, content_hash: String, address: String) {
    let app = app.clone();
    thread::spawn(move || {
        let Some(page) = fetch_page(&address) else { return };
        let images = app.state::<ClipState>().images_dir();
        let preview = page.image.as_deref().and_then(|src| fetch(src, MAX_IMAGE)).and_then(|bytes| {
            let image = image::load_from_memory(&bytes).ok()?;
            save_thumbnail(&images, image)
        });
        finish(&app, &content_hash, page.title, preview);
    });
}

/// Makes a thumbnail for a copied image file, then updates the item with `content_hash`.
pub fn file(app: &AppHandle, content_hash: String, path: String) {
    let path = Path::new(&path);
    let is_image = path
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| IMAGE_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()));
    let small_enough = std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.len() <= MAX_FILE);
    if !is_image || !small_enough {
        return;
    }
    let app = app.clone();
    let path = path.to_path_buf();
    thread::spawn(move || {
        let images = app.state::<ClipState>().images_dir();
        let preview = image::open(&path).ok().and_then(|image| save_thumbnail(&images, image));
        if preview.is_some() {
            finish(&app, &content_hash, None, preview);
        }
    });
}

fn finish(app: &AppHandle, content_hash: &str, title: Option<String>, preview: Option<String>) {
    if title.is_none() && preview.is_none() {
        return;
    }
    app.state::<ClipState>().set_preview(content_hash, title, preview);
    let _ = app.emit("clipboard-changed", ());
}

fn save_thumbnail(dir: &Path, image: image::DynamicImage) -> Option<String> {
    let thumb =
        if image.width() > THUMB || image.height() > THUMB { image.thumbnail(THUMB, THUMB) } else { image };
    std::fs::create_dir_all(dir).ok()?;
    let name = format!("preview-{}.png", Uuid::new_v4());
    thumb.to_rgba8().save(dir.join(&name)).ok()?;
    Some(name)
}

fn fetch_page(address: &str) -> Option<PageInfo> {
    let (final_url, bytes) = get(address, MAX_PAGE, true)?;
    let html = String::from_utf8_lossy(&bytes);
    Some(linkmeta::parse(&html, &final_url))
}

fn fetch(address: &str, limit: u64) -> Option<Vec<u8>> {
    get(address, limit, false).map(|(_, bytes)| bytes)
}

/// GETs a public URL, following up to four redirects and checking every hop, so a page can't
/// send the request on to a local address.
fn get(address: &str, limit: u64, html_only: bool) -> Option<(Url, Vec<u8>)> {
    let agent: Agent = Agent::config_builder()
        .max_redirects(0)
        .http_status_as_error(false)
        .timeout_global(Some(Duration::from_secs(8)))
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Marquee link preview")
        .tls_config(TlsConfig::builder().provider(TlsProvider::NativeTls).build())
        .build()
        .into();
    let mut url = Url::parse(address).ok()?;
    for _ in 0..5 {
        if !is_public(&url) {
            return None;
        }
        let mut response = agent.get(url.as_str()).call().ok()?;
        let status = response.status();
        if status.is_redirection() {
            let location = response.headers().get("location")?.to_str().ok()?;
            url = url.join(location).ok()?;
            continue;
        }
        if !status.is_success() {
            return None;
        }
        if html_only {
            let kind = response.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("");
            if !kind.is_empty() && !kind.contains("html") {
                return None;
            }
        }
        let bytes = response.body_mut().with_config().limit(limit).read_to_vec().ok()?;
        return Some((url, bytes));
    }
    None
}

/// A public URL whose host also resolves only to public addresses.
fn is_public(url: &Url) -> bool {
    if !linkmeta::is_public_url(url) {
        return false;
    }
    let (Some(host), Some(port)) = (url.host_str(), url.port_or_known_default()) else { return false };
    let host = host.trim_start_matches('[').trim_end_matches(']');
    match (host, port).to_socket_addrs() {
        Ok(addrs) => {
            let addrs: Vec<_> = addrs.collect();
            !addrs.is_empty() && addrs.iter().all(|a| linkmeta::is_public_ip(a.ip()))
        }
        Err(_) => false,
    }
}
