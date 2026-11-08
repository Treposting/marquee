//! Copy Text's results, ported from the macOS app's `RecognizedContent` and `LinkFinder`: the
//! text and QR code contents found in a capture, what goes on the clipboard, and the web and
//! email links to offer to open.

use url::Url;

/// The prompt lists at most this many links.
pub const LINK_LIMIT: usize = 5;

/// What Copy Text found: printed text, and the contents of any QR codes.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RecognizedContent {
    pub text: String,
    /// Decoded QR code contents, without duplicates.
    pub codes: Vec<String>,
}

impl RecognizedContent {
    pub fn is_empty(&self) -> bool {
        self.text.is_empty() && self.codes.is_empty()
    }

    /// The codes first (scanning one is usually the point), then the text, each once.
    pub fn clipboard_text(&self) -> String {
        let mut parts: Vec<&str> = Vec::new();
        for part in self.codes.iter().map(String::as_str).chain([self.text.as_str()]) {
            if !part.is_empty() && !parts.contains(&part) {
                parts.push(part);
            }
        }
        parts.join("\n\n")
    }

    /// Links to offer, codes first.
    pub fn links(&self) -> Vec<Url> {
        find_links(&self.clipboard_text())
    }

    /// "Copied QR code", "Copied text (120 characters)", "Copied text and QR code"…
    pub fn summary(&self) -> String {
        let code =
            if self.codes.len() == 1 { "QR code".to_string() } else { format!("{} codes", self.codes.len()) };
        match (self.text.is_empty(), self.codes.is_empty()) {
            (false, true) => format!("Copied text ({} characters)", self.text.chars().count()),
            (true, false) => format!("Copied {code}"),
            (false, false) => format!("Copied text and {code}"),
            (true, true) => "No text or QR code found".to_string(),
        }
    }
}

/// Web and email links in reading order, without duplicates, at most `LINK_LIMIT`. Bare
/// domains like "github.com/x" become http links and email addresses become mailto links;
/// file names ("report.pdf") and other schemes are left out.
pub fn find_links(text: &str) -> Vec<Url> {
    let mut seen = Vec::<String>::new();
    let mut links = Vec::new();
    for token in text.split_whitespace() {
        let Some(url) = link_from(trim_punctuation(token)) else { continue };
        let key = url.as_str().to_ascii_lowercase();
        if seen.contains(&key) {
            continue;
        }
        seen.push(key);
        links.push(url);
        if links.len() == LINK_LIMIT {
            break;
        }
    }
    links
}

/// How a link reads in the prompt: no scheme, no trailing slash; the address alone for email.
pub fn display_text(url: &Url) -> String {
    let text = url.as_str();
    let lower = text.to_ascii_lowercase();
    let mut out = ["mailto:", "https://", "http://"]
        .iter()
        .find(|p| lower.starts_with(*p))
        .map_or(text, |p| &text[p.len()..])
        .to_string();
    if out.ends_with('/') {
        out.pop();
    }
    out
}

/// Strips quotes, brackets and sentence punctuation around a word; a closing bracket stays
/// when the word also opens one, as in Wikipedia links.
fn trim_punctuation(token: &str) -> &str {
    let token = token.trim_start_matches(|c: char| "\"'([{<«“‘".contains(c));
    let mut end = token.len();
    while let Some(c) = token[..end].chars().last() {
        let opens = match c {
            ')' => token[..end].contains('('),
            ']' => token[..end].contains('['),
            _ => false,
        };
        if ".,;:!?\"'>»”’}".contains(c) || ((c == ')' || c == ']') && !opens) {
            end -= c.len_utf8();
        } else {
            break;
        }
    }
    &token[..end]
}

fn link_from(token: &str) -> Option<Url> {
    if token.is_empty() {
        return None;
    }
    let lower = token.to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        return Url::parse(token)
            .ok()
            .filter(|u| u.host_str().is_some_and(|h| h.contains('.') || h == "localhost"));
    }
    if lower.starts_with("mailto:") {
        return is_email(&token[7..]).then(|| Url::parse(token).ok()).flatten();
    }
    if is_email(token) {
        return Url::parse(&format!("mailto:{token}")).ok();
    }
    let host = token.split(['/', '?', '#']).next()?;
    let host = host.split(':').next()?;
    if !is_domain(host) {
        return None;
    }
    Url::parse(&format!("http://{token}")).ok()
}

fn is_email(text: &str) -> bool {
    let Some((local, domain)) = text.split_once('@') else { return false };
    !local.is_empty()
        && local.chars().all(|c| c.is_alphanumeric() || "._%+-".contains(c))
        && is_domain(domain)
}

