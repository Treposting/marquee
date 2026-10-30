//! Clipboard items, categories and filters, ported from the macOS app's `ClipItem` and
//! `ClipCategory`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ClipKind {
    Text,
    Link,
    Image,
    File,
}

impl ClipKind {
    pub fn label(self) -> &'static str {
        match self {
            ClipKind::Text => "Text",
            ClipKind::Link => "Link",
            ClipKind::Image => "Image",
            ClipKind::File => "File",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipItem {
    pub id: Uuid,
    pub kind: ClipKind,
    /// Plain text for text and link items.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// Absolute paths for file items.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file_paths: Option<Vec<String>>,
    /// File name inside the store's images folder for image items.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_name: Option<String>,
    /// SHA-256 of the content, used to de-duplicate.
    pub content_hash: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_app_name: Option<String>,
    /// The source app's identity: a bundle ID on macOS, an executable name on Windows.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_app_id: Option<String>,
    pub date: DateTime<Utc>,
    #[serde(default)]
    pub pinned: bool,
    /// The user's category, if any. Items in a category are never trimmed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category_id: Option<Uuid>,
    /// The page title for link items, when link previews are on.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link_title: Option<String>,
    /// A thumbnail in the store's images folder: a link's preview image, or a copied image file.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview_name: Option<String>,
}

impl ClipItem {
    pub fn new(kind: ClipKind, content_hash: String, source: Option<&SourceApp>) -> Self {
        ClipItem {
            id: Uuid::new_v4(),
            kind,
            text: None,
            file_paths: None,
            image_name: None,
            content_hash,
            source_app_name: source.map(|s| s.name.clone()),
            source_app_id: source.map(|s| s.id.clone()),
            date: Utc::now(),
            pinned: false,
            category_id: None,
            link_title: None,
            preview_name: None,
        }
    }

    /// Kept when history is trimmed or cleared.
    pub fn is_kept(&self) -> bool {
        self.pinned || self.category_id.is_some()
    }

    /// Text that search matches against.
    pub fn searchable_text(&self) -> String {
        let files = self.file_paths.as_ref().map(|p| p.join(" "));
        [self.text.clone(), self.link_title.clone(), files, self.source_app_name.clone()]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" ")
    }
}

/// The app something was copied from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceApp {
    pub name: String,
    pub id: String,
}

/// A readable name for an app from its executable: "notepad.exe" → "Notepad",
/// "WINWORD.EXE" → "Winword", "msedge.exe" → "Msedge".
pub fn app_display_name(exe: &str) -> String {
    let stem = exe.rsplit_once('.').map_or(exe, |(stem, _)| stem);
    let mut chars = stem.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars.flat_map(char::to_lowercase)).collect(),
        None => exe.to_string(),
    }
}

/// The palette offered when making a category.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tint {
    Red,
    Orange,
    Yellow,
    Green,
    Mint,
    Teal,
    Blue,
    Indigo,
    Purple,
    Pink,
    Brown,
    Gray,
}

/// A user-made category for clipboard items: a name and a color. Items in a category are
/// kept like pinned items.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Category {
    pub id: Uuid,
    pub name: String,
    pub tint: Tint,
}

/// What the clipboard history shows: everything, one kind of item, pinned items, or a category.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ClipFilter {
    All,
    Text,
    Links,
    Images,
    Files,
    Pinned,
    Category(Uuid),
}

impl ClipFilter {
    pub fn matches(self, item: &ClipItem) -> bool {
        match self {
            ClipFilter::All => true,
            ClipFilter::Text => item.kind == ClipKind::Text,
            ClipFilter::Links => item.kind == ClipKind::Link,
            ClipFilter::Images => item.kind == ClipKind::Image,
            ClipFilter::Files => item.kind == ClipKind::File,
            ClipFilter::Pinned => item.pinned,
            ClipFilter::Category(id) => item.category_id == Some(id),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_names_from_executables() {
        assert_eq!(app_display_name("notepad.exe"), "Notepad");
        assert_eq!(app_display_name("WINWORD.EXE"), "Winword");
        assert_eq!(app_display_name("Code"), "Code");
    }
}
