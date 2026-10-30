//! The capture library: every screenshot kept as a PNG with a small thumbnail, newest first,
//! up to 300 like the macOS app. The index is `library.json` in the same folder.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const LIMIT: usize = 300;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryItem {
    pub id: String,
    pub width: u32,
    pub height: u32,
    pub created: DateTime<Utc>,
}

impl LibraryItem {
    pub fn new(width: u32, height: u32, created: DateTime<Utc>) -> LibraryItem {
        LibraryItem { id: uuid::Uuid::new_v4().to_string(), width, height, created }
    }
}

#[derive(Debug)]
pub struct Library {
    dir: PathBuf,
    items: Vec<LibraryItem>,
}

impl Library {
    /// Opens the library in `dir`; a missing or unreadable index gives an empty library.
    pub fn load(dir: &Path) -> Library {
        let items = fs::read(dir.join("library.json"))
            .ok()
            .and_then(|data| serde_json::from_slice::<Vec<LibraryItem>>(&data).ok())
            .unwrap_or_default();
        Library { dir: dir.to_path_buf(), items }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Newest first.
    pub fn items(&self) -> &[LibraryItem] {
        &self.items
    }

    pub fn get(&self, id: &str) -> Option<&LibraryItem> {
        self.items.iter().find(|i| i.id == id)
    }

    pub fn image_path(&self, item: &LibraryItem) -> PathBuf {
        self.dir.join(format!("{}.png", item.id))
    }

    pub fn thumb_path(&self, item: &LibraryItem) -> PathBuf {
        self.dir.join(format!("{}.thumb.png", item.id))
    }

    /// Adds an item whose files are already written, drops what's past the limit (deleting
    /// their files) and saves the index.
    pub fn add(&mut self, item: LibraryItem) -> io::Result<()> {
        self.items.insert(0, item);
        while self.items.len() > LIMIT {
            if let Some(old) = self.items.pop() {
                self.delete_files(&old);
            }
        }
        self.save()
    }

    /// Removes an item and its files. Returns whether it was there.
    pub fn remove(&mut self, id: &str) -> io::Result<bool> {
        let Some(index) = self.items.iter().position(|i| i.id == id) else { return Ok(false) };
        let item = self.items.remove(index);
        self.delete_files(&item);
        self.save()?;
        Ok(true)
    }

    pub fn clear(&mut self) -> io::Result<()> {
        for item in std::mem::take(&mut self.items) {
            self.delete_files(&item);
        }
        self.save()
    }

    fn delete_files(&self, item: &LibraryItem) {
        let _ = fs::remove_file(self.image_path(item));
        let _ = fs::remove_file(self.thumb_path(item));
    }

    fn save(&self) -> io::Result<()> {
        fs::create_dir_all(&self.dir)?;
        let path = self.dir.join("library.json");
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec(&self.items).map_err(io::Error::other)?)?;
        fs::rename(tmp, path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("marquee-library-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn add_with_files(library: &mut Library) -> LibraryItem {
        let item = LibraryItem::new(800, 600, Utc::now());
        fs::write(library.image_path(&item), b"png").unwrap();
        fs::write(library.thumb_path(&item), b"thumb").unwrap();
        library.add(item.clone()).unwrap();
        item
    }

    #[test]
    fn keeps_newest_first_and_round_trips() {
        let dir = temp_dir();
        let mut library = Library::load(&dir);
        let first = add_with_files(&mut library);
        let second = add_with_files(&mut library);
        let ids: Vec<_> = Library::load(&dir).items().iter().map(|i| i.id.clone()).collect();
        assert_eq!(ids, vec![second.id, first.id]);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn remove_deletes_the_files() {
        let dir = temp_dir();
        let mut library = Library::load(&dir);
        let item = add_with_files(&mut library);
        assert!(library.remove(&item.id).unwrap());
        assert!(!library.image_path(&item).exists() && !library.thumb_path(&item).exists());
        assert!(!library.remove(&item.id).unwrap());
        assert!(Library::load(&dir).items().is_empty());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn drops_the_oldest_past_the_limit() {
        let dir = temp_dir();
        let mut library = Library::load(&dir);
        let oldest = add_with_files(&mut library);
        for _ in 0..LIMIT {
            library.add(LibraryItem::new(10, 10, Utc::now())).unwrap();
        }
        assert_eq!(library.items().len(), LIMIT);
        assert!(library.get(&oldest.id).is_none());
        assert!(!library.image_path(&oldest).exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn clear_empties_it() {
        let dir = temp_dir();
        let mut library = Library::load(&dir);
        let item = add_with_files(&mut library);
        library.clear().unwrap();
        assert!(library.items().is_empty() && !library.image_path(&item).exists());
        fs::remove_dir_all(dir).unwrap();
    }
}