/// "github.com", "www.example.co.uk": letters, digits and hyphens in dotted labels, ending
/// in a known top-level domain (so "report.pdf" or "main.rs" isn't a link).
fn is_domain(host: &str) -> bool {
    let labels: Vec<&str> = host.split('.').collect();
    if labels.len() < 2 || labels.iter().any(|l| l.is_empty() || l.starts_with('-') || l.ends_with('-')) {
        return false;
    }
    if !labels.iter().all(|l| l.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')) {
        return false;
    }
    let tld = labels.last().unwrap().to_ascii_lowercase();
    if host.to_ascii_lowercase().starts_with("www.") {
        return tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic());
    }
    const COMMON: &[&str] = &[
        "com", "net", "org", "io", "dev", "app", "ai", "co", "me", "gov", "edu", "info", "biz", "xyz", "tv",
        "gg", "ly", "so", "to", "site", "online", "store", "tech", "blog", "page", "link", "news", "cloud",
        "design", "studio", "shop", "art", "team", "tools", "email", "live", "pro", "one", "fm", "im",
    ];
    // Two-letter country domains, except ones that are also common file extensions.
    const FILE_LIKE: &[&str] =
        &["js", "py", "rs", "md", "ts", "cs", "go", "rb", "db", "sh", "ps", "gz", "xz", "pl", "cc", "hh"];
    COMMON.contains(&tld.as_str())
        || (tld.len() == 2
            && tld.chars().all(|c| c.is_ascii_alphabetic())
            && !FILE_LIKE.contains(&tld.as_str()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn links(text: &str) -> Vec<String> {
        find_links(text).into_iter().map(String::from).collect()
    }

    #[test]
    fn finds_web_and_email_links_in_order() {
        let found = links(
            "Release notes: https://github.com/Treposting/marquee/releases\n\
             Questions? hello@marquee.app or see treposting.github.io/marquee.",
        );
        assert_eq!(
            found,
            [
                "https://github.com/Treposting/marquee/releases",
                "mailto:hello@marquee.app",
                "http://treposting.github.io/marquee"
            ]
        );
    }

    #[test]
    fn skips_files_duplicates_and_other_schemes() {
        assert_eq!(
            links("https://example.com https://EXAMPLE.com ftp://files.example.com/a.zip report.pdf main.rs"),
            ["https://example.com/"]
        );
        assert!(links("Just a sentence, with no address in it.").is_empty());
        assert!(links("").is_empty());
    }

    #[test]
    fn punctuation_and_brackets() {
        assert_eq!(links("(see www.example.org)."), ["http://www.example.org/"]);
        assert_eq!(
            links("https://en.wikipedia.org/wiki/Rust_(programming_language)"),
            ["https://en.wikipedia.org/wiki/Rust_(programming_language)"]
        );
    }

    #[test]
    fn at_most_five() {
        let text: Vec<String> = (1..=8).map(|i| format!("https://site{i}.example.com")).collect();
        assert_eq!(find_links(&text.join(" ")).len(), LINK_LIMIT);
    }

    #[test]
    fn display_text_drops_the_scheme() {
        let url = |s: &str| Url::parse(s).unwrap();
        assert_eq!(
            display_text(&url("https://github.com/Treposting/marquee/")),
            "github.com/Treposting/marquee"
        );
        assert_eq!(display_text(&url("mailto:hello@marquee.app")), "hello@marquee.app");
        assert_eq!(display_text(&url("http://example.com/a?b=1")), "example.com/a?b=1");
    }

    #[test]
    fn codes_come_first_and_appear_once() {
        let content = RecognizedContent {
            text: "Scan to join\nhttps://marquee.app/join".into(),
            codes: vec!["https://marquee.app/join".into()],
        };
        assert_eq!(
            content.clipboard_text(),
            "https://marquee.app/join\n\nScan to join\nhttps://marquee.app/join"
        );
        assert_eq!(content.links().iter().map(Url::as_str).collect::<Vec<_>>(), ["https://marquee.app/join"]);
    }

    #[test]
    fn summaries() {
        let c = |t: &str, codes: &[&str]| RecognizedContent {
            text: t.into(),
            codes: codes.iter().map(|s| s.to_string()).collect(),
        };
        assert_eq!(c("Hello", &[]).summary(), "Copied text (5 characters)");
        assert_eq!(c("", &["mailto:a@b.co"]).summary(), "Copied QR code");
        assert_eq!(c("Hello", &["a", "b"]).summary(), "Copied text and 2 codes");
        assert_eq!(c("", &[]).summary(), "No text or QR code found");
        assert!(c("", &[]).is_empty());
        assert!(c("", &["WIFI:S:Home;T:WPA;P:secret;;"]).links().is_empty());
    }
}
