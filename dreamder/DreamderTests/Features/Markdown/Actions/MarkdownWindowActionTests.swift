import AppKit
import CodeEditSourceEditor
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct MarkdownWindowActionTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let manager: EditorManager
        let codeFile: CodeFileDocument
        let editorInstance: EditorInstance

        var text: String {
            codeFile.content?.string ?? ""
        }

        var selections: [NSRange] {
            editorInstance.cursorPositions.map(\.range)
        }

        func select(_ ranges: [NSRange]) {
            editorInstance.cursorPositions = ranges.map { CursorPosition(range: $0) }
        }

        func close() {
            controller.window?.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL, fileName: String, content: String) throws -> Harness {
        try content.write(to: directory.appending(path: fileName), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        let manager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: fileName).path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: file)
        let editorInstance = try #require(manager.activeEditor.selectedTab)
        let codeFile = try #require(editorInstance.file.fileDocument)
        return Harness(
            workspace: workspace,
            controller: controller,
            manager: manager,
            codeFile: codeFile,
            editorInstance: editorInstance
        )
    }

    @Test
    func boldActionWrapsTheSelectionInTheDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "hello world\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 5)])

            harness.controller.markdownToggleBold(nil)

            #expect(harness.text == "**hello** world\n")
            #expect(harness.selections == [NSRange(location: 2, length: 5)])
        }
    }

    @Test
    func boldActionTwiceRestoresTheDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "hello world\n")
            defer { harness.close() }
            harness.select([NSRange(location: 6, length: 5)])

            harness.controller.markdownToggleBold(nil)
            #expect(harness.text == "hello **world**\n")
            harness.controller.markdownToggleBold(nil)

            #expect(harness.text == "hello world\n")
        }
    }

    @Test
    func headerActionsRewriteTheCaretLine() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "Title\n")
            defer { harness.close() }
            harness.select([NSRange(location: 2, length: 0)])

            harness.controller.markdownHeaderSubtitle(nil)
            #expect(harness.text == "## Title\n")
            harness.controller.markdownHeaderUp(nil)
            #expect(harness.text == "# Title\n")
            harness.controller.markdownHeaderNormal(nil)
            #expect(harness.text == "Title\n")
        }
    }

    @Test
    func formatTableActionRewritesTheTable() throws {
        try withTempDir { directory in
            let content = "# Intro\n\n| a |bb|\n|---|---|\n| 1 |2|\n"
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: content)
            defer { harness.close() }
            harness.select([NSRange(location: 14, length: 0)])

            harness.controller.markdownFormatTable(nil)

            #expect(harness.text == "# Intro\n\n| a | bb |\n|---|----|\n| 1 | 2  |\n")
        }
    }

    @Test
    func tableOfContentsActionInsertsTheBlockAtTheCaret() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "\n# Intro\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 0)])

            harness.controller.markdownGenerateTableOfContents(nil)

            #expect(harness.text.hasPrefix("<!-- TOC -->\n"))
            #expect(harness.text.contains("* [Intro](#intro)"))
        }
    }

    @Test
    func actionsIgnoreNonMarkdownFiles() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Code.swift", content: "let a = 1\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 3)])

            harness.controller.markdownToggleBold(nil)

            #expect(harness.text == "let a = 1\n")
            #expect(harness.controller.isActiveEditorMarkdown == false)
        }
    }

    @Test
    func markdownFileIsReportedAsMarkdown() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "text\n")
            defer { harness.close() }

            #expect(harness.controller.isActiveEditorMarkdown)
        }
    }

    @Test
    func italicStrikethroughAndCodeSpanActionsWrapTheSelection() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "one two three\n")
            defer { harness.close() }

            harness.select([NSRange(location: 0, length: 3)])
            harness.controller.markdownToggleItalic(nil)
            #expect(harness.text == "*one* two three\n")

            harness.select([NSRange(location: 6, length: 3)])
            harness.controller.markdownToggleStrikethrough(nil)
            #expect(harness.text == "*one* ~~two~~ three\n")

            harness.select([NSRange(location: 14, length: 5)])
            harness.controller.markdownToggleCodeSpan(nil)
            #expect(harness.text == "*one* ~~two~~ `three`\n")
        }
    }

    @Test
    func createLinkActionWrapsTheSelectionAndPlacesTheCaretInTheDestination() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "visit docs now\n")
            defer { harness.close() }
            NSPasteboard.general.clearContents()
            harness.select([NSRange(location: 6, length: 4)])

            harness.controller.markdownCreateLink(nil)

            #expect(harness.text == "visit [docs]() now\n")
            #expect(harness.selections == [NSRange(location: 13, length: 0)])
        }
    }

    @Test
    func everyHeaderLevelActionSetsItsLevelAndHeaderDownStopsAtSix() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "Title\n")
            defer { harness.close() }
            harness.select([NSRange(location: 1, length: 0)])

            harness.controller.markdownHeaderTitle(nil)
            #expect(harness.text == "# Title\n")
            harness.controller.markdownHeading3(nil)
            #expect(harness.text == "### Title\n")
            harness.controller.markdownHeading4(nil)
            #expect(harness.text == "#### Title\n")
            harness.controller.markdownHeading5(nil)
            #expect(harness.text == "##### Title\n")
            harness.controller.markdownHeading6(nil)
            #expect(harness.text == "###### Title\n")
            harness.controller.markdownHeaderDown(nil)
            #expect(harness.text == "###### Title\n")
            harness.controller.markdownHeaderUp(nil)
            #expect(harness.text == "##### Title\n")
        }
    }

    @Test
    func insertTableCommandInsertsAnAlignedTableAtTheCaret() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "Intro\n\n")
            defer { harness.close() }
            harness.select([NSRange(location: 7, length: 0)])

            let performed = harness.controller.performMarkdownCommand(.insertTable(contentRows: 1, columns: 2))

            #expect(performed)
            #expect(harness.text == "Intro\n\n|   |   |\n|---|---|\n|   |   |\n")
        }
    }

    @Test
    func emphasisAndTableStylePreferencesComeFromDefaults() {
        let name = "dreamder.tests.markdown.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(MarkdownEditorPreferences.emphasisStyle(defaults: defaults) == .asterisks)
        #expect(MarkdownEditorPreferences.tableStyle(defaults: defaults) == .aligned)

        defaults.set("underscores", forKey: MarkdownEditorPreferences.emphasisStyleKey)
        defaults.set("compact", forKey: MarkdownEditorPreferences.tableStyleKey)
        #expect(MarkdownEditorPreferences.emphasisStyle(defaults: defaults) == .underscores)
        #expect(MarkdownEditorPreferences.tableStyle(defaults: defaults) == .compact)

        defaults.set("tight", forKey: MarkdownEditorPreferences.tableStyleKey)
        #expect(MarkdownEditorPreferences.tableStyle(defaults: defaults) == .tight)
    }
}
