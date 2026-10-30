//! Link previews: which addresses may be fetched, and the title and image a page declares
//! (Open Graph, Twitter cards or `<title>`). The platform layer does the fetching.

use std::net::IpAddr;

use url::{Host, Url};

/// What a page says about itself.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct PageInfo {
    pub title: Option<String>,
    /// Absolute http(s) URL of the preview image.
    pub image: Option<String>,
}

/// True for http(s) URLs on the public internet. Previews never reach local machines or
/// private networks: no localhost, private or link-local addresses, and no single-label or
/// `.local`-style names.
pub fn is_public_url(url: &Url) -> bool {
    if !matches!(url.scheme(), "http" | "https") || !url.username().is_empty() || url.password().is_some() {
        return false;
    }
    match url.host() {
        Some(Host::Ipv4(ip)) => is_public_ip(IpAddr::V4(ip)),
        Some(Host::Ipv6(ip)) => is_public_ip(IpAddr::V6(ip)),
        Some(Host::Domain(name)) => {
            let name = name.trim_end_matches('.').to_ascii_lowercase();
            const LOCAL: [&str; 6] = [".local", ".localhost", ".internal", ".lan", ".home", ".corp"];
            name.contains('.') && name != "localhost" && !LOCAL.iter().any(|s| name.ends_with(s))
        }
        None => false,
    }
}

/// True unless the address is loopback, private, link-local, shared, documentation or the like.
pub fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let [a, b, ..] = v4.octets();
            !(v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_unspecified()
                || v4.is_broadcast()
                || v4.is_documentation()
                || v4.is_multicast()
                || a == 0
                || (a == 100 && (64..128).contains(&b))
                || (a == 198 && (b == 18 || b == 19))
                || a >= 240)
        }
        IpAddr::V6(v6) => {
            if let Some(v4) = v6.to_ipv4_mapped() {
                return is_public_ip(IpAddr::V4(v4));
            }
            let first = v6.segments()[0];
            !(v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                || (first & 0xfe00) == 0xfc00
                || (first & 0xffc0) == 0xfe80)
        }
    }
}

/// Reads the title and preview image from a page's HTML. Relative image URLs resolve
/// against `base`.
pub fn parse(html: &str, base: &Url) -> PageInfo {
    // The head is enough, and keeps big pages cheap.
    let head = match find_ci(html, "</head") {
        Some(end) => &html[..end],
        None => &html[..floor_char_boundary(html, 256 * 1024)],
    };
    let mut og_title = None;
    let mut twitter_title = None;
    let mut og_image = None;
    let mut twitter_image = None;
    let mut rest = head;
    while let Some(start) = find_ci(rest, "<meta") {
        rest = &rest[start + 5..];
        let end = rest.find('>').unwrap_or(rest.len());
        let attrs = attributes(&rest[..end]);
        let get = |name: &str| attrs.iter().find(|(k, _)| k == name).map(|(_, v)| v.clone());
        let key = get("property").or_else(|| get("name")).unwrap_or_default().to_ascii_lowercase();
        let Some(content) = get("content").map(|c| decode(&c)).filter(|c| !c.trim().is_empty()) else {
            continue;
        };
        let slot = match key.as_str() {
            "og:title" => &mut og_title,
            "twitter:title" => &mut twitter_title,
            "og:image" | "og:image:url" | "og:image:secure_url" => &mut og_image,
            "twitter:image" | "twitter:image:src" => &mut twitter_image,
            _ => continue,
        };
        slot.get_or_insert(content);
    }
    let title_tag = find_ci(head, "<title").and_then(|start| {
        let after = &head[start..];
        let open = after.find('>')? + 1;
        let close = find_ci(&after[open..], "</title")?;
        Some(decode(&after[open..open + close]))
    });
    let title = og_title
        .or(twitter_title)
        .or(title_tag)
        .map(|t| t.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|t| !t.is_empty())
        .map(|t| t.chars().take(200).collect());
    let image = og_image
        .or(twitter_image)
        .and_then(|src| base.join(src.trim()).ok())
        .filter(|u| matches!(u.scheme(), "http" | "https"))
        .map(String::from);
    PageInfo { title, image }
}

/// Case-insensitive search for an ASCII needle.
fn find_ci(haystack: &str, needle: &str) -> Option<usize> {
    let h = haystack.as_bytes();
    let n = needle.as_bytes();
    (0..h.len().saturating_sub(n.len() - 1)).find(|&i| h[i..i + n.len()].eq_ignore_ascii_case(n))
}

