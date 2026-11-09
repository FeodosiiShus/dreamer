import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorActionCoordinatorTests {
    @Test
    func detachedCoordinatorIgnoresEveryCommand() {
        let coordinator = EditorActionCoordinator()

        coordinator.duplicateLineOrSelection()
        coordinator.deleteLine()
        coordinator.joinLines()
        coordinator.moveLines(up: true)
        coordinator.moveLines(up: false)
        coordinator.selectNextOccurrence()
        coordinator.selectAllOccurrences()
        coordinator.unselectLastOccurrence()
        coordinator.cloneCaret(above: true)
        coordinator.indentSelection()
        coordinator.unindentSelection()
        coordinator.goToLine(line: 1, column: 1)
        coordinator.showGoToLine()

        #expect(coordinator.toggleLineComment() == .unchanged)
        #expect(coordinator.toggleBlockComment() == .unchanged)
        #expect(coordinator.toggleSoftWraps() == nil)
        #expect(!coordinator.isMonitoringInput)
        #expect(!coordinator.goToLinePresenter.isPresented)
    }

    @Test
    func detachedEditorInstanceKeepsItsSoftWrapOverrideEmpty() {
        let instance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/one.txt")))

        instance.toggleSoftWraps()

        #expect(instance.wrapLinesOverride == nil)
    }

    @Test
    func readOnlyEditorsRejectEveryEdit() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "ReadOnly.swift",
                markup: "<selection>aa\nbb<caret></selection>\n",
                isEditable: false
            )
            defer { harness.close() }
            let original = harness.text
            let actions = harness.actions

            actions.duplicateLineOrSelection()
            actions.deleteLine()
            actions.joinLines()
            actions.moveLines(up: false)
            actions.indentSelection()
            actions.unindentSelection()

            #expect(actions.toggleLineComment() == .unchanged)
            #expect(actions.toggleBlockComment() == .unchanged)
            #expect(harness.text == original)
        }
    }

    @Test
    func anEditIsOneUndoStepAndCanBeRedone() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "aa<caret>\nbb\n")
            defer { harness.close() }

            harness.actions.duplicateLineOrSelection()
            #expect(harness.text == "aa\naa\nbb\n")

            harness.textView.undoManager?.undo()
            #expect(harness.text == "aa\nbb\n")

            harness.textView.undoManager?.redo()
            #expect(harness.text == "aa\naa\nbb\n")
        }
    }

    @Test
    func unknownLanguagesReportUnsupportedComments() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Sample.unknownext",
                markup: "aa<caret>\n"
            )
            defer { harness.close() }

            guard case .unsupported = harness.actions.toggleLineComment() else {
                Issue.record("expected unsupported line comment")
                return
            }
            guard case .unsupported = harness.actions.toggleBlockComment() else {
                Issue.record("expected unsupported block comment")
                return
            }
            #expect(harness.text == "aa\n")
        }
    }

    @Test
    func softWrapsToggleOnTheHostedEditor() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "aa<caret>\n")
            defer { harness.close() }

            #expect(!harness.textView.wrapLines)
            #expect(harness.actions.toggleSoftWraps() == true)
            #expect(harness.textView.wrapLines)
            #expect(harness.actions.toggleSoftWraps() == false)
            #expect(!harness.textView.wrapLines)
        }
    }

    @Test
    func indentAndUnindentShiftTheSelectedLines() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                markup: "<selection>a\nb<caret></selection>"
            )
            defer { harness.close() }
            try await eventually { harness.controller.cursorPositions.map(\.range) == harness.selections }

            harness.actions.indentSelection()
            #expect(harness.text != "a\nb")

            harness.actions.unindentSelection()
            #expect(harness.text == "a\nb")
        }
    }

    @Test
    func goToLineClampsLineAndColumn() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "ab\ncde\nf<caret>")
            defer { harness.close() }
            let actions = harness.actions

            actions.goToLine(line: 2, column: 3)
            #expect(harness.selections == [NSRange(location: 5, length: 0)])

            actions.goToLine(line: 99, column: nil)
            #expect(harness.selections == [NSRange(location: 7, length: 0)])

            actions.goToLine(line: 0, column: 99)
            #expect(harness.selections == [NSRange(location: 2, length: 0)])

            actions.goToLine(line: 2, column: 0)
            #expect(harness.selections == [NSRange(location: 3, length: 0)])
        }
    }

    @Test
    func goToLinePopupMovesTheCaretWhenSubmitted() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "aa\nbb<caret>\ncc")
            defer { harness.close() }

            harness.actions.showGoToLine()

            let presenter = harness.actions.goToLinePresenter
            #expect(presenter.isPresented)
            let popover = try #require(presenter.popover)
            let hosting = try #require(popover.contentViewController as? NSHostingController<GoToLinePopupView>)
            let model = hosting.rootView.model
            #expect(model.input == "2:3")
            #expect(model.lineCount == 3)

            model.input = "3:2"
            model.submit()

            #expect(harness.selections == [NSRange(location: 7, length: 0)])
            #expect(!presenter.isPresented)
        }
    }

    @Test
    func occurrenceSelectionForgetsAPrimaryThatIsNoLongerSelected() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "foo f<caret>oo foo")
            defer { harness.close() }
            let actions = harness.actions

            actions.selectNextOccurrence()
            #expect(harness.selections == [NSRange(location: 4, length: 3)])
            actions.selectNextOccurrence()
            #expect(harness.selections.count == 2)

            harness.setSelections([NSRange(location: 0, length: 3)])
            actions.selectNextOccurrence()

            #expect(harness.selections.contains(NSRange(location: 0, length: 3)))
            #expect(harness.selections.count == 2)
        }
    }

    @Test
    func cloningAtTheTopOfTheDocumentChangesNothing() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "a<caret>b\ncd")
            defer { harness.close() }

            harness.actions.cloneCaret(above: true)

            #expect(harness.selections == [NSRange(location: 1, length: 0)])
        }
    }

    @Test
    func theRangeTranslatorRoutesLineMovesThroughTheActions() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "aa\nb<caret>b\ncc\n")
            defer { harness.close() }

            harness.fixture.editorInstance.rangeTranslator.moveLinesUp()
            #expect(harness.text == "bb\naa\ncc\n")

            harness.fixture.editorInstance.rangeTranslator.moveLinesDown()
            #expect(harness.text == "aa\nbb\ncc\n")
        }
    }

    @Test
    func commandBracketsDoNotIndentThroughTheDefaultMenuRoute() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "alpha<caret>")
            defer { harness.close() }
            try await eventually { harness.actions.isMonitoringInput }
            let window = harness.hosted.window
            window.makeFirstResponder(harness.textView)
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.command],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: "]",
                    charactersIgnoringModifiers: "]",
                    isARepeat: false,
                    keyCode: 30
                )
            )

            NSApp.sendEvent(event)

            #expect(harness.text == "alpha")
        }
    }

    @Test
    func joiningTwoLineCommentsUsesTheFilesCommentPrefix() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(
                in: directory,
                fileName: "Join.swift",
                markup: "// one<caret>\n// two\n"
            )
            defer { harness.close() }

            harness.actions.joinLines()

            #expect(harness.rendered == EditorMarkup.normalized("// one<caret> two\n"))
        }
    }
}
