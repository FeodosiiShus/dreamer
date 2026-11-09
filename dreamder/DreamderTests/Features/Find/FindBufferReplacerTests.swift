import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindBufferReplacerTests {
    private static let original = "aa foo bb foo cc"
    private static let firstFoo = NSRange(location: 3, length: 3)
    private static let secondFoo = NSRange(location: 10, length: 3)

    @MainActor
    private struct Session {
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let textView: TextView

        var document: CodeFileDocument { fixture.document }

        func close() {
            hosted.close()
        }
    }

    private func job(for document: CodeFileDocument, ranges: [NSRange], replace: String = "quux") throws -> FindReplaceJob {
        var model = FindModel()
        model.stringToFind = "foo"
        model.stringToReplace = replace
        let regex = try #require(model.compileMatcher())
        let url = try #require(document.fileURL)
        return FindReplaceJob(url: url, ranges: ranges, model: model, regex: regex)
    }

    private func hostedSession(in directory: URL, contents: String = FindBufferReplacerTests.original) async throws -> Session {
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "buffer.txt",
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, fixture.document.textViewBinder],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { fixture.document.attachedTextView != nil }
        let textView = try #require(fixture.document.attachedTextView)
        return Session(fixture: fixture, hosted: hosted, textView: textView)
    }

    private func carets(_ textView: TextView) -> [NSRange] {
        textView.selectionManager.textSelections.map(\.range)
    }

    @Test
    func attachedBufferIsEditedThroughTheTextView() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }

            let outcome = FindBufferReplacer.apply(
                try job(for: session.document, ranges: [Self.firstFoo, Self.secondFoo]),
                to: session.document
            )

            #expect(
                outcome == .replaced(
                    FindReplaceResult(
                        text: "aa quux bb quux cc",
                        applied: [
                            FindReplaceEdit(range: Self.firstFoo, replacement: "quux"),
                            FindReplaceEdit(range: Self.secondFoo, replacement: "quux")
                        ],
                        missing: 0
                    )
                )
            )
            #expect(session.textView.string == "aa quux bb quux cc")
            #expect(session.document.content?.string == "aa quux bb quux cc")
        }
    }

    @Test
    func undoRestoresTheOriginalTextInOneStepAndRedoReapplies() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }
            let undoManager = try #require(session.textView.undoManager)

            _ = FindBufferReplacer.apply(
                try job(for: session.document, ranges: [Self.firstFoo, Self.secondFoo]),
                to: session.document
            )
            #expect(session.textView.string == "aa quux bb quux cc")

            undoManager.undo()
            try await eventually { session.textView.string == Self.original }
            #expect(session.document.content?.string == Self.original)

            undoManager.redo()
            try await eventually { session.textView.string == "aa quux bb quux cc" }
            #expect(session.document.content?.string == "aa quux bb quux cc")
        }
    }

    @Test
    func caretsBeforeBetweenAndAfterReplacedMatchesAreMapped() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }
            session.textView.selectionManager.setSelectedRanges([
                NSRange(location: 1, length: 0),
                NSRange(location: 8, length: 0),
                NSRange(location: 16, length: 0)
            ])

            _ = FindBufferReplacer.apply(try job(for: session.document, ranges: [Self.firstFoo]), to: session.document)

            #expect(session.textView.string == "aa quux bb foo cc")
            #expect(
                carets(session.textView) == [
                    NSRange(location: 1, length: 0),
                    NSRange(location: 9, length: 0),
                    NSRange(location: 17, length: 0)
                ]
            )
        }
    }

    @Test
    func caretsAreMappedThroughEveryReplacementOfOneJob() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }
            session.textView.selectionManager.setSelectedRanges([
                NSRange(location: 8, length: 0),
                NSRange(location: 16, length: 0)
            ])

            _ = FindBufferReplacer.apply(
                try job(for: session.document, ranges: [Self.firstFoo, Self.secondFoo]),
                to: session.document
            )

            #expect(carets(session.textView) == [NSRange(location: 9, length: 0), NSRange(location: 18, length: 0)])
        }
    }

    @Test
    func changedTextIsStaleAndKeepsTheBuffer() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }

            let outcome = FindBufferReplacer.apply(
                try job(for: session.document, ranges: [NSRange(location: 40, length: 3)]),
                to: session.document
            )

            #expect(outcome == .stale)
            #expect(session.textView.string == Self.original)
        }
    }

    @Test
    func missingRangesAreCountedInTheResult() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }

            let outcome = FindBufferReplacer.apply(
                try job(for: session.document, ranges: [Self.firstFoo, NSRange(location: 40, length: 3)]),
                to: session.document
            )

            guard case .replaced(let result) = outcome else {
                Issue.record("expected replaced, got \(outcome)")
                return
            }
            #expect(result.missing == 1)
            #expect(!outcome.isClean)
            #expect(result.text == "aa quux bb foo cc")
        }
    }

    @Test
    func nonEditableTextViewFailsAndKeepsTheBuffer() async throws {
        try await withTempDir { dir in
            let session = try await hostedSession(in: dir)
            defer { session.close() }
            session.textView.isEditable = false

            let outcome = FindBufferReplacer.apply(
                try job(for: session.document, ranges: [Self.firstFoo]),
                to: session.document
            )

            #expect(outcome == .failed("buffer.txt is read-only"))
            #expect(session.textView.string == Self.original)
        }
    }

    @Test
    func readOnlyDocumentFails() throws {
        try withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "binary.swift",
                contents: "foo\u{0}foo"
            )
            #expect(fixture.document.isReadOnly)

            let outcome = FindBufferReplacer.apply(
                try job(for: fixture.document, ranges: [NSRange(location: 0, length: 3)]),
                to: fixture.document
            )

            #expect(outcome == .failed("binary.swift is read-only"))
        }
    }

    @Test
    func documentWithoutLoadedTextFails() throws {
        try withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "image.png",
                typeIdentifier: "public.png",
                contents: "foo\u{0}foo"
            )

            let outcome = FindBufferReplacer.apply(
                try job(for: fixture.document, ranges: [NSRange(location: 0, length: 3)]),
                to: fixture.document
            )

            #expect(outcome == .failed("image.png is read-only"))
        }
    }

    @Test
    func unattachedDocumentIsEditedInStorageAndMarkedEdited() throws {
        try withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "detached.txt",
                typeIdentifier: "public.plain-text",
                contents: Self.original
            )
            let document = fixture.document
            #expect(document.attachedTextView == nil)
            #expect(!document.isDocumentEdited)

            let outcome = FindBufferReplacer.apply(
                try job(for: document, ranges: [Self.firstFoo, Self.secondFoo], replace: "x"),
                to: document
            )

            #expect(
                outcome == .replaced(
                    FindReplaceResult(
                        text: "aa x bb x cc",
                        applied: [
                            FindReplaceEdit(range: Self.firstFoo, replacement: "x"),
                            FindReplaceEdit(range: Self.secondFoo, replacement: "x")
                        ],
                        missing: 0
                    )
                )
            )
            #expect(document.content?.string == "aa x bb x cc")
            #expect(document.isDocumentEdited)
            let url = try #require(document.fileURL)
            #expect(try String(contentsOf: url, encoding: .utf8) == Self.original)
        }
    }

    @Test
    func unattachedDocumentWithStaleRangesStaysClean() throws {
        try withTempDir { dir in
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "detached.txt",
                typeIdentifier: "public.plain-text",
                contents: Self.original
            )

            let outcome = FindBufferReplacer.apply(
                try job(for: fixture.document, ranges: [NSRange(location: 40, length: 3)]),
                to: fixture.document
            )

            #expect(outcome == .stale)
            #expect(!fixture.document.isDocumentEdited)
            #expect(fixture.document.content?.string == Self.original)
        }
    }
}
