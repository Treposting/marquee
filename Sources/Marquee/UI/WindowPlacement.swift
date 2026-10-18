import AppKit

extension NSWindow {
    /// Puts the window in the exact middle of the screen the pointer is on.
    ///
    /// `NSWindow.center()` isn't used: it places windows above center on the main screen, and
    /// it runs before SwiftUI has sized the window, which then grows from its bottom-left
    /// corner and ends up off to the side. Windows that can't be resized are first sized to
    /// their content here.
    func centerOnActiveScreen() {
        if !styleMask.contains(.resizable), let content = contentViewController?.view ?? contentView {
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            if fitting.width > 10, fitting.height > 10 { setContentSize(fitting) }
        }
        guard let visible = (NSScreen.underMouse ?? screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = frame.size
        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: max(visible.minY, min(visible.maxY - size.height, (visible.midY - size.height / 2).rounded()))
        )
        setFrameOrigin(origin)
    }
}
