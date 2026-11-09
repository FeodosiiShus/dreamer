import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class RollbackRecorder {
    var urls: [URL] = []
    let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    func ask(_ url: URL) -> Bool {
        urls.append(url)
        return answer
    }
}

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorSourceControlMenuTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["Sources"]
    private static let files = ["a.txt", "b.txt", "Sources/main.swift"]
    private static let annotateTitle = "Annotate with Git Blame"

    private func documents(for file: CEWorkspaceFile) -> [CodeFileDocument] {
        let target = file.url.resolvingSymlinksInPath().path(percentEncoded: false)
        return NSDocumentController.shared.documents
            .compactMap { $0 as? CodeFileDocument }
            .filter { $0.fileURL?.resolvingSymlinksInPath().path(percentEncoded: false) == target }
    }

    private func discard(_ documents: [CodeFileDocument]) {
        for document in documents {
            document.windowControllers.forEach { $0.window?.isReleasedWhenClosed = false }
            document.close()
        }
    }

    private func modalCount(_ title: String) -> Int {
        DreamderHeadless.suppressedModals.filter { $0 == title }.count
    }

    private func markAsRepository(_ harness: Harness) throws {
        let manager = try #require(harness.workspace.sourceControlManager)
        manager.isGitRepository = true
    }

    private func firstTab(_ harness: Harness, for file: CEWorkspaceFile) throws -> EditorInstance {
        try #require(harness.editor.tabs.first { $0.file == file })
    }

    private func blame(_ harness: Harness, for file: CEWorkspaceFile) throws -> GitBlameCoordinator {
        let tab = try firstTab(harness, for: file)
        let document = try #require(file.fileDocument)
        return GitBlameCoordinator(editorInstance: tab, codeFile: document)
    }

    private func detachedMenu(_ harness: Harness, item: CEWorkspaceFile?, attached: Bool) -> ProjectNavigatorMenu {
        let menu = ProjectNavigatorMenu(harness.controller)
        menu.item = item
        menu.workspace = attached ? harness.workspace : nil
        return menu
    }

    @Test
    func openInNewWindowShowsEverySelectedFileInItsOwnDocumentWindow() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.txt")
            harness.select([a, b])
            let menu = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Open in New Window", in: menu)?.isEnabled == true)

            try harness.perform("Open in New Window", in: menu)

            let aDocuments = documents(for: a)
            let bDocuments = documents(for: b)
            defer {
                discard(aDocuments)
                discard(bDocuments)
            }
            let aDocument = try #require(aDocuments.first)
            let bDocument = try #require(bDocuments.first)
            #expect(aDocuments.count == 1)
            #expect(bDocuments.count == 1)
            #expect(aDocument.fileURL?.lastPathComponent == "a.txt")
            #expect(a.fileDocument === aDocument)
            #expect(b.fileDocument === bDocument)
            #expect(!aDocument.windowControllers.isEmpty)
            #expect(!bDocument.windowControllers.isEmpty)
        }
    }

    @Test
    func openInNewWindowSkipsFoldersAndIsDisabledWhenTheSelectionContainsOne() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")
            harness.select([a, sources])
            let menu = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Open in New Window", in: menu)?.isEnabled == false)

            menu.openInNewWindow()

            let aDocuments = documents(for: a)
            defer { discard(aDocuments) }
            #expect(aDocuments.count == 1)
            #expect(documents(for: sources).isEmpty)
            #expect(sources.fileDocument == nil)
        }
    }

    @Test
    func openInNewWindowIsDisabledForAnEmptySelection() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.select([])
            harness.click(nil)
            let menu = harness.menu
            menu.workspace = harness.workspace
            menu.item = a

            menu.rebuild()

            #expect(harness.menuItem(titled: "Open in New Window", in: menu)?.isEnabled == false)
            menu.openInNewWindow()
            #expect(documents(for: a).isEmpty)
        }
    }

    @Test
    func openInNewWindowReusesTheDocumentOfAnOpenTabAndDoesNotAddAnotherWindow() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let tabDocument = try #require(a.fileDocument)
            let menu = harness.buildMenu(clicking: a)

            try harness.perform("Open in New Window", in: menu)

            let opened = documents(for: a)
            defer { discard(opened) }
            #expect(opened.count == 1)
            #expect(opened.first === tabDocument)
            #expect(a.fileDocument === tabDocument)
            #expect(tabDocument.windowControllers.count == 1)

            try harness.perform("Open in New Window", in: menu)

            #expect(tabDocument.windowControllers.count == 1)
            #expect(documents(for: a).count == 1)
        }
    }

    @Test
    func openInNewWindowReportsFilesThatCannotBeLoadedAndContinuesWithTheOthers() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.txt")
            harness.select([a, b])
            let menu = harness.buildMenu(clicking: a)
            try harness.remove("a.txt")
            let modalsBefore = DreamderHeadless.suppressedModals.count

            menu.openInNewWindow()

            let bDocuments = documents(for: b)
            defer { discard(bDocuments) }
            #expect(documents(for: a).isEmpty)
            #expect(a.fileDocument == nil)
            #expect(bDocuments.count == 1)
            #expect(DreamderHeadless.suppressedModals.count > modalsBefore)
        }
    }

    @Test
    func openingAMissingFileInANewEditorWindowThrowsAndRegistersNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let ghost = CEWorkspaceFile(url: harness.url("ghost-window"))

            #expect(throws: (any Error).self) {
                try NSDocumentController.shared.openInNewEditorWindow(ghost)
            }

            #expect(ghost.fileDocument == nil)
            #expect(documents(for: ghost).isEmpty)
        }
    }

    @Test
    func openWithExternalEditorReportsEveryFileThatCannotBeOpened() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.txt")
            #expect(!a.openWithExternalEditor())
            harness.select([a, b])
            let menu = harness.buildMenu(clicking: a)
            let aTitle = "Cannot open \"a.txt\" with an external application"
            let bTitle = "Cannot open \"b.txt\" with an external application"
            let aBefore = modalCount(aTitle)
            let bBefore = modalCount(bTitle)

            try harness.perform("Open with External Editor", in: menu)

            #expect(modalCount(aTitle) == aBefore + 1)
            #expect(modalCount(bTitle) == bBefore + 1)
            #expect(DreamderHeadless.suppressedExternalOpens.contains(a.url.absoluteString))
        }
    }

    @Test
    func sourceControlSubmenuIsDisabledOutsideARepository() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let menu = harness.buildMenu(clicking: a)

            for title in ["Show History", Self.annotateTitle, "Rollback…"] {
                #expect(harness.menuItem(titled: title, in: menu)?.isEnabled == false)
            }
        }
    }

    @Test
    func sourceControlSubmenuEnablesHistoryForFoldersAndEverythingForFiles() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")

            let fileMenu = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Show History", in: fileMenu)?.isEnabled == true)
            #expect(harness.menuItem(titled: Self.annotateTitle, in: fileMenu)?.isEnabled == true)
            #expect(harness.menuItem(titled: "Rollback…", in: fileMenu)?.isEnabled == true)
            #expect(harness.menuItem(titled: Self.annotateTitle, in: fileMenu)?.state == .off)

            let folderMenu = harness.buildMenu(clicking: sources)
            #expect(harness.menuItem(titled: "Show History", in: folderMenu)?.isEnabled == true)
            #expect(harness.menuItem(titled: Self.annotateTitle, in: folderMenu)?.isEnabled == false)
            #expect(harness.menuItem(titled: "Rollback…", in: folderMenu)?.isEnabled == false)
        }
    }

    @Test
    func showHistoryRevealsTheGitToolWindow() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let sources = try harness.file("Sources")
            harness.workspace.toolWindowManager.hide(.git)
            #expect(!harness.workspace.toolWindowManager.isVisible(.git))
            let menu = harness.buildMenu(clicking: sources)

            try harness.perform("Show History", in: menu)

            #expect(harness.workspace.toolWindowManager.isVisible(.git))
        }
    }

    @Test
    func openAsSubmenuKeepsItsLeafItemsDisabled() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Sources")
            let main = try harness.file("Sources/main.swift")
            let sources = try harness.file("Sources")

            let fileMenu = harness.buildMenu(clicking: main)
            let fileSubmenu = try #require(harness.menuItem(titled: "Open As", in: fileMenu)?.submenu)
            let fileItems = fileSubmenu.items.filter { !$0.isSeparatorItem }
            #expect(harness.titles(of: fileSubmenu).contains("Source Code"))
            #expect(!fileItems.isEmpty)
            #expect(fileItems.allSatisfy { !$0.isEnabled })

            let folderMenu = harness.buildMenu(clicking: sources)
            let folderSubmenu = try #require(harness.menuItem(titled: "Open As", in: folderMenu)?.submenu)
            #expect(harness.titles(of: folderSubmenu) == ["<None>"])
            #expect(folderSubmenu.items.allSatisfy { !$0.isEnabled })
        }
    }

    @Test
    func isAnnotatingIsFalseWithoutATabOrACoordinatorAndFollowsTheCoordinator() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let menu = harness.buildMenu(clicking: a)
            #expect(!menu.isAnnotating(a))

            harness.editor.openTab(file: a, asTemporary: false)
            #expect(!menu.isAnnotating(a))

            let coordinator = try blame(harness, for: a)
            withExtendedLifetime(coordinator) {
                #expect(!menu.isAnnotating(a))
                coordinator.toggleAnnotate()
                #expect(menu.isAnnotating(a))
                coordinator.toggleAnnotate()
                #expect(!menu.isAnnotating(a))
            }

            let detached = detachedMenu(harness, item: a, attached: false)
            #expect(!detached.isAnnotating(a))
        }
    }

    @Test
    func annotateItemShowsAnOnStateWhileTheCoordinatorIsAnnotating() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let coordinator = try blame(harness, for: a)
            withExtendedLifetime(coordinator) {
                coordinator.toggleAnnotate()

                let annotating = harness.buildMenu(clicking: a)
                #expect(harness.menuItem(titled: Self.annotateTitle, in: annotating)?.state == .on)

                coordinator.toggleAnnotate()

                let idle = harness.buildMenu(clicking: a)
                #expect(harness.menuItem(titled: Self.annotateTitle, in: idle)?.state == .off)
            }
        }
    }

    @Test
    func annotateTogglesTheCoordinatorOfTheOpenedTabImmediately() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let coordinator = try blame(harness, for: a)
            let menu = harness.buildMenu(clicking: a)

            try harness.perform(Self.annotateTitle, in: menu)

            withExtendedLifetime(coordinator) {
                #expect(coordinator.isAnnotating)
            }
        }
    }

    @Test
    func annotateOpensTheTabAndTogglesTheCoordinatorThatRegistersLater() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            #expect(harness.editor.tabs.isEmpty)
            let menu = harness.buildMenu(clicking: a)

            try harness.perform(Self.annotateTitle, in: menu)

            #expect(harness.editor.tabs.contains { $0.file == a })
            let coordinator = try blame(harness, for: a)
            await menu.blameRetry?.value
            withExtendedLifetime(coordinator) {
                #expect(coordinator.isAnnotating)
                #expect(menu.isAnnotating(a))
            }
        }
    }

    @Test
    func annotateDoesNothingForFoldersWithoutItemOrWithoutAnEditor() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")

            detachedMenu(harness, item: sources, attached: true).annotate()
            detachedMenu(harness, item: nil, attached: true).annotate()
            detachedMenu(harness, item: a, attached: false).annotate()

            #expect(harness.editor.tabs.isEmpty)
        }
    }

    @Test
    func toggleBlameWithoutRetriesLeavesAnUnregisteredTabUntouched() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let tab = try firstTab(harness, for: a)
            let menu = harness.buildMenu(clicking: a)

            menu.toggleBlame(for: tab, attempts: 0)
            let late = try blame(harness, for: a)
            await menu.blameRetry?.value

            withExtendedLifetime(late) {
                #expect(!late.isAnnotating)
            }
        }
    }

    @Test
    func toggleBlameTogglesARegisteredCoordinatorEvenWithoutRetries() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let tab = try firstTab(harness, for: a)
            let coordinator = try blame(harness, for: a)
            let menu = harness.buildMenu(clicking: a)

            menu.toggleBlame(for: tab, attempts: 0)

            withExtendedLifetime(coordinator) {
                #expect(coordinator.isAnnotating)
            }
        }
    }

    @Test
    func toggleBlameRetriesUntilTheCoordinatorAppears() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let tab = try firstTab(harness, for: a)
            let menu = harness.buildMenu(clicking: a)

            menu.toggleBlame(for: tab, attempts: 3)
            let coordinator = try blame(harness, for: a)

            await menu.blameRetry?.value
            withExtendedLifetime(coordinator) {
                #expect(coordinator.isAnnotating)
            }
        }
    }

    @Test
    func rollbackDiscardsChangesOnlyAfterTheConfirmation() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            let confirm = RollbackRecorder(answer: true)
            harness.controller.confirmRollback = { confirm.ask($0) }
            let menu = harness.buildMenu(clicking: a)
            let failures = modalCount("Failed to discard changes")

            try harness.perform("Rollback…", in: menu)

            #expect(confirm.urls == [a.url])
            try await eventually(timeout: .seconds(90)) { modalCount("Failed to discard changes") > failures }
            #expect(try harness.contents("a.txt") == "content of a.txt\n")
        }
    }

    @Test
    func rollbackDoesNothingWhenTheConfirmationIsDeclined() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            let decline = RollbackRecorder(answer: false)
            harness.controller.confirmRollback = { decline.ask($0) }
            let menu = harness.buildMenu(clicking: a)

            try harness.perform("Rollback…", in: menu)
            try await Task.sleep(for: .milliseconds(300))

            #expect(decline.urls == [a.url])
            #expect(try harness.contents("a.txt") == "content of a.txt\n")
        }
    }

    @Test
    func rollbackWithoutACustomConfirmationShowsTheDialogThatHeadlessModeCancels() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try markAsRepository(harness)
            let a = try harness.file("a.txt")
            let menu = harness.buildMenu(clicking: a)
            let before = modalCount("Rollback Changes")

            try harness.perform("Rollback…", in: menu)
            try await Task.sleep(for: .milliseconds(300))

            #expect(modalCount("Rollback Changes") > before)
        }
    }

    @Test
    func rollbackIgnoresMissingItemOrSourceControlManager() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let confirm = RollbackRecorder(answer: true)
            harness.controller.confirmRollback = { confirm.ask($0) }

            detachedMenu(harness, item: nil, attached: true).rollback()
            detachedMenu(harness, item: a, attached: false).rollback()

            #expect(confirm.urls.isEmpty)
        }
    }
}
