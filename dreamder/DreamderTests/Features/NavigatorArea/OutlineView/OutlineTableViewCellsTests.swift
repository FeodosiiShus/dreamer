import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct OutlineTableViewCellsTests {
    private let frame = NSRect(x: 0, y: 0, width: 300, height: 22)

    private func decoder() throws -> NSKeyedUnarchiver {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        return try NSKeyedUnarchiver(forReadingFrom: data)
    }

    private func components(_ color: NSColor?) -> [CGFloat] {
        guard let converted = color?.usingColorSpace(.sRGB) else { return [] }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent]
    }

    private func write(_ name: String, in dir: URL) throws -> CEWorkspaceFile {
        let url = dir.appending(path: name)
        try "content\n".write(to: url, atomically: true, encoding: .utf8)
        return CEWorkspaceFile(url: url)
    }

    @Test
    func standardCellBuildsLabelsAndIconAndLaysThemOut() {
        let cell = StandardTableViewCell(frame: frame)

        #expect(cell.textField is StandardTableViewCell.SpecialSelectTextField)
        #expect(cell.textField?.isEditable == false)
        #expect(cell.textField?.isSelectable == false)
        #expect(cell.secondaryLabel?.isEditable == false)
        #expect(cell.secondaryLabel?.alignment == .center)
        #expect(cell.imageView?.imageScaling == .scaleProportionallyDown)
        #expect(cell.imageView?.frame == NSRect(x: 3, y: 3, width: 16, height: 16))
        #expect(cell.textField?.frame.minX == 24)
        #expect(cell.textField?.frame.height == 18)
        #expect(cell.secondaryLabel?.frame.width == 0)
        #expect(cell.subviews.count == 3)
    }

    @Test
    func editableStandardCellMakesItsLabelEditable() {
        let cell = StandardTableViewCell(frame: frame, isEditable: true)

        #expect(cell.textField?.isEditable == true)
        #expect(cell.textField?.isSelectable == true)
    }

    @Test
    func secondaryLabelCanFollowThePrimaryLabel() {
        let cell = StandardTableViewCell(frame: frame)
        cell.textField?.stringValue = "name.swift"
        cell.secondaryLabel?.stringValue = "3"

        cell.secondaryLabelRightAligned = false
        let label = cell.textField
        let secondary = cell.secondaryLabel
        #expect(label?.frame.minX == 24)
        #expect(secondary?.frame.minX == (label?.frame.maxX ?? 0) + 2)
        #expect(secondary?.frame.height == 18)

        cell.secondaryLabelRightAligned = true
        #expect(cell.secondaryLabel?.frame.width == 0)
        #expect(cell.secondaryLabel?.frame.minX ?? 0 > 24)
    }

    @Test
    func layoutIsSkippedWithoutAPrimaryLabel() {
        let cell = StandardTableViewCell(frame: frame)
        let marker = NSRect(x: 40, y: 1, width: 5, height: 5)
        cell.imageView?.frame = marker
        cell.textField = nil

        cell.resizeSubviews(withOldSize: .zero)

        #expect(cell.imageView?.frame == marker)
    }

    @Test
    func cellsCannotBeDecodedAndTheDefaultInitializersWork() throws {
        #expect(StandardTableViewCell(coder: try decoder()) == nil)
        #expect(FileSystemTableViewCell(coder: try decoder()) == nil)
        let plain = FileSystemTableViewCell(frame: frame)
        #expect(plain.fileItem == nil)
        #expect(plain.textField?.delegate === plain)
    }

    @Test
    func labelSelectsOnlyTheNameWithoutItsExtension() {
        let field = StandardTableViewCell.SpecialSelectTextField(frame: .zero)
        field.stringValue = "name.swift"
        #expect(field.becomeFirstResponder())

        let noExtension = StandardTableViewCell.SpecialSelectTextField(frame: .zero)
        noExtension.stringValue = "Makefile"
        #expect(noExtension.becomeFirstResponder())
    }

    @Test
    func labelTogglesItsBackgroundLayerWhileEditing() {
        let field = StandardTableViewCell.SpecialSelectTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        let editor = NSTextView()

        field.textDidBeginEditing(Notification(name: NSText.didBeginEditingNotification, object: editor))
        #expect(field.wantsLayer)
        #expect(field.layer?.backgroundColor != nil)

        field.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor))
        #expect(!field.wantsLayer)
        #expect(field.layer?.backgroundColor == nil)
    }

    @Test
    func fileCellShowsTheFileIconAndName() async throws {
        try withTempDir { dir in
            let item = try write("Main.swift", in: dir)
            let cell = FileSystemTableViewCell(frame: frame, item: item, isEditable: false)

            #expect(cell.fileItem === item)
            #expect(cell.imageView?.image?.name() == "fileTypes/swiftLang")
            #expect(cell.textField?.stringValue == item.labelFileName())
            #expect(cell.imageView?.imageScaling == .scaleProportionallyDown)
            #expect(cell.imageView?.contentTintColor == nil)
        }
    }

    @Test
    func folderCellsUseTheFolderOrExcludedRootIconAndDimExcludedFolders() async throws {
        try withTempDir { dir in
            let plain = dir.appending(path: "plain", directoryHint: .isDirectory)
            let modules = dir.appending(path: "node_modules", directoryHint: .isDirectory)
            let nested = modules.appending(path: "pkg", directoryHint: .isDirectory)
            for folder in [plain, nested] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let scope = WorkspaceFileScope(rootURL: dir)
            @MainActor func folderCell(_ url: URL, parent: URL) -> FileSystemTableViewCell {
                let state = ProjectNavigatorExclusion.resolve(
                    url: url,
                    isFolder: true,
                    parentURL: parent,
                    scope: scope
                )
                return FileSystemTableViewCell(frame: frame, item: CEWorkspaceFile(url: url), exclusion: state)
            }
            @MainActor func nameColor(_ cell: FileSystemTableViewCell) -> [CGFloat] {
                components(cell.textField?.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            }

            let plainCell = folderCell(plain, parent: dir)
            let modulesCell = folderCell(modules, parent: dir)
            let nestedCell = folderCell(nested, parent: modules)

            #expect(plainCell.exclusion == .included)
            #expect(plainCell.imageView?.image?.name() == "nodes/folder")
            #expect(plainCell.imageView?.alphaValue == 1)
            #expect(nameColor(plainCell) == components(NSColor(Islands.foreground)))
            #expect(modulesCell.exclusion == .excludedRoot)
            #expect(modulesCell.imageView?.image?.name() == "nodes/excludeRoot")
            #expect(modulesCell.imageView?.alphaValue == FileSystemTableViewCell.excludedIconAlpha)
            #expect(nameColor(modulesCell) == components(NSColor(Islands.secondaryForeground)))
            #expect(nestedCell.exclusion == .excludedContent)
            #expect(nestedCell.imageView?.image?.name() == "nodes/folder")
            #expect(nestedCell.imageView?.alphaValue == FileSystemTableViewCell.excludedIconAlpha)
            #expect(nameColor(nestedCell) == components(NSColor(Islands.secondaryForeground)))
        }
    }

    @Test
    func ignoredFilesUseTheIgnoredColourUnlessTheyCarryAGitStatus() async throws {
        try withTempDir { dir in
            try "*.log\n".write(to: dir.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
            let ignored = try write("debug.log", in: dir)
            let tracked = try write("main.swift", in: dir)
            let scope = WorkspaceFileScope(rootURL: dir)
            @MainActor func state(_ file: CEWorkspaceFile) -> ProjectNavigatorExclusion {
                ProjectNavigatorExclusion.resolve(url: file.url, isFolder: false, parentURL: dir, scope: scope)
            }

            let ignoredCell = FileSystemTableViewCell(frame: frame, item: ignored, exclusion: state(ignored))
            let trackedCell = FileSystemTableViewCell(frame: frame, item: tracked, exclusion: state(tracked))

            #expect(ignoredCell.exclusion == .excludedRoot)
            #expect(components(ignoredCell.nameColor(for: ignored)) == components(NSColor(Islands.fileIgnored)))
            #expect(ignoredCell.imageView?.alphaValue == 1)
            #expect(components(trackedCell.nameColor(for: tracked)) == components(NSColor(Islands.foreground)))
            ignored.gitStatus = .modified
            #expect(components(ignoredCell.nameColor(for: ignored)) == components(NSColor(Islands.fileModified)))
        }
    }

    @Test
    func exclusionResolvesToIncludedWithoutAScopeOrForIncludedItems() async throws {
        try withTempDir { dir in
            let file = dir.appending(path: "a.txt")
            #expect(ProjectNavigatorExclusion.resolve(url: file, isFolder: false, parentURL: dir, scope: nil) == .included)
            let scope = WorkspaceFileScope(rootURL: dir)
            #expect(ProjectNavigatorExclusion.resolve(url: file, isFolder: false, parentURL: dir, scope: scope) == .included)
            #expect(ProjectNavigatorExclusion.resolve(url: dir, isFolder: true, parentURL: nil, scope: scope) == .included)
            let modules = dir.appending(path: "node_modules", directoryHint: .isDirectory)
            #expect(ProjectNavigatorExclusion.resolve(url: modules, isFolder: true, parentURL: nil, scope: scope) == .excludedRoot)
            #expect(!ProjectNavigatorExclusion.included.isExcluded)
            #expect(ProjectNavigatorExclusion.excludedContent.isExcluded)
        }
    }

    @Test
    func missingIntelliJIconFallsBackToTheSystemIcon() async throws {
        try withTempDir { dir in
            let item = try write("Main.swift", in: dir)
            let cell = FileSystemTableViewCell(frame: frame, item: nil)
            #expect(cell.fileItem == nil)
            #expect(cell.imageView?.image == nil)

            var requested: [String] = []
            cell.addIcon(item: item) { name in
                requested.append(name)
                return nil
            }

            #expect(requested == ["fileTypes/swiftLang"])
            #expect(cell.fileItem === item)
            #expect(cell.imageView?.image != nil)
            #expect(cell.imageView?.image?.name() != "fileTypes/swiftLang")
        }
    }

    @Test
    func navigatorFilterBoldsTheMatchAndDimsNonMatchingNames() async throws {
        try withTempDir { dir in
            let item = try write("Mainfile", in: dir)
            let name = item.labelFileName()

            let matching = FileSystemTableViewCell(frame: frame, item: item, navigatorFilter: " MAIN ")
            let matchedValue = try #require(matching.textField?.attributedStringValue)
            let matchedFont = matchedValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            let restFont = matchedValue.attribute(.font, at: name.count - 1, effectiveRange: nil) as? NSFont
            #expect(matchedFont != restFont)
            #expect(
                components(matchedValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                    == components(NSColor(Islands.foreground))
            )

            let missing = FileSystemTableViewCell(frame: frame, item: item, navigatorFilter: "zzz")
            let missingValue = try #require(missing.textField?.attributedStringValue)
            #expect(
                components(missingValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                    == components(NSColor(Islands.secondaryForeground))
            )

            let blank = FileSystemTableViewCell(frame: frame, item: item, navigatorFilter: "   ")
            let blankValue = try #require(blank.textField?.attributedStringValue)
            #expect(
                blankValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    == blankValue.attribute(.font, at: name.count - 1, effectiveRange: nil) as? NSFont
            )
            #expect(
                components(blankValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                    == components(NSColor(Islands.foreground))
            )
        }
    }

    @Test
    func nameColorFollowsTheVersionControlStatus() async throws {
        try withTempDir { dir in
            let item = try write("Colors.swift", in: dir)
            let cell = FileSystemTableViewCell(frame: frame, item: item)
            let expectations: [(GitStatus?, Color)] = [
                (nil, Islands.foreground),
                (GitStatus.none, Islands.foreground),
                (.modified, Islands.fileModified),
                (.renamed, Islands.fileModified),
                (.copied, Islands.fileModified),
                (.fileTypeChange, Islands.fileModified),
                (.added, Islands.fileAdded),
                (.untracked, Islands.fileUnversioned),
                (.deleted, Islands.fileDeleted),
                (.unmerged, Islands.fileConflict)
            ]
            for (status, color) in expectations {
                item.gitStatus = status
                #expect(components(cell.nameColor(for: item)) == components(NSColor(color)))
            }
        }
    }

    @Test
    func typingValidatesTheProposedFileName() async throws {
        try withTempDir { dir in
            let item = try write("old.txt", in: dir)
            _ = try write("taken.txt", in: dir)
            let cell = FileSystemTableViewCell(frame: frame, item: item, isEditable: true)
            let notification = Notification(name: NSControl.textDidChangeNotification)

            cell.textField?.stringValue = "new.txt"
            cell.controlTextDidChange(notification)
            #expect(cell.textField?.backgroundColor != errorRed)

            cell.textField?.stringValue = "taken.txt"
            cell.controlTextDidChange(notification)
            #expect(cell.textField?.backgroundColor == errorRed)

            cell.textField?.stringValue = "fresh.txt"
            cell.controlTextDidChange(notification)
            #expect(cell.textField?.backgroundColor != errorRed)

            let orphan = FileSystemTableViewCell(frame: frame, item: nil, isEditable: true)
            orphan.textField?.stringValue = "taken.txt"
            orphan.controlTextDidChange(notification)
            #expect(orphan.textField?.backgroundColor != errorRed)
        }
    }

    @Test
    func finishingEditingRenamesTheFileOnDisk() async throws {
        try withTempDir { dir in
            let item = try write("old.txt", in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let cell = FileSystemTableViewCell(frame: frame, item: item, isEditable: true)
            cell.workspace = workspace

            cell.textField?.stringValue = "renamed.txt"
            cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

            #expect(FileManager.default.fileExists(atPath: dir.appending(path: "renamed.txt").path))
            #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "old.txt").path))
            #expect(cell.textField?.backgroundColor != errorRed)
        }
    }

    @Test
    func finishingEditingWithAnInvalidNameRestoresTheLabel() async throws {
        try withTempDir { dir in
            let item = try write("old.txt", in: dir)
            let cell = FileSystemTableViewCell(frame: frame, item: item, isEditable: true)

            cell.textField?.stringValue = ""
            cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

            #expect(cell.textField?.stringValue == item.labelFileName())
            #expect(cell.textField?.backgroundColor == errorRed)
            #expect(FileManager.default.fileExists(atPath: dir.appending(path: "old.txt").path))
        }
    }

    @Test
    func projectCellValidatesTypedNamesLikeAFileCellWhenItIsNotCreating() async throws {
        try withTempDir { dir in
            let item = try write("old.txt", in: dir)
            _ = try write("taken.txt", in: dir)
            let cell = ProjectNavigatorTableViewCell(frame: frame, item: item)

            cell.textField?.stringValue = "taken.txt"
            cell.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            #expect(cell.textField?.backgroundColor == errorRed)

            cell.textField?.stringValue = "fresh.txt"
            cell.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            #expect(cell.textField?.backgroundColor != errorRed)
        }
    }

    @Test
    func projectCellCommitsAValidCreationNameWhenEditingEnds() async throws {
        let cell = ProjectNavigatorTableViewCell(frame: frame, item: nil)
        var committed: [String] = []
        var cancelled = 0
        cell.creationEditing = ProjectNavigatorTableViewCell.CreationEditing(
            validate: { _ in nil },
            commit: { committed.append($0) },
            cancel: { cancelled += 1 }
        )

        cell.textField?.stringValue = "fresh.txt"
        cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
        cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

        #expect(committed == ["fresh.txt"])
        #expect(cancelled == 0)
    }

    @Test
    func finishingEditingWithoutAWorkspaceOrItemDoesNothing() async throws {
        try withTempDir { dir in
            let item = try write("old.txt", in: dir)
            let detached = FileSystemTableViewCell(frame: frame, item: item, isEditable: true)
            detached.textField?.stringValue = "other.txt"
            detached.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
            #expect(FileManager.default.fileExists(atPath: dir.appending(path: "old.txt").path))

            let orphan = FileSystemTableViewCell(frame: frame, item: nil, isEditable: true)
            orphan.textField?.stringValue = "other.txt"
            orphan.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
            #expect(orphan.textField?.stringValue == "other.txt")
        }
    }

    @Test
    func failedRenameReportsTheErrorInAnAlert() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let ghost = CEWorkspaceFile(url: dir.appending(path: "ghost.txt"))
            let cell = FileSystemTableViewCell(frame: frame, item: ghost, isEditable: true)
            cell.workspace = workspace
            let message = NSAlert(error: CEWorkspaceFileManager.FileManagerError.originFileNotFound).messageText

            cell.textField?.stringValue = "other.txt"
            cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

            #expect(DreamderHeadless.suppressedModals.contains(message))
        }
    }
}
