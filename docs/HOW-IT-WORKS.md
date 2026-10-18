# How CleanShot X and Paste work (and how Marquee does it)

This project is a **clean-room reimplementation**. We did not decompile, disassemble, or copy code or assets from either app. Their EULAs prohibit reverse engineering the binaries, and none of it is needed. Both apps are built on public macOS APIs, and their behavior can be seen from the outside and in their docs and reviews. This file records that behavior and the API each feature maps to.

## CleanShot X: observed behavior

- **Menu-bar app** with global shortcuts. Users often remap the system ⇧⌘3/4/5 to it.
- **Capture modes:** area, window, fullscreen, previous area, self-timer, scrolling capture, screen recording (video/GIF), and text capture (OCR).
- **Quick Access Overlay:** after a capture, a thumbnail appears in a screen corner. Hover actions are copy, save, annotate (pencil), pin, and close. The thumbnail can be dragged into any app. Overlays stack when you take several captures.
- **Annotation editor:** arrows, shapes, text, highlighter, numbered "counter" steps, blur/pixelate, crop, and backgrounds.
- **Pin screenshots:** a borderless always-on-top window you can move, resize, and fade.
- **Cloud upload:** shareable links.

### How it maps to macOS APIs

| Feature | API | Marquee |
|---|---|---|
| Global shortcuts | Carbon `RegisterEventHotKey`. Needs no permission and swallows the key event. | `App/HotKeyCenter.swift` |
| Area/window/fullscreen capture | `ScreenCaptureKit` (`SCScreenshotManager`) or `CGWindowListCreateImage`, plus a custom selection overlay. The simpler route: Apple's `/usr/sbin/screencapture -i` provides the same crosshair UI. | `Capture/CaptureService.swift` uses `screencapture` |
| Permission | Screen Recording (TCC), prompted on first capture | automatic |
| Quick Access overlay | `NSPanel` with `.nonactivatingPanel`, `.floating` level, `.canJoinAllSpaces`. Drag-out via `NSItemProvider` file URL. | `Capture/QuickAccessOverlay.swift` |
| Annotation | Custom drawing canvas; export by rendering shapes over the bitmap | SwiftUI `Canvas` + `ImageRenderer` (`Annotate/`) |
| Pixelate | Core Image `CIPixellate`, clipped to the selected rect | `AnnotationRenderer.pixelate` |
| Pin | Borderless floating `NSPanel` with an `NSImageView` | `Capture/PinnedImageWindow.swift` |
| OCR | Vision `VNRecognizeTextRequest` | `Capture/TextRecognizer.swift` |
| Screen recording | `ScreenCaptureKit` `SCStream` (with `sourceRect` for an area) → `AVAssetWriter` H.264/AAC MP4 | `Record/ScreenRecorder.swift`, `Record/RecordingOutput.swift` |
| Area picker for recording | Full-screen transparent window with a crosshair drag selection | `Record/AreaSelector.swift` |
| GIF export | `AVAssetImageGenerator` frames → `CGImageDestination` (GIF) | `Record/VideoTools.swift` |
| Custom shortcuts | Recorder UI captures `keyDown`; stored in UserDefaults and re-registered with Carbon | `App/Shortcuts.swift`, `UI/ShortcutRecorder.swift` |
| Scrolling capture | Repeated captures while scrolling, stitched by matching overlapping rows | roadmap |

## Paste: observed behavior

- Runs in the background and records everything you copy: text, rich text, images, files, and links. Each entry shows the app it came from.
- **⇧⌘V** opens a full-width panel along the bottom of the screen with a horizontal row of cards. You can search, filter by type, and organize items into pinboards.
- Pressing Enter or double-clicking **pastes into the app you were just in**. The panel doesn't steal focus from that app.
- Skips passwords from password managers.

### How it maps to macOS APIs

