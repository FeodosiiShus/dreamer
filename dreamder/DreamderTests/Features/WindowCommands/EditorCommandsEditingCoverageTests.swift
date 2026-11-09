import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class UnsupportedReasonRecorder {
    private(set) var reasons: [String] = []

    func record(_ reason: String) {
        reasons.append(reason)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorCommandsEditingCoverageTests {
    private func open(
        _ directory: URL,
        _ markup: String,
        fileName: String = "Lines.txt",
        isEditable: Bool = true
    ) async throws -> EditorCommandHarness {
        try await EditorCommandHarness.open(in: directory, fileName: fileName, markup: markup, isEditable: isEditable)
    }

    @Test
    func lineEditButtonsDuplicateDeleteAndJoinTheCaretLine() async throws {
        try await withTempDir { directory in
            let duplicate = try await open(directory, "aa<caret>\nbb\n", fileName: "Duplicate.txt")
            defer { duplicate.close() }
            let duplicateTab = duplicate.fixture.editorInstance
            let duplicateMenu = CommandsACoverageSupport.host {
                EditorCommands.LineEditButtons(currentTab: { duplicateTab })
            }
            defer { duplicateMenu.close() }
            #expect(duplicateMenu.titles == ["Duplicate Line or Selection", "Delete Line", "Join Lines"])
            try duplicateMenu.click(0)
            #expect(duplicate.text == "aa\naa\nbb\n")

            let delete = try await open(directory, "aa\nb<caret>b\ncc\n", fileName: "Delete.txt")
            defer { delete.close() }
            let deleteTab = delete.fixture.editorInstance
            let deleteMenu = CommandsACoverageSupport.host {
                EditorCommands.LineEditButtons(currentTab: { deleteTab })
            }
            defer { deleteMenu.close() }
            try deleteMenu.click(1)
            #expect(delete.text == "aa\ncc\n")

            let join = try await open(directory, "a<caret>a\nbb\n", fileName: "Join.txt")
            defer { join.close() }
            let joinTab = join.fixture.editorInstance
            let joinMenu = CommandsACoverageSupport.host {
                EditorCommands.LineEditButtons(currentTab: { joinTab })
            }
            defer { joinMenu.close() }
            try joinMenu.click(2)
            #expect(join.text == "aa bb\n")
        }
    }

    @Test
    func lineEditButtonsDoNothingWhenDisabledOrWithoutATab() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, "aa<caret>\nbb\n")
            defer { harness.close() }
            let tab = harness.fixture.editorInstance
            let disabled = CommandsACoverageSupport.host {
                EditorCommands.LineEditButtons(currentTab: { tab }, isEnabled: false)
            }
            defer { disabled.close() }
            try disabled.click(0)
            try disabled.click(1)
            try disabled.click(2)
            #expect(disabled.enabledStates == [false, false, false])
            #expect(harness.text == "aa\nbb\n")

            let detached = CommandsACoverageSupport.host {
                EditorCommands.LineEditButtons(currentTab: { nil })
            }
            defer { detached.close() }
            try detached.click(0)
            try detached.click(1)
            try detached.click(2)
            #expect(harness.text == "aa\nbb\n")
        }
    }

    @Test
    func commentButtonsToggleCommentsAndReportUnsupportedLanguages() async throws {
        try await withTempDir { directory in
            let line = try await open(directory, "aa<caret>\n", fileName: "Line.swift")
            defer { line.close() }
            let lineTab = line.fixture.editorInstance
            let lineMenu = CommandsACoverageSupport.host {
                EditorCommands.CommentButtons(currentTab: { lineTab })
            }
            defer { lineMenu.close() }
            try lineMenu.click(0)
            #expect(line.text.hasPrefix("//"))

            let block = try await open(directory, "aa<caret>\n", fileName: "Block.swift")
            defer { block.close() }
            let blockTab = block.fixture.editorInstance
            let blockMenu = CommandsACoverageSupport.host {
                EditorCommands.CommentButtons(currentTab: { blockTab })
            }
            defer { blockMenu.close() }
            try blockMenu.click(1)
            #expect(block.text.contains("/*"))

            let unknown = try await open(directory, "aa<caret>\n", fileName: "Unknown.unknownext")
            defer { unknown.close() }
            let unknownTab = unknown.fixture.editorInstance
            let recorder = UnsupportedReasonRecorder()
            let unknownMenu = CommandsACoverageSupport.host {
                EditorCommands.CommentButtons(currentTab: { unknownTab }, onUnsupported: { recorder.record($0) })
            }
            defer { unknownMenu.close() }
            try unknownMenu.click(0)
            try unknownMenu.click(1)
            #expect(recorder.reasons.count == 2)
            #expect(unknown.text == "aa\n")

            let detachedRecorder = UnsupportedReasonRecorder()
            let detached = CommandsACoverageSupport.host {
                EditorCommands.CommentButtons(currentTab: { nil }, onUnsupported: { detachedRecorder.record($0) })
            }
            defer { detached.close() }
            try detached.click(0)
            try detached.click(1)
            #expect(detachedRecorder.reasons.isEmpty)
        }
    }

    @Test
    func selectionButtonsDriveOccurrenceSelectionAndCaretCloning() async throws {
        try await withTempDir { directory in
            let occurrences = try await open(directory, "foo f<caret>oo foo\n", fileName: "Occurrences.txt")
            defer { occurrences.close() }
            let occurrenceTab = occurrences.fixture.editorInstance
            let occurrenceMenu = CommandsACoverageSupport.host {
                EditorCommands.SelectionButtons(currentTab: { occurrenceTab })
            }
            defer { occurrenceMenu.close() }

            try occurrenceMenu.click(0)
            #expect(occurrences.selections == [NSRange(location: 4, length: 3)])
            try occurrenceMenu.click(0)
            #expect(occurrences.selections.count == 2)
            try occurrenceMenu.click(1)
            #expect(occurrences.selections == [NSRange(location: 4, length: 3)])
            try occurrenceMenu.click(2)
            #expect(occurrences.selections.count == 3)

            let above = try await open(directory, "ab\nc<caret>d\n", fileName: "Above.txt")
            defer { above.close() }
            let aboveTab = above.fixture.editorInstance
            let aboveMenu = CommandsACoverageSupport.host {
                EditorCommands.SelectionButtons(currentTab: { aboveTab })
            }
            defer { aboveMenu.close() }
            try aboveMenu.click(3)
            #expect(above.selections == [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)])

            let below = try await open(directory, "a<caret>b\ncd\n", fileName: "Below.txt")
            defer { below.close() }
            let belowTab = below.fixture.editorInstance
            let belowMenu = CommandsACoverageSupport.host {
                EditorCommands.SelectionButtons(currentTab: { belowTab })
            }
            defer { belowMenu.close() }
            try belowMenu.click(4)
            #expect(below.selections == [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)])

            let detached = CommandsACoverageSupport.host {
                EditorCommands.SelectionButtons(currentTab: { nil }, isEnabled: false)
            }
            defer { detached.close() }
            for index in 0..<5 {
                try detached.click(index)
            }
            #expect(detached.enabledStates == [false, false, false, false, false])
        }
    }

    @Test
    func indentButtonsShiftTheSelectedLinesAndBack() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, "<selection>a\nb<caret></selection>")
            defer { harness.close() }
            try await eventually { harness.controller.cursorPositions.map(\.range) == harness.selections }
            let tab = harness.fixture.editorInstance
            let menu = CommandsACoverageSupport.host {
                EditorCommands.IndentButtons(currentTab: { tab })
            }
            defer { menu.close() }

            try menu.click(0)
            #expect(harness.text.hasPrefix(" ") || harness.text.hasPrefix("\t"))
            try menu.click(1)
            #expect(harness.text == "a\nb")

            let detached = CommandsACoverageSupport.host {
                EditorCommands.IndentButtons(currentTab: { nil }, isEnabled: false)
            }
            defer { detached.close() }
            try detached.click(0)
            try detached.click(1)
            #expect(harness.text == "a\nb")
        }
    }

    @Test
    func goToLineButtonPresentsThePopup() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, "aa\nbb<caret>\ncc")
            defer { harness.close() }
            let tab = harness.fixture.editorInstance
            let menu = CommandsACoverageSupport.host {
                EditorCommands.GoToLineButton(currentTab: { tab })
            }
            defer { menu.close() }

            try menu.click(0)

            #expect(harness.actions.goToLinePresenter.isPresented)
            harness.actions.goToLinePresenter.dismiss()

            let disabled = CommandsACoverageSupport.host {
                EditorCommands.GoToLineButton(currentTab: { nil }, isEnabled: false)
            }
            defer { disabled.close() }
            try disabled.click(0)
            #expect(!harness.actions.goToLinePresenter.isPresented)
        }
    }

    @Test
    func softWrapButtonTogglesTheEditorAndRemembersTheOverride() async throws {
        try await withTempDir { directory in
            let harness = try await open(directory, "aa<caret>\n")
            defer { harness.close() }
            let tab = harness.fixture.editorInstance
            let menu = CommandsACoverageSupport.host {
                EditorCommands.SoftWrapButton(currentTab: { tab })
            }
            defer { menu.close() }

            #expect(!harness.textView.wrapLines)
            try menu.click(0)
            #expect(harness.textView.wrapLines)
            #expect(tab.wrapLinesOverride == true)
            try menu.click(0)
            #expect(!harness.textView.wrapLines)
            #expect(tab.wrapLinesOverride == false)

            let detached = CommandsACoverageSupport.host {
                EditorCommands.SoftWrapButton(currentTab: { nil }, isEnabled: false)
            }
            defer { detached.close() }
            try detached.click(0)
            #expect(detached.enabledStates == [false])
        }
    }
}
