<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/banner-dark.png">
  <img src="docs/assets/banner-light.png" alt="Marquee: capture the screen, keep the clipboard" width="100%">
</picture>

A free, open-source menu-bar app for macOS that takes screenshots and screen recordings, measures and picks colors, and remembers everything you copy.

[![Build](https://github.com/Treposting/marquee/actions/workflows/build.yml/badge.svg)](https://github.com/Treposting/marquee/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/Treposting/marquee?label=release&color=FFCF1A)](https://github.com/Treposting/marquee/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1D1D1F)
[![MIT license](https://img.shields.io/badge/license-MIT-1D1D1F)](LICENSE)

[**Download**](https://github.com/Treposting/marquee/releases/latest) &nbsp;·&nbsp;
[Website](https://treposting.github.io/marquee/) &nbsp;·&nbsp;
[Demo video](https://treposting.github.io/marquee/#demo) &nbsp;·&nbsp;
[How it works](docs/HOW-IT-WORKS.md) &nbsp;·&nbsp;
[Report a bug](https://github.com/Treposting/marquee/issues)

</div>

---

## Contents

- [What's new](#whats-new)
- [Features](#features)
- [Install](#install)
- [Using Marquee](#using-marquee)
- [Privacy](#privacy)
- [Troubleshooting](#troubleshooting)
- [Updates](#updates)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## What's new

**0.5.18**
- **Recordings keep their true colors** (no more washed-out video), and Annotate always fits its toolbar.
- **Quick Access hides after 20 seconds** if unused, and can be tucked to the screen's edge.
- **Copy and paste sounds work everywhere**, play once, and you can pick them.
- **More Liquid Glass**: glass cards across every page and a glass tab bar in Settings.
- **QuitX**: a card on Home and a page in the sidebar for the free menu bar app that quits apps.

**0.5.17**
- **Drag text anywhere in the video editor**, with a layers panel to show, hide, reorder and delete text.

**0.5.16**
- **More video editing.** Cut sections out of the middle and put text on the video (caption, bold or highlight).
- **Mute the mic or hide the camera while recording**, and separate voice files saved in a folder with their video.
- **Redact three ways** in Annotate: pixelate, smooth blur or a solid block, and redactions stay movable. A new Select tool moves any shape.
- **Updates show up within the hour**: a red dot on the menu bar icon and a notification.
- **Windows open in the middle of your screen**, and the camera bubble follows its settings right away.

**0.5.15**
- **Edit recordings.** Trim, remove the sound, and export as MP4 (original, 1080p or 720p) or GIF, from the ✂ on a recording's thumbnail or Library → Edit….
- **Recording resolution.** Record at full Retina sharpness, 1080p or 720p.
- **A new Quick Access thumbnail.** Hover for actions in its corners and Copy in the middle.
- **A cleaner annotation editor** with one glass toolbar and single-key tools.
- **About Marquee** shows who makes it, with a Buy Me a Coffee link.

**0.5.14**
- **Ignore apps in clipboard history.** Nothing copied in Passwords, Keychain Access or popular password managers is saved, even when the app doesn't mark it as private. Add any other app in **Settings → Clipboard → Ignored apps**, or right-click an item → **Ignore Copies from <App>**.

**0.5.13**
- **Liquid Glass everywhere.** Every page of the Marquee window shares one macOS 26/27 design: a large title, the page's controls grouped on glass, and matching rounded cards. The update window, onboarding, Quick Access and toolbars match.

**0.5.12**
- **Updates install from anywhere.** Opened from the disk image or a protected copy, an update now installs into Applications (asking for your password if your account needs it) and closes any other running copy first, instead of failing with "can't replace itself".

**0.5.11**
- **All-in-One remembers.** **Screenshot** and **Record** repeat what you used last; the small icon on each switches between Area, Full Screen, Window and Scrolling, with a back button.
- **Scrolling capture** <sup>macOS 14+</sup>. One long screenshot of anything that scrolls, by hand or with **Auto-scroll**. Fixed headers and bottom bars appear once.
- **Camera bubble.** Show yourself in recordings with any connected camera, in a circle, rounded, square or portrait bubble with an optional glow border. Drag it anywhere, even while recording.
- **Your voice as its own file.** Optionally save the microphone as an .m4a next to the recording.

**0.5.10**
- **Clipboard categories.** Make categories with a name and a color, add any item, and filter by them. Items in a category are kept like pinned ones.
- **Link previews.** Copied links show the page's title, image and icon.
- **A better clipboard panel.** It sits on the bottom edge of the screen, a click pastes, times read "5 min ago", and scrolling no longer reaches the app behind it.
- **14 more menu bar icons.**

**0.5.9**
- **Measure guides.** Press H or V to add a guide; guides snap to edges, show the distance between them, and move with a drag or the arrow keys.
- **Measure on every display** at once.

**0.5.8**
- **Image and video previews** for files you copy in Finder.

**0.5.7**
- **A new Home** with All-in-One up front and your latest capture beside it.
- **Choose the menu bar icon**, or use your own image.
- **Copy and paste sounds**, color swatches for copied colors, and clipboard cards tinted by their app.
- **Fixed:** picking a color could freeze the screen; Restart Marquee didn't reopen the app.

**0.5.6**
- **All-in-One, everything in one bar.** **Screenshot ▾** and **Record ▾** each offer Selected Area, Full Screen or Window. Copy the area with <kbd>⌘</kbd><kbd>C</kbd>, and use F / W (⇧F / ⇧W to record) as quick keys.
- **Record a window.** Hover to highlight it, click to record.
- **Permissions stay after updates.** Releases are signed with one stable certificate (from 0.5.5), and the Permissions page can repair stale entries.
- **Dark-mode app icon**, a Liquid Glass All-in-One toolbar, and shortcuts grouped by category.

**0.5**
- **The Marquee window.** Every action, your capture library, clipboard history, picked colors, permissions and settings, in one app. The menu bar keeps the shortcuts you use most.
- **Onboarding.** A short walkthrough on first launch sets up permissions and shows the key shortcuts.
- **All-in-One** (⌥⇧⌘A). Select an area, then screenshot, record, copy text or pin from one toolbar.
- **Shortcuts you choose.** Only All-in-One and Clipboard History have shortcuts by default; add the rest yourself.
- **Color picker.** Copy any on-screen color as HEX, RGB, HSL or SwiftUI.

**0.4**
- **Measure.** A PixelSnap-style ruler: distances, snap to element, keep, copy, capture.
- **Microphone and desktop audio** in recordings, chosen on a new recording toolbar with a live level meter.
- **Countdown or instant start**, and a blinking timer in the menu bar while recording.
- **In-app updates.** Future versions install from inside the app.

**0.3**: **ShotPaste is now Marquee.** The app was renamed now that it covers capture, clipboard history and measuring. If you used ShotPaste 0.2.0, Marquee moves your clipboard history, settings and shortcuts over the first time it runs. macOS treats it as a new app, so it asks for Screen Recording and Accessibility again.

**0.2**
- **Screen recording.** Record an area or the full screen to MP4, then save it as a GIF.
- **Custom shortcuts.** Change every global shortcut in Settings.
- **DMG installer.** One universal download for Apple Silicon and Intel.
- **New look.** A new logo and app icon, and a [website](https://treposting.github.io/marquee/).

See all [releases](https://github.com/Treposting/marquee/releases).

## Features

### The Marquee window

Open it from the menu bar or the Dock. The sidebar has:
- **Home:** one button for every action, plus your latest captures.
- **Library:** every screenshot and recording you've taken. Open, copy, annotate, reveal or save any of them.
- **Clipboard:** your whole history as a searchable grid. Double-click an item to copy it.
- **Colors:** the colors you've picked, in any format.
- **Permissions:** what Marquee is allowed to do, with a button to fix anything missing.
- **Settings.**

The first time you open Marquee, a short walkthrough sets up permissions and shows the main shortcuts.

### All-in-One

Press <kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>A</kbd> and the toolbar appears right away. Until you select an area, actions use the whole screen.

- **Screenshot** and **Record** repeat what you used last: an area, the full screen or a window. A selection always wins. The small icon at the end of each button shows the target; click it to choose **Area**, **Full Screen** or **Window** (‹ or <kbd>Esc</kbd> goes back). Your choice is remembered.
- **Copy** (<kbd>⌘</kbd><kbd>C</kbd> or <kbd>⌃</kbd><kbd>C</kbd>) puts the area straight on the clipboard.
- **Copy Text** (T), **Pin** (P), **Color** (C), and a gear (,) for Settings.
- **Drag** to select; drag elsewhere for a new selection, inside it to move it, or a handle to resize it. Arrow keys nudge it (⇧ for 10), <kbd>⌫</kbd> goes back to the whole screen, <kbd>Esc</kbd> cancels.

| Key | Action |
|---|---|
| <kbd>↩</kbd> | Screenshot (the selection, or your last target) |
| <kbd>F</kbd> / <kbd>W</kbd> | Screenshot the full screen / a window |
| <kbd>S</kbd> | Scrolling capture of the selection |
| <kbd>R</kbd> | Record (the selection, or your last target) |
| <kbd>⇧</kbd><kbd>F</kbd> / <kbd>⇧</kbd><kbd>W</kbd> | Record the full screen / a window |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy the area to the clipboard |

### Capture

- **Area, window or full screen.** Uses the native macOS crosshair, so Space switches to window mode and Esc cancels.
- **Scrolling capture** <sup>macOS 14+</sup>. Select the part that scrolls, then scroll down (or press **Auto-scroll**) and press **Done**: Marquee stitches one long screenshot. Fixed headers and bottom bars appear once. Start it from All-in-One (Screenshot → Scrolling, or press S), the menu, Home, or a shortcut you set. Auto-scroll needs the Accessibility permission.
- **Self-timer.** Captures the full screen after 5 seconds.
- **Copy text (OCR).** Select part of the screen and the text in it goes to your clipboard. It uses Apple's Vision framework on your Mac.
- **Quick Access overlay.** A thumbnail appears after each capture. Hover it for actions in its corners (close, pin, save, annotate) and Copy in the middle, or drag it straight into Slack, Mail or Finder. Tuck it to the screen's edge with the tab on its side, and it hides itself after 20 seconds if you don't use it.
- **Annotate.** Add arrows, rectangles, ellipses, freehand pen, highlights, text and numbered steps. Redact anything sensitive by pixelating, blurring or covering it; redactions stay movable. Select (V) moves any shape. One-key tools: V, A, R, O, P, H, T, N, X.
- **Pin to screen.** Keep a screenshot floating above every window.

### Record

- **Area or full screen** to MP4 (H.264), at 30 or 60 fps.
- **Recording toolbar.** After you pick the area, a toolbar appears under it. Choose any microphone (built-in, USB or Bluetooth) with a live level meter, turn desktop audio on or off, then press Record. Recording starts instantly or after a 3, 5 or 10 second countdown that ends with "Go", whichever you choose in Settings.
- **Microphone and desktop audio together**, mixed into one soundtrack that plays everywhere.
- **Your voice as its own file.** Turn on **Also Save My Voice as a Separate File** (microphone menu or Settings → Recording) and each recording gets its own folder in your screenshots folder with the video and your voice (.m4a), named alike.
- **Mute while recording.** The microphone and camera buttons on the recording toolbar mute the mic (silence is recorded, so the sound stays in sync) or hide the camera bubble, and bring them back.
- **Camera bubble.** Show yourself in the recording with any connected camera (built-in, USB, capture card, virtual camera, iPhone or Desk View): pick a camera, a shape (circle, rounded, square, portrait), a size, a corner and a border, including yellow, blue, pink and rainbow glows, from the **Camera** menu on the recording toolbar or in Settings → Recording. Drag the bubble anywhere, even while recording.
- **While recording:** a timer, the mic meter, Stop and Discard on the toolbar. The menu bar shows a blinking red dot with the elapsed time (`12s`, then `4:05`, then `1:04:05`); click it to stop. The cursor is optional.
- **Edit recordings.** Trim the start and end, cut sections out of the middle, add text on top (drag it anywhere, with a layers panel to show, hide and reorder it), remove the sound, and export as MP4 (original, 1080p or 720p) or GIF, from the scissors on the thumbnail or Library → Edit….
- **Resolution.** Record at your display's full Retina sharpness, or at 1080p or 720p for smaller files (Settings → Recording).
- **Save as GIF** from the overlay with one click.

### Measure <sup>macOS 14+</sup>

- **Distances.** Point anywhere and see the distance to the nearest edge in every direction, like a designer's ruler.
- **Snap to element.** Drag a box around a button, an icon or a block of text and it shrinks to the element's exact size.
- **Keep, copy, capture.** Space keeps a measurement on screen, ⌘C copies `140 × 48`, and ⌘S sends the screen with your measurements to the Quick Access overlay.
- **Guides.** Press H or V to add a horizontal or vertical guide at the pointer. Guides snap to nearby edges, show the distance between them, and move with a drag or the arrow keys (⇧ for 10 pt).
- **Every display.** All your displays freeze and can be measured at once.
- **Points or pixels.** Sizes are in points; hold ⇧ to see pixels.

### Color picker

- **Any pixel.** Choose **Pick Color** (from the menu bar, the Marquee window, or a shortcut you set), click anywhere on screen, and the color is copied.
- **Your format.** HEX (`#FFCF1A`), RGB, HSL or SwiftUI `Color(red:green:blue:)`. Choose it in **Colors**.
- **History.** The last 48 colors are kept in **Colors**; click a swatch to copy it again.

### Clipboard history

- **Remembers** text, links, images and files, along with the app each one came from.
- **Image and video previews.** Copy an image or video file in Finder and its card shows a preview, with a play badge on videos, instead of the file icon.
- **Link previews.** Copied links show the page's title, image and icon when the site has them (its Open Graph tags). Turn this off in Settings → Clipboard.
- **Color swatches.** Copy a color like `#FFCF1A`, `rgb(255, 207, 26)` or `hsl(47, 100%, 55%)` and its card shows a small swatch in front of it.
- **Cards in the source app's color.** Each card's header takes the main color of the app it came from.
- **Opens with ⇧⌘V** as a panel attached to the bottom of the screen. Type to search, or filter by type.
- **Categories.** Make your own categories with a name and a color (click **+**), then right-click any item → **Add to Category**. Items in a category are kept, like pinned ones. Right-click a category to edit or delete it; its items go back to the main history.
- **Click to paste** into the app you were using, which stays in front the whole time. The panel closes when you paste, press Esc, or click outside it.
- **Pin** items you reuse. Duplicates move to the front instead of piling up.
- **Includes your screenshots.** Every one you copy also lands in history.

## Install

1. Download `Marquee-x.y.z.dmg` from the [latest release](https://github.com/Treposting/marquee/releases/latest).
2. Open the DMG and drag **Marquee** into **Applications**.
3. Releases aren't notarized by Apple yet, so the first launch needs one of these:
   - right-click the app and choose **Open**, or
   - run `xattr -dr com.apple.quarantine /Applications/Marquee.app`.

Marquee runs on **macOS 13 Ventura through macOS 27 Golden Gate**. On macOS 26 and 27 it uses Liquid Glass, and it follows macOS 27's glass transparency setting. The DMG is a universal build, so it runs natively on Apple Silicon and Intel.

### Permissions

| Permission | Needed for | When macOS asks |
|---|---|---|
| **Screen & System Audio Recording** | Screenshots of other apps, screen recording, desktop audio | On your first capture. Quit and reopen Marquee after allowing it. |
| **Microphone** | Recording your voice | The first time you turn on a microphone in the recording toolbar. |
| **Camera** | Showing yourself in a recording | The first time you turn on the camera in the recording toolbar. |
| **Accessibility** | Pasting a history item straight into the active app | The first time you paste from history. Without it, the item is copied and you press ⌘V yourself. |

## Using Marquee

### Global shortcuts

Out of the box only two shortcuts are set: **All-in-One** (<kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>A</kbd>), which reaches every capture, and **Clipboard History** (<kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd>). Add a shortcut for anything else you use often in **Settings → Shortcuts**, where they're grouped into Capture, Record, Tools and Clipboard. Click **Record Shortcut** and press keys, press ⌫ to remove one, or click ↺ to restore its default. You can also pick them during onboarding.

| Category | Actions |
|---|---|
| Capture | All-in-One, Capture Area, Capture Window, Capture Full Screen, Capture Scrolling, Capture Full Screen in 5 Seconds, Capture Text (OCR) |
| Record | Record Area, Record Screen (press again to stop) |
| Tools | Measure (press again or Esc to stop), Pick Color |
| Clipboard | Clipboard History |

### In the clipboard panel

| Key | Action |
|---|---|
| Type | Search |
| <kbd>←</kbd> <kbd>→</kbd> | Select an item |
| <kbd>↩</kbd> or double-click | Paste |
| <kbd>⌘</kbd><kbd>1</kbd>–<kbd>⌘</kbd><kbd>9</kbd> | Paste one of the first nine items |
| <kbd>⌘</kbd><kbd>P</kbd> | Pin or unpin |
| <kbd>⌘</kbd><kbd>⌫</kbd> | Delete |
| <kbd>Esc</kbd> | Close |

### In the annotation editor

| Key | Action |
|---|---|
| <kbd>⌘</kbd><kbd>Z</kbd> / <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Z</kbd> | Undo / redo |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy the annotated image |
| <kbd>⌘</kbd><kbd>S</kbd> | Save as… |
| <kbd>⌘</kbd><kbd>↩</kbd> | Done |

### While measuring

| Key | Action |
|---|---|
| Move the pointer | Distances to the nearest edges |
| Drag | Snap to the element inside the box |
| <kbd>H</kbd> / <kbd>V</kbd> | Add a horizontal or vertical guide at the pointer |
| Drag a guide | Move it (snaps to nearby edges) |
| <kbd>←</kbd> <kbd>→</kbd> / <kbd>↑</kbd> <kbd>↓</kbd> | Nudge the selected guide 1 pt (<kbd>⇧</kbd>: 10 pt) |
| <kbd>Tab</kbd> | Select the next guide |
| <kbd>Space</kbd> | Keep the current measurement on screen |
| <kbd>⌫</kbd> | Remove the selected guide, or clear kept measurements |
| Hold <kbd>⇧</kbd> | Show pixels instead of points |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy the last measurement |
| <kbd>⌘</kbd><kbd>S</kbd> | Capture the screen with measurements |
| <kbd>Esc</kbd> | Stop measuring |

### When recording

1. Drag to select an area. Press <kbd>↩</kbd> to use the whole screen, or <kbd>Esc</kbd> to cancel.
2. On the toolbar, pick a microphone and turn desktop audio on or off. Then press <kbd>↩</kbd> or **Record**. Pressing the record shortcut again also starts it.
3. To finish, press **Stop** on the toolbar, click the red button in the menu bar, or press the record shortcut again. **Discard** throws the recording away.

### Settings

| Tab | What you can change |
|---|---|
| Capture | Show the overlay, auto-hide it, copy and/or save after capture, save folder, shutter sound, copy and paste sounds (pick from the macOS sounds), window shadow, launch at login, menu bar icon (a built-in symbol or your own image), automatic update checks |
| Recording | Default microphone, desktop audio, start instantly or after 3/5/10 seconds, frame rate, cursor |
| Measure | Edge-detection tolerance |
| Clipboard | Turn history on or off, history size (100 to 5,000 items), paste directly into apps |
| Shortcuts | Every global shortcut |

## Privacy

- **No account and no uploads.** Captures and history never leave your Mac. Marquee makes two kinds of network request, and you can turn both off in Settings: the daily update check to GitHub, and link previews, which load a copied link's title and image from its website (links to your own network are never loaded).
- **Clipboard history** is stored in `~/Library/Application Support/Marquee/`. Clear it from **Clipboard** in the Marquee window at any time; pinned items are kept.
- **The Library** keeps a copy of your last 300 captures in `~/Library/Application Support/Marquee/Library`. Clear it from **Library** at any time.
- **Passwords are skipped.** Password managers mark what they copy with `org.nspasteboard.ConcealedType` or `TransientType`, and Marquee never records those items. On top of that, nothing copied in Passwords, Keychain Access, 1Password, Bitwarden, LastPass, Dashlane, Keeper, NordPass, Proton Pass, Enpass, KeePassXC or Strongbox is saved, even if the app doesn't mark it.
- **Ignore any app.** Add apps whose copies should never be saved in **Settings → Clipboard → Ignored apps**, or right-click an item → **Ignore Copies from <App>** (and optionally delete what's already saved from it).
- **Pause history** from **Clipboard** in the Marquee window when you're copying something sensitive.

## Troubleshooting

<details>
<summary><b>Captures only show my desktop wallpaper</b></summary>

Marquee doesn't have Screen Recording permission yet. Open **System Settings → Privacy & Security → Screen & System Audio Recording**, turn Marquee on, then quit and reopen it.
</details>

<details>
<summary><b>Clipboard history stays empty</b></summary>

From macOS 15.4, macOS can ask before, or block, apps that read the clipboard in the background, and clipboard history depends on that. **Settings → Clipboard** shows a warning when this applies. Open **System Settings → Privacy & Security**, find the clipboard (Paste) setting, and choose **Always Allow** for Marquee.
</details>

<details>
<summary><b>macOS asks for permissions again after an update</b></summary>

macOS ties permissions to how an app is signed. Older releases were signed ad hoc, so every update looked like a new app. Releases are now signed with one stable certificate, so after granting them once more they stay. If a switch is on in System Settings but Marquee still shows the permission as missing, open **Permissions** in the Marquee window and click **Fix Permissions**, then **Restart Marquee**. Maintainers: see [docs/SIGNING.md](docs/SIGNING.md).
</details>

<details>
<summary><b>"Marquee can't replace itself where it's running from" when updating</b></summary>

Versions up to 0.5.11 showed this when Marquee was opened straight from the disk image, or from a copy macOS runs in a protected place. From 0.5.12 the updater installs into Applications instead (asking for your password if your account needs it) and closes any other copy of Marquee first. To get past it once: download the DMG from the [releases page](https://github.com/Treposting/marquee/releases/latest), drag Marquee into Applications, replace the old copy, and open it from there.
</details>

<details>
<summary><b>⇧⌘V no longer does "Paste and Match Style"</b></summary>

Marquee uses that shortcut for clipboard history by default. Change it in **Settings → Shortcuts** if you'd rather keep the app's own shortcut.
</details>

<details>
<summary><b>A shortcut does nothing</b></summary>

Another app may already own that key combination. Pick a different one in **Settings → Shortcuts**.
</details>

## Updates

Marquee updates itself (from version 0.4):
- **Checks:** once a day it asks GitHub whether a newer release exists. You can also choose **Check for Updates…** in the menu bar or Settings.
- **Installs:** when one is available, you see the release notes. **Install Update** downloads it and checks that it's a genuine Marquee build signed with the same certificate. Then **Restart to Update** swaps it in and reopens the app.
- **Keeps permissions:** releases from 0.5.5 on share one signing certificate, so Screen Recording, Microphone and Accessibility stay allowed after an update.

Turn off automatic checks in **Settings → Capture → Updates**. Updates only ever come from [this repository's releases](https://github.com/Treposting/marquee/releases).

## Roadmap

- [x] Screenshots, annotation, OCR, pinning
- [x] Clipboard history with search and direct paste
- [x] Screen recording with GIF export
- [x] Customizable shortcuts
- [x] Universal DMG and GitHub Releases
- [x] Measure: distances, snap to element, keep, copy, capture
- [x] In-app updates from GitHub Releases
- [x] App window, onboarding, All-in-One and color picker
- [x] Measure guides with arrow-key nudging, and multiple displays at once
- [x] Microphone and desktop audio in recordings
- [x] Webcam overlay in recordings
- [x] Scrolling capture
- [ ] Rich text (RTF/HTML) in clipboard history
- [x] Exclude specific apps from history
- [ ] Notarized releases

Ideas and requests are welcome in [Issues](https://github.com/Treposting/marquee/issues).

## Contributing

1. Fork the repo and create a branch from `main`.
2. Make your change. You need Xcode 26: `make run` builds and launches the app, and `swift test` runs the tests.
3. Open a pull request. CI runs the tests and builds the universal app and DMG on every push, and it needs to pass.

Working on an issue? Mention it in your commit messages (`… (#12)`, and `Fixes #12` in the commit that fixes it). A bot then keeps the issue updated: work started, fixed, and the release it shipped in.

Marquee has no third-party dependencies; [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) explains each feature and the Apple API behind it.

<details>
<summary><b>Project layout</b></summary>

```
Sources/Marquee/
├── App/         Entry point, menu bar, global shortcuts, preferences
├── Window/      Marquee window (Home, Library, Clipboard, Colors, Permissions), onboarding
├── Capture/     Screenshots, All-in-One, Quick Access overlay, pinned windows, OCR
├── Library/     Saved captures
├── Color/       Color picker and history
├── Record/      Recording toolbar, ScreenCaptureKit recorder, microphone, MP4 writer, GIF export
├── Measure/     Screen ruler: snapshot, edge finder, overlay
├── Annotate/    Annotation model, renderer and editor window
├── Clipboard/   Pasteboard monitor, history store, history panel, auto-paste
├── Update/      In-app updates from GitHub Releases
└── UI/          Settings, shortcut recorder, toasts, Liquid Glass helpers
Tests/           Unit tests
scripts/         App bundle, icon, DMG and signing scripts
site/            Website (deployed to GitHub Pages)
```

</details>

### Releasing

1. Move the CHANGELOG's "Unreleased" notes under a dated heading such as `## 0.5.15 — 2026-10-20`, add a **What's new** entry to this README, and add a line under **Releases** in [TASKS.md](TASKS.md).
2. Go to **Actions → Release → Run workflow** and enter the version, or leave it empty to release the version already in `Resources/Info.plist`.

The workflow updates `Info.plist` if the version changed, runs the tests, signs and builds the universal DMG and update zip, creates the tag, and publishes a GitHub Release. The release notes are that version's CHANGELOG section followed by install steps; Marquee's update window shows them. Don't push tags by hand.

## License

[MIT](LICENSE). Made by [Nahid Hassan Bulbul](https://github.com/0nahid) ([website](https://nahid.pages.dev/)). If Marquee helps you, you can [buy me a coffee](https://buymeacoffee.com/0nahid).

Marquee is an independent project. It is built only on public Apple APIs and contains no code or assets from any commercial app.