| Feature | API | Marquee |
|---|---|---|
| Detect clipboard changes | macOS has **no** change notification. Clipboard managers poll `NSPasteboard.general.changeCount` (every ~0.5 s) and read the new contents when it changes. | `Clipboard/ClipboardMonitor.swift` |
| Source app | `NSWorkspace.shared.frontmostApplication` at the time of the change | same |
| Privacy | The [nspasteboard.org](http://nspasteboard.org) convention: apps add `org.nspasteboard.ConcealedType` / `TransientType` markers, and clipboard managers skip those entries | same |
| Storage | Local database plus image files | JSON + PNG files in `~/Library/Application Support/Marquee` (`ClipboardStore.swift`) |
| Panel that doesn't steal focus | Borderless `NSPanel` with `.nonactivatingPanel` and `canBecomeKey = true`. It gets keyboard input while the other app stays active. | `Clipboard/HistoryPanel.swift` |
| Paste into the other app | Write the item to `NSPasteboard`, hide the panel, then post a synthetic ⌘V with `CGEvent`. Needs the **Accessibility** permission. | `Clipboard/Paster.swift` |
| Avoid re-recording our own paste | After writing, store the new `changeCount` as "seen" | `ClipboardMonitor.ignoreCurrentContents()` |

## Why the two fit together

A screenshot copied by the capture side lands on the pasteboard. The history side then records it like any other copy, so every screenshot you took is also one ⇧⌘V away.

## In-app updates

| Step | API | Marquee |
|---|---|---|
| Find the latest version | GitHub REST API `GET /repos/Treposting/marquee/releases/latest` | `Update/Updater.swift` |
| Compare versions | Numeric comparison of `CFBundleShortVersionString` and the release tag | `Update/AppVersion.swift` |
| Download | `URLSession` download task with progress | `UpdateDownloader` |
| Verify | `ditto` to unzip; bundle ID and version must match; `SecStaticCodeCheckValidity`, plus the running app's designated requirement when it isn't ad-hoc signed | `UpdateInstaller` |
| Install | A small shell helper waits for Marquee to quit, swaps the bundle, and reopens it | `UpdateInstaller.replaceAndRelaunch` |

## Scrolling capture

| Step | API | Marquee |
|---|---|---|
| Grab the area ~10× a second | `SCScreenshotManager.captureImage` with `sourceRect` (macOS 14) | `Capture/ScrollCapture.swift` |
| Find how far it scrolled | Row fingerprints; fixed top/bottom rows set aside; best-matching offset of the moving middle | `Capture/ScrollStitcher.swift` (unit tested) |
| Auto-scroll | `CGEvent` scroll-wheel events (needs Accessibility) | `ScrollCaptureController` |

## Camera and voice

| Step | API | Marquee |
|---|---|---|
| Camera bubble | `AVCaptureSession` + `AVCaptureVideoPreviewLayer` in a borderless panel, clipped to the chosen shape | `Record/CameraOverlay.swift` |
| Keep it in the video | Marquee's windows are excluded from recordings, except the bubble (`SCContentFilter … exceptingWindows:`) | `Record/ScreenRecorder.swift` |
| Voice file | The microphone is its own audio track; it's copied to an .m4a (`AVAssetExportSession`, AppleM4A) before tracks are mixed | `Record/AudioMixdown.swift` |

## Editing recordings

| Step | API | Marquee |
|---|---|---|
| Play and trim | `AVPlayerView` with `beginTrimming` (QuickTime's trim bar) | `Record/VideoEditor.swift` |
| Export | `AVMutableComposition` of the kept range (sound optional) + `AVAssetExportSession` (passthrough, 1080p or 720p presets) | `VideoExport` |
| Resolution while recording | Output size fitted inside 1920×1080 or 1280×720 | `ScreenRecorder.outputSize` (unit tested) |

## Measure

| Step | API | Marquee |
|---|---|---|
| Freeze the screen | `SCScreenshotManager.captureImage` (macOS 14) | `Measure/ScreenSnapshot.swift` |
| Read pixels | Draw the `CGImage` into an RGBA `CGContext` | `PixelBuffer` |
| Find edges | Walk from the pointer until the color changes beyond a tolerance; snap by trimming the background color | `Measure/EdgeFinder.swift` (unit tested) |
| Draw | Core Animation layers over the frozen image | `Measure/MeasureView.swift` |
| Guides | Positions kept as pixel boundaries; snap to the nearest edge from the same walk; gaps between neighbours | `Measure/Guides.swift` (unit tested) |
| Every display | One frozen snapshot and one window per display; the window under the pointer takes the keys | `Measure/MeasureController.swift` |

