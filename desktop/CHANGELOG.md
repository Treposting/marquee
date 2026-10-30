# Marquee for Windows changelog

Early previews of the Windows app. The Release Windows workflow copies a version's section into its pre-release notes.

## Unreleased

- **Capture opens right away.** Area, Window and All-in-One used to take a couple of seconds to show the selection. Marquee now prepares the capture screen, Quick Access and the clipboard panel when it starts, so they appear as soon as you press the shortcut or click.
- **Settings has a gear icon** in the sidebar and the All-in-One toolbar.
- **A cleaner Home.** The tools that work today are larger cards with their shortcuts, and features still on their way to Windows are listed together under "Coming to Windows". The unfinished Colors page is gone until the color picker arrives.
- The capture hint at the top of the screen disappears once you start selecting, and an empty Library has a button to take your first screenshot.

## 0.4.1

- **Quiet start at sign-in.** With Settings → Launch at login on, Marquee now starts in the tray when you sign in to Windows, instead of opening its window every time. Opening Marquee yourself still shows the window.

## 0.4.0

- **All-in-One** (Ctrl+Alt+Shift+A): the toolbar appears right away, and its actions use the full screen until you select an area. Drag to select, drag inside the selection to move it, drag a handle to resize it, use the arrow keys to nudge it (Shift for 10 pixels) and Delete to go back to the full screen. Then **Screenshot** (Enter), **Copy** (Ctrl+C, straight to the clipboard), **Window** (W, then click one) or **Full Screen** (F). The gear opens Settings and Esc cancels. Recording, Copy Text, Pin and the color picker join the toolbar as they arrive on Windows.
- **Clipboard history.** Marquee remembers the text, links, images and files you copy, with the app each came from. Copying the same thing again moves it to the top instead of adding a duplicate. It keeps up to the number set in Settings → Clipboard; pinned items are always kept.
- **Clipboard History panel** (Ctrl+Alt+Shift+V): opens along the bottom of the screen. Type to search, filter by kind, use the arrow keys to choose, and press Enter (or double-click) to paste into the app you were using. Ctrl+1 to Ctrl+9 paste one of the first nine, Ctrl+P pins, Delete removes, Esc closes. With "Paste into the app you were using" off, the item is copied and you press Ctrl+V yourself.
- **Clipboard page** in the Marquee window: the same history as a grid, with search, filters, Copy, Pin and Delete, plus Pause history and Clear history (pinned items stay).
- **Private copies stay private.** Copies that password managers mark as private (the way Windows' own clipboard history is told to skip them) are never recorded, nor is anything from the apps in Settings → Clipboard → Ignored apps, or anything copied while history is paused.

## 0.3.0

- **Quick Access.** After every screenshot, a thumbnail appears in the bottom-left corner of the screen. Hover it to **Copy** or **Save**, or use the small buttons to open it, show it in its folder or close it. Up to four stack up, newest on top. Each one hides after the time set in Settings (it waits while you hover), and the arrow tucks them against the screen's edge until you want them back.
- **Library.** The Library page keeps your last 300 screenshots, newest first. Copy, save, open, show in folder or delete any of them, or clear the whole library.
- **Settings → After capture** now does what it says: with Quick Access off, you get a notification instead, as before.

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
