import AppKit
import Synchronization
import Testing
@testable import Dreamder

final class SearchPanelCloseCounter: Sendable {
    let count = Mutex(0)
}

@MainActor
@Suite(.uiGate)
struct SearchPanelTests {
    @Test func panelIsAFloatingTitlelessSearchBar() throws {
        let panel = SearchPanel()
        defer { panel.close() }

        #expect(panel.delegate === panel)
        #expect(panel.styleMask.contains([.fullSizeContentView, .titled, .resizable]))
        #expect(panel.titlebarAppearsTransparent)
        #expect(panel.isMovableByWindowBackground)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.contentRect(forFrameRect: panel.frame).size == NSSize(width: 500, height: 48))
    }

    @Test func standardWindowButtonsAreHidden() throws {
        let panel = SearchPanel()
        defer { panel.close() }

        let closeButton = try #require(panel.standardWindowButton(.closeButton))
        #expect(closeButton.isHidden)
    }

    @Test func resigningKeyClosesThePanel() {
        let panel = SearchPanel()
        panel.orderFront(nil)
        let counter = SearchPanelCloseCounter()
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: nil
        ) { _ in counter.count.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(token) }

        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))

        #expect(counter.count.withLock { $0 } == 1)
    }
}
