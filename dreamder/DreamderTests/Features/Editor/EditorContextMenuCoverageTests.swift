import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
private struct ContextMenuCoverageSession {
    static let source = "alpha\nbravo\ncharlie\n"

    let workspace: WorkspaceDocument
    let hosted: HostedSourceEditor
    let textView: TextView
    let coordinator: EditorContextMenuCoordinator
    let fileURL: URL

    static func open(
        in directory: URL,
        fileName: String = "Notes.txt",
        initializeGit: Bool = false,
        defaultSeams: Bool = false
    ) async throws -> Self {
        if initializeGit {
            let git = try await GitMergeFixture(root: directory)
            try git.write(fileName, source)
            try await git.commit("initial")
        }
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: fileName,
            typeIdentifier: "public.plain-text",
            contents: source
        )
        let coordinator = defaultSeams
            ? EditorContextMenuCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            : EditorContextMenuCoordinator(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document,
                pasteboard: InMemoryPasteboard(),
                hasLanguageServer: { _ in false }
            )
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, coordinator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let textView = try #require(hosted.controller?.textView)
        let fileURL = try #require(fixture.document.fileURL)
        try await eventually {
            hosted.window.layoutIfNeeded()
            guard let rect = textView.layoutManager.rectForOffset(14) else { return false }
            return textView.bounds.contains(NSPoint(x: rect.midX, y: rect.midY))
        }
        if initializeGit {
            try await eventually { workspace.sourceControlManager?.isGitRepository == true }
        }
        textView.isEditable = true
        return Self(workspace: workspace, hosted: hosted, textView: textView, coordinator: coordinator, fileURL: fileURL)
    }

    func close() {
        hosted.close()
        workspace.close()
    }

    func select(_ range: NSRange) {
        textView.selectionManager.setSelectedRange(range)
    }

    var selectedRanges: [NSRange] {
        textView.selectionManager.textSelections.map(\.range)
    }

    func event(
        _ type: NSEvent.EventType,
        flags: NSEvent.ModifierFlags = [],
        atOffset offset: Int
    ) throws -> NSEvent {
        let rect = try #require(textView.layoutManager.rectForOffset(offset))
        let local = NSPoint(x: rect.midX, y: rect.midY)
        return try #require(
            NSEvent.mouseEvent(
                with: type,
                location: textView.convert(local, to: nil),
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: hosted.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    func contextMenu(atOffset offset: Int = 2) throws -> NSMenu {
        let click = try event(.rightMouseDown, atOffset: offset)
        return try #require(textView.menu(for: click))
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorContextMenuCoverageTests {
    private func item(_ menu: NSMenu, _ titles: String...) -> NSMenuItem? {
        var current: NSMenu? = menu
        var found: NSMenuItem?
        for title in titles {
            found = current?.items.first { $0.title == title }
            current = found?.submenu
        }
        return found
    }

    private func perform(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    @Test
    func theDefaultCollaboratorsAskTheLanguageServicesAndSkipTheClipboardWhenReadOnly() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(in: directory, defaultSeams: true)
            defer { session.close() }
            session.textView.isEditable = false

            let menu = try session.contextMenu()

            #expect(item(menu, "Find Usages")?.isEnabled == false)
            #expect(item(menu, "Show Usages")?.isEnabled == false)
            #expect(item(menu, "Go To", "Declaration or Usages")?.isEnabled == false)
            #expect(item(menu, "Paste")?.isEnabled == false)
            #expect(item(menu, "Find in Files…")?.isEnabled == true)
        }
    }

    @Test
    func projectRelativePathsDropTheRootAndFallBackToTheAbsolutePathOutsideIt() {
        let root = URL(fileURLWithPath: "/workspace/project", isDirectory: true)

        #expect(
            EditorContextMenuCoordinator.projectRelativePath(
                of: URL(fileURLWithPath: "/workspace/project/Sources/Notes.txt"),
                root: root
            ) == "Sources/Notes.txt"
        )
        #expect(
            EditorContextMenuCoordinator.projectRelativePath(
                of: URL(fileURLWithPath: "/workspace/project/Sources/../Notes.txt"),
                root: root
            ) == "Notes.txt"
        )
        #expect(
            EditorContextMenuCoordinator.projectRelativePath(
                of: URL(fileURLWithPath: "/workspace/other/Notes.txt"),
                root: root
            ) == "/workspace/other/Notes.txt"
        )
        #expect(
            EditorContextMenuCoordinator.projectRelativePath(
                of: URL(fileURLWithPath: "/workspace/project"),
                root: root
            ) == "/workspace/project"
        )
    }

    @Test
    func openInFinderRevealsTheFile() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(in: directory, fileName: "RevealTarget.txt")
            defer { session.close() }
            let menu = try session.contextMenu()

            let finder = try #require(item(menu, "Open In", "Finder"))
            #expect(perform(finder))

            #expect(DreamderHeadless.suppressedExternalOpens.contains { $0.hasSuffix("/RevealTarget.txt") })
        }
    }

    @Test
    func goToItemsForwardToTheNavigationCommandsWithoutOpeningTabsWhenNoServerAnswers() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(in: directory)
            defer { session.close() }
            let workspace = session.workspace
            let before = workspace.editorManager?.activeEditor.tabs.count
            let menu = try session.contextMenu()

            let declaration = try #require(item(menu, "Go To", "Declaration or Usages"))
            let typeDeclaration = try #require(item(menu, "Go To", "Type Declaration"))
            #expect(perform(declaration))
            #expect(perform(typeDeclaration))
            try await Task.sleep(for: .milliseconds(100))

            #expect(workspace.editorManager?.activeEditor.tabs.count == before)
        }
    }

    @Test
    func showDiffOpensTheWorkingTreeDiffWindowOfTheFile() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(
                in: directory,
                fileName: "DiffTarget.txt",
                initializeGit: true
            )
            defer { session.close() }
            try "changed\n".write(to: session.fileURL, atomically: true, encoding: .utf8)
            let menu = try session.contextMenu()

            let showDiff = try #require(item(menu, "Git", "Show Diff"))
            #expect(perform(showDiff))

            let diffWindow = NSApp.windows.first {
                $0.windowController is DiffViewerWindowController && $0.title.hasPrefix("DiffTarget.txt")
            }
            let window = try #require(diffWindow)
            window.close()
        }
    }

    @Test
    func rollbackWithoutAHostedWindowAsksThroughAModalAndKeepsTheFileUntilConfirmed() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(
                in: directory,
                fileName: "ModalRollback.txt",
                initializeGit: true
            )
            defer { session.close() }
            try "locally changed\n".write(to: session.fileURL, atomically: true, encoding: .utf8)
            let menu = try session.contextMenu()
            let rollback = try #require(item(menu, "Git", "Rollback…"))
            let before = DreamderHeadless.suppressedModals.filter { $0 == "Rollback Changes" }.count
            session.coordinator.destroy()

            #expect(perform(rollback))

            let after = DreamderHeadless.suppressedModals.filter { $0 == "Rollback Changes" }.count
            #expect(after > before)
            try await Task.sleep(for: .milliseconds(300))
            #expect(try String(contentsOf: session.fileURL, encoding: .utf8) == "locally changed\n")
        }
    }

    @Test
    func confirmingTheRollbackRestoresTheCommittedContents() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(
                in: directory,
                fileName: "ConfirmRollback.txt",
                initializeGit: true
            )
            defer { session.close() }
            try "locally changed\n".write(to: session.fileURL, atomically: true, encoding: .utf8)

            EditorContextMenuCoordinator.confirmRollback(
                .alertFirstButtonReturn,
                url: session.fileURL,
                in: session.workspace
            )

            try await eventually {
                (try? String(contentsOf: session.fileURL, encoding: .utf8)) == ContextMenuCoverageSession.source
            }
        }
    }

    @Test
    func cancellingTheRollbackLeavesTheFileUntouched() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(
                in: directory,
                fileName: "CancelRollback.txt",
                initializeGit: true
            )
            defer { session.close() }
            try "locally changed\n".write(to: session.fileURL, atomically: true, encoding: .utf8)

            EditorContextMenuCoordinator.confirmRollback(
                .alertSecondButtonReturn,
                url: session.fileURL,
                in: session.workspace
            )

            try await Task.sleep(for: .milliseconds(300))
            #expect(try String(contentsOf: session.fileURL, encoding: .utf8) == "locally changed\n")
        }
    }

    @Test
    func theMenuHandlerIgnoresNonContextEventsAndStopsAnsweringAfterDestroy() async throws {
        try await withTempDir { directory in
            let session = try await ContextMenuCoverageSession.open(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 12, length: 7))
            let handler = try #require(EditorContextMenuInstaller.handler(for: session.textView))
            let plainClick = try session.event(.leftMouseDown, atOffset: 2)

            let menu = try #require(handler(plainClick))

            #expect(item(menu, "Find Usages") != nil)
            #expect(session.selectedRanges == [NSRange(location: 12, length: 7)])

            session.coordinator.destroy()

            #expect(handler(plainClick) == nil)
        }
    }
}
