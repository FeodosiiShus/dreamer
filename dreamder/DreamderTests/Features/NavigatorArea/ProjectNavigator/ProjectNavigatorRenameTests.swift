import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorRenameTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["Sources", "Empty"]
    private static let files = ["a.txt", "b.md", "Sources/main.swift"]

    private func finishEditing(_ cell: ProjectNavigatorTableViewCell, with name: String) {
        cell.textField?.stringValue = name
        cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }

    private func render(_ row: NavigatorTableRowView) throws -> NSBitmapImageRep {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 120,
                pixelsHigh: 22,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        row.drawSelection(in: row.bounds)
        row.drawBackground(in: row.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    @Test
    func finishingAnEditWithAValidNameRenamesTheFileAndOpensIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            let cell = try #require(harness.cell(for: a))

            finishEditing(cell, with: "renamed.txt")

            #expect(harness.exists("renamed.txt"))
            #expect(!harness.exists("a.txt"))
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "renamed.txt")
            #expect(harness.editor.tabs.contains { $0.file.name == "renamed.txt" })
            #expect(!harness.editor.tabs.contains { $0.file.name == "a.txt" })
        }
    }

    @Test
    func finishingAnEditWithAnInvalidNameRestoresTheLabel() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let cell = try #require(harness.cell(for: a))

            finishEditing(cell, with: "b.md")
            #expect(cell.textField?.stringValue == "a.txt")

            finishEditing(cell, with: "")
            #expect(cell.textField?.stringValue == "a.txt")

            finishEditing(cell, with: "a.txt")
            #expect(cell.textField?.stringValue == "a.txt")

            finishEditing(cell, with: "bad:name.txt")
            #expect(cell.textField?.stringValue == "a.txt")

            #expect(harness.exists("a.txt"))
            #expect(harness.exists("b.md"))
        }
    }

    @Test
    func renamingAFolderKeepsTheEditorsUntouched() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let empty = try harness.file("Empty")
            let cell = try #require(harness.cell(for: empty))

            finishEditing(cell, with: "Renamed")

            #expect(harness.exists("Renamed"))
            #expect(!harness.exists("Empty"))
            #expect(harness.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func finishingAnEditReloadsTheOutlineWhenTheReloadWasDeferred() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.controller.cellDidFinishEditing()

            harness.controller.shouldReloadAfterDoneEditing = true
            try harness.remove("b.md")
            harness.controller.cellDidFinishEditing()

            #expect(harness.row(of: a) >= 0)
        }
    }

    @Test
    func moveFileReportsAnErrorWhenTheDestinationExists() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")

            harness.controller.moveFile(file: a, to: b.url)

            #expect(DreamderHeadless.suppressedModals.contains("Destination already exists"))
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func moveFileMovesFilesAndFoldersIntoOtherFolders() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let empty = try harness.file("Empty")

            harness.controller.moveFile(file: a, to: harness.url("Sources/a.txt"))
            harness.controller.moveFile(file: empty, to: harness.url("Sources/Empty"))

            #expect(harness.exists("Sources/a.txt"))
            #expect(harness.exists("Sources/Empty"))
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "a.txt")
        }
    }

    @Test
    func copyFileCopiesOrReportsAnError() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")

            harness.controller.copyFile(file: a, to: harness.url("a-copy.txt"))
            #expect(try harness.contents("a-copy.txt") == "content of a.txt\n")

            harness.controller.copyFile(file: a, to: b.url)
            #expect(DreamderHeadless.suppressedModals.contains("Failed to find origin file"))
            #expect(try harness.contents("b.md") == "content of b.md\n")
        }
    }

    @Test
    func disclosureButtonReflectsAndTogglesTheExpansionState() async throws {
        let cell = ProjectNavigatorTableViewCell(frame: NSRect(x: 0, y: 0, width: 240, height: 22), item: nil)
        let button = try #require(cell.subviews.compactMap { $0 as? NSButton }.first)
        var toggles = 0
        cell.onToggleDisclosure = { toggles += 1 }

        #expect(button.isHidden)
        cell.isExpandable = true
        #expect(!button.isHidden)

        _ = button.sendAction(button.action, to: button.target)
        #expect(toggles == 1)

        cell.isExpanded = true
        #expect(button.image != nil)
        cell.isExpanded = false
        #expect(button.image != nil)

        cell.isExpandable = false
        #expect(button.isHidden)
    }

    @Test
    func disclosureGutterShiftsTheContent() async throws {
        let frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        let file = CEWorkspaceFile(url: URL(filePath: "/tmp/x.txt"))
        let cell = ProjectNavigatorTableViewCell(frame: frame, item: file)
        let imageView = try #require(cell.imageView)

        cell.showsDisclosureGutter = true
        let withGutter = imageView.frame.origin.x
        cell.showsDisclosureGutter = false
        let withoutGutter = imageView.frame.origin.x

        #expect(withGutter > withoutGutter)
        #expect(cell.textField?.accessibilityIdentifier() == "ProjectNavigatorTableViewCell-x.txt")
    }

    @Test
    func cellWithoutAFileIgnoresEditingAndCannotBeDecoded() async throws {
        let cell = ProjectNavigatorTableViewCell(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))

        #expect(cell.fileItem == nil)
        #expect(ProjectNavigatorTableViewCell(coder: NSCoder()) == nil)
    }

    @Test
    func rowViewPaintsTheSelectionOnlyWhenSelected() async throws {
        let row = NavigatorTableRowView(frame: NSRect(x: 0, y: 0, width: 120, height: 22))

        let unselected = try render(row)
        #expect(unselected.colorAt(x: 60, y: 11)?.alphaComponent == 0)

        row.isSelected = true
        row.isEmphasized = true
        let emphasized = try render(row)
        #expect((emphasized.colorAt(x: 60, y: 11)?.alphaComponent ?? 0) > 0)

        row.isEmphasized = false
        let inactive = try render(row)
        #expect((inactive.colorAt(x: 60, y: 11)?.alphaComponent ?? 0) > 0)

        row.selectionHighlightStyle = .none
        let hidden = try render(row)
        #expect(hidden.colorAt(x: 60, y: 11)?.alphaComponent == 0)
    }
}
