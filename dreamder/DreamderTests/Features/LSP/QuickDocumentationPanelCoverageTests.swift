import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class CloseCounter {
    var count = 0
}

@MainActor
@Suite(.uiGate)
struct QuickDocumentationPanelCoverageTests {
    private func makeParent(in visible: NSRect) -> NSWindow {
        let parent = NSWindow(
            contentRect: NSRect(x: visible.minX + 100, y: visible.minY + 100, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        return parent
    }

    private func visibleFrame() throws -> NSRect {
        try #require(NSScreen.main).visibleFrame
    }

    @Test
    func panelNeverBecomesKeyOrMain() {
        let panel = QuickDocumentationPanel(size: NSSize(width: 300, height: 100))

        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test
    func panelWithoutAnchorIsCenteredNearTheTopOfItsParent() throws {
        let parent = makeParent(in: try visibleFrame())
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))

        panel.place(in: parent, beside: nil)

        #expect(panel.frame.size == NSSize(width: 400, height: 200))
        #expect(panel.frame.midX == parent.frame.midX)
        #expect(panel.frame.maxY == parent.frame.maxY - 92)
    }

    @Test
    func panelIsPlacedBelowTheAnchorWhenThereIsRoom() throws {
        let visible = try visibleFrame()
        let parent = makeParent(in: visible)
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))
        let anchor = NSRect(x: visible.minX + 150, y: visible.minY + 500, width: 4, height: 18)

        panel.place(in: parent, beside: anchor)

        #expect(panel.frame.minX == anchor.minX)
        #expect(panel.frame.maxY == anchor.minY - 6)
    }

    @Test
    func panelIsPlacedAboveTheAnchorWhenTheScreenBottomIsTooClose() throws {
        let visible = try visibleFrame()
        let parent = makeParent(in: visible)
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))
        let anchor = NSRect(x: visible.minX + 150, y: visible.minY + 20, width: 4, height: 18)

        panel.place(in: parent, beside: anchor)

        #expect(panel.frame.minY == anchor.maxY + 6)
    }

    @Test
    func panelIsClampedInsideTheVisibleScreenArea() throws {
        let visible = try visibleFrame()
        let parent = makeParent(in: visible)
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 400, height: 200))

        panel.place(in: parent, beside: NSRect(x: visible.maxX + 500, y: visible.minY + 500, width: 4, height: 18))
        #expect(panel.frame.maxX == visible.maxX - 8)

        panel.place(in: parent, beside: NSRect(x: visible.minX - 500, y: visible.minY + 500, width: 4, height: 18))
        #expect(panel.frame.minX == visible.minX + 8)

        panel.place(in: parent, beside: NSRect(x: visible.minX + 150, y: visible.maxY + 500, width: 4, height: 18))
        #expect(panel.frame.maxY == visible.maxY - 8)
    }

    @Test
    func closingThePanelDetachesItAndRunsTheCloseHandlerOnce() throws {
        let parent = makeParent(in: try visibleFrame())
        defer { parent.close() }
        let panel = QuickDocumentationPanel(size: NSSize(width: 300, height: 100))
        let counter = CloseCounter()
        panel.onClose = { counter.count += 1 }
        parent.addChildWindow(panel, ordered: .above)

        panel.close()
        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: panel))

        #expect(counter.count == 1)
        #expect(panel.onClose == nil)
        #expect(parent.childWindows?.contains(panel) != true)
    }
}

@MainActor
@Suite(.uiGate)
struct QuickDocumentationViewCoverageTests {
    private func host(_ model: QuickDocumentationViewModel) -> HostedView {
        HostedViewFixture.host(size: model.size) {
            QuickDocumentationView(model: model)
        }
    }

    @Test
    func everyBlockKindRendersVisibleContent() async throws {
        let markdown = "**Int** — a `number` with [link](https://example.com)\n\n"
            + "```swift\nlet value = 1\n```\n\nTail."
        let models = [
            QuickDocumentationViewModel(content: QuickDocumentationContent(text: markdown, isMarkdown: true)),
            QuickDocumentationViewModel(content: QuickDocumentationContent(text: "Int\nA number", isMarkdown: false)),
            QuickDocumentationViewModel(message: "No documentation found")
        ]

        for model in models {
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func differentContentRendersDifferently() async throws {
        let prose = host(QuickDocumentationViewModel(message: "Int"))
        let code = host(QuickDocumentationViewModel(
            content: QuickDocumentationContent(text: "```swift\nfunc run() -> Int\n```", isMarkdown: true)
        ))
        defer {
            prose.close()
            code.close()
        }
        try await prose.settle()
        try await code.settle()

        #expect(HostedView.pixelsDiffer(prose.snapshot(), code.snapshot()))
    }

    @Test
    func closingTheModelCallsTheDismissHandlerWhenOneIsSet() {
        let model = QuickDocumentationViewModel(message: "docs")
        let counter = CloseCounter()

        model.close()
        model.dismiss = { counter.count += 1 }
        model.close()

        #expect(counter.count == 1)
    }
}
