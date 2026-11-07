import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct MarkdownPreviewHostedTests {
    private static let document = "# Title\n\nbody\n"

    @Test
    func textEditsRenderOnceWhileAttributeOnlyPassesDoNotRender() async throws {
        try await withTempDir { directory in
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "Doc.md",
                typeIdentifier: "public.source-code",
                contents: Self.document
            )
            let recorder = MarkdownRenderRecorder()
            let model = MarkdownPreviewModel(codeFile: fixture.document, render: { [recorder] in recorder.render($0) })
            let hosted = fixture.host(
                coordinators: [fixture.document.contentCoordinator],
                size: NSSize(width: 900, height: 600)
            )
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView != nil }

            model.start()
            try await eventually { recorder.texts.count == 1 }

            let storage = try #require(fixture.document.content)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: 3))
            storage.endEditing()
            try await Task.sleep(for: .milliseconds(300))
            #expect(recorder.texts == [Self.document])

            let textView = try #require(hosted.controller?.textView)
            textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "A ")
            try await eventually { recorder.texts.count == 2 }
            try await Task.sleep(for: .milliseconds(300))
            #expect(recorder.texts == [Self.document, "A " + Self.document])
        }
    }

    @Test
    func scrollingTheEditorPublishesTheFirstVisibleLineOffset() async throws {
        try await withTempDir { directory in
            let lines = (0..<600).map { "line \($0) with some text" }.joined(separator: "\n")
            let fixture = try HostedSourceEditorFixture.make(
                in: directory,
                fileName: "Long.md",
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

            let clipView = controller.scrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: 3_000))
            controller.scrollView.reflectScrolledClipView(clipView)

            try await eventually { (scrollSync.scrollState.sourceOffset ?? 0) > 0 }
            let offset = try #require(scrollSync.scrollState.sourceOffset)
            let text = lines as NSString
            #expect(offset < text.length)
            #expect(text.substring(with: NSRange(location: offset - 1, length: 1)) == "\n")
            #expect(offset == controller.textView.visibleTextRange?.location)
        }
    }
}