fn floor_char_boundary(s: &str, mut i: usize) -> usize {
    if i >= s.len() {
        return s.len();
    }
    while !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

/// `name="value"` pairs from inside a tag; names are lowercased.
fn attributes(tag: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut chars = tag.char_indices().peekable();
    while let Some(&(i, c)) = chars.peek() {
        if !(c.is_ascii_alphanumeric() || c == ':' || c == '-' || c == '_') {
            chars.next();
            continue;
        }
        let mut end = i;
        while let Some(&(j, c)) = chars.peek() {
            if c.is_ascii_alphanumeric() || c == ':' || c == '-' || c == '_' {
                end = j + c.len_utf8();
                chars.next();
            } else {
                break;
            }
        }
        let name = tag[i..end].to_ascii_lowercase();
        while chars.peek().is_some_and(|&(_, c)| c.is_whitespace()) {
            chars.next();
        }
        if chars.peek().map(|&(_, c)| c) != Some('=') {
            out.push((name, String::new()));
            continue;
        }
        chars.next();
        while chars.peek().is_some_and(|&(_, c)| c.is_whitespace()) {
            chars.next();
        }
        let value = match chars.peek().map(|&(_, c)| c) {
            Some(q @ ('"' | '\'')) => {
                chars.next();
                let mut v = String::new();
                for (_, c) in chars.by_ref() {
                    if c == q {
                        break;
                    }
                    v.push(c);
                }
                v
            }
            _ => {
                let mut v = String::new();
                while let Some(&(_, c)) = chars.peek() {
                    if c.is_whitespace() || c == '/' && v.is_empty() {
                        break;
                    }
                    v.push(c);
                    chars.next();
                }
                v
            }
        };
        out.push((name, value));
    }
    out
}

/// Decodes the HTML entities pages commonly use in titles.
fn decode(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        rest = &rest[amp..];
        let Some(semi) = rest[..rest.len().min(12)].find(';') else {
            out.push('&');
            rest = &rest[1..];
            continue;
        };
        let entity = &rest[1..semi];
        let decoded = match entity {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            "nbsp" => Some(' '),
            _ => entity
                .strip_prefix("#x")
                .or_else(|| entity.strip_prefix("#X"))
                .and_then(|hex| u32::from_str_radix(hex, 16).ok())
                .or_else(|| entity.strip_prefix('#').and_then(|d| d.parse().ok()))
                .and_then(char::from_u32),
        };
        match decoded {
            Some(c) => {
                out.push(c);
                rest = &rest[semi + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url(s: &str) -> Url {
        Url::parse(s).unwrap()
    }

    #[test]
    fn only_public_addresses() {
        assert!(is_public_url(&url("https://github.com/Treposting/marquee")));
        assert!(is_public_url(&url("http://93.184.216.34/")));
        for local in [
            "http://localhost:3000",
            "http://127.0.0.1",
            "http://10.0.0.5",
            "http://192.168.1.1/admin",
            "http://169.254.169.254/latest",
            "http://[::1]/",
            "http://[fd00::1]/",
            "http://[::ffff:127.0.0.1]/",
            "http://router/",
            "http://printer.local/",
            "http://nas.lan/",
            "file:///C:/Windows",
            "https://user:pass@example.com/",
        ] {
            assert!(!is_public_url(&url(local)), "{local}");
        }
    }

    #[test]
    fn reads_open_graph_first() {
        let html = r#"<html><head><title>Plain</title>
            <meta property="og:title" content="Marquee &amp; friends">
            <meta content='/img/card.png' property='og:image'/>
            </head><body><meta property="og:title" content="ignored"></body>"#;
        let info = parse(html, &url("https://example.com/a/b"));
        assert_eq!(info.title.as_deref(), Some("Marquee & friends"));
        assert_eq!(info.image.as_deref(), Some("https://example.com/img/card.png"));
    }

    #[test]
    fn falls_back_to_title_tag() {
        let info = parse("<HEAD><TITLE>\n  Hello &#8212; world\n</TITLE></HEAD>", &url("https://e.com"));
        assert_eq!(info.title.as_deref(), Some("Hello — world"));
        assert_eq!(info.image, None);
        assert_eq!(parse("", &url("https://e.com")), PageInfo::default());
    }

    #[test]
    fn twitter_cards_and_bad_images() {
        let html = r#"<meta name="twitter:title" content="Tweet"><meta name="twitter:image" content="javascript:alert(1)">"#;
        let info = parse(html, &url("https://e.com"));
        assert_eq!(info.title.as_deref(), Some("Tweet"));
        assert_eq!(info.image, None);
    }
}
