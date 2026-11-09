import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorCommandsACoverageTests {
    private func openedEditor(in directory: URL, workspace: WorkspaceDocument) throws -> Editor {
        try "let one = 1\n".write(to: directory.appending(path: "One.swift"), atomically: true, encoding: .utf8)
        let manager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: "One.swift").path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: file)
        return manager.activeEditor
    }

    private func hostedLines(
        in directory: URL,
        text: String,
        caret: Int
    ) async throws -> (fixture: HostedSourceEditorFixture, hosted: HostedSourceEditor, textView: TextView) {
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "Lines.txt",
            typeIdentifier: "public.plain-text",
            contents: text
        )
        let hosted = fixture.host(
            coordinators: [fixture.editorInstance.rangeTranslator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: text)
        controller.setCursorPositions([CursorPosition(range: NSRange(location: caret, length: 0))])
        return (fixture, hosted, textView)
    }

    @Test
    func canNavigateIsFalseWithoutAnEditor() {
        #expect(EditorCommands.canNavigate(editor: nil, lspService: LSPService()) == false)
    }

    @Test
    func canNavigateIsFalseForATabWithoutALanguageClient() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let editor = try openedEditor(in: directory, workspace: workspace)
            #expect(editor.selectedTab != nil)

            #expect(EditorCommands.canNavigate(editor: editor, lspService: LSPService()) == false)
        }
    }

    @Test
    func moveLineUpButtonSwapsTheCaretLineWithThePreviousOne() async throws {
        try await withTempDir { directory in
            let session = try await hostedLines(in: directory, text: "aa\nbb\ncc\n", caret: 4)
            defer { session.hosted.close() }
            let tab = session.fixture.editorInstance
            let menu = CommandsACoverageSupport.host {
                EditorCommands.MoveLinesButtons(currentTab: { tab })
            }
            defer { menu.close() }

            try menu.click(titled: "Move Line Up")

            #expect(session.textView.string == "bb\naa\ncc\n")
        }
    }

    @Test
    func moveLineDownButtonSwapsTheCaretLineWithTheNextOne() async throws {
        try await withTempDir { directory in
            let session = try await hostedLines(in: directory, text: "aa\nbb\ncc\n", caret: 1)
            defer { session.hosted.close() }
            let tab = session.fixture.editorInstance
            let menu = CommandsACoverageSupport.host {
                EditorCommands.MoveLinesButtons(currentTab: { tab })
            }
            defer { menu.close() }

            try menu.click(titled: "Move Line Down")

            #expect(session.textView.string == "bb\naa\ncc\n")
        }
    }

    @Test
    func moveLineButtonsDoNothingWithoutATab() throws {
        let menu = CommandsACoverageSupport.host {
            EditorCommands.MoveLinesButtons(currentTab: { nil })
        }
        defer { menu.close() }

        try menu.click(titled: "Move Line Up")
        try menu.click(titled: "Move Line Down")

        #expect(menu.titles == ["Move Line Up", "Move Line Down"])
    }

    @Test
    func quickDocumentationButtonsSendTheActionWhenEnabled() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            EditorCommands.QuickDocumentationButtons(isEnabled: true, target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)

        #expect(recorder.received == ["showQuickDocumentation(_:)", "showQuickDocumentation(_:)"])
    }

    @Test
    func quickDocumentationButtonsAreDisabledWhenNavigationIsUnavailable() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            EditorCommands.QuickDocumentationButtons(isEnabled: false, target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)
        try menu.click(1)

        #expect(menu.items.count == 2)
        #expect(menu.enabledStates.allSatisfy { !$0 })
        #expect(recorder.received.isEmpty)
    }

    @Test
    func editorFocusNeedsATabAndATextViewAsFirstResponder() async throws {
        try await withTempDir { directory in
            let session = try await hostedLines(in: directory, text: "aa\n", caret: 0)
            defer { session.hosted.close() }
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let emptyEditor = try #require(workspace.editorManager?.activeEditor)
            #expect(emptyEditor.selectedTab == nil)

            #expect(EditorCommands.isEditorFocused(editor: nil, firstResponder: session.textView) == false)
            #expect(EditorCommands.isEditorFocused(editor: emptyEditor, firstResponder: session.textView) == false)

            let editor = try openedEditor(in: directory, workspace: workspace)

            #expect(EditorCommands.isEditorFocused(editor: editor, firstResponder: nil) == false)
            #expect(EditorCommands.isEditorFocused(editor: editor, firstResponder: NSResponder()) == false)
            #expect(EditorCommands.isEditorFocused(editor: editor, firstResponder: session.textView))
        }
    }

    @Test
    func activeEditorFollowsTheWindowControllerWorkspace() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer {
                controller.window?.close()
                workspace.close()
            }

            #expect(EditorCommands.activeEditor(of: nil) == nil)
            #expect(EditorCommands.activeEditor(of: controller) === workspace.editorManager?.activeEditor)
        }
    }

    @Test
    func editorMenuOffersTheEditingItemsForTheSelectedTab() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer {
                controller.window?.close()
                workspace.close()
            }
            _ = try openedEditor(in: directory, workspace: workspace)
            let editorMenu = EditorCommands.EditorMenu(windowController: controller)
            let menu = CommandsACoverageSupport.host {
                EditorCommands.EditorMenu(windowController: controller)
            }
            defer { menu.close() }

            #expect(menu.items.count == 16)
            #expect(menu.titles.first == "Duplicate Line or Selection")
            #expect(menu.item(titled: "Structure") != nil)
            #expect(menu.item(titled: "Quick Documentation") != nil)
            #expect(editorMenu.selectedTab() != nil)
            #expect(editorMenu.selectedTab() === workspace.editorManager?.activeEditor.selectedTab)
        }
    }

    @Test
    func editorMenuHasNoTabWithoutAWindowController() {
        #expect(EditorCommands.EditorMenu(windowController: nil).selectedTab() == nil)
        #expect(EditorCommands.SoftWrapMenuItem(windowController: nil).selectedTab() == nil)
    }

    @Test
    func softWrapMenuItemIsEnabledOnlyWithAnOpenTab() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer {
                controller.window?.close()
                workspace.close()
            }
            let detached = CommandsACoverageSupport.host {
                EditorCommands.SoftWrapMenuItem(windowController: nil)
            }
            let withoutTab = CommandsACoverageSupport.host {
                EditorCommands.SoftWrapMenuItem(windowController: controller)
            }
            defer {
                detached.close()
                withoutTab.close()
            }

            #expect(detached.titles == ["Toggle Soft Wraps"])
            #expect(detached.enabledStates == [false])
            #expect(withoutTab.enabledStates == [false])

            let editor = try openedEditor(in: directory, workspace: workspace)
            let withTab = CommandsACoverageSupport.host {
                EditorCommands.SoftWrapMenuItem(windowController: controller)
            }
            defer { withTab.close() }

            #expect(withTab.enabledStates == [true])
            try withTab.click(0)
            #expect(editor.selectedTab?.wrapLinesOverride == nil)
        }
    }

    @Test
    func commandBodyBuildsWithoutAWindowController() {
        _ = EditorCommands().body
    }
}
