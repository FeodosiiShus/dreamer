import AppKit
import CodeEditSourceEditor
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private enum DefinitionChooserSamples {
    static func row(_ line: Int, in directory: String = "/tmp/project") -> LSPUsageRow {
        LSPUsageRow(
            uri: "file://\(directory)/Target\(line).swift",
            fileURL: URL(fileURLWithPath: "\(directory)/Target\(line).swift"),
            fileName: "Target\(line).swift",
            fileIconName: "fileTypes/swiftLang",
            relativeDirectory: "Sources",
            line: line,
            column: 4,
            lineText: "func target\(line)() {}",
            matchRange: NSRange(location: 5, length: 7)
        )
    }

    static func keyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

@MainActor
private final class DefinitionChooserOpenedRows {
    var rows: [LSPUsageRow] = []
}

@MainActor
@Suite(.uiGate)
struct DefinitionChooserViewModelTests {
    @Test
    func titlesFollowTheKind() {
        let rows = [DefinitionChooserSamples.row(1)]
        #expect(DefinitionChooserViewModel(rows: rows, kind: .declaration).title == "Choose Declaration")
        #expect(DefinitionChooserViewModel(rows: rows, kind: .implementation).title == "Choose Implementation")
        #expect(DefinitionChooserViewModel(rows: rows, kind: .typeDeclaration).title == "Choose Type Declaration")
    }

    @Test
    func sizesFollowRowsAndMessages() {
        let few = DefinitionChooserViewModel(rows: (1...3).map { DefinitionChooserSamples.row($0) }, kind: .declaration)
        #expect(!few.isMessage)
        #expect(few.message == nil)
        #expect(few.panelWidth == 620)
        #expect(few.preferredHeight == 114)

        let many = DefinitionChooserViewModel(rows: (1...40).map { DefinitionChooserSamples.row($0) }, kind: .implementation)
        #expect(many.preferredHeight == 420)

        let message = DefinitionChooserViewModel(message: "No implementations found", title: "Go to Implementation")
        #expect(message.isMessage)
        #expect(message.rows.isEmpty)
        #expect(message.panelWidth == 380)
        #expect(message.preferredHeight == 80)
        #expect(message.title == "Go to Implementation")
    }

    @Test
    func arrowKeysWrapReturnOpensAndEscapeCloses() throws {
        let model = DefinitionChooserViewModel(
            rows: (1...3).map { DefinitionChooserSamples.row($0) },
            kind: .declaration
        )
        var opened: [Int] = []
        var closed = 0
        model.openRow = { opened.append($0.line) }
        model.dismiss = { closed += 1 }

        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(126)))
        #expect(model.selectedIndex == 2)
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(125)))
        #expect(model.selectedIndex == 0)
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(125)))
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(36)))
        #expect(opened == [2])
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(76)))
        #expect(opened == [2, 2])
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(125, flags: .command)) == false)
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(0)) == false)
        #expect(model.handle(event: try DefinitionChooserSamples.keyEvent(53)))
        #expect(closed == 1)
    }

    @Test
    func selectionIgnoresOutOfRangeIndexes() {
        let model = DefinitionChooserViewModel(
            rows: (1...3).map { DefinitionChooserSamples.row($0) },
            kind: .declaration
        )
        var opened: [Int] = []
        model.openRow = { opened.append($0.line) }

        model.select(7)
        #expect(model.selectedIndex == 0)
        model.select(2)
        #expect(model.selectedRow?.line == 3)
        model.open(1)
        #expect(model.selectedIndex == 1)
        #expect(opened == [2])
        model.open(9)
        #expect(opened == [2, 2])
        model.close()
    }

    @Test
    func messagesIgnoreNavigation() {
        let model = DefinitionChooserViewModel(message: "Nothing", title: "Go to Declaration")
        var opened = 0
        model.openRow = { _ in opened += 1 }

        model.moveSelection(1)
        model.activate()
        model.open(0)

        #expect(model.selectedIndex == 0)
        #expect(model.selectedRow == nil)
        #expect(opened == 0)
    }
}

