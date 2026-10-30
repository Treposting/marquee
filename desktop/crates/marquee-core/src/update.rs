//! Update checks for the Windows app: which GitHub release is newer than the running version.
//! Windows previews are pre-releases tagged `windows-vX.Y.Z`; the Mac app's `vX.Y.Z` releases
//! are skipped.

use serde::Deserialize;

pub const TAG_PREFIX: &str = "windows-v";
/// The NSIS installer's file name ends with this.
pub const INSTALLER_SUFFIX: &str = "-windows-x64-setup.exe";

/// A version like 0.4.2. Ordering compares major, then minor, then patch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version(pub u64, pub u64, pub u64);

impl Version {
    /// "0.4.2", "v0.4.2" or "windows-v0.4.2"; a pre-release suffix ("-beta") is ignored.
    pub fn parse(text: &str) -> Option<Version> {
        let core = text.trim().trim_start_matches(TAG_PREFIX).trim_start_matches('v');
        let core = core.split(['-', '+']).next()?;
        let mut parts = core.split('.').map(|p| p.parse::<u64>().ok());
        let version =
            Version(parts.next()??, parts.next().unwrap_or(Some(0))?, parts.next().unwrap_or(Some(0))?);
        parts.next().is_none().then_some(version)
    }
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.0, self.1, self.2)
    }
}

/// The installer attached to a release.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Installer {
    pub name: String,
    pub url: String,
    pub size: u64,
    /// Lowercase hex SHA-256 from GitHub, when it reports one.
    pub sha256: Option<String>,
}

/// A Windows release.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Release {
    pub version: Version,
    /// The release notes (Markdown).
    pub notes: String,
    /// The release's page on GitHub.
    pub page_url: String,
    pub installer: Option<Installer>,
}

#[derive(Deserialize)]
struct RawRelease {
    tag_name: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    body: Option<String>,
    html_url: String,
    #[serde(default)]
    assets: Vec<RawAsset>,
}

#[derive(Deserialize)]
struct RawAsset {
    name: String,
    browser_download_url: String,
    #[serde(default)]
    size: u64,
    #[serde(default)]
    digest: Option<String>,
}

/// Windows releases from the GitHub API's release list, newest version first.
pub fn parse_releases(json: &str) -> Result<Vec<Release>, serde_json::Error> {
    let raw: Vec<RawRelease> = serde_json::from_str(json)?;
    let mut releases: Vec<Release> = raw
        .into_iter()
        .filter(|r| !r.draft && r.tag_name.starts_with(TAG_PREFIX))
        .filter_map(|r| {
            let version = Version::parse(&r.tag_name)?;
            let installer =
                r.assets.into_iter().find(|a| a.name.ends_with(INSTALLER_SUFFIX)).map(|a| Installer {
                    sha256: a
                        .digest
                        .and_then(|d| d.strip_prefix("sha256:").map(str::to_ascii_lowercase))
                        .filter(|h| h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit())),
                    name: a.name,
                    url: a.browser_download_url,
                    size: a.size,
                });
            Some(Release { version, notes: r.body.unwrap_or_default(), page_url: r.html_url, installer })
        })
        .collect();
    releases.sort_by_key(|r| std::cmp::Reverse(r.version));
    Ok(releases)
}

/// The newest release with an installer that's newer than `current`.
pub fn newer_than(releases: Vec<Release>, current: Version) -> Option<Release> {
    releases.into_iter().filter(|r| r.installer.is_some()).find(|r| r.version > current)
}

/// Only GitHub's own hosts may serve an installer.
pub fn is_trusted_download(url: &str) -> bool {
    url::Url::parse(url).is_ok_and(|u| {
        u.scheme() == "https"
            && matches!(
                u.host_str(),
                Some("github.com" | "objects.githubusercontent.com" | "release-assets.githubusercontent.com")
            )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions() {
        assert_eq!(Version::parse("windows-v0.4.2"), Some(Version(0, 4, 2)));
        assert_eq!(Version::parse("v1.2"), Some(Version(1, 2, 0)));
        assert_eq!(Version::parse("0.10.0-beta"), Some(Version(0, 10, 0)));
        assert_eq!(Version::parse("1.2.3.4"), None);
        assert_eq!(Version::parse("abc"), None);
        assert!(Version(0, 10, 0) > Version(0, 9, 9));
        assert_eq!(Version(0, 4, 2).to_string(), "0.4.2");
    }

    const JSON: &str = r#"[
      {"tag_name": "v0.5.19", "draft": false, "body": "mac", "html_url": "https://github.com/x/mac", "assets": []},
      {"tag_name": "windows-v0.4.2", "draft": false, "body": "- Faster", "html_url": "https://github.com/x/w042",
       "assets": [
         {"name": "Marquee-0.4.2-windows-x64.msi", "browser_download_url": "https://github.com/x/a.msi", "size": 5},
         {"name": "Marquee-0.4.2-windows-x64-setup.exe", "browser_download_url": "https://github.com/x/a.exe", "size": 9,
          "digest": "sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"}]},
      {"tag_name": "windows-v0.5.0", "draft": true, "html_url": "https://github.com/x/draft", "assets": []},
      {"tag_name": "windows-v0.4.10", "draft": false, "html_url": "https://github.com/x/w0410", "assets": []}
    ]"#;

    #[test]
    fn picks_newest_windows_release_with_an_installer() {
        let releases = parse_releases(JSON).unwrap();
        let versions: Vec<_> = releases.iter().map(|r| r.version).collect();
        assert_eq!(versions, [Version(0, 4, 10), Version(0, 4, 2)]);
        let newer = newer_than(releases.clone(), Version(0, 4, 1)).unwrap();
        assert_eq!(newer.version, Version(0, 4, 2));
        let installer = newer.installer.unwrap();
        assert_eq!(installer.url, "https://github.com/x/a.exe");
        assert_eq!(
            installer.sha256.as_deref(),
            Some("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
        );
        assert_eq!(newer.notes, "- Faster");
        assert!(newer_than(releases, Version(0, 4, 2)).is_none());
    }

    #[test]
    fn trusted_downloads() {
        assert!(is_trusted_download("https://github.com/Treposting/marquee/releases/download/x/a.exe"));
        assert!(is_trusted_download(
            "https://objects.githubusercontent.com/github-production-release-asset/1"
        ));
        assert!(!is_trusted_download("http://github.com/a.exe"));
        assert!(!is_trusted_download("https://github.com.evil.example/a.exe"));
    }
}
