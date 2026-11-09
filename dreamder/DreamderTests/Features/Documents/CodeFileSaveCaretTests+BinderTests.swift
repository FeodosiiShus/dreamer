import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension CodeFileSaveCaretTests {
    @Test
    func theBinderAttachesTheTextViewOfTheHostedEditor() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "a\n")
            defer { session.close() }

            #expect(session.document.attachedTextView === session.textView)
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
