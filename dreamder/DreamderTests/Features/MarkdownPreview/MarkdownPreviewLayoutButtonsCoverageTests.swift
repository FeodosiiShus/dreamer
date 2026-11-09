import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownPreviewLayoutButtonsCoverageTests {
    private let file = URL(fileURLWithPath: "/tmp/notes/README.md")
    private let size = NSSize(width: 120, height: 40)

    @Test
    func hoveringTracksOnlyTheModeThatIsCurrentlyHovered() {
        let hover = MarkdownPreviewLayoutHover()
        #expect(hover.hovered == nil)

        hover.update(.previewOnly, isHovering: true)
        #expect(hover.hovered == .previewOnly)

        hover.update(.editorOnly, isHovering: false)
        #expect(hover.hovered == .previewOnly)

        hover.update(.editorOnly, isHovering: true)
        #expect(hover.hovered == .editorOnly)

        hover.update(.editorOnly, isHovering: false)
        #expect(hover.hovered == nil)
    }

    @Test
    func hoverActionsFeedTheHoverModel() {
        let hover = MarkdownPreviewLayoutHover()

        MarkdownPreviewLayoutButtons.hoverAction(for: .previewOnly, hover: hover)(true)
        #expect(hover.hovered == .previewOnly)

        MarkdownPreviewLayoutButtons.hoverAction(for: .previewOnly, hover: hover)(false)
        #expect(hover.hovered == nil)
    }

    @Test
    func selectionActionsSelectTheLayoutAndFlipTheOrientationOfTheSelectedSplit() throws {
        try withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            #expect(store.layout(for: file) == .editorAndPreview)

            MarkdownPreviewLayoutButtons.selectionAction(for: .previewOnly, store: store, url: file)()
            #expect(store.layout(for: file) == .previewOnly)

            MarkdownPreviewLayoutButtons.selectionAction(for: .editorAndPreview, store: store, url: file)()
            #expect(store.layout(for: file) == .editorAndPreview)
            let orientation = store.isVerticalSplit(for: file)

            MarkdownPreviewLayoutButtons.selectionAction(for: .editorAndPreview, store: store, url: file)()
            #expect(store.isVerticalSplit(for: file) == !orientation)
        }
    }

    @Test
    func theButtonsRenderTheSelectedHoveredAndIdleBackgrounds() async throws {
        try await withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            let hover = MarkdownPreviewLayoutHover()
            let hosted = HostedViewFixture.host(size: size) {
                MarkdownPreviewLayoutButtons(store: store, url: file, hover: hover)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            let idle = hosted.snapshot()

            MarkdownPreviewLayoutButtons.hoverAction(for: .previewOnly, hover: hover)(true)
            try await hosted.settle(.milliseconds(100))
            let hovered = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(idle, hovered))

            MarkdownPreviewLayoutButtons.hoverAction(for: .previewOnly, hover: hover)(false)
            try await hosted.settle(.milliseconds(100))
            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()) == false)

            MarkdownPreviewLayoutButtons.selectionAction(for: .editorOnly, store: store, url: file)()
            try await hosted.settle(.milliseconds(100))
            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))
            #expect(store.layout(for: file) == .editorOnly)

            store.setVerticalSplit(false)
            MarkdownPreviewLayoutButtons.selectionAction(for: .editorAndPreview, store: store, url: file)()
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
        }
    }

    @Test
    func replacingTheRootViewKeepsTheButtonsRendering() async throws {
        try await withTempDir { directory in
            let store = MarkdownPreviewStoreHarness(directory: directory).makeStore()
            let hosted = HostedViewFixture.host(size: size) {
                MarkdownPreviewLayoutButtons(store: store, url: file)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())

            hosted.hosting.rootView = AnyView(MarkdownPreviewLayoutButtons(store: store, url: file))
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
        }
    }
}
