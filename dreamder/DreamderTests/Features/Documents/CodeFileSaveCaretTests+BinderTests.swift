import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension CodeFileSaveCaretTests {
    @Test
    func theBinderAttachesTheTextViewAndDetachesItOnDestroy() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "a\n")
            defer { session.close() }

            #expect(session.document.attachedTextView === session.textView)

            session.document.textViewBinder.destroy()

            #expect(session.document.attachedTextView == nil)
        }
    }

    @Test
    func destroyingABinderDoesNotDetachAnotherSplitsTextView() async throws {
        try await withTempDir { dir in
            let first = try await openSession(in: dir, name: "first.txt", contents: "a\n")
            defer { first.close() }
            let second = try await openSession(in: dir, name: "second.txt", contents: "b\n")
            defer { second.close() }
            first.document.attachedController = second.hosted.controller

            first.document.textViewBinder.destroy()

            #expect(first.document.attachedTextView === second.textView)
        }
    }

    @Test
    func aReplacementThatChangesNothingMarksNoLine() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab\ncd\n")
            defer { session.close() }
            let before = session.document.modifiedLines

            session.document.trackDidReplace(range: NSRange(location: 0, length: 0), with: "", in: session.textView)

            #expect(session.document.modifiedLines == before)
        }
    }

    @Test
    func aReplacementBeyondTheLaidOutTextMarksTheFirstLine() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab\ncd\n")
            defer { session.close() }
            #expect(!session.document.modifiedLines.contains(0))

            session.document.trackDidReplace(
                range: NSRange(location: 10_000, length: 1),
                with: "x",
                in: session.textView
            )

            #expect(session.document.modifiedLines.contains(0))
        }
    }
}
