import AppKit
import CodeEditSourceEditor
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownCommandsCoverage {
    @MainActor
    private struct MenuHarness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let editorInstance: EditorInstance
        let codeFile: CodeFileDocument

        var text: String {
            codeFile.content?.string ?? ""
        }

        func select(_ ranges: [NSRange]) {
            editorInstance.cursorPositions = ranges.map { CursorPosition(range: $0) }
        }

        func close() {
            controller.window?.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL, fileName: String, content: String) throws -> MenuHarness {
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
        return MenuHarness(workspace: workspace, controller: controller, editorInstance: editorInstance, codeFile: codeFile)
    }

    @Test
    func groupsPartitionEveryItemExactlyOnceInMenuOrder() {
        let grouped = MarkdownMenuItem.styling
            + MarkdownMenuItem.link
            + MarkdownMenuItem.headerLevels
            + MarkdownMenuItem.headerSteps
            + MarkdownMenuItem.table
            + MarkdownMenuItem.tableOfContents

        #expect(grouped == MarkdownMenuItem.allCases)
        #expect(MarkdownMenuItem.allCases.count == 17)
    }

    @Test
    func titlesAreTheMenuLabels() {
        let titles = MarkdownMenuItem.allCases.map(\.title)

        #expect(titles == [
            "Bold", "Italic", "Strikethrough", "Code Span", "Create Link",
            "Normal", "Title", "Subtitle", "Heading 3", "Heading 4", "Heading 5", "Heading 6",
            "Header Up", "Header Down", "Insert Table…", "Format Table", "Generate Table of Contents"
        ])
    }

    @Test
    func menuShortcutsComeFromTheKeymapAndOnlyBoldItalicStrikethroughCodeLinkAreBound() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let keymap = Keymap(defaults: defaults)

        #expect(keymap.keyboardShortcut(for: MarkdownMenuItem.bold.command) == KeyboardShortcut("b", modifiers: .control))
        #expect(keymap.keyboardShortcut(for: MarkdownMenuItem.italic.command) == KeyboardShortcut("i", modifiers: .control))
        #expect(
            keymap.keyboardShortcut(for: MarkdownMenuItem.strikethrough.command)
                == KeyboardShortcut("s", modifiers: [.control, .shift])
        )
        #expect(
            keymap.keyboardShortcut(for: MarkdownMenuItem.codeSpan.command)
                == KeyboardShortcut("c", modifiers: [.control, .shift])
        )
        #expect(
            keymap.keyboardShortcut(for: MarkdownMenuItem.createLink.command)
                == KeyboardShortcut("u", modifiers: [.control, .shift])
        )
        let unbound = MarkdownMenuItem.allCases.filter { keymap.keyboardShortcut(for: $0.command) == nil }
        #expect(unbound.count == 12)
        #expect(unbound.contains(.bold) == false)
        #expect(KeymapShortcutModifier.shortcut(for: MarkdownMenuItem.bold.command, at: 0, isEnabled: false, in: keymap) == nil)
    }

    @Test
    func everyActionIsADistinctSelectorTheWindowControllerImplements() {
        let selectors = MarkdownMenuItem.allCases.map(\.action)

        #expect(Set(selectors).count == MarkdownMenuItem.allCases.count)
        for selector in selectors {
            #expect(DreamderWindowController.instancesRespond(to: selector))
        }
    }

    @Test
    func everyItemIsHandledByTheWindowControllerEvenWhenTheActiveFileIsNotMarkdown() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Code.swift", content: "let a = 1\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 3)])

            for item in MarkdownMenuItem.allCases {
                #expect(item.send(to: harness.controller), "\(item.title)")
            }

            #expect(harness.text == "let a = 1\n")
        }
    }

    @Test
    func stylingItemsEditTheSelectionOfTheActiveMarkdownFile() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "one two three four\n")
            defer { harness.close() }

            harness.select([NSRange(location: 0, length: 3)])
            MarkdownMenuItem.bold.send(to: harness.controller)
            #expect(harness.text == "**one** two three four\n")

            harness.select([NSRange(location: 8, length: 3)])
            MarkdownMenuItem.italic.send(to: harness.controller)
            #expect(harness.text == "**one** *two* three four\n")

            harness.select([NSRange(location: 14, length: 5)])
            MarkdownMenuItem.strikethrough.send(to: harness.controller)
            #expect(harness.text == "**one** *two* ~~three~~ four\n")

            harness.select([NSRange(location: 24, length: 4)])
            MarkdownMenuItem.codeSpan.send(to: harness.controller)
            #expect(harness.text == "**one** *two* ~~three~~ `four`\n")
        }
    }

    @Test
    func createLinkItemWrapsTheSelectionInALink() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "visit docs now\n")
            defer { harness.close() }
            harness.controller.markdownClipboard = { nil }
            harness.select([NSRange(location: 6, length: 4)])

            MarkdownMenuItem.createLink.send(to: harness.controller)

            #expect(harness.text == "visit [docs]() now\n")
        }
    }

    @Test
    func headerItemsRewriteTheCaretLine() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "Title\n")
            defer { harness.close() }
            harness.select([NSRange(location: 2, length: 0)])

            let steps: [(MarkdownMenuItem, String)] = [
                (.headerTitle, "# Title\n"),
                (.headerSubtitle, "## Title\n"),
                (.heading3, "### Title\n"),
                (.heading4, "#### Title\n"),
                (.heading5, "##### Title\n"),
                (.heading6, "###### Title\n"),
                (.headerDown, "###### Title\n"),
                (.headerUp, "##### Title\n"),
                (.headerNormal, "Title\n")
            ]
            for (item, expected) in steps {
                item.send(to: harness.controller)
                #expect(harness.text == expected, "\(item.title)")
            }
        }
    }

    @Test
    func tableItemsFormatTheTableAndGenerateTheContents() throws {
        try withTempDir { directory in
            let content = "# Intro\n\n| a |bb|\n|---|---|\n| 1 |2|\n"
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: content)
            defer { harness.close() }
            harness.select([NSRange(location: 14, length: 0)])

            MarkdownMenuItem.formatTable.send(to: harness.controller)
            #expect(harness.text == "# Intro\n\n| a | bb |\n|---|----|\n| 1 | 2  |\n")

            harness.select([NSRange(location: 0, length: 0)])
            MarkdownMenuItem.generateTableOfContents.send(to: harness.controller)
            #expect(harness.text.hasPrefix("<!-- TOC -->\n"))
            #expect(harness.text.contains("* [Intro](#intro)"))
        }
    }

    @Test
    func buttonActionSendsItsItemToTheTarget() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Notes.md", content: "hello\n")
            defer { harness.close() }
            harness.select([NSRange(location: 0, length: 5)])

            MarkdownMenuButton(item: .bold, isActive: true, target: harness.controller).perform()

            #expect(harness.text == "**hello**\n")
        }
    }

    @Test
    func buttonWithoutTargetFallsBackToTheResponderChain() {
        MarkdownMenuButton(item: .formatTable, isActive: true).perform()
        MarkdownMenuItem.bold.send()
    }

    @Test
    func buttonBodiesBuildForActiveAndInactiveMenus() {
        for item in MarkdownMenuItem.allCases {
            _ = MarkdownMenuButton(item: item, isActive: true).body
            _ = MarkdownMenuButton(item: item, isActive: false).body
        }
    }

    @Test
    func menuContentBodyBuildsForActiveAndInactiveMenus() {
        _ = MarkdownMenuContent(isActive: true).body
        _ = MarkdownMenuContent(isActive: false).body
    }

    @Test
    func commandMenuBodyBuildsWithoutAWindowController() {
        let commands = MarkdownCommands()

        #expect(commands.windowController == nil)
        _ = commands.body
    }

    @Test
    func hostedMenuContentRendersWhenActiveAndWhenDisabled() async throws {
        let active = HostedViewFixture.host(size: NSSize(width: 300, height: 400)) {
            VStack { MarkdownMenuContent(isActive: true) }
        }
        let inactive = HostedViewFixture.host(size: NSSize(width: 300, height: 400)) {
            VStack { MarkdownMenuContent(isActive: false) }
        }
        defer {
            active.close()
            inactive.close()
        }

        try await active.settle()
        try await inactive.settle()

        #expect(active.renders())
        #expect(inactive.renders())
    }
}
