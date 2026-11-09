import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileSaveCaretTests {
    private static let trimAndFinalNewline = """
        root = true
        [*.txt]
        trim_trailing_whitespace = true
        insert_final_newline = true

        """

    @MainActor
    struct Session {
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let textView: TextView

        var document: CodeFileDocument { fixture.document }

        var selections: [NSRange] {
            textView.selectionManager.textSelections.map(\.range)
        }

        func close() {
            hosted.close()
        }
    }

    private static let allLinesWithoutCaretRule = SaveActionSettings(
        trailingSpaces: .allLines,
        keepTrailingSpacesOnCaretLine: false,
        ensureFinalNewline: false
    )

    private static let silentEditorConfig = "root = true\n"

    func openSession(
        in directory: URL,
        name: String = "caret.txt",
        contents: String,
        editorConfig: String = CodeFileSaveCaretTests.trimAndFinalNewline
    ) async throws -> Session {
        try editorConfig.write(
            to: directory.appending(path: ".editorconfig"),
            atomically: true,
            encoding: .utf8
        )
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: name,
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, fixture.document.textViewBinder],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView != nil }
        let textView = try #require(hosted.controller?.textView)
        return Session(fixture: fixture, hosted: hosted, textView: textView)
    }

    @Test
    func caretAtTheEndStaysBeforeTheAppendedNewline() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab  \ncd  \nef")
            defer { session.close() }
            session.textView.selectionManager.setSelectedRange(NSRange(location: 12, length: 0))

            #expect(session.document.applySaveActions(settings: Self.allLinesWithoutCaretRule))

            #expect(session.textView.string == "ab\ncd\nef\n")
            #expect(session.document.content?.string == "ab\ncd\nef\n")
            #expect(session.selections == [NSRange(location: 8, length: 0)])
        }
    }

    @Test
    func caretsBeforeInsideAndAfterTrimmedWhitespaceAreRemapped() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab  \ncd  \nef")
            defer { session.close() }
            session.textView.selectionManager.setSelectedRanges([
                NSRange(location: 1, length: 0),
                NSRange(location: 3, length: 0),
                NSRange(location: 7, length: 0),
                NSRange(location: 11, length: 0)
            ])

            #expect(session.document.applySaveActions(settings: Self.allLinesWithoutCaretRule))

            #expect(
                session.selections == [
                    NSRange(location: 1, length: 0),
                    NSRange(location: 2, length: 0),
                    NSRange(location: 5, length: 0),
                    NSRange(location: 7, length: 0)
                ]
            )
        }
    }

    @Test
    func aCaretOnALineWithoutTrailingWhitespaceDoesNotMove() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "first\nsecond  \nthird\n")
            defer { session.close() }
            session.textView.selectionManager.setSelectedRange(NSRange(location: 3, length: 0))

            #expect(session.document.applySaveActions(settings: Self.allLinesWithoutCaretRule))

            #expect(session.textView.string == "first\nsecond\nthird\n")
            #expect(session.selections == [NSRange(location: 3, length: 0)])
        }
    }

    @Test
    func aNonEditableTextViewFallsBackToTheStorage() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab  \ncd")
            defer { session.close() }
            session.textView.isEditable = false

            #expect(session.document.applySaveActions(settings: Self.allLinesWithoutCaretRule))

            #expect(session.document.content?.string == "ab\ncd\n")
        }
    }

    @Test
    func caretLineKeepsItsTrailingSpacesWhenTheOptionIsOn() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab  \ncd  \nef  \n")
            defer { session.close() }
            session.textView.selectionManager.setSelectedRange(NSRange(location: 8, length: 0))
            let keep = SaveActionSettings(
                trailingSpaces: .allLines,
                keepTrailingSpacesOnCaretLine: true,
                ensureFinalNewline: false
            )

            #expect(session.document.applySaveActions(settings: keep))

            #expect(session.textView.string == "ab\ncd  \nef\n")
            #expect(session.selections == [NSRange(location: 6, length: 0)])
        }
    }

    @Test
    func caretLineLosesItsTrailingSpacesWhenTheOptionIsOff() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab  \ncd  \nef  \n")
            defer { session.close() }
            session.textView.selectionManager.setSelectedRange(NSRange(location: 8, length: 0))

            #expect(session.document.applySaveActions(settings: Self.allLinesWithoutCaretRule))

            #expect(session.textView.string == "ab\ncd\nef\n")
            #expect(session.selections == [NSRange(location: 5, length: 0)])
        }
    }

    @Test
    func modifiedLinesModeOnlyTouchesLinesEditedSinceOpen() async throws {
        try await withTempDir { dir in
            let session = try await openSession(
                in: dir,
                contents: "a  \nb  \nc  \n",
                editorConfig: Self.silentEditorConfig
            )
            defer { session.close() }
            let modified = SaveActionSettings(
                trailingSpaces: .modifiedLines,
                keepTrailingSpacesOnCaretLine: false,
                ensureFinalNewline: false
            )
            #expect(session.document.modifiedLines.isEmpty)
            #expect(!session.document.applySaveActions(settings: modified))

            session.textView.replaceCharacters(in: NSRange(location: 5, length: 0), with: "x")

            #expect(session.document.modifiedLines == IndexSet([1]))
            #expect(session.document.applySaveActions(settings: modified))
            #expect(session.textView.string == "a  \nbx\nc  \n")
        }
    }

    @Test
    func allLinesModeTouchesUntouchedLinesToo() async throws {
        try await withTempDir { dir in
            let session = try await openSession(
                in: dir,
                contents: "a  \nb  \nc  \n",
                editorConfig: Self.silentEditorConfig
            )
            defer { session.close() }
            session.textView.replaceCharacters(in: NSRange(location: 5, length: 0), with: "x")

            #expect(session.document.applySaveActions(settings: Self.allLinesWithoutCaretRule))

            #expect(session.textView.string == "a\nbx\nc\n")
        }
    }

    @Test
    func modifiedLinesFollowInsertionsAndDeletionsOfLineBreaks() async throws {
        try await withTempDir { dir in
            let session = try await openSession(
                in: dir,
                contents: "a\nb\nc\nd\n",
                editorConfig: Self.silentEditorConfig
            )
            defer { session.close() }

            session.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: "x")
            #expect(session.document.modifiedLines == IndexSet([3]))

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "new\n")
            #expect(session.document.modifiedLines == IndexSet([0, 1, 4]))

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
            #expect(session.document.modifiedLines == IndexSet([0, 3]))

            session.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "")
            #expect(session.document.modifiedLines == IndexSet([0, 3]))
        }
    }

    @Test
    func savingClearsTheModifiedLinesExceptDeferredCaretLines() async throws {
        try await withTempDir { dir in
            let session = try await openSession(
                in: dir,
                contents: "a  \nb  \n",
                editorConfig: Self.silentEditorConfig
            )
            defer { session.close() }
            let keep = SaveActionSettings(
                trailingSpaces: .modifiedLines,
                keepTrailingSpacesOnCaretLine: true,
                ensureFinalNewline: false
            )
            session.textView.replaceCharacters(in: NSRange(location: 1, length: 0), with: "x")
            session.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: "y")
            session.textView.selectionManager.setSelectedRange(NSRange(location: 8, length: 0))
            #expect(session.document.modifiedLines == IndexSet([0, 1]))

            #expect(session.document.applySaveActions(settings: keep))
            #expect(session.document.modifiedLines == IndexSet([0, 1]))

            session.document.updateChangeCount(
                withToken: session.document.changeCountToken(for: .saveOperation),
                for: .saveOperation
            )

            #expect(session.document.modifiedLines == IndexSet([1]))
            #expect(session.textView.string == "ax\nby  \n")
        }
    }
}
