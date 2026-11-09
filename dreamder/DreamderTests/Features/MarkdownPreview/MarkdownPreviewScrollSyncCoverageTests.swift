import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownPreviewScrollSyncCoverageTests {
    @Test
    func followIgnoresRepeatedOffsets() {
        let state = MarkdownPreviewScrollState()
        #expect(state.sourceOffset == nil)
        state.follow(5)
        state.follow(5)
        #expect(state.sourceOffset == 5)
        state.follow(9)
        #expect(state.sourceOffset == 9)
    }

    @Test
    func publishingWithoutControllerLeavesOffsetUntouched() {
        let coordinator = MarkdownScrollSyncCoordinator()
        coordinator.publishFirstVisibleOffset()
        #expect(coordinator.scrollState.sourceOffset == nil)
    }

    @Test
    func destroyStopsFollowingTheEditorScroll() async throws {
        try await withTempDir { directory in
            let lines = (0..<600).map { "line \($0) with some text" }.joined(separator: "\n")
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "Destroy.md",
                typeIdentifier: "public.source-code",
                contents: lines
            )
            let scrollSync = MarkdownScrollSyncCoordinator()
            let hosted = fixture.host(
                coordinators: [fixture.document.contentCoordinator, scrollSync],
                size: NSSize(width: 900, height: 400)
            )
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView != nil }
            let controller = try #require(hosted.controller)

            scrollSync.destroy()
            let before = scrollSync.scrollState.sourceOffset

            let clipView = controller.scrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: 3_000))
            controller.scrollView.reflectScrolledClipView(clipView)
            try await Task.sleep(for: .milliseconds(300))

            #expect(scrollSync.scrollState.sourceOffset == before)
            scrollSync.publishFirstVisibleOffset()
            #expect(scrollSync.scrollState.sourceOffset == before)
        }
    }
}
