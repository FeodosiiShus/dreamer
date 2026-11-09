import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct EditorContextMenuCoordinatorTests {
    private static let source = "alpha\nbravo\ncharlie\n"
    private static let f7 = String(UnicodeScalar(NSF7FunctionKey) ?? "\u{7F}")

    @MainActor
    private final class MenuEnvironment {
        var serverAvailable = false
        let pasteboard = InMemoryPasteboard()
        private(set) var queriedURLs: [URL] = []

        init() {
            canPaste = true
        }

        var canPaste: Bool {
            get { pasteboard.canReadPlainText }
            set {
                if newValue {
                    pasteboard.replaceContents(withText: "clipboard")
                } else {
                    pasteboard.removeAllContents()
                }
            }
        }

        var written: [String] {
            pasteboard.textWrites.filter { $0 != "clipboard" }
        }

        func checkServer(_ url: URL) -> Bool {
            queriedURLs.append(url)
            return serverAvailable
        }
    }

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument?
        let hosted: HostedSourceEditor
        let textView: TextView
        let coordinator: EditorContextMenuCoordinator
        let blame: GitBlameCoordinator?
        let environment: MenuEnvironment
        let fileURL: URL

        func close() {
            hosted.close()
            workspace?.close()
        }

        func select(_ range: NSRange) {
            textView.selectionManager.setSelectedRange(range)
        }

        var selectedRanges: [NSRange] {
            textView.selectionManager.textSelections.map(\.range)
        }
    }

    private func openSession(
        in directory: URL,
        fileName: String = "Notes.txt",
        registerWorkspace: Bool = true,
        initializeGit: Bool = false,
        withBlame: Bool = true
    ) async throws -> Session {
        if initializeGit {
            let git = try await GitMergeFixture(root: directory)
            try git.write(fileName, Self.source)
            try await git.commit("initial")
        }
        var workspace: WorkspaceDocument?
        if registerWorkspace {
            workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        }
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: fileName,
            typeIdentifier: "public.plain-text",
            contents: Self.source
        )
        let environment = MenuEnvironment()
        let blame = withBlame
            ? GitBlameCoordinator(editorInstance: fixture.editorInstance, codeFile: fixture.document)
            : nil
        let coordinator = EditorContextMenuCoordinator(
            editorInstance: fixture.editorInstance,
            codeFile: fixture.document,
            pasteboard: environment.pasteboard,
            hasLanguageServer: { environment.checkServer($0) }
        )
        var coordinators: [TextViewCoordinator] = [fixture.document.contentCoordinator]
        if let blame {
            coordinators.append(blame)
        }
        coordinators.append(coordinator)
        let hosted = fixture.host(coordinators: coordinators, size: NSSize(width: 900, height: 600))
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let textView = try #require(hosted.controller?.textView)
        let fileURL = try #require(fixture.document.fileURL)
        try await eventually {
            hosted.window.layoutIfNeeded()
            guard let rect = textView.layoutManager.rectForOffset(14) else { return false }
            return textView.bounds.contains(NSPoint(x: rect.midX, y: rect.midY))
        }
        if initializeGit, let workspace {
            try await eventually { workspace.sourceControlManager?.isGitRepository == true }
        }
        textView.isEditable = true
        return Session(
            workspace: workspace,
            hosted: hosted,
            textView: textView,
            coordinator: coordinator,
            blame: blame,
            environment: environment,
            fileURL: fileURL
        )
    }

    private func clickPoint(in session: Session, atOffset offset: Int?) throws -> NSPoint {
        guard let offset else { return NSPoint(x: 4, y: 4) }
        let rect = try #require(session.textView.layoutManager.rectForOffset(offset))
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        flags: NSEvent.ModifierFlags = [],
        in session: Session,
        atOffset offset: Int? = nil
    ) throws -> NSEvent {
        let local = try clickPoint(in: session, atOffset: offset)
        return try #require(
            NSEvent.mouseEvent(
                with: type,
                location: session.textView.convert(local, to: nil),
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: session.hosted.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func contextMenu(_ session: Session, atOffset offset: Int? = nil) throws -> NSMenu {
        let event = try mouseEvent(.rightMouseDown, in: session, atOffset: offset)
        return try #require(session.textView.menu(for: event))
    }

    private func item(_ menu: NSMenu, _ titles: String...) -> NSMenuItem? {
        var current: NSMenu? = menu
        var found: NSMenuItem?
        for title in titles {
            found = current?.items.first { $0.title == title }
            current = found?.submenu
        }
        return found
    }

    private func titles(_ menu: NSMenu?) -> [String] {
        (menu?.items ?? []).map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func isEnabled(_ menu: NSMenu, _ path: String...) -> Bool? {
        var current: NSMenu? = menu
        var found: NSMenuItem?
        for title in path {
            found = current?.items.first { $0.title == title }
            current = found?.submenu
        }
        return found?.isEnabled
    }

    @discardableResult
    private func perform(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    @Test
    func menuListsTheEditorActionsInIntelliJOrder() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }

            let menu = try contextMenu(session)

            #expect(titles(menu) == [
                "Cut", "Copy", "Paste", "Copy Path/Reference", "-",
                "Find in Files…", "Find Usages", "Show Usages", "Go To", "Quick Documentation", "-",
                "Open In"
            ])
            #expect(titles(item(menu, "Copy Path/Reference")?.submenu) == [
                "Absolute Path", "Path From Project Root", "File Name"
            ])
            #expect(titles(item(menu, "Go To")?.submenu) == ["Declaration or Usages", "Type Declaration"])
            #expect(titles(item(menu, "Open In")?.submenu) == ["Finder", "Terminal"])
        }
    }

    @Test
    func menuItemsCarryTheIntelliJShortcuts() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let menu = try contextMenu(session)
            let expected: [(path: [String], key: String, modifiers: NSEvent.ModifierFlags)] = [
                (["Cut"], "x", [.command]),
                (["Copy"], "c", [.command]),
                (["Paste"], "v", [.command]),
                (["Find in Files…"], "f", [.command, .shift]),
                (["Find Usages"], Self.f7, [.option]),
                (["Show Usages"], Self.f7, [.option, .command]),
                (["Quick Documentation"], "j", [.control]),
                (["Copy Path/Reference", "Absolute Path"], "c", [.command, .shift]),
                (["Go To", "Declaration or Usages"], "b", [.command]),
                (["Go To", "Type Declaration"], "b", [.command, .shift])
            ]

            for entry in expected {
                var current: NSMenu? = menu
                var found: NSMenuItem?
                for title in entry.path {
                    found = current?.items.first { $0.title == title }
                    current = found?.submenu
                }
                let target = try #require(found, "missing \(entry.path)")
                #expect(target.keyEquivalent == entry.key, "\(entry.path)")
                #expect(target.keyEquivalentModifierMask == entry.modifiers, "\(entry.path)")
            }
        }
    }

    @Test
    func clipboardItemsUseTheStandardResponderActions() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let menu = try contextMenu(session)

            #expect(item(menu, "Cut")?.action == #selector(NSText.cut(_:)))
            #expect(item(menu, "Copy")?.action == #selector(NSText.copy(_:)))
            #expect(item(menu, "Paste")?.action == #selector(NSText.paste(_:)))
            #expect(item(menu, "Find in Files…")?.action == #selector(DreamderWindowController.openSearchNavigator(_:)))
            #expect(item(menu, "Find Usages")?.action == #selector(DreamderWindowController.findUsages(_:)))
            #expect(item(menu, "Show Usages")?.action == #selector(DreamderWindowController.showUsages(_:)))
            #expect(
                item(menu, "Quick Documentation")?.action == #selector(DreamderWindowController.showQuickDocumentation(_:))
            )
        }
    }

    @Test
    func cutAndCopyAreDisabledWithoutASelection() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 3, length: 0))

            let menu = try contextMenu(session, atOffset: 3)

            #expect(isEnabled(menu, "Cut") == false)
            #expect(isEnabled(menu, "Copy") == false)
        }
    }

    @Test
    func aSelectionEnablesCutAndCopy() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 0, length: 5))

            let menu = try contextMenu(session, atOffset: 2)

            #expect(isEnabled(menu, "Cut") == true)
            #expect(isEnabled(menu, "Copy") == true)
        }
    }

    @Test
    func aReadOnlyEditorCannotCutButCanStillCopy() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.textView.isEditable = false
            session.select(NSRange(location: 0, length: 5))
            session.environment.canPaste = true

            let menu = try contextMenu(session, atOffset: 2)

            #expect(isEnabled(menu, "Cut") == false)
            #expect(isEnabled(menu, "Copy") == true)
            #expect(isEnabled(menu, "Paste") == false)
        }
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func pasteNeedsAnEditableEditorAndTextOnTheClipboard(isEditable: Bool, clipboardHasText: Bool) async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.textView.isEditable = isEditable
            session.environment.canPaste = clipboardHasText

            let menu = try contextMenu(session)

            #expect(isEnabled(menu, "Paste") == (isEditable && clipboardHasText))
        }
    }

    @Test
    func workspaceBoundItemsAreDisabledOutsideAWorkspace() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, registerWorkspace: false)
            defer { session.close() }

            let menu = try contextMenu(session)

            #expect(isEnabled(menu, "Find in Files…") == false)
            #expect(isEnabled(menu, "Copy Path/Reference", "Path From Project Root") == false)
            #expect(isEnabled(menu, "Open In", "Terminal") == false)
            #expect(isEnabled(menu, "Copy Path/Reference", "Absolute Path") == true)
            #expect(isEnabled(menu, "Copy Path/Reference", "File Name") == true)
            #expect(isEnabled(menu, "Open In", "Finder") == true)
            #expect(item(menu, "Git") == nil)
        }
    }

    @Test
    func workspaceBoundItemsAreEnabledInsideAWorkspace() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }

            let menu = try contextMenu(session)

            #expect(isEnabled(menu, "Find in Files…") == true)
            #expect(isEnabled(menu, "Copy Path/Reference", "Path From Project Root") == true)
            #expect(isEnabled(menu, "Open In", "Terminal") == true)
        }
    }

    @Test
    func languageServerItemsAreDisabledWithoutAServerForTheFile() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.environment.serverAvailable = false

            let menu = try contextMenu(session)

            #expect(isEnabled(menu, "Find Usages") == false)
            #expect(isEnabled(menu, "Show Usages") == false)
            #expect(isEnabled(menu, "Quick Documentation") == false)
            #expect(isEnabled(menu, "Go To", "Declaration or Usages") == false)
            #expect(isEnabled(menu, "Go To", "Type Declaration") == false)
            #expect(session.environment.queriedURLs.allSatisfy { $0 == session.fileURL })
            #expect(session.environment.queriedURLs.isEmpty == false)
        }
    }

    @Test
    func languageServerItemsAreEnabledWhenAServerHasTheFileOpen() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.environment.serverAvailable = true

            let menu = try contextMenu(session)

            #expect(isEnabled(menu, "Find Usages") == true)
            #expect(isEnabled(menu, "Show Usages") == true)
            #expect(isEnabled(menu, "Quick Documentation") == true)
            #expect(isEnabled(menu, "Go To", "Declaration or Usages") == true)
            #expect(isEnabled(menu, "Go To", "Type Declaration") == true)
        }
    }

    @Test
    func gitMenuIsOfferedOnlyInsideARepository() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, initializeGit: true)
            defer { session.close() }

            let menu = try contextMenu(session)

            #expect(titles(menu).last == "Git")
            #expect(titles(item(menu, "Git")?.submenu) == [
                "Annotate with Git Blame", "Show Diff", "Rollback…", "Show History"
            ])
            #expect(isEnabled(menu, "Git", "Annotate with Git Blame") == true)
            #expect(isEnabled(menu, "Git", "Show Diff") == true)
            #expect(isEnabled(menu, "Git", "Rollback…") == true)
            #expect(isEnabled(menu, "Git", "Show History") == true)
        }
    }

    @Test
    func annotateIsDisabledWhenTheEditorHasNoBlameCoordinator() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, initializeGit: true, withBlame: false)
            defer { session.close() }

            let menu = try contextMenu(session)

            #expect(isEnabled(menu, "Git", "Annotate with Git Blame") == false)
            let annotate = try #require(item(menu, "Git", "Annotate with Git Blame"))
            #expect(annotate.state == .off)
        }
    }

    @Test
    func annotateTogglesTheBlameColumnAndShowsItsState() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, initializeGit: true)
            defer { session.close() }
            let blame = try #require(session.blame)

            let beforeMenu = try contextMenu(session)
            let before = try #require(item(beforeMenu, "Git", "Annotate with Git Blame"))
            #expect(before.state == .off)
            #expect(blame.isAnnotating == false)
            #expect(perform(before))

            #expect(blame.isAnnotating)
            let duringMenu = try contextMenu(session)
            let during = try #require(item(duringMenu, "Git", "Annotate with Git Blame"))
            #expect(during.state == .on)
            #expect(perform(during))

            #expect(blame.isAnnotating == false)
            let afterMenu = try contextMenu(session)
            let after = try #require(item(afterMenu, "Git", "Annotate with Git Blame"))
            #expect(after.state == .off)
        }
    }

    @Test
    func copyReferenceItemsPutTheMatchingTextOnTheClipboard() async throws {
        try await withTempDir { directory in
            try FileManager.default.createDirectory(
                at: directory.appending(path: "Sources", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            let session = try await openSession(in: directory, fileName: "Sources/Notes.txt")
            defer { session.close() }
            let menu = try contextMenu(session)

            let absolute = try #require(item(menu, "Copy Path/Reference", "Absolute Path"))
            let relative = try #require(item(menu, "Copy Path/Reference", "Path From Project Root"))
            let name = try #require(item(menu, "Copy Path/Reference", "File Name"))
            #expect(perform(absolute))
            #expect(perform(relative))
            #expect(perform(name))

            #expect(session.environment.written == [
                session.fileURL.path(percentEncoded: false),
                "Sources/Notes.txt",
                "Notes.txt"
            ])
        }
    }

    @Test
    func openInTerminalStartsATerminalInTheFilesFolderAndShowsTheTerminalToolWindow() async throws {
        try await withTempDir { directory in
            try FileManager.default.createDirectory(
                at: directory.appending(path: "Sources", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            let session = try await openSession(in: directory, fileName: "Sources/Notes.txt")
            defer { session.close() }
            let workspace = try #require(session.workspace)
            workspace.toolWindowManager.hideAll()
            let before = workspace.utilityAreaModel?.terminals.count ?? 0
            let menu = try contextMenu(session)

            let terminal = try #require(item(menu, "Open In", "Terminal"))
            #expect(perform(terminal))

            let terminals = try #require(workspace.utilityAreaModel?.terminals)
            #expect(terminals.count == before + 1)
            #expect(terminals.last?.url.path(percentEncoded: false) == session.fileURL.deletingLastPathComponent().path(percentEncoded: false))
            #expect(workspace.toolWindowManager.isVisible(.terminal))
        }
    }

    @Test
    func showHistoryRevealsTheGitToolWindow() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, initializeGit: true)
            defer { session.close() }
            let workspace = try #require(session.workspace)
            workspace.toolWindowManager.hideAll()
            let menu = try contextMenu(session)

            let showHistory = try #require(item(menu, "Git", "Show History"))
            #expect(perform(showHistory))

            #expect(workspace.toolWindowManager.isVisible(.git))
        }
    }

    @Test
    func rollbackAsksForConfirmationAndLeavesTheFileUntouchedUntilConfirmed() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, initializeGit: true)
            defer { session.close() }
            try "locally changed\n".write(to: session.fileURL, atomically: true, encoding: .utf8)
            let menu = try contextMenu(session)

            let rollback = try #require(item(menu, "Git", "Rollback…"))
            #expect(perform(rollback))

            #expect(DreamderHeadless.suppressedModals.contains("Rollback Changes"))
            try await Task.sleep(for: .milliseconds(300))
            #expect(try String(contentsOf: session.fileURL, encoding: .utf8) == "locally changed\n")
        }
    }

    @Test
    func rightClickOutsideTheSelectionMovesTheCaretToTheClickedPosition() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 12, length: 7))
            let target = try clickPoint(in: session, atOffset: 2)
            #expect(session.textView.bounds.contains(target))
            let expectedOffset = session.textView.layoutManager.textOffsetAtPoint(target) ?? 0

            let menu = try contextMenu(session, atOffset: 2)

            try await eventually { session.selectedRanges == [NSRange(location: expectedOffset, length: 0)] }
            #expect(isEnabled(menu, "Copy") == false)
        }
    }

    @Test
    func rightClickInsideTheSelectionKeepsIt() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 12, length: 7))

            let menu = try contextMenu(session, atOffset: 15)

            #expect(session.selectedRanges == [NSRange(location: 12, length: 7)])
            #expect(isEnabled(menu, "Copy") == true)
        }
    }

    @Test
    func controlClickBehavesLikeARightClick() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 12, length: 7))
            let target = try clickPoint(in: session, atOffset: 2)
            #expect(session.textView.bounds.contains(target))
            let expectedOffset = session.textView.layoutManager.textOffsetAtPoint(target) ?? 0
            let event = try mouseEvent(.leftMouseDown, flags: .control, in: session, atOffset: 2)

            let menu = try #require(session.textView.menu(for: event))

            #expect(titles(menu).contains("Find Usages"))
            try await eventually { session.selectedRanges == [NSRange(location: expectedOffset, length: 0)] }
        }
    }

    @Test
    func plainLeftClickDoesNotOpenTheEditorMenuAndKeepsTheSelection() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 0, length: 5))
            let event = try mouseEvent(.leftMouseDown, in: session, atOffset: 14)

            let menu = session.textView.menu(for: event)

            #expect(titles(menu).contains("Find Usages") == false)
            #expect(session.selectedRanges == [NSRange(location: 0, length: 5)])
        }
    }

    @Test
    func rightClickOutsideTheTextViewBuildsTheMenuWithoutMovingTheCaret() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            session.select(NSRange(location: 0, length: 5))
            let outside = NSPoint(x: -500, y: -500)
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .rightMouseDown,
                    location: outside,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: session.hosted.window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                )
            )

            let menu = try #require(session.textView.menu(for: event))

            #expect(titles(menu).contains("Find Usages"))
            #expect(session.selectedRanges == [NSRange(location: 0, length: 5)])
        }
    }

    @Test
    func destroyingTheCoordinatorRestoresTheDefaultMenuBehavior() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            #expect(EditorContextMenuInstaller.handler(for: session.textView) != nil)

            session.coordinator.destroy()

            #expect(EditorContextMenuInstaller.handler(for: session.textView) == nil)
            let event = try mouseEvent(.rightMouseDown, in: session)
            #expect(titles(session.textView.menu(for: event)).contains("Find Usages") == false)
        }
    }
}
