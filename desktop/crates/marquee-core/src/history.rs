//! Clipboard history, ported from the macOS app's `ClipboardStore`. Pure logic: the platform
//! layer watches the clipboard, stores image files and calls in here.

use std::fs;
use std::io;
use std::path::Path;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::clip::{Category, ClipFilter, ClipItem, ClipKind, SourceApp, Tint};

/// Newest first. Pinned items and items in a category are never trimmed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct History {
    pub items: Vec<ClipItem>,
    #[serde(default)]
    pub categories: Vec<Category>,
}

/// Image files the caller should delete because their items left history.
pub type Removed = Vec<String>;

impl History {
    pub fn load(path: &Path) -> io::Result<History> {
        match fs::read(path) {
            Ok(data) => serde_json::from_slice(&data).map_err(io::Error::other),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(History::default()),
            Err(e) => Err(e),
        }
    }

    /// Writes atomically: a temporary file, then a rename.
    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec(self).map_err(io::Error::other)?)?;
        fs::rename(tmp, path)
    }

    pub fn add_text(&mut self, text: &str, source: Option<&SourceApp>, limit: usize) -> Removed {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return Vec::new();
        }
        let kind = if is_link(trimmed) { ClipKind::Link } else { ClipKind::Text };
        let mut item = ClipItem::new(kind, hash(text.as_bytes()), source);
        item.text = Some(text.to_string());
        self.insert(item, limit)
    }

    pub fn add_files(&mut self, paths: &[String], source: Option<&SourceApp>, limit: usize) -> Removed {
        if paths.is_empty() {
            return Vec::new();
        }
        let mut item = ClipItem::new(ClipKind::File, hash(paths.join("\n").as_bytes()), source);
        item.file_paths = Some(paths.to_vec());
        self.insert(item, limit)
    }

    /// Adds an image the caller already saved as `image_name`. If the same image is already
    /// in history it moves to the top instead, and `image_name` is returned for deletion.
    pub fn add_image(
        &mut self,
        content_hash: String,
        image_name: String,
        source: Option<&SourceApp>,
        limit: usize,
    ) -> Removed {
        if self.bring_to_front(&content_hash) {
            return vec![image_name];
        }
        let mut item = ClipItem::new(ClipKind::Image, content_hash, source);
        item.image_name = Some(image_name);
        self.insert(item, limit)
    }

    /// True if `content_hash` is in history, without changing anything.
    pub fn contains(&self, content_hash: &str) -> bool {
        self.items.iter().any(|i| i.content_hash == content_hash)
    }

    fn insert(&mut self, item: ClipItem, limit: usize) -> Removed {
        if self.bring_to_front(&item.content_hash) {
            return Vec::new();
        }
        self.items.insert(0, item);
        self.trim(limit)
    }

    /// If the same content is already stored, move it to the top instead of duplicating.
    fn bring_to_front(&mut self, content_hash: &str) -> bool {
        let Some(index) = self.items.iter().position(|i| i.content_hash == content_hash) else {
            return false;
        };
        let mut existing = self.items.remove(index);
        existing.date = Utc::now();
        self.items.insert(0, existing);
        true
    }

    /// Moves an item to the top, e.g. after it's copied or pasted from history.
    pub fn touch(&mut self, id: Uuid) {
        if let Some(hash) = self.get(id).map(|i| i.content_hash.clone()) {
            self.bring_to_front(&hash);
        }
    }

    pub fn get(&self, id: Uuid) -> Option<&ClipItem> {
        self.items.iter().find(|i| i.id == id)
    }

    pub fn toggle_pin(&mut self, id: Uuid) {
        if let Some(item) = self.items.iter_mut().find(|i| i.id == id) {
            item.pinned = !item.pinned;
        }
    }

    pub fn remove(&mut self, id: Uuid) -> Removed {
        let (gone, kept) = std::mem::take(&mut self.items).into_iter().partition(|i| i.id == id);
        self.items = kept;
        image_names(gone)
    }

    /// Removes everything copied from one app, e.g. after the user starts ignoring it.
    pub fn remove_from_app(&mut self, app_id: &str) -> Removed {
        let (gone, kept) = std::mem::take(&mut self.items)
            .into_iter()
            .partition(|i| i.source_app_id.as_deref() == Some(app_id));
        self.items = kept;
        image_names(gone)
    }

    /// Clears history. With `keep_pinned`, pinned items and items in a category stay.
    pub fn clear(&mut self, keep_pinned: bool) -> Removed {
        let (kept, gone) =
            std::mem::take(&mut self.items).into_iter().partition(|i| keep_pinned && i.is_kept());
        self.items = kept;
        image_names(gone)
    }

    /// Keeps at most `limit` items that aren't pinned or in a category.
    pub fn trim(&mut self, limit: usize) -> Removed {
        let mut unkept_seen = 0;
        let mut removed = Vec::new();
        self.items.retain(|item| {
            if item.is_kept() {
                return true;
            }
            unkept_seen += 1;
            if unkept_seen <= limit {
                true
            } else {
                removed.extend(item.image_name.clone());
                removed.extend(item.preview_name.clone());
                false
            }
        });
        removed
    }

    /// Items for a filter and search text, in history order.
    pub fn matching(&self, filter: ClipFilter, query: &str) -> Vec<&ClipItem> {
        let q = query.trim().to_lowercase();
        self.items
            .iter()
            .filter(|i| {
                filter.matches(i) && (q.is_empty() || i.searchable_text().to_lowercase().contains(&q))
            })
            .collect()
    }

    // Categories

    pub fn add_category(&mut self, name: &str, tint: Tint) -> &Category {
        self.categories.push(Category { id: Uuid::new_v4(), name: clean_name(name), tint });
        self.categories.last().expect("just pushed")
    }

    pub fn update_category(&mut self, id: Uuid, name: &str, tint: Tint) {
        if let Some(c) = self.categories.iter_mut().find(|c| c.id == id) {
            c.name = clean_name(name);
            c.tint = tint;
        }
    }

    /// Deletes a category; its items stay in history.
    pub fn delete_category(&mut self, id: Uuid) {
        self.categories.retain(|c| c.id != id);
        for item in self.items.iter_mut().filter(|i| i.category_id == Some(id)) {
            item.category_id = None;
        }
    }

    /// Sets the preview found for the item with `content_hash`. Returns files to delete: the
    /// item's old preview, or the new one if the item has left history meanwhile.
    pub fn set_preview(
        &mut self,
        content_hash: &str,
        link_title: Option<String>,
        preview_name: Option<String>,
    ) -> Removed {
        let Some(item) = self.items.iter_mut().find(|i| i.content_hash == content_hash) else {
            return preview_name.into_iter().collect();
        };
        if link_title.is_some() {
            item.link_title = link_title;
        }
        match preview_name {
            Some(name) => item.preview_name.replace(name).into_iter().collect(),
            None => Vec::new(),
        }
    }

    pub fn set_category(&mut self, category: Option<Uuid>, item: Uuid) {
        if let Some(i) = self.items.iter_mut().find(|i| i.id == item) {
            i.category_id = category;
        }
    }
}

