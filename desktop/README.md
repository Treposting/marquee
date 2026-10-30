# Marquee for Windows (and later Linux)

A Rust port of Marquee: screenshots, screen recording, a screen ruler, a color picker and clipboard history, with the same behavior as the macOS app. It lives on the `windows-port` branch while it grows, and doesn't touch the macOS app.

**Status:** phase 2 is done. The tray app, global shortcuts, settings and the Marquee window are in place; screenshots work (area, window picker, full screen, self-timer with a countdown), with copy, save, the shutter sound, the Quick Access thumbnail and the Library. Clipboard history (phase 3, with categories, link and file previews) and All-in-One are in too.

**Downloads:** previews are GitHub pre-releases tagged `windows-vX.Y.Z`, with an NSIS installer (`…-setup.exe`) and an MSI. They're unsigned for now, so SmartScreen asks first (More info → Run anyway). Every push that touches `desktop/` also builds them as the `Marquee-Windows` artifact of the [Desktop (Windows)](../.github/workflows/desktop.yml) run.

## Releasing a preview

1. Add a `## X.Y.Z` section to [CHANGELOG.md](CHANGELOG.md) on this branch and push.
2. Run **Actions → Release Windows** with that version (branch `windows-port`). The workflow lives on `main` because GitHub only lists manual workflows from the default branch.
3. It sets the version in `Cargo.toml` and `tauri.conf.json`, tests, builds, commits "Release Windows vX.Y.Z" to this branch and publishes the `windows-vX.Y.Z` pre-release. Pull afterwards.

Pre-releases are never GitHub's "latest" release, so the Mac app's updater and the site's download buttons keep pointing at the Mac release.

## Layout

```
desktop/
├── crates/marquee-core   Platform-independent logic ported from the Swift app, with tests:
│                         clipboard history, settings, shortcuts, "5 min ago" ages
├── crates/marquee-icon   Draws the app and tray icons at build time from the same geometry as
│                         site/assets/logo.svg, so the repo has no binary assets
└── crates/marquee-app    The app (Tauri 2): tray, global shortcuts, launch at login, single
                          instance, screenshots (capture.rs), the window (ui/: HTML, CSS, JS)
```

## Build

Needs Rust (stable) and, on Windows, the WebView2 runtime (already on Windows 11).

```
cd desktop
cargo test                      # core + icon tests
cargo run -p marquee-app        # run the app (also runs on macOS, for UI work)
cargo install tauri-cli --version "^2" --locked
cd crates/marquee-app && cargo tauri build   # NSIS installer and MSI in target/release/bundle
```

CI (`.github/workflows/desktop.yml`, `windows-latest`) runs fmt, clippy (`-D warnings`), tests and builds the installers on every push that touches `desktop/`.

## Plan

Windows first, then Linux X11, then Wayland through portals.

| Phase | What | Windows APIs / crates |
|---|---|---|
| **1 ✅** | Tray, menu, global shortcuts, settings, launch at login, window | Tauri 2, `tauri-plugin-global-shortcut`, `tauri-plugin-autostart` |
| **2 ✅** | Screenshots: area overlay on a frozen frame (Space for windows), window picker, full screen, self-timer with countdown; copy, save, shutter sound; Quick Access thumbnails (auto-hide, tuck to the edge); Library of the last 300 | `xcap`, `arboard`, `PlaySound`, notifications; opaque overlay windows; Tauri's asset protocol for thumbnails |
| **3 ✅** | Clipboard history ✅: text, links, images, files with the source app; the Ctrl+Alt+Shift+V panel that pastes into the previous app; the Clipboard page; skips private copies (password managers), ignored apps and paused history | `arboard`, `GetClipboardSequenceNumber`, the clipboard formats Windows' history honors, `SendInput` |
| 4 | Annotate ✅, pin ✅, color picker, Measure, copy text (OCR), scrolling capture | `tiny-skia`; Measure edge finder and scroll stitcher ported into `marquee-core`; `Windows.Media.Ocr` |
| 5 | Recording with mic and desktop audio, camera bubble, GIF, video editor | Graphics Capture + Media Foundation H.264 (or `ffmpeg-next`), WASAPI loopback, `cpal`, `nokhwa`, `gifski` |
| 6 | Updater, code signing, release workflow, site | Tauri updater, Authenticode (Azure Trusted Signing) |

Linux later: X11 works much like Windows. Wayland needs `xdg-desktop-portal` (Screenshot, ScreenCast via PipeWire, GlobalShortcuts, RemoteDesktop for paste) and `wlr-layer-shell` for overlays; GNOME will get a reduced set.

## Differences from macOS

- Default shortcuts: All-in-One **Ctrl+Alt+Shift+A**, Clipboard History **Ctrl+Alt+Shift+V** (Ctrl+Shift+V is "paste as plain text" in many Windows apps). Every other action has none until you set one.
- Ignored apps are matched by executable name (`KeePass.exe`); common password managers are on the list from the start.
- Settings are JSON in `%APPDATA%\io.github.treposting.marquee\settings.json`.
- Screenshots are saved to `Pictures\Marquee` unless you choose another folder in Settings.
