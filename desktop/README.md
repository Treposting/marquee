# Marquee for Windows (and later Linux)

A Rust port of Marquee: screenshots, screen recording, a screen ruler, a color picker and clipboard history, with the same behavior as the macOS app. It lives on the `windows-port` branch while it grows, and doesn't touch the macOS app.

**Status:** phase 1 — tray app, global shortcuts, settings and the Marquee window. Captures come next. Early, unsigned builds are attached to each [Desktop (Windows)](../.github/workflows/desktop.yml) run as the `Marquee-Windows` artifact (NSIS installer and MSI).

## Layout

```
desktop/
├── crates/marquee-core   Platform-independent logic ported from the Swift app, with tests:
│                         clipboard history, settings, shortcuts, "5 min ago" ages
├── crates/marquee-icon   Draws the app and tray icons at build time from the same geometry as
│                         site/assets/logo.svg, so the repo has no binary assets
└── crates/marquee-app    The app (Tauri 2): tray, global shortcuts, launch at login, single
                          instance, the window (ui/: HTML, CSS, JS) with Mica on Windows 11
```

## Build

Needs Rust (stable) and, on Windows, the WebView2 runtime (already on Windows 11).

```
cd desktop
cargo test                      # core + icon tests
cargo run -p marquee-app        # run the app (also runs on macOS, without Mica, for UI work)
cargo install tauri-cli --version "^2" --locked
cd crates/marquee-app && cargo tauri build   # NSIS installer and MSI in target/release/bundle
```

CI (`.github/workflows/desktop.yml`, `windows-latest`) runs fmt, clippy (`-D warnings`), tests and builds the installers on every push that touches `desktop/`.

## Plan

Windows first, then Linux X11, then Wayland through portals.

| Phase | What | Windows APIs / crates |
|---|---|---|
| **1 ✅** | Tray, menu, global shortcuts, settings, launch at login, window | Tauri 2, `tauri-plugin-global-shortcut`, `tauri-plugin-autostart`, `window-vibrancy` (Mica) |
| 2 | Screenshots: area overlay, window, full screen, self-timer; Quick Access thumbnail (20 s auto-hide, tuck to side); Library | Windows Graphics Capture (`windows-capture`) or `xcap`; transparent topmost overlay window |
| 3 | Clipboard history, ⇧-style panel, paste into the previous app, ignore password managers | `AddClipboardFormatListener`, `arboard`, `SendInput`; skip `ExcludeClipboardContentFromMonitorProcessing` / `CanIncludeInClipboardHistory` |
| 4 | Annotate, pin, color picker, Measure, copy text (OCR), scrolling capture | `tiny-skia`; Measure edge finder and scroll stitcher ported into `marquee-core`; `Windows.Media.Ocr` |
| 5 | Recording with mic and desktop audio, camera bubble, GIF, video editor | Graphics Capture + Media Foundation H.264 (or `ffmpeg-next`), WASAPI loopback, `cpal`, `nokhwa`, `gifski` |
| 6 | Updater, code signing, release workflow, site | Tauri updater, Authenticode (Azure Trusted Signing) |

Linux later: X11 works much like Windows. Wayland needs `xdg-desktop-portal` (Screenshot, ScreenCast via PipeWire, GlobalShortcuts, RemoteDesktop for paste) and `wlr-layer-shell` for overlays; GNOME will get a reduced set.

## Differences from macOS

- Default shortcuts: All-in-One **Ctrl+Alt+Shift+A**, Clipboard History **Ctrl+Alt+Shift+V** (Ctrl+Shift+V is "paste as plain text" in many Windows apps). Every other action has none until you set one.
- Ignored apps are matched by executable name (`KeePass.exe`); common password managers are on the list from the start.
- Settings are JSON in `%APPDATA%\io.github.treposting.marquee\settings.json`.
