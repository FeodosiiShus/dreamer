import AppKit
import SwiftUI

enum WelcomeWindowStyle {
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
    }
}

struct WelcomeWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> WelcomeWindowObserverView {
        WelcomeWindowObserverView()
    }

    func updateNSView(_ nsView: WelcomeWindowObserverView, context: Context) {}
}

final class WelcomeWindowObserverView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            WelcomeWindowStyle.apply(to: window)
        }
    }
}
