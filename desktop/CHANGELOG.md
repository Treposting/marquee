# Marquee for Windows changelog

Early previews of the Windows app. The Release Windows workflow copies a version's section into its pre-release notes.

## 0.2.2

- **Simpler Capture Area.** Area capture now shows only the dimmed screen and your selection with its size. The crosshair lines and the magnifier are gone; together they looked as if Measure and the color picker had started too.
- **Self-timer countdown.** Capture Full Screen in 5 Seconds now shows a 5, 4, 3, 2, 1 countdown in the middle of the screen. It leaves before the screenshot, so it's never in it, and it doesn't take the keyboard away from the app you're capturing.

## 0.2.1

- **Capture Area.** Drag over any part of the screen. The display freezes first, so you capture exactly what you saw. A size label, crosshair and magnifier help you hit the edges; Esc or a right-click cancels.
- **Pick a window.** Capture Window now lets you click the window you want; windows light up as you hover. In either capture, press Space to switch between dragging an area and picking a window.

## 0.2.0

- **Screenshots.** Capture the full screen (the display under the pointer), the window in front, or the full screen after 5 seconds, from the tray, a shortcut or Home. The window capture skips Marquee itself, the taskbar and minimized windows.
- **After capture**, as set in Settings: copy to the clipboard, save as a PNG named like `Marquee 2026-10-30 at 14.03.22.png`, and play a shutter sound. A notification says what happened. If both copy and save are off, the screenshot is copied so it isn't lost.
- **Save folder**: `Pictures\Marquee` unless you choose another one in Settings → General.
- **Fixed**: an empty "is on its way to Windows" message no longer shows every time the window opens.

## 0.1.1

- **Faster, no more double cursor.** The Marquee window no longer makes the whole system sluggish or leaves a second cursor on screen. Its see-through background and blur were too heavy for some PCs, so the window now uses solid Windows colors.

## 0.1.0

First preview: the groundwork. Captures, recording and clipboard history come in the next previews.

- **Tray icon** with the same menu as the Mac app's menu bar: All-in-One, Capture, Record, Measure, Pick Color, Clipboard History.
- **Global shortcuts**: All-in-One is Ctrl+Alt+Shift+A and Clipboard History is Ctrl+Alt+Shift+V. Set your own for any action in Settings → Shortcuts.
- **The Marquee window** with Mica, Home and Settings: after-capture options, sounds, launch at login, clipboard history size and ignored apps (password managers are ignored from the start).
- Closing the window keeps Marquee in the tray. Opening it again shows the running copy.
