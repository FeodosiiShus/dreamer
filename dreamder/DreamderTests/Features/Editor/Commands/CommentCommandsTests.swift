import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CommentCommandsTests {
    nonisolated struct LineCase: Sendable, CustomStringConvertible {
        let fileName: String
        let before: String
        let after: String

        var description: String { fileName + " " + before }
    }

    nonisolated static let lineCases: [LineCase] = [
        LineCase(
            fileName: "Sample.java",
            before: "class A {\n    int a;<caret>\n}\n",
            after: "class A {\n//    int a;\n}<caret>\n"
        ),
        LineCase(
            fileName: "Sample.java",
            before: "class A {\n//    int a;<caret>\n}\n",
            after: "class A {\n    int a;\n}<caret>\n"
        ),
        LineCase(
            fileName: "Sample.py",
            before: "def f():\n    x = 1<caret>\n",
            after: "def f():\n    # x = 1\n<caret>"
        ),
        LineCase(
            fileName: "Sample.tsx",
            before: "const a = (\n  <div>\n    <b/><caret>\n  </div>\n);\n",
            after: "const a = (\n  <div>\n    {/* <b/> */}\n  </div><caret>\n);\n"
        ),
        LineCase(
            fileName: "Sample.json",
            before: "{\n  \"a\": 1<caret>\n}\n",
            after: "{\n//  \"a\": 1\n}<caret>\n"
        ),
        LineCase(
            fileName: "Sample.java",
            before: "class A {\n<selection>    int a;\n    int b;\n</selection>}\n",
            after: "class A {\n<selection>//    int a;\n//    int b;\n</selection>}\n"
        ),
    ]

    @Test(arguments: CommentCommandsTests.lineCases)
    func lineCommentIsAppliedAndUndoneInOneStep(testCase: LineCase) async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: testCase.fileName,
                markup: testCase.before
            )
            defer { harness.close() }
            let original = harness.text

            #expect(harness.actions.toggleLineComment() == .applied)
            #expect(harness.rendered == EditorMarkup.normalized(testCase.after))

            harness.textView.undoManager?.undo()
            #expect(harness.text == original)
        }
    }

    @Test
    func lineCommentOverSeveralLinesIsOneUndoStepAndRedoable() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.java",
                markup: "a<caret>\n\nb<caret>\n"
            )
            defer { harness.close() }
            let original = harness.text

            #expect(harness.actions.toggleLineComment() == .applied)
            #expect(harness.text == "//a\n\n//b\n")

            harness.textView.undoManager?.undo()
            #expect(harness.text == original)

            harness.textView.undoManager?.redo()
            #expect(harness.text == "//a\n\n//b\n")
        }
    }

    @Test
    func lineCommentTogglesBackToTheOriginalText() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.swift",
                markup: "let a = 1<caret>\nlet b = 2\n"
            )
            defer { harness.close() }

            #expect(harness.actions.toggleLineComment() == .applied)
            #expect(harness.text == "// let a = 1\nlet b = 2\n")

            harness.setSelections([NSRange(location: 0, length: 0)])
            #expect(harness.actions.toggleLineComment() == .applied)
            #expect(harness.text == "let a = 1\nlet b = 2\n")
        }
    }

    @Test
    func blockCommentInsertsAnEmptyCommentAtTheCaretAndUndoes() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.java",
                markup: "a<caret>b"
            )
            defer { harness.close() }
            let original = harness.text

            #expect(harness.actions.toggleBlockComment() == .applied)
            #expect(harness.rendered == EditorMarkup.normalized("a/*<caret>*/b"))

            harness.textView.undoManager?.undo()
            #expect(harness.text == original)
        }
    }

    @Test
    func plainTextFilesReportUnsupportedComments() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.txt",
                markup: "a<caret>\n"
            )
            defer { harness.close() }

            #expect(harness.actions.toggleLineComment() == .unsupported(LineCommenter.unsupportedMessage))
            #expect(harness.actions.toggleBlockComment() == .unsupported(BlockCommenter.unsupportedMessage))
            #expect(harness.text == "a\n")
        }
    }

    @Test
    func languagesWithoutBlockCommentsReportUnsupportedBlockComments() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.py",
                markup: "a<caret>\n"
            )
            defer { harness.close() }

            #expect(harness.actions.toggleBlockComment() == .unsupported(BlockCommenter.unsupportedMessage))
            #expect(harness.text == "a\n")
        }
    }

    @Test
    func emptyBufferIsLeftUnchangedByLineComment() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.java",
                markup: ""
            )
            defer { harness.close() }

            #expect(harness.actions.toggleLineComment() == .unchanged)
            #expect(harness.text.isEmpty)
        }
    }

    @Test
    func readOnlyEditorIgnoresBothCommentCommands() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.java",
                markup: "a<caret>\n",
                isEditable: false
            )
            defer { harness.close() }

            #expect(harness.actions.toggleLineComment() == .unchanged)
            #expect(harness.actions.toggleBlockComment() == .unchanged)
            #expect(harness.text == "a\n")
        }
    }

    @Test
    func caretsOnlyOnCommentedLinesUncommentThemAndKeepTheOtherCaret() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.java",
                markup: "//a<caret>\nx\n//b<caret>\n"
            )
            defer { harness.close() }

            #expect(harness.actions.toggleLineComment() == .applied)
            #expect(harness.rendered == EditorMarkup.normalized("a\nx<caret>\nb\n<caret>"))
        }
    }
}
