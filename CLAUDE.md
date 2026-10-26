# Marquee

A free, open-source macOS menu-bar app: screenshots, screen recording with audio, a screen ruler (Measure), a color picker and clipboard history. It's a clean-room take on CleanShot X + Paste + PixelSnap, built only on public Apple APIs.

- Repo: github.com/Treposting/marquee · Website: https://treposting.github.io/marquee/ (from `site/`)
- What's done and what's next: **[TASKS.md](TASKS.md)**. Start there.
- How each feature works and which Apple API it uses: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)

## Build and test

- Swift package, `swift-tools-version 5.9`, Swift 5 language mode, macOS 13+. No third-party dependencies.
- Needs **Xcode 26** (macOS 26 SDK, for Liquid Glass). CI uses the `macos-26` runner.
- `swift build`, `swift test` (about 60 tests in `Tests/MarqueeTests`)
- `make app` builds `build/Marquee.app`; `make run` builds and opens it; `make dmg` builds the universal DMG and update zip.
- CI (`.github/workflows/build.yml`) runs on every push: tests, the universal app/DMG, a self-signed signing check, and icon previews. Build only on a Mac; there's no Linux build.

## Layout

```
Sources/Marquee/
├── App/        AppDelegate (menu bar menu, main menu, action routing), AppModel, shortcuts, hotkeys, preferences
├── Window/     Marquee window (Home, Library, Clipboard, Colors, Permissions, Settings) and onboarding
├── Capture/    screencapture wrapper, All-in-One overlay + toolbar, WindowPicker, Quick Access overlay, pinning, OCR
├── Record/     AreaSelector, recording toolbar, ScreenCaptureKit recorder, mic, audio mixdown, GIF export
├── Measure/    screen ruler (macOS 14+): snapshot, edge finder, overlay
├── Color/      color picker (NSColorSampler) and history
├── Library/    saved captures (~/Library/Application Support/Marquee/Library)
├── Clipboard/  pasteboard monitor, history store, panel, auto-paste
├── Annotate/   annotation editor
├── Update/     in-app updater (GitHub Releases, signature check, swap on restart)
└── UI/         Settings, ShortcutRecorder, Toast, Glass helpers
scripts/  build-app.sh, make-dmg.sh, make-icon.swift (light + dark Icon Composer icon), signing cert script
site/     landing page (single index.html) + assets, including the demo video
video/    demo.html (time-driven scene) + render.mjs (Playwright → ffmpeg)
```

## Conventions

- Write code that matches the surrounding style. Doc comments on types and non-obvious functions, no noise comments.
- Main-actor work: use `Task { @MainActor in … }` or the `runAfter(_:)` helper (UI/MainThread.swift), not `DispatchQueue.main` closures. SwiftUI button actions that touch AppKit are `@MainActor () -> Void`.
- Don't use tuple key paths like `id: \.0` in SwiftUI; use small structs.
- Liquid Glass only through `UI/Glass.swift` (`glassSurface`, `glassButtonStyle`, `hudSurface`, `GlassGroup`). They fall back to materials before macOS 26. Check APIs newer than macOS 13 with `#available`.
- NSHostingView in borderless panels: measure `fittingSize` **before** setting `sizingOptions = []`, or the panel ends up zero-sized.
- Never pass a possibly-null rect (e.g. `insetBy` on a small rect) to AppKit cursor rects.
- Global shortcuts: only All-in-One (⌥⇧⌘A) and Clipboard History (⇧⌘V) have defaults; everything else is user-defined (`ShortcutAction.defaultCombo`).
- Copy for users: plain, specific, sentence case. Update `README.md`, `CHANGELOG.md` ("Unreleased") and `site/index.html` when a user-facing feature changes.

## Working on GitHub issues

The **Issue updates** workflow (`.github/workflows/issue-updates.yml`, logic in `.github/scripts/issue-status.js`) keeps issues up to date from commit messages, so:

- **Mention the issue in every commit** for it, e.g. `Detect permissions granted to older builds (#6)`. The first mention posts "Work has started" and adds the `in progress` label. Each commit is listed in one status comment on the issue.
- **The commit that fixes it** says `Fixes #6` in its message. When it reaches `main`, the issue gets "Fixed, ships in the next release" and the `fixed (unreleased)` label (GitHub also closes it).
- **The Release workflow** then comments "Released in vX.Y.Z", sets `released` and closes it. Don't close issues by hand.
- When you start on an issue, post a short plain note for the reporter with what you found or plan: `gh issue comment 6 --body "…"`. Ask there if you need steps, logs or a macOS version. Keep it user-facing: no internal jargon.
- Don't mention an issue number in commits that aren't about that issue (it would post on it). Hex colors like `#FFCF1A` are ignored.

## Releasing

- Never push tags by hand. Run **Actions → Release** (`release.yml`, workflow_dispatch) with a `version` input like `0.5.7`. It bumps `Resources/Info.plist`, runs tests, signs with the project certificate, builds the DMG + zip and publishes the GitHub Release. Then pull `main` (the workflow pushes a "Release vX" commit).
- Before releasing, update the docs for that version, every time:
  - CHANGELOG.md: move the "Unreleased" notes under a dated heading (`## 0.5.15 — 2026-10-20`). The Release workflow copies this section into the GitHub release notes, which Marquee's update window shows to users, so write it for them.
  - README.md: add a short **What's new** entry at the top of that section.
  - TASKS.md: add a line under **Releases**, bump the "Status as of" line, and update **Done** / **Needs checking** for what changed.
- Signing: secrets `MACOS_SIGNING_IDENTITY`, `MACOS_SIGNING_CERT_PASSWORD`, `MACOS_SIGNING_CERT_P12` hold a self-signed certificate. The workflow signs by the identity's SHA-1 hash and fails if the app comes out ad-hoc signed. Keeping one certificate is what lets macOS keep permissions across updates; never change it. See docs/SIGNING.md.
- The in-app updater only installs builds signed with the same certificate.

## Demo video

`node video/render.mjs` renders `video/demo.html` to `site/assets/demo.mp4` (about 50 s, narrated). It needs Playwright with Chromium (`npm i playwright && npx playwright install chromium`, or point `NODE_PATH` at an install). When the app's UI changes, update the matching scene in `demo.html` too.

Narration: the `VOICEOVER` list in `demo.html` (start time, line). With `GEMINI_API_KEY` in `.env` at the repo root (git-ignored, never commit it) the lines are spoken by Gemini TTS, voice Kore; otherwise by macOS `say`. Spoken lines are cached in `video/voice/` (git-ignored), so only changed lines are requested again; the free tier allows about 10 requests a day per model, and the script moves on to the next TTS model when one runs out. It warns when a line runs into the next part; move the scene times in `T` until it doesn't. `--no-voice` renders silently.

Then make the WebM (with audio) and poster:

```
ffmpeg -y -i site/assets/demo.mp4 -c:v libvpx-vp9 -b:v 0 -crf 36 -row-mt 1 -c:a libopus -b:a 96k site/assets/demo.webm
ffmpeg -y -ss 8.7 -i site/assets/demo.mp4 -frames:v 1 -q:v 4 site/assets/demo-poster.jpg
```

`node video/render.mjs --stills 3,7.2` writes single frames to `video/stills/` (git-ignored) for checking.
