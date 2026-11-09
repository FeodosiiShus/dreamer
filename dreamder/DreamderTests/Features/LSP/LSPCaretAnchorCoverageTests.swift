import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LSPCaretAnchorCoverageTests {
    private static let source = "alpha beta\ngamma\n"

    private func hostEditor(in directory: URL) async throws -> (hosted: HostedSourceEditor, textView: TextView) {
        let fixture = try HostedSourceEditorFixture.make(in: directory, contents: Self.source)
        let hosted = fixture.host(coordinators: [])
        try await eventually { hosted.controller?.textView != nil }
        let textView = try #require(hosted.controller?.textView)
        try await eventually {
            hosted.window.layoutIfNeeded()
            return textView.layoutManager.rectForOffset(0) != nil
        }
        hosted.window.makeFirstResponder(textView)
        return (hosted, textView)
    }

    @Test
    func theAnchorFollowsTheCaretOfTheFocusedEditor() async throws {
        try await withTempDir { directory in
            let (hosted, textView) = try await hostEditor(in: directory)
            defer { hosted.close() }
            hosted.controller?.setCursorPositions([CursorPosition(range: NSRange(location: 6, length: 0))])

            let anchor = try #require(LSPCaretAnchor.screenRect(in: hosted.window))

            let caret = try #require(textView.layoutManager.rectForOffset(6))
            let expected = hosted.window.convertToScreen(textView.convert(caret, to: nil))
            #expect(anchor == expected)
        }
    }

    @Test
    func withoutASelectionTheAnchorSitsAtTheEndOfTheText() async throws {
        try await withTempDir { directory in
            let (hosted, textView) = try await hostEditor(in: directory)
            defer { hosted.close() }
            textView.selectionManager.setSelectedRanges([])

            let anchor = try #require(LSPCaretAnchor.screenRect(in: hosted.window))

            let caret = try #require(textView.layoutManager.rectForOffset(textView.textStorage.length))
            let expected = hosted.window.convertToScreen(textView.convert(caret, to: nil))
            #expect(anchor == expected)
        }
    }

    @Test
    func aCaretWithoutALayoutRectYieldsNoAnchor() async throws {
        try await withTempDir { directory in
            let (hosted, textView) = try await hostEditor(in: directory)
            defer { hosted.close() }
            hosted.controller?.setCursorPositions([CursorPosition(range: NSRange(location: 0, length: 0))])
            let selection = try #require(textView.selectionManager.textSelections.first)
            selection.range = NSRange(location: -1, length: 0)

            #expect(textView.layoutManager.rectForOffset(-1) == nil)
            #expect(LSPCaretAnchor.screenRect(in: hosted.window) == nil)
        }
    }

    @Test
    func aWindowWithoutContentYieldsNoAnchor() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = nil
        defer { window.close() }

        #expect(LSPCaretAnchor.screenRect(in: window) == nil)
        #expect(LSPCaretAnchor.screenRect(in: nil) == nil)
    }
}
