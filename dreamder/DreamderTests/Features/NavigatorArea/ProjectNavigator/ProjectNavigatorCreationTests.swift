import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorCreationTests {
    typealias Harness = ProjectNavigatorControllerHarness
    typealias PendingCreation = ProjectNavigatorViewController.PendingCreation

    private static let folders = ["Sources", "Empty"]
    private static let files = ["a.txt", "Sources/main.swift"]
    private static let placeholderName = ProjectNavigatorViewController.placeholderName

    private func settle(_ harness: Harness) async throws {
        try await eventually { harness.fileManager.pendingLoads.isEmpty }
    }

    private func beginInRoot(_ harness: Harness, _ kind: NewItemKind = .file, contents: Data? = nil) {
        harness.controller.beginCreation(kind: kind, in: harness.rootFile, contents: contents)
    }

    private func beginInSources(_ harness: Harness, _ kind: NewItemKind = .file) async throws {
        try harness.expand("Sources")
        try await settle(harness)
        harness.controller.beginCreation(kind: kind, in: try harness.file("Sources"))
    }

    private func rootHasPlaceholder(_ harness: Harness) -> Bool {
        harness.childNames(of: harness.rootFile).contains(Self.placeholderName)
    }

    private func hasTab(_ harness: Harness, named name: String) -> Bool {
        harness.editor.tabs.contains { $0.file.name == name }
    }

    private func isRevealed(_ controller: ProjectNavigatorViewController) -> Bool {
        controller.revealPendingItem()
        return controller.pendingReveal == nil
    }

    private func detachedFile(named name: String, under parent: CEWorkspaceFile?) -> CEWorkspaceFile {
        let base = parent?.url ?? URL(filePath: "/nowhere")
        let file = CEWorkspaceFile(url: base.appending(path: name))
        file.parent = parent
        return file
    }

    private func thrownError(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private func failureDescription(_ error: Error?) -> String? {
        (error as? CEWorkspaceFileManager.FileManagerError)?.errorDescription
    }

    @discardableResult
    private func send(_ command: Selector, to cell: ProjectNavigatorTableViewCell) -> Bool {
        guard let field = cell.textField else { return false }
        return cell.control(field, textView: NSTextView(), doCommandBy: command)
    }

    @Test
    func returnWithAValidNameCreatesTheFileOpensATabAndHighlightsIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            #expect(harness.controller.pendingCreation?.kind == .file)
            #expect(rootHasPlaceholder(harness))

            let handled = try harness.submitCreation("new.txt")

            #expect(handled)
            #expect(harness.exists("new.txt"))
            #expect(try harness.contents("new.txt") == "")
            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
            #expect(harness.childNames(of: harness.rootFile).contains("new.txt"))
            #expect(hasTab(harness, named: "new.txt"))
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "new.txt")
            #expect(try harness.names(in: "").contains(Self.placeholderName) == false)
        }
    }

    @Test
    func returnWithAValidNameCreatesADirectoryWithoutOpeningATab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, .directory)
            let tabsBefore = harness.editor.tabs.count

            try harness.submitCreation("NewDir")

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: harness.url("NewDir").path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(harness.editor.tabs.count == tabsBefore)
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "NewDir")
            #expect(harness.controller.pendingCreation == nil)
            #expect(harness.childNames(of: harness.rootFile).contains("NewDir"))
        }
    }

    @Test
    func directoryPlaceholderIsNotExpandableAndFilePlaceholderIsNot() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, .directory)
            let placeholder = try #require(harness.controller.pendingCreation?.placeholder)
            let controller = harness.controller

            #expect(!controller.outlineView(harness.outlineView, isItemExpandable: placeholder))
            #expect(controller.outlineView(harness.outlineView, isItemExpandable: try harness.file("Sources")))
            #expect(!controller.outlineView(harness.outlineView, isItemExpandable: try harness.file("a.txt")))
            #expect(!controller.outlineView(harness.outlineView, isItemExpandable: "not a file"))
        }
    }

    @Test
    func placeholderCellShowsTheKindSpecificHint() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            #expect(harness.placeholderCell?.textField?.placeholderString == "File name")
            #expect(harness.placeholderCell?.textField?.stringValue == "")
            #expect(harness.controller.pendingCreation?.placeholder.name == Self.placeholderName)

            beginInRoot(harness, .directory)
            #expect(harness.placeholderCell?.textField?.placeholderString == "Directory name")
        }
    }

    @Test
    func placeholderIsTheFirstChildAndTakesKeyboardFocus() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)

            #expect(harness.childNames(of: harness.rootFile).first == Self.placeholderName)
            let placeholder = try #require(harness.controller.pendingCreation?.placeholder)
            #expect(harness.outlineView.selectedRow == harness.row(of: placeholder))
            let cell = try #require(harness.placeholderCell)
            let responder = harness.window.firstResponder
            #expect(responder === cell.textField || (responder as? NSText)?.delegate === cell.textField)
        }
    }

    @Test
    func escapeCancelsWithoutCreatingAnything() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            beginInRoot(harness)

            let handled = try harness.cancelCreationWithEscape()

            #expect(handled)
            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func finishedCellIgnoresFurtherCommands() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let cell = try #require(harness.placeholderCell)
            let field = try #require(cell.textField)

            try harness.cancelCreationWithEscape()
            field.stringValue = "late.txt"
            let again = send(#selector(NSResponder.insertNewline(_:)), to: cell)
            cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

            #expect(!again)
            #expect(!harness.exists("late.txt"))
        }
    }

    @Test
    func blurAfterReturnDoesNotCommitTwice() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let cell = try #require(harness.placeholderCell)

            try harness.submitCreation("first.txt")
            cell.textField?.stringValue = "second.txt"
            cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

            #expect(harness.exists("first.txt"))
            #expect(!harness.exists("second.txt"))
        }
    }

    @Test
    func unrelatedCommandsAreNotHandledByTheCreationCell() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let cell = try #require(harness.placeholderCell)

            let handled = send(#selector(NSResponder.moveUp(_:)), to: cell)

            #expect(!handled)
            #expect(harness.controller.pendingCreation != nil)
        }
    }

    @Test
    func cellsWithoutCreationDoNotHandleCommandsAndForwardTextChanges() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let cell = try #require(harness.cell(for: try harness.file("a.txt")))
            let field = try #require(cell.textField)
            field.stringValue = "b:c"

            let handled = send(#selector(NSResponder.insertNewline(_:)), to: cell)
            cell.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))

            #expect(!handled)
            #expect(field.toolTip == nil)
        }
    }

    @Test
    func standaloneCreationEditingCallsBackForEveryOutcome() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let folder = try #require(harness.cell(for: try harness.file("Sources")))
            var committed: [String] = []
            var cancelled = 0
            folder.creationEditing = ProjectNavigatorTableViewCell.CreationEditing(
                validate: { $0 == "bad" ? "no" : nil },
                commit: { committed.append($0) },
                cancel: { cancelled += 1 }
            )
            let field = try #require(folder.textField)
            #expect(field.placeholderString == "Directory name")

            field.stringValue = "bad"
            let rejected = send(#selector(NSResponder.insertNewline(_:)), to: folder)
            #expect(rejected)
            #expect(field.toolTip == "no")
            #expect(committed.isEmpty && cancelled == 0)

            field.stringValue = "good"
            folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            #expect(field.toolTip == nil)
            _ = send(#selector(NSResponder.insertNewline(_:)), to: folder)
            #expect(committed == ["good"])
            #expect(cancelled == 0)
        }
    }

    @Test
    func settingNilCreationEditingLeavesTheCellAlone() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let cell = try #require(harness.cell(for: try harness.file("a.txt")))
            let before = cell.textField?.stringValue

            cell.creationEditing = nil

            #expect(cell.textField?.stringValue == before)
            #expect(cell.textField?.placeholderString != "File name")
        }
    }

    @Test
    func blurWithAValidNameCommits() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)

            try harness.blurCreation(with: "blurred.txt")

            #expect(harness.exists("blurred.txt"))
            #expect(harness.controller.pendingCreation == nil)
            #expect(hasTab(harness, named: "blurred.txt"))
        }
    }

    @Test
    func blurWithABlankNameCancels() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            beginInRoot(harness)

            try harness.blurCreation(with: "   ")

            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func blurWithAnInvalidNameCancels() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            beginInRoot(harness)

            try harness.blurCreation(with: "a.txt")

            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func returnWithABlankNameCancels() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            beginInRoot(harness)

            let handled = try harness.submitCreation("  \n ")

            #expect(handled)
            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func returnWithAnExistingFileKeepsEditingAndShowsTheError() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            beginInRoot(harness)

            let handled = try harness.submitCreation("a.txt")

            #expect(handled)
            #expect(harness.controller.pendingCreation != nil)
            #expect(harness.placeholderCell?.textField?.toolTip == "A file with the name 'a.txt' already exists")
            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func returnWithAnExistingDirectoryKeepsEditingAndShowsTheError() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, .directory)

            try harness.submitCreation("Sources")

            #expect(harness.controller.pendingCreation != nil)
            #expect(
                harness.placeholderCell?.textField?.toolTip == "A directory with the name 'Sources' already exists"
            )
        }
    }

    @Test
    func returnWithAnInvalidCharacterKeepsEditingAndShowsTheError() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)

            try harness.submitCreation("bad:name")

            #expect(harness.controller.pendingCreation != nil)
            #expect(harness.placeholderCell?.textField?.toolTip == "'bad:name' is an invalid file name")
            #expect(!harness.exists("bad:name"))
        }
    }

    @Test
    func returnWithDotDotKeepsEditingAndShowsTheError() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)

            try harness.submitCreation("..")

            #expect(harness.controller.pendingCreation != nil)
            #expect(harness.placeholderCell?.textField?.toolTip == "'..' is an invalid file name")
        }
    }

    @Test
    func errorIsClearedOnceTheNameBecomesValid() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            try harness.submitCreation("a.txt")
            let cell = try #require(harness.placeholderCell)
            #expect(cell.textField?.toolTip != nil)

            try harness.submitCreation("b.txt")

            #expect(harness.exists("b.txt"))
            #expect(harness.controller.pendingCreation == nil)
        }
    }

    @Test
    func liveValidationShowsAndClearsTheError() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let cell = try #require(harness.placeholderCell)
            let field = try #require(cell.textField)
            let change = Notification(name: NSControl.textDidChangeNotification)

            field.stringValue = ""
            cell.controlTextDidChange(change)
            #expect(field.toolTip == nil)

            field.stringValue = "   "
            cell.controlTextDidChange(change)
            #expect(field.toolTip == nil)

            field.stringValue = "a.txt"
            cell.controlTextDidChange(change)
            #expect(field.toolTip == "A file with the name 'a.txt' already exists")

            field.stringValue = "fresh.txt"
            cell.controlTextDidChange(change)
            #expect(field.toolTip == nil)

            field.stringValue = "x:y"
            cell.controlTextDidChange(change)
            #expect(field.toolTip == "'x:y' is an invalid file name")

            field.stringValue = ""
            cell.controlTextDidChange(change)
            #expect(field.toolTip == nil)
        }
    }

    @Test
    func liveValidationPaintsTheFieldLayerWhenItHasOne() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let cell = try #require(harness.placeholderCell)
            let field = try #require(cell.textField)
            field.wantsLayer = true
            let change = Notification(name: NSControl.textDidChangeNotification)

            field.stringValue = "a.txt"
            cell.controlTextDidChange(change)
            #expect(field.layer?.backgroundColor == errorRed.cgColor)

            field.stringValue = ""
            cell.controlTextDidChange(change)
            #expect(field.layer?.backgroundColor == NSColor.textBackgroundColor.cgColor)
        }
    }

    @Test
    func cellsWithoutALabelSkipLayoutAndTreatTheEnteredNameAsEmpty() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let cell = try #require(harness.cell(for: try harness.file("a.txt")))
            let frame = cell.imageView?.frame

            cell.textField = nil
            cell.resizeSubviews(withOldSize: .zero)

            #expect(cell.enteredName == "")
            #expect(cell.imageView?.frame == frame)
        }
    }

    @Test
    func beginningACreationNextToAParentlessFileDoesNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let ghost = CEWorkspaceFile(url: harness.url("ghost-creation.txt"))

            harness.controller.beginCreation(kind: .file, in: ghost)

            #expect(harness.controller.pendingCreation == nil)
        }
    }

    @Test
    func nestedPathCreatesIntermediateFoldersAndRevealsTheFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, reloadsOnFileEvents: true) { harness in
            beginInRoot(harness)

            try harness.submitCreation("a/b/c.swift")

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: harness.url("a/b").path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(try harness.contents("a/b/c.swift") == "import Foundation\n")
            #expect(hasTab(harness, named: "c.swift"))
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "c.swift")
            let controller = harness.controller
            try await eventually { isRevealed(controller) }
            let created = try harness.file("a/b/c.swift")
            #expect(harness.row(of: created) >= 0)
            #expect(harness.outlineView.selectedRow == harness.row(of: created))
        }
    }

    @Test
    func nestedDirectoryPathCreatesEveryLevel() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, reloadsOnFileEvents: true) { harness in
            beginInRoot(harness, .directory)
            let tabsBefore = harness.editor.tabs.count

            try harness.submitCreation("x/y/z")

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: harness.url("x/y/z").path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(harness.editor.tabs.count == tabsBefore)
            let controller = harness.controller
            try await eventually { isRevealed(controller) }
        }
    }

    @Test
    func dotDotInsideTheProjectWorks() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try await beginInSources(harness)

            try harness.submitCreation("../up.txt")

            #expect(harness.exists("up.txt"))
            #expect(!harness.exists("Sources/up.txt"))
        }
    }

    @Test
    func pathsOutsideTheProjectAreRejected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)

            try harness.submitCreation("../outside.txt")
            #expect(harness.controller.pendingCreation != nil)
            #expect(
                harness.placeholderCell?.textField?.toolTip == "The file must be created inside the project"
            )
            #expect(!FileManager.default.fileExists(atPath: harness.root.deletingLastPathComponent()
                .appending(path: "outside.txt").path))

            try harness.submitCreation("~/dreamder-creation-test.txt")
            #expect(harness.controller.pendingCreation != nil)
            #expect(
                harness.placeholderCell?.textField?.toolTip == "The file must be created inside the project"
            )
            #expect(!FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "dreamder-creation-test.txt").path
            ))
        }
    }

    @Test
    func directoryOutsideTheProjectUsesTheDirectoryNoun() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, .directory)

            try harness.submitCreation("../outside-dir")

            #expect(
                harness.placeholderCell?.textField?.toolTip == "The directory must be created inside the project"
            )
        }
    }

    @Test
    func leadingAndTrailingSlashesAreIgnoredWhenCommitting() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            try harness.submitCreation("/slashed.txt")
            #expect(harness.exists("slashed.txt"))

            beginInRoot(harness, .directory)
            try harness.submitCreation("slashed-dir/")
            #expect(harness.exists("slashed-dir"))
        }
    }

    @Test
    func creatingNextToAFileLandsInItsParent() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.expand("Sources")
            try await settle(harness)
            let sibling = try harness.file("Sources/main.swift")

            harness.controller.beginCreation(kind: .file, in: sibling)
            #expect(harness.controller.pendingCreation?.folder.name == "Sources")
            try harness.submitCreation("beside.swift")

            #expect(harness.exists("Sources/beside.swift"))
            #expect(!harness.exists("beside.swift"))
        }
    }

    @Test
    func creatingNextToARootFileLandsInTheRoot() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.beginCreation(kind: .file, in: try harness.file("a.txt"))
            #expect(harness.controller.pendingCreation?.folder === harness.rootFile)

            try harness.submitCreation("b.txt")

            #expect(harness.exists("b.txt"))
        }
    }

    @Test
    func creatingInAFolderExpandsItAndPutsThePlaceholderFirst() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try await beginInSources(harness)
            let sources = try harness.file("Sources")

            #expect(harness.outlineView.isItemExpanded(sources))
            #expect(harness.childNames(of: sources).first == Self.placeholderName)
            try harness.submitCreation("inside.swift")
            #expect(harness.exists("Sources/inside.swift"))
            #expect(harness.childNames(of: sources).contains("inside.swift"))
        }
    }

    @Test
    func secondBeginCancelsTheFirst() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let first = try #require(harness.controller.pendingCreation?.placeholder)

            try await beginInSources(harness, .directory)

            let second = try #require(harness.controller.pendingCreation)
            #expect(second.placeholder !== first)
            #expect(second.kind == .directory)
            #expect(!rootHasPlaceholder(harness))
            #expect(harness.childNames(of: second.folder).contains(Self.placeholderName))
        }
    }

    @Test
    func cancelWithoutPendingCreationIsANoOp() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")

            harness.controller.cancelCreation()

            #expect(harness.controller.pendingCreation == nil)
            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func commitWithoutPendingCreationIsANoOp() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")

            harness.controller.commitCreation(named: "ghost.txt")

            #expect(try harness.names(in: "") == before)
            #expect(harness.controller.pendingCreation == nil)
        }
    }

    @Test
    func commitWithoutAWorkspaceKeepsThePendingCreation() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let bare = ProjectNavigatorViewController()
            let placeholder = detachedFile(named: Self.placeholderName, under: harness.rootFile)
            bare.pendingCreation = PendingCreation(
                kind: .file,
                folder: harness.rootFile,
                placeholder: placeholder,
                contents: nil
            )

            bare.commitCreation(named: "ghost.txt")

            #expect(bare.pendingCreation != nil)
            #expect(bare.creationErrorMessage(for: "a.txt") == nil)
            #expect(!harness.exists("ghost.txt"))
        }
    }

    @Test
    func creationErrorMessageIsNilWithoutPendingCreation() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.controller.creationErrorMessage(for: "a.txt") == nil)
            #expect(ProjectNavigatorViewController().creationErrorMessage(for: "a.txt") == nil)
        }
    }

    @Test
    func creationErrorMessageValidatesAgainstThePendingFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)

            let message = harness.controller.creationErrorMessage(for: "a.txt")
            #expect(message == "A file with the name 'a.txt' already exists")
            #expect(harness.controller.creationErrorMessage(for: "ok.txt") == nil)
            #expect(harness.controller.creationErrorMessage(for: "") == "Specify a file name")
        }
    }

    @Test
    func focusWithoutPendingCreationOrRowIsANoOp() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.focusPendingCreation()
            #expect(harness.controller.pendingCreation == nil)

            harness.controller.pendingCreation = PendingCreation(
                kind: .file,
                folder: harness.rootFile,
                placeholder: detachedFile(named: "ghost", under: harness.rootFile),
                contents: nil
            )
            let selectedBefore = harness.outlineView.selectedRow

            harness.controller.focusPendingCreation()

            #expect(harness.outlineView.selectedRow == selectedBefore)
            harness.controller.pendingCreation = nil
        }
    }

    @Test
    func commitTimeValidationFailureAlertsForFiles() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            try harness.write("raced.txt", "original\n")

            harness.controller.commitCreation(named: "raced.txt")

            #expect(DreamderHeadless.suppressedModals.contains("Cannot Create File"))
            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
            #expect(try harness.contents("raced.txt") == "original\n")
        }
    }

    @Test
    func commitTimeValidationFailureAlertsForDirectories() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, .directory)
            try harness.makeDirectory("raced-dir")

            harness.controller.commitCreation(named: "raced-dir")

            #expect(DreamderHeadless.suppressedModals.contains("Cannot Create Directory"))
            #expect(harness.controller.pendingCreation == nil)
            #expect(!rootHasPlaceholder(harness))
        }
    }

    @Test
    func creationInARemovedFolderFailsWithoutCreatingAnything() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try await beginInSources(harness)
            try harness.remove("Sources")

            harness.controller.commitCreation(named: "orphan.txt")

            #expect(harness.controller.pendingCreation == nil)
            #expect(!harness.exists("Sources"))
            #expect(!hasTab(harness, named: "orphan.txt"))
        }
    }

    @Test
    func creationInALockedFolderFailsWithoutCreatingAnything() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try await beginInSources(harness)
            try harness.lock("Sources")

            harness.controller.commitCreation(named: "denied.txt")

            #expect(harness.controller.pendingCreation == nil)
            #expect(!harness.exists("Sources/denied.txt"))
            #expect(!hasTab(harness, named: "denied.txt"))
        }
    }

    @Test
    func menuActionsNeverCreateUntitledItems() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let root = harness.rootFile
            let before = try harness.names(in: "")

            var menu = harness.buildMenu(clicking: root)
            try harness.perform("New File...", in: menu)
            #expect(harness.controller.pendingCreation?.kind == .file)
            #expect(try harness.names(in: "") == before)
            try harness.cancelCreationWithEscape()

            menu = harness.buildMenu(clicking: root)
            try harness.perform("New Folder", in: menu)
            #expect(harness.controller.pendingCreation?.kind == .directory)
            #expect(try harness.names(in: "") == before)
            try harness.cancelCreationWithEscape()

            harness.pasteboard.replaceContents(withText: "clipboard text")
            menu = harness.buildMenu(clicking: root)
            try harness.perform("New File from Clipboard", in: menu)
            #expect(harness.controller.pendingCreation?.contents == Data("clipboard text".utf8))
            #expect(try harness.names(in: "") == before)
            try harness.submitCreation("from-clipboard.txt")

            #expect(try harness.contents("from-clipboard.txt") == "clipboard text")
            #expect(try harness.names(in: "").contains { $0.hasPrefix("untitled") } == false)
        }
    }

    @Test
    func selectingThePlaceholderNeverOpensATab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            let placeholder = try #require(harness.controller.pendingCreation?.placeholder)
            #expect(harness.outlineView.selectedRow == harness.row(of: placeholder))
            let tabsBefore = harness.editor.tabs.count
            let temporaryBefore = harness.editor.temporaryTab?.file.name

            harness.controller.shouldSendSelectionUpdate = true
            harness.controller.outlineViewSelectionDidChange(
                Notification(name: NSOutlineView.selectionDidChangeNotification, object: harness.outlineView)
            )

            #expect(harness.editor.tabs.count == tabsBefore)
            #expect(harness.editor.temporaryTab?.file.name == temporaryBefore)
            #expect(!hasTab(harness, named: Self.placeholderName))
        }
    }

    @Test
    func selectingARealFileStillOpensItsTemporaryTab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let file = try harness.file("a.txt")

            harness.controller.shouldSendSelectionUpdate = true
            harness.outlineView.selectRowIndexes(IndexSet(integer: harness.row(of: file)), byExtendingSelection: false)

            #expect(hasTab(harness, named: "a.txt"))
        }
    }

    @Test
    func revealDefersWhileAnAncestorIsLoading() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let ghost = detachedFile(named: "pending.swift", under: sources)
            harness.fileManager.pendingLoads.insert(sources.id)

            #expect(harness.controller.hasLoadingAncestor(ghost))
            harness.controller.reveal(ghost)

            #expect(harness.controller.pendingReveal === ghost)

            harness.fileManager.pendingLoads.remove(sources.id)
            #expect(!harness.controller.hasLoadingAncestor(ghost))
            #expect(!isRevealed(harness.controller))
            harness.controller.pendingReveal = nil
        }
    }

    @Test
    func revealOfAMissingFileWithoutLoadingAncestorAlerts() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let ghost = detachedFile(named: "gone.swift", under: try harness.file("Sources"))

            harness.controller.reveal(ghost)

            #expect(harness.controller.pendingReveal == nil)
            #expect(DreamderHeadless.suppressedModals.contains("Could not find file"))
        }
    }

    @Test
    func pendingRevealClearsOnceTheRowExists() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, reloadsOnFileEvents: true) { harness in
            harness.controller.revealPendingItem()
            #expect(harness.controller.pendingReveal == nil)

            let rootless = detachedFile(named: "rootless", under: nil)
            harness.controller.pendingReveal = rootless
            harness.controller.revealPendingItem()
            #expect(harness.controller.pendingReveal === rootless)

            let real = try harness.file("Sources/main.swift")
            harness.controller.pendingReveal = real
            try await eventually { isRevealed(harness.controller) }

            #expect(harness.controller.pendingReveal == nil)
            #expect(harness.outlineView.selectedRow == harness.row(of: real))
        }
    }

    @Test
    func hasLoadingAncestorIsFalseWithoutAWorkspace() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let bare = ProjectNavigatorViewController()

            let file = try harness.file("a.txt")
            #expect(!bare.hasLoadingAncestor(file))
            #expect(!harness.controller.hasLoadingAncestor(file))
        }
    }

    @Test
    func hasLoadingAncestorWalksEveryParentAndFindsALoadingFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let sources = try harness.file("Sources")
            let middle = detachedFile(named: "middle", under: sources)
            let leaf = detachedFile(named: "leaf", under: middle)

            #expect(!harness.controller.hasLoadingAncestor(leaf))

            harness.fileManager.pendingLoads.insert(sources.id)

            #expect(harness.controller.hasLoadingAncestor(leaf))
            harness.fileManager.pendingLoads.remove(sources.id)
        }
    }

    @Test
    func swiftFilesGetTheSwiftTemplate() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            try harness.submitCreation("Main.swift")
            #expect(try harness.contents("Main.swift") == "import Foundation\n")
        }
    }

    @Test
    func markdownFilesGetATitleFromTheFileName() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            try harness.submitCreation("notes.md")
            #expect(try harness.contents("notes.md") == "# notes\n")
        }
    }

    @Test
    func goFilesGetThePackageOfTheirFolder() async throws {
        try await Harness.run(folders: ["my-app"], files: []) { harness in
            harness.controller.beginCreation(kind: .file, in: try harness.file("my-app"))
            try harness.submitCreation("server.go")
            #expect(try harness.contents("my-app/server.go") == "package my_app\n")
        }
    }

    @Test
    func emptyTemplateExtensionsProduceEmptyFiles() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            for name in ["a.ts", "a.js", "a.py", "a.rs"] {
                beginInRoot(harness)
                try harness.submitCreation(name)
                #expect(harness.exists(name))
                #expect(try harness.contents(name) == "")
            }
        }
    }

    @Test
    func unknownOrMissingExtensionsProduceEmptyFiles() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            for name in ["data.xyz", "Makefile"] {
                beginInRoot(harness)
                try harness.submitCreation(name)
                #expect(try harness.contents(name) == "")
            }
        }
    }

    @Test
    func uppercaseExtensionUsesTheTemplate() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness)
            try harness.submitCreation("Main.SWIFT")
            #expect(try harness.contents("Main.SWIFT") == "import Foundation\n")
        }
    }

    @Test
    func clipboardContentsBeatTheTemplate() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, contents: Data("from clipboard\n".utf8))
            try harness.submitCreation("Main.swift")
            #expect(try harness.contents("Main.swift") == "from clipboard\n")
        }
    }

    @Test
    func directoriesIgnoreProvidedContents() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            beginInRoot(harness, .directory, contents: Data("ignored".utf8))
            try harness.submitCreation("Folder.swift")
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: harness.url("Folder.swift").path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
    }

    @Test
    func workspaceOverrideTemplateIsRendered() async throws {
        try await Harness.run(folders: ["my-app"], files: []) { harness in
            try harness.write(".dreamder/fileTemplates/swift.txt", "// ${NAME} in ${PACKAGE_NAME}\n")
            harness.controller.beginCreation(kind: .file, in: try harness.file("my-app"))
            try harness.submitCreation("Main.swift")
            #expect(try harness.contents("my-app/Main.swift") == "// Main in my_app\n")
        }
    }

    @Test
    func emptyOverrideTemplateProducesAnEmptyFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write(".dreamder/fileTemplates/swift.txt", "")
            beginInRoot(harness)
            try harness.submitCreation("Empty.swift")
            #expect(try harness.contents("Empty.swift") == "")
        }
    }

    @Test
    func fileManagerCreatesAFileWithContents() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let plan = NewItemPlan(kind: .file, target: harness.url("made.txt"), directoriesToCreate: [])

            let created = try harness.fileManager.create(plan, contents: Data("hello".utf8))

            #expect(created.name == "made.txt")
            #expect(!created.isFolder)
            #expect(try harness.contents("made.txt") == "hello")
        }
    }

    @Test
    func fileManagerCreatesADirectoryWithIntermediateDirectories() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let plan = NewItemPlan(
                kind: .directory,
                target: harness.url("p/q/r"),
                directoriesToCreate: [harness.url("p"), harness.url("p/q")]
            )

            let created = try harness.fileManager.create(plan)

            #expect(created.isFolder)
            #expect(created.name == "r")
            #expect(harness.exists("p/q/r"))
        }
    }

    @Test
    func fileManagerRejectsAnExistingTarget() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let plan = NewItemPlan(kind: .file, target: harness.url("a.txt"), directoriesToCreate: [])

            let error = thrownError { try harness.fileManager.create(plan) }

            #expect(failureDescription(error) == "Destination already exists")
            let contents = try harness.contents("a.txt")
            #expect(contents == "content of a.txt\n")
        }
    }

    @Test
    func fileManagerRejectsAPlanOutsideTheRoot() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let outside = try makeTemporaryDirectory(label: "CreationOutside")
            defer { removeTemporaryDirectory(outside) }
            let plan = NewItemPlan(kind: .file, target: outside.appending(path: "x.txt"), directoriesToCreate: [])

            let error = thrownError { try harness.fileManager.create(plan) }

            #expect(failureDescription(error) == "File not found in Dreamder")
        }
    }

    @Test
    func fileManagerFailsWhenTheFileCannotBeWritten() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let plan = NewItemPlan(kind: .file, target: harness.url("missing/x.txt"), directoriesToCreate: [])

            let error = thrownError { try harness.fileManager.create(plan) }

            #expect((error as NSError?)?.domain == NSCocoaErrorDomain)
            #expect(!harness.exists("missing"))
        }
    }

    @Test
    func refreshPicksUpNewChildrenAndIgnoresUnknownDirectories() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let manager = harness.fileManager
            let root = harness.rootFile
            try await eventually { manager.childrenOfFile(root)?.isEmpty == false }
            try harness.write("fresh.txt")

            try manager.refresh(directoryAt: harness.root)

            #expect(manager.childrenOfFile(root)?.contains { $0.name == "fresh.txt" } == true)
            try manager.refresh(directoryAt: harness.url("not-indexed"))
            #expect(manager.getFile(harness.url("not-indexed").path) == nil)
        }
    }
}
