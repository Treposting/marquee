# Tasks

Status as of v0.5.17 (2026-10-18). Project context and conventions are in [CLAUDE.md](CLAUDE.md); release history is in [CHANGELOG.md](CHANGELOG.md).

## Done

**Capture**
- [x] Area, window, full screen, timed (5 s) and OCR capture through `/usr/sbin/screencapture`
- [x] Scrolling capture (macOS 14+): select, scroll or Auto-scroll, stitched by row fingerprints; fixed headers/footers once
- [x] Quick Access overlay: thumbnail sized to the capture; hover shows close/pin/save/annotate (GIF/edit for recordings) in the corners and Copy in the middle; drag out
- [x] Annotation editor: arrows, shapes, pen, highlight, text, numbered steps, pixelate
- [x] Pin screenshots above all windows
- [x] All-in-One (⌥⇧⌘A): toolbar first; editable selection (redraw, move, resize, nudge, ⌫ for whole screen); Screenshot and Record repeat the last target, with an inline Area / Full Screen / Window / Scrolling picker; Copy (⌘C/⌃C), Copy Text, Pin, Color, Settings; keys ↩ F W S R ⇧F ⇧W T P C ,
- [x] WindowPicker: hover-highlight a window and click to record it
- [x] Capture library (last 300 captures) in the Marquee window

**Record**
- [x] Area / full screen / window to MP4 (H.264, 30/60 fps), optional cursor
- [x] Microphone (any input, live level meter) and desktop audio, mixed into one track; optional separate voice .m4a
- [x] Camera bubble: any connected camera (built-in, USB, capture card, virtual, iPhone, Desk View); shape, size, corner, border with glows, mirror; draggable; follows plug/unplug
- [x] Video editor: trim (AVPlayerView trim bar), mute, copy, export MP4 original/1080p/720p or GIF; recording resolution Original/1080p/720p
- [x] Recording toolbar; instant start or 3/5/10 s countdown; blinking menu-bar timer; GIF export

**Tools**
- [x] Measure (macOS 14+): distances, snap to element, keep, copy, capture; points/pixels; guides (H/V, snap, drag, arrow-key nudging, gaps); every display at once
- [x] Color picker: HEX / RGB / HSL / SwiftUI, 48-color history; activates Marquee first so clicks and Esc work

**Clipboard**
- [x] History of text, links, images, files with source app; search, filters, pins, direct paste; pause
- [x] Privacy: skips concealed/transient items; ignores password managers and Keychain by default; user ignore list
- [x] Categories with colors; link previews (Open Graph, never local addresses); image/video previews for copied files; color swatches; cards tinted by source app
- [x] ⇧⌘V panel attached to the bottom edge (click to paste, closes on Esc/paste/outside click, catches all scrolls) and a full Clipboard page

**App**
- [x] Marquee window: Home, Library, Clipboard, Colors, Permissions, Settings; shows in the Dock while open
- [x] Liquid Glass design across the app (shared page header, glass controls, matching cards; `UI/PageStyle.swift`) with fallbacks before macOS 26
- [x] Onboarding (welcome, permissions, record shortcuts, launch at login)
- [x] Menu-bar menu with a choice of 24 icons or your own image; standard main menu (Edit commands work in text fields)
- [x] Shortcuts grouped by category; only All-in-One and Clipboard History have defaults
- [x] Copy and paste sounds; light and dark Icon Composer app icon
- [x] In-app updates from GitHub Releases: verified signature; installs into Applications when the running copy can't be replaced (admin prompt if needed); closes other running copies
- [x] Stable self-signed release signing (from 0.5.5) so permissions survive updates; Permissions page with Fix Permissions (tccutil reset) and Restart Marquee
- [x] Release workflow, universal DMG + zip, CI with tests

**Project**
- [x] Issue updates bot: progress, fixed and released comments plus labels, driven by commit messages and the Release workflow