@MainActor
@Suite(.uiGate)
struct DefinitionChooserViewTests {
    @Test
    func rowsRenderAndFollowTheSelection() async throws {
        let model = DefinitionChooserViewModel(
            rows: (1...40).map { DefinitionChooserSamples.row($0) },
            kind: .typeDeclaration
        )
        let hosted = HostedViewFixture.host(size: NSSize(width: 620, height: 300)) {
            DefinitionChooserView(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()
        #expect(hosted.renders())
        let before = hosted.snapshot()

        model.moveSelection(1)
        model.moveSelection(-3)
        try await hosted.settle()

        #expect(model.selectedIndex == 38)
        #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
    }

    @Test
    func messagesRender() async throws {
        let model = DefinitionChooserViewModel(message: "No type declaration found", title: "Go to Type Declaration")
        let hosted = HostedViewFixture.host(size: NSSize(width: 380, height: 80)) {
            DefinitionChooserView(model: model)
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func aSelectionOutsideTheRowsKeepsTheListRendered() async throws {
        let model = DefinitionChooserViewModel(rows: [DefinitionChooserSamples.row(1)], kind: .declaration)
        let hosted = HostedViewFixture.host(size: NSSize(width: 620, height: 200)) {
            DefinitionChooserView(model: model)
        }
        defer { hosted.close() }
        try await hosted.settle()

        model.selectedIndex = 99
        try await hosted.settle()

        #expect(model.selectedRow == nil)
        #expect(hosted.renders())
    }

    @Test
    func rowCallbacksSelectAndOpenTheirOwnRow() async throws {
        let rows = (1...5).map { DefinitionChooserSamples.row($0) }
        let model = DefinitionChooserViewModel(rows: rows, kind: .declaration)
        let opened = DefinitionChooserOpenedRows()
        model.openRow = { opened.rows.append($0) }
        let view = DefinitionChooserView(model: model)

        let selectable = view.rowView(at: 2, row: rows[2])
        let openable = view.rowView(at: 3, row: rows[3])
        selectable.onSelect()

        #expect(model.selectedIndex == 2)
        #expect(opened.rows.isEmpty)

        openable.onOpen()

        #expect(opened.rows.first == rows[3])
        #expect(model.selectedIndex == 3)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct DefinitionChooserPanelHostTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }

        var panels: [ShowUsagesPanel] {
            window.childWindows?.compactMap { $0 as? ShowUsagesPanel } ?? []
        }

        var model: DefinitionChooserViewModel? {
            (panels.first?.contentView as? NSHostingView<DefinitionChooserView>)?.rootView.model
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        try "func target() {}\n".write(
            to: directory.appending(path: "Target1.swift"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Harness(workspace: workspace, controller: controller, window: window)
    }

    @Test
    func messagesAppearAsAFixedSizeChildPanel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            DefinitionChooserPanelHost.shared.showMessage(
                "No implementations found",
                title: "Go to Implementation",
                in: harness.controller
            )

            let panel = try #require(harness.panels.first)
            let hostingView = try #require(panel.contentView as? NSHostingView<DefinitionChooserView>)
            #expect(hostingView.sizingOptions == [])
            #expect(panel.frame.size == NSSize(width: 380, height: 80))
            #expect(harness.model?.message == "No implementations found")
            #expect(harness.model?.title == "Go to Implementation")
        }
    }

    @Test
    func rowsSizeThePanelAndANewPanelReplacesTheOldOne() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let rows = (1...3).map { DefinitionChooserSamples.row($0, in: directory.path(percentEncoded: false)) }

            DefinitionChooserPanelHost.shared.show(rows: rows, kind: .declaration, in: harness.controller)
            let first = try #require(harness.panels.first)
            #expect(first.frame.size == NSSize(width: 620, height: 114))
            #expect(harness.model?.title == "Choose Declaration")
            #expect(harness.model?.rows == rows)

            DefinitionChooserPanelHost.shared.show(rows: rows, kind: .implementation, in: harness.controller)

            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== first)
            #expect(harness.model?.title == "Choose Implementation")
        }
    }

    @Test
    func dismissClosesThePanelAndAllowsShowingAgain() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let rows = [DefinitionChooserSamples.row(1, in: directory.path(percentEncoded: false))]
            DefinitionChooserPanelHost.shared.show(rows: rows, kind: .declaration, in: harness.controller)

            harness.model?.close()
            #expect(harness.panels.isEmpty)

            DefinitionChooserPanelHost.shared.show(rows: rows, kind: .declaration, in: harness.controller)
            #expect(harness.panels.count == 1)
        }
    }

    @Test
    func choosingARowClosesThePanelWithoutRestoringFocusAndJumps() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let rows = [DefinitionChooserSamples.row(1, in: directory.path(percentEncoded: false))]
            DefinitionChooserPanelHost.shared.show(rows: rows, kind: .declaration, in: harness.controller)
            let panel = try #require(harness.panels.first)

            harness.model?.activate()

            #expect(harness.panels.isEmpty)
            #expect(panel.restoresFocusOnClose == false)
            let selected = harness.workspace.editorManager?.activeEditor.selectedTab
            #expect(selected?.file.url.lastPathComponent == "Target1.swift")
            #expect(selected?.cursorPositions.first?.start.line == 2)
            #expect(selected?.cursorPositions.first?.start.column == 5)
        }
    }

    @Test
    func choosingARowWithoutAWorkspaceOnlyClosesThePanel() throws {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        let controller = DreamderWindowController(window: window, workspace: nil)
        defer {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
        }
        DefinitionChooserPanelHost.shared.show(rows: [DefinitionChooserSamples.row(1)], kind: .declaration, in: controller)
        let panel = try #require(window.childWindows?.compactMap { $0 as? ShowUsagesPanel }.first)
        let model = try #require((panel.contentView as? NSHostingView<DefinitionChooserView>)?.rootView.model)

        model.activate()

        #expect(window.childWindows?.isEmpty ?? true)
    }

    @Test
    func keyEventsReachTheModel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let rows = (1...3).map { DefinitionChooserSamples.row($0, in: directory.path(percentEncoded: false)) }
            DefinitionChooserPanelHost.shared.show(rows: rows, kind: .declaration, in: harness.controller)
            let panel = try #require(harness.panels.first)

            panel.sendEvent(try DefinitionChooserSamples.keyEvent(125))
            #expect(harness.model?.selectedIndex == 1)
            #expect(panel.onKeyEvent?(try DefinitionChooserSamples.keyEvent(0)) == false)
            #expect(panel.onKeyEvent?(try DefinitionChooserSamples.keyEvent(126)) == true)
            #expect(harness.model?.selectedIndex == 0)

            panel.sendEvent(try DefinitionChooserSamples.keyEvent(53))
            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func controllersWithoutAWindowShowNothing() {
        let controller = DreamderWindowController(window: nil, workspace: nil)

        DefinitionChooserPanelHost.shared.showMessage("Nothing", title: "Go to Declaration", in: controller)

        #expect(controller.window == nil)
    }
}