fn image_names(items: Vec<ClipItem>) -> Removed {
    items.into_iter().flat_map(|i| [i.image_name, i.preview_name]).flatten().collect()
}

fn clean_name(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        "Untitled".to_string()
    } else {
        trimmed.to_string()
    }
}

/// Lowercase hex SHA-256.
pub fn hash(data: &[u8]) -> String {
    Sha256::digest(data).iter().map(|b| format!("{b:02x}")).collect()
}

/// An http(s) URL with a host and no spaces counts as a link.
pub fn is_link(text: &str) -> bool {
    if text.chars().any(char::is_whitespace) {
        return false;
    }
    match url::Url::parse(text) {
        Ok(url) => matches!(url.scheme(), "http" | "https") && url.host().is_some(),
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app() -> SourceApp {
        SourceApp { name: "Notepad".into(), id: "notepad.exe".into() }
    }

    #[test]
    fn newest_first_and_duplicates_move_to_top() {
        let mut h = History::default();
        h.add_text("one", Some(&app()), 10);
        h.add_text("two", None, 10);
        h.add_text("one", None, 10);
        let texts: Vec<_> = h.items.iter().map(|i| i.text.clone().unwrap()).collect();
        assert_eq!(texts, ["one", "two"]);
        assert_eq!(h.items[0].source_app_name.as_deref(), Some("Notepad"));
    }

    #[test]
    fn blank_text_is_ignored() {
        let mut h = History::default();
        h.add_text("  \n", None, 10);
        assert!(h.items.is_empty());
    }

    #[test]
    fn links_are_detected() {
        assert!(is_link("https://github.com/Treposting/marquee"));
        assert!(!is_link("github.com"));
        assert!(!is_link("https://a.com and more"));
        assert!(!is_link("ftp://example.com"));
        let mut h = History::default();
        h.add_text("http://example.com/x", None, 10);
        assert_eq!(h.items[0].kind, ClipKind::Link);
    }

    #[test]
    fn trim_keeps_pinned_and_categorized() {
        let mut h = History::default();
        h.add_text("a", None, 10);
        let pinned = h.items[0].id;
        h.toggle_pin(pinned);
        h.add_text("b", None, 10);
        let cat = h.add_category(" Work ", Tint::Blue).id;
        assert_eq!(h.categories[0].name, "Work");
        h.set_category(Some(cat), h.items[0].id);
        for t in ["c", "d", "e"] {
            h.add_text(t, None, 2);
        }
        let texts: Vec<_> = h.items.iter().map(|i| i.text.clone().unwrap()).collect();
        assert_eq!(texts, ["e", "d", "b", "a"]);
    }

    #[test]
    fn touch_moves_item_to_top() {
        let mut h = History::default();
        h.add_text("a", None, 10);
        h.add_text("b", None, 10);
        let a = h.items[1].id;
        h.touch(a);
        assert_eq!(h.items[0].id, a);
    }

    #[test]
    fn duplicate_image_returns_new_file_for_deletion() {
        let mut h = History::default();
        assert!(h.add_image("abc".into(), "1.png".into(), None, 10).is_empty());
        h.add_text("x", None, 10);
        let removed = h.add_image("abc".into(), "2.png".into(), None, 10);
        assert_eq!(removed, ["2.png"]);
        assert_eq!(h.items[0].image_name.as_deref(), Some("1.png"));
    }

    #[test]
    fn clear_and_remove_report_image_files() {
        let mut h = History::default();
        h.add_image("h1".into(), "1.png".into(), None, 10);
        h.add_image("h2".into(), "2.png".into(), None, 10);
        h.toggle_pin(h.items[0].id);
        assert_eq!(h.clear(true), ["1.png"]);
        assert_eq!(h.items.len(), 1);
        assert_eq!(h.clear(false), ["2.png"]);
    }

    #[test]
    fn previews_are_set_and_cleaned_up() {
        let mut h = History::default();
        h.add_text("https://example.com", None, 10);
        let hash = h.items[0].content_hash.clone();
        assert!(h.set_preview(&hash, Some("Example".into()), Some("p1.png".into())).is_empty());
        assert_eq!(h.set_preview(&hash, None, Some("p2.png".into())), ["p1.png"]);
        assert_eq!(h.items[0].link_title.as_deref(), Some("Example"));
        assert_eq!(h.matching(ClipFilter::All, "exam").len(), 1);
        assert_eq!(h.set_preview("gone", None, Some("p3.png".into())), ["p3.png"]);
        assert_eq!(h.clear(false), ["p2.png"]);
    }

    #[test]
    fn deleting_a_category_keeps_its_items() {
        let mut h = History::default();
        h.add_text("a", None, 10);
        let cat = h.add_category("Keep", Tint::Red).id;
        h.set_category(Some(cat), h.items[0].id);
        h.delete_category(cat);
        assert_eq!(h.items.len(), 1);
        assert!(h.items[0].category_id.is_none());
    }

    #[test]
    fn filter_and_search() {
        let mut h = History::default();
        h.add_text("hello world", Some(&app()), 10);
        h.add_text("https://example.com", None, 10);
        h.add_files(&["C:\\Users\\me\\report.pdf".into()], None, 10);
        assert_eq!(h.matching(ClipFilter::Links, "").len(), 1);
        assert_eq!(h.matching(ClipFilter::All, "REPORT").len(), 1);
        assert_eq!(h.matching(ClipFilter::All, "notepad").len(), 1);
        assert_eq!(h.matching(ClipFilter::Pinned, "").len(), 0);
    }

    #[test]
    fn remove_from_app() {
        let mut h = History::default();
        h.add_text("secret", Some(&app()), 10);
        h.add_text("other", None, 10);
        h.remove_from_app("notepad.exe");
        assert_eq!(h.items.len(), 1);
    }

    #[test]
    fn save_and_load_round_trip() {
        let dir = std::env::temp_dir().join(format!("marquee-test-{}", Uuid::new_v4()));
        let path = dir.join("history.json");
        let mut h = History::default();
        h.add_text("persist me", Some(&app()), 10);
        h.add_category("Saved", Tint::Green);
        h.save(&path).unwrap();
        let loaded = History::load(&path).unwrap();
        assert_eq!(loaded.items, h.items);
        assert_eq!(loaded.categories, h.categories);
        assert!(History::load(&dir.join("missing.json")).unwrap().items.is_empty());
        fs::remove_dir_all(dir).unwrap();
    }
}