**Site and docs**
- [x] Landing page (ruler-yellow design) with the 28-second demo pinned in the hero (re-rendered for the 0.5.14 UI: target picker, scrolling capture, camera bubble, guides, clipboard panel)
- [x] README (What's new per release), CHANGELOG, HOW-IT-WORKS, SIGNING docs

## Releases

Each release adds a "What's new" entry to README.md, a dated CHANGELOG section, and a line here.

- **0.5.17:** video editor text drag-anywhere overlays; layers panel (show/hide, reorder, delete) and timeline lanes
- **0.5.16:** video cut sections and text overlays; mute mic / hide camera mid-recording; voice folder; redact styles and Select tool; hourly update checks with red dot and notification; centered windows; icon Stop; fixes #7 (camera bubble) and #8 (copy/paste sound)
- **0.5.15:** video editor (trim, mute, export MP4/GIF); recording resolution; Quick Access hover corners; annotate redesign; About info and Buy Me a Coffee
- **0.5.14:** ignore password managers, Keychain and chosen apps in clipboard history
- **0.5.13:** Liquid Glass design across the whole app
- **0.5.12:** updater installs into Applications from a disk image or protected copy; closes other running copies
- **0.5.11:** All-in-One remembers targets; scrolling capture; camera bubble; separate voice file
- **0.5.10:** clipboard categories, link previews, bottom-edge panel with click-to-paste and scroll fix; 14 more menu-bar icons
- **0.5.9:** Measure guides; measuring on every display
- **0.5.8:** image and video previews for copied files
- **0.5.7:** new Home; menu-bar icon choice; copy/paste sounds; clipboard color swatches and app-tinted cards; color-picker freeze and Restart Marquee fixed (#6)
- **0.5.6:** All-in-One full screen and window targets, ⌘C copy, window recording
- **0.5.5:** stable release signing so permissions survive updates

## Needs checking on a real Mac

Built and passing CI, but not yet tried by hand:

- [ ] All-in-One: no crash when dragging; ⌘C copies the area; F/W/S/⇧F/⇧W; the remembered target and the inline target picker (back with ‹ or Esc)
- [ ] Recording a window with WindowPicker (highlight follows the pointer; multi-display)
- [ ] Permissions persist across an update (install 0.5.14, then update to the next release)
- [ ] Updater from a disk image or a standard account: installs into Applications, asks for a password when needed, closes other copies
- [ ] Fix Permissions / Restart Marquee on the Permissions page
- [ ] Camera bubble: each shape/size/corner/glow, dragging while recording, switching and unplugging cameras, mirror; voice file saved next to the recording
- [ ] Scrolling capture: manual scroll and Auto-scroll on a long web page, a page with a sticky header, and a chat
- [ ] Measure guides (H/V, drag, arrows, Tab, ⌫) and measuring on two displays at once
- [ ] Color picker from the menu bar, a shortcut, Home and All-in-One: clicks and Esc work
- [ ] Video editor: trim, cut sections (I/O, Remove Section), text overlays (drag to place, layers panel show/hide/reorder, export position), mute, copy, export MP4/GIF; recording at 1080p/720p
- [ ] Annotate: redact styles, moving/resizing redactions, Select tool, small images show every control
- [ ] Updates: red dot, menu item and notification when a release appears (hourly check); windows open centered
- [ ] Quick Access hover corners and the new annotate toolbar (color dots show their colors on glass)
- [ ] Clipboard panel: Magic Mouse scrolling over a browser, click to paste, closing rules, categories, link and file previews
- [ ] Ignored apps: copies from Passwords and an added app aren't saved; "Ignore and Delete Its Items"
- [ ] Liquid Glass pages in light and dark mode, and on macOS 13–15 (material fallbacks)

## Next up

1. **Custom domain**: point marquee.nahid.bd at GitHub Pages: add `site/CNAME` containing `marquee.nahid.bd`, update links in README / site / `video/demo.html` if the canonical URL changes. Needs a DNS CNAME `marquee → treposting.github.io` at the domain provider.
2. **Social versions of the demo**: square (1080×1080) and vertical (1080×1920) renders. Make `video/demo.html` size-aware or add a layout per format.

## Backlog

- [ ] Rich text (RTF/HTML) in clipboard history
- [ ] Notarized releases (needs an Apple Developer ID, $99/year; removes the right-click → Open step)
- [ ] Windows version: proposed as a separate native C#/.NET app built in phases (capture + clipboard first). Not started; waiting on a go-ahead.

## Notes

- The release signing certificate (`marquee-signing.p12` and its password) lives with the maintainer and in the repo secrets. Losing it means users re-grant permissions once.
- Releases are triggered from Actions, never by pushing tags.
