import SwiftUI
import AppKit

/// The window runs its content under a transparent title bar; the app's own bar (52 tall) sits where the title bar
/// would be, with the traffic lights centred in it. No NSToolbar: on macOS 26 a scroll view next to one runs its
/// content under it and its backdrop takes clicks meant for the bar, so the title bar's own container is made the
/// bar's height instead and the three buttons are placed by hand (again after every layout AppKit does).
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Chrome() }
    func updateNSView(_ v: NSView, context: Context) {}

    final class Chrome: NSView {
        static let bar: CGFloat = 52
        static let inset: CGFloat = 20
        private var watching: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for w in watching { NotificationCenter.default.removeObserver(w) }
            watching = []
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.toolbar = nil
            w.minSize = NSSize(width: Layout.minWidth, height: Layout.minHeight)
            w.tabbingMode = .disallowed
            w.isMovableByWindowBackground = true
            for name in [NSWindow.didResizeNotification, NSWindow.didUpdateNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                watching.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: nil) { [weak self] _ in self?.place() })
            }
            place()
        }

        private func place() {
            guard let w = window, !w.styleMask.contains(.fullScreen),
                  let close = w.standardWindowButton(.closeButton), let titlebar = close.superview, let container = titlebar.superview else { return }
            let h = Chrome.bar
            var f = container.frame
            let y = w.frame.height - h
            if f.height != h || f.origin.y != y {
                f.size.height = h
                f.origin.y = y
                container.frame = f
            }
            let shift = Chrome.inset - close.frame.minX
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let b = w.standardWindowButton(kind) else { continue }
                let to = NSPoint(x: b.frame.minX + shift, y: ((h - b.frame.height) / 2).rounded())
                if b.frame.origin != to { b.setFrameOrigin(to) }
            }
        }
    }
}
