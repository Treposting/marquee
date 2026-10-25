# Changelog

All notable changes to Marquee. Versions follow [semantic versioning](https://semver.org).

## Unreleased

## 0.5.18 — 2026-10-25

### Added
- **QuitX on Home.** A small card for [QuitX](https://quitx.kiron.dev), a free, open-source menu bar app to quit, force quit and manage running apps. Close it with ✕ and it stays hidden; QuitX also has its own page under "More apps" in the sidebar.
- **Choose the copy and paste sounds.** Settings → Capture → General has a Copy sound and a Paste sound picker with every macOS sound (Tink, Pop, Glass, Purr, Bottle…). Picking one plays it.
- **Tuck Quick Access to the side.** Hover the thumbnail and click the tab on its left edge: it slides off the screen, leaving a small handle. Click the handle to bring it back. A tucked thumbnail doesn't hide by itself.

### Changed
- **Liquid Glass across the Marquee window.** Cards, Home's action tiles, Library captures and clipboard cards sit on glass, and Settings switches tabs with a glass bar while keeping native macOS controls.
- **Quick Access hides itself after 20 seconds** if you don't use it. Hovering it pauses the countdown, and it stays while you annotate. Change or turn it off in Settings → Capture → Hide overlay after.
- **Pasting from clipboard history moves the item to the top**, like copying it again.

### Fixed
- **Copy and paste sounds in other apps.** The sound now plays when you copy anywhere, and when you paste with ⌘V in any app (pasting needs Marquee allowed in Accessibility), even with no Marquee window open. Pasting from clipboard history plays one sound, not two.
- **Recordings look washed out.** Videos are now recorded in sRGB and tagged with their color profile, so colors match the screen. (#10)
- **Annotate window with a small screenshot:** the window is now always wide enough for the whole toolbar, so no tools are cut off.

## 0.5.17 — 2026-10-18

### Added
- **Video editor: drag text anywhere, and layers.** Text sits on the video as an overlay: drag it to place it and double-click it to edit it; it exports in the same spot at any size. A Layers panel lists each text above the video: show or hide it (hidden text isn't exported), drag to change which is in front, and delete it with ✕ or ⌫. Each text also gets a lane under the timeline showing when it's on screen.

## 0.5.16 — 2026-10-18

### Added
- **Mute the mic or hide the camera while recording**: buttons on the recording toolbar. A muted mic records silence, so the sound stays in sync; a hidden camera leaves the video until you show it again.
- **Separate voice files have their own folder**: the video and your voice (.m4a) are saved together in a folder named after the recording, so you always know which voice goes with which video.
- **Video editor: cut sections and add text.** Mark a start and end (I and O) and remove that part; playback skips it and the timeline shows it in red. Add text on top in three styles (caption, bold, highlight) at the top, middle or bottom, for the whole video, between the marks, or for 3 seconds. Everything stays editable until you export.
- **Annotate: redact three ways.** The redact tool pixelates, smoothly blurs, or covers with a solid block (Secure). Redactions stay movable and resizable after you place them, and the new Select tool (V) moves any shape; ⌫ deletes it. Undo covers moves too.
- **Know about updates sooner**: Marquee checks for a new version every hour and after your Mac wakes (was once a day). When one is found, the menu bar icon gets a red dot, the menu offers "Update Available", and a notification appears; click it to see what's new. Turn the notification off in Settings → Capture → Updates.

### Changed
- **Windows open in the middle of the screen you're on**: the Marquee window, Software Update, onboarding, and the annotation and video editors.
- **Annotate fits small images**: tools stay on top and Copy, Save and Done move to the bottom, so every control shows however small the capture is.
- **Website**: a Buy Me a Coffee button next to Download.
- **Recording toolbar**: Stop is an icon, so the bar keeps its size however long you record.

### Fixed
- **Camera bubble follows settings right away** ([#7](https://github.com/Treposting/marquee/issues/7)): a new position in Settings moves it at once, without turning the camera off and on, and a new size keeps it in its corner and inside the recording area instead of pushing it off screen.
- **Copy and paste sounds didn't play** for some people while the screenshot shutter did ([#8](https://github.com/Treposting/marquee/issues/8)). They now play as system sound effects, the same way as the shutter: through the device set in System Settings → Sound → "Play sound effects through", at the alert volume.

## 0.5.15 — 2026-10-18

### Added
- **Edit recordings**: trim the start and end with the QuickTime trim bar, remove the sound, then copy the result or export it as MP4 (original size, 1080p or 720p) or GIF. Open the editor from the scissors on a recording's thumbnail, or right-click a recording in the Library → Edit….
- **About Marquee**: the About panel (app menu, and now the menu bar menu) and the bottom of Home show who makes Marquee, with links to GitHub, the website and the source code, and a Buy Me a Coffee link (also in the menu bar menu and on the website).
- **Recording resolution**: Settings → Recording → Video → Resolution: Original (Retina), 1080p or 720p, for smaller files.

### Changed
- **Quick Access thumbnail**: the capture fills the thumbnail, sized to its shape. Hover to see the actions around it: close and pin (Save as GIF for recordings) in the top corners, save and annotate (edit for recordings) in the bottom corners, and Copy in the middle.
- **Annotate**: a cleaner editor. Tools, colors, three stroke sizes and undo sit on one glass toolbar; Copy, Save and Done on the right. Single keys pick tools (A arrow, R rectangle, O ellipse, P pen, H highlight, T text, N step, X pixelate). The image has rounded corners and a size and zoom readout.

## 0.5.14 — 2026-10-17

### Added
- **Ignore apps in clipboard history**: nothing copied in Passwords, Keychain Access, 1Password, Bitwarden, LastPass, Dashlane, Keeper, NordPass, Proton Pass, Enpass, KeePassXC or Strongbox is saved, even when the app doesn't mark it as private (on by default). Add any other app in Settings → Clipboard → Ignored apps, or right-click an item → Ignore Copies from <App>, optionally deleting what's already saved from it.

## 0.5.13 — 2026-10-17

### Changed
- **The whole app follows the macOS 26/27 Liquid Glass design.** Every page of the Marquee window (Home, Library, Clipboard, Colors, Permissions, Settings) has the same large title, with its controls grouped on glass: capsule search, glass menus and buttons. Cards and tiles share one set of rounded corners. The update window, onboarding, shortcut recorder, Quick Access, annotation and recording toolbars match, and the on-screen hints are capsules. Older macOS versions get the closest material look.

## 0.5.12 — 2026-10-17

### Fixed
- **Updating no longer fails with "Marquee can't replace itself where it's running from".** When Marquee runs from the disk image or a protected copy, the update now installs into Applications. If your account can't write there, macOS asks for an administrator password. Any other copy of Marquee that's running is closed first, so the new version opens instead of an old copy. Restart Marquee on the Permissions page closes other copies too.

## 0.5.11 — 2026-10-17

### Added
- **Camera in recordings**: show yourself in a bubble inside the recording. Works with any camera connected to the Mac: built-in, USB webcams and capture cards, virtual cameras (OBS, Camo), iPhone through Continuity Camera and Desk View. The list updates as cameras are plugged in, and if the camera in use is unplugged, Marquee switches to another one. Choose the camera, shape (circle, rounded, square, portrait), size, corner, border (plain, or a yellow, blue, pink or rainbow glow) and mirroring from the new Camera menu on the recording toolbar or in Settings → Recording, and drag the bubble anywhere, even while recording.
- **Save your voice separately**: optionally save the microphone as its own .m4a file next to the recording, for editing.
- **Scrolling capture** (macOS 14+): select the part that scrolls, scroll down or press Auto-scroll, then Done for one long screenshot. Fixed headers and bottom bars appear once, and it tells you if you scroll too fast. Start it from All-in-One (Screenshot → Scrolling, or S), the menu bar, Home, or a shortcut.

### Changed
- **All-in-One toolbar** is smaller and has no menus. **Screenshot** and **Record** run with the target you used last (area, full screen or window), and a selection always wins. The small icon at the end of each button shows that target; click it to switch the bar to Area / Full Screen / Window (and Scrolling for screenshots), with a back button (or Esc). Return and R use your last choice; F, W, ⇧F and ⇧W still pick directly. Copy, Copy Text, Pin and Color are icons with tooltips. The size readout is gone from the bar; the size still shows next to the selection.

## 0.5.10 — 2026-10-17

### Added
- **More menu bar icons**: 14 more built-in symbols to choose from in Settings → Capture.
- **Clipboard categories**: make categories with a name and a color, add any item to one (right-click → Add to Category), and filter by it. Items in a category are kept like pinned ones. Right-click a category to edit or delete it; deleting it keeps its items in history.
- **Link previews in clipboard history**: copied links show the page's image, icon and title when the site provides them (Open Graph), and the site's name in the footer. Links to your own network are never loaded. Turn it off in Settings → Clipboard.

### Changed
- **Clipboard panel**: attached to the bottom of the screen with only its top corners rounded, capsule filter chips and search in the macOS 27 style, and smoother card corners with matching borders.
- **Clipboard panel**: click a card to paste it straight into your app (the panel closes). Pasting an older item no longer moves it to the front. The panel stays open until you press Esc, paste, or click outside it.
- **Clipboard times** show minutes, hours or days ("5 min ago") instead of counting seconds.

### Fixed
- **Scrolling the clipboard panel** with a Magic Mouse or trackpad could reach the app behind it (a browser would go back or forward). The panel now catches every scroll, and up/down scrolling moves the cards sideways.

## 0.5.9 — 2026-10-17

### Added
- **Measure guides**: press H or V to add a horizontal or vertical guide at the pointer. Guides snap to nearby edges, show the distance between neighbouring guides, and move with a drag or the arrow keys (⇧ for 10 pt). Tab selects the next guide, ⌫ removes it.
- **Measure on every display**: all displays freeze and can be measured at once. Keys go to the display under the pointer.

## 0.5.8 — 2026-10-17

### Added
- **Clipboard history**: copied image and video files show a preview (Quick Look thumbnail) instead of the file icon. Videos get a play badge.

## 0.5.7 — 2026-10-17

### Added
- **Menu bar icon**: choose a different symbol or your own image in Settings → Capture. Your image can take the menu bar's color or keep its own.
- **Clipboard history**: a copied color (`#FFCF1A`, `rgb(…)`, `hsl(…)`) shows a small swatch in front of it, and each card's header takes the main color of its source app's icon.
- **Copy and paste sounds**: a short sound when Marquee copies something or pastes from clipboard history. Turn it off in Settings → Capture.

### Changed
- **Home** is redesigned: All-in-One up front with its shortcut, your latest capture next to it, and every other action in compact rows.

### Fixed
- **Picking a color could freeze the screen**: the magnifier showed while another app was active, so clicks and Esc never reached it. Marquee now makes itself active first.
- **Restart Marquee** on the Permissions page quit Marquee without opening it again ([#6](https://github.com/Treposting/marquee/issues/6)).
- When Screen Recording is missing, the recording and Measure alerts now open Marquee's Permissions page, where Fix Permissions clears entries left by older versions.

## 0.5.6 — 2026-10-15

### Added
- **All-in-One**: Screenshot and Record have a ▾ menu for Selected Area, Full Screen or Window. Keys: F / W for a full-screen or window screenshot, ⇧F / ⇧W to record them.
- **Copy the area** with ⌘C (or ⌃C) in All-in-One, or the new Copy button.
- **Record a window**: hover to highlight a window, click to record it.

## 0.5.5 — 2026-10-15

### Changed
- Releases are signed with the project's stable certificate. Grant permissions once more after installing this version; after that they stay across updates.

## 0.5.4 — 2026-10-15

### Fixed
- **Permissions survive updates** once releases are signed with the project's certificate (one more re-grant when moving from an ad-hoc build). Release signing now works with a self-signed certificate, and a release fails instead of quietly falling back to ad-hoc signing.

### Added
- Permissions page: **Fix Permissions** clears stale entries from older versions and asks again, and **Restart Marquee** applies Screen Recording.

## 0.5.3 — 2026-10-15

### Fixed
- The All-in-One toolbar didn't appear in 0.5.2, so only the selection showed.

### Added
- All-in-One toolbar: **Color** (C) picks a color, and a gear (,) opens Settings.

## 0.5.2 — 2026-10-15

### Fixed
- All-in-One could crash as soon as you started dragging a selection.

### Changed
- **All-in-One toolbar** redesigned as a Liquid Glass bar that follows light and dark mode, with Screenshot as the default action and key hints on every button.
- **Shortcuts** are grouped into Capture, Record, Tools and Clipboard. Only All-in-One (⌥⇧⌘A) and Clipboard History (⇧⌘V) are set by default; add the others you want in Settings or during onboarding.

## 0.5.1 — 2026-10-15

### Changed
- **All-in-One** shows its toolbar right away and works on the whole screen until you select an area. The selection stays editable: drag elsewhere for a new one, drag inside to move it, drag a handle to resize, arrow keys to nudge, ⌫ to go back to the whole screen.
- **Dark-mode app icon**: a graphite tile with yellow marks on macOS 26 and later, instead of a darkened yellow tile. The website logo follows dark mode too.

## 0.5.0 — 2026-10-15

### Added
- **Marquee window** with a sidebar: Home (every action as a button, recent captures), Library (all screenshots and recordings), Clipboard (searchable history grid), Colors, Permissions and Settings. Marquee shows in the Dock while it's open.
- **Onboarding** on first launch: welcome, permissions, key shortcuts and launch at login.
- **All-in-One** (⌥⇧⌘A): select an area, then Screenshot, Record, Copy Text or Pin from one toolbar.
- **Color picker** (⌥⇧⌘C): copy any on-screen color as HEX, RGB, HSL or SwiftUI, with a history of 48 colors.
- Main menu with standard Edit commands, so ⌘C/⌘V work in text fields.

### Changed
- The menu bar menu is shorter: Open Marquee, the main actions, Settings, updates and Quit. Pause and clear history moved to the Clipboard page.

## 0.4.1 — 2026-10-15

### Added
- **Liquid Glass** on macOS 26 and 27: Quick Access overlay, recording toolbar and countdown, clipboard history panel, toasts and the annotation editor's floating toolbar. Builds now use the macOS 26 SDK, so standard windows and controls get the new look too. macOS 13–15 keep the previous materials.
- Settings → Clipboard warns when macOS limits background clipboard access (macOS 15.4+) and explains how to allow it.

### Changed
- VoiceOver: labels for icon-only buttons and color swatches; toasts are announced.
- Reduce Motion: no pulsing record dot, and a simple fade for the countdown.

## 0.4.0 — 2026-10-15

### Added
- **Measure** (⌥⇧⌘M, macOS 14+): point anywhere to see distances to the nearest edges, drag to snap to an element's exact size, Space to keep measurements on screen, ⇧ for pixels, ⌘C to copy, ⌘S to capture the screen with measurements.
- **Microphone recording**: pick any input (built-in, USB, Bluetooth) on the new recording toolbar, with a live level meter. Microphone and desktop audio can be recorded together and are mixed into one soundtrack.
- **Recording toolbar**: appears under the selected area with microphone, desktop audio and Record; a 3-2-1 countdown; then a timer, level meter, Stop and Discard while recording.
- **Start options**: record instantly, or after a 3, 5 or 10 second countdown (3, 2, 1, Go).
- **Menu-bar timer**: a blinking red dot and the elapsed time while recording (12s → 4:05 → 1:04:05).
- **In-app updates**: Marquee checks GitHub for new releases, downloads and verifies them, and installs on restart. "Check for Updates…" is in the menu bar and Settings.
- Unit tests, run in CI on every push.
- Optional stable code signing for releases, so permissions survive updates ([docs/SIGNING.md](docs/SIGNING.md)).

## 0.3.0 — 2026-10-15

### Changed
- **ShotPaste is now Marquee.** New bundle ID; clipboard history, settings and shortcuts move over automatically on first launch.
- New logo and app icon, and a redesigned website.
- Clipboard "Link" items are teal instead of purple.

## 0.2.0 — 2026-10-14

### Added
- Screen recording to MP4 (area or full screen, 30/60 fps, optional computer audio and cursor), with GIF export.
- Customizable global shortcuts.
- Universal DMG and one-click GitHub releases.

## 0.1.0 — 2026-10-14

### Added
- Screenshots (area, window, full screen, self-timer), Quick Access overlay, annotation editor, pin to screen, OCR.
- Clipboard history with search, filters, pinning and direct paste.
