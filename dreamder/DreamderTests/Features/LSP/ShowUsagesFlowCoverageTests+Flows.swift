import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

extension ShowUsagesFlowCoverageTests {
    @Test
    func showAndFindUsagesActionsPresentThePopupForTheActiveEditor() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")

            harness.controller.showUsages(nil)
            let first = try #require(harness.panels.first)
            harness.controller.findUsages(nil)

            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== first)
            #expect(harness.panelModel?.isMessage == true)
        }
    }

    @Test
    func hostShowsRowsAndReplacesThePreviousPanelOfTheSameWindow() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let rows = [
                harness.row(for: "helper.py", line: 0, column: 4),
                harness.row(for: "main.py", line: 2, column: 8)
            ]

            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)
            let first = try #require(harness.panels.first)
            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)

            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== first)
            #expect(!first.isVisible)
            #expect(harness.panelModel?.rows == rows)
            #expect(harness.panels.first?.frame.width == 620)
        }
    }

    @Test
    func keyboardNavigatesWrapsAndEscapeClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let rows = [
                harness.row(for: "helper.py", line: 0, column: 4),
                harness.row(for: "main.py", line: 2, column: 8)
            ]
            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)
            let panel = try #require(harness.panels.first)
            let model = try #require(harness.panelModel)

            panel.sendEvent(try harness.keyEvent(125))
            #expect(model.selectedIndex == 1)
            panel.sendEvent(try harness.keyEvent(125))
            #expect(model.selectedIndex == 0)
            panel.sendEvent(try harness.keyEvent(126))
            #expect(model.selectedIndex == 1)

            panel.sendEvent(try harness.keyEvent(53))

            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func returnOpensTheSelectedUsageInTheEditorAndClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let rows = [
                harness.row(for: "main.py", line: 0, column: 0),
                harness.row(for: "helper.py", line: 1, column: 4)
            ]
            ShowUsagesPanelHost.shared.show(rows: rows, symbol: "helper", in: harness.controller)
            let panel = try #require(harness.panels.first)

            panel.sendEvent(try harness.keyEvent(125))
            panel.sendEvent(try harness.keyEvent(36))

            let selected = try #require(harness.workspace.editorManager?.activeEditor.selectedTab)
            #expect(selected.file.url.lastPathComponent == "helper.py")
            #expect(selected.cursorPositions.first?.start.line == 2)
            #expect(selected.cursorPositions.first?.start.column == 5)
            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func openingAUsageAfterTheWorkspaceIsGoneOnlyClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            ShowUsagesPanelHost.shared.show(
                rows: [harness.row(for: "helper.py", line: 0, column: 0)],
                symbol: "helper",
                in: harness.controller
            )
            let model = try #require(harness.panelModel)
            harness.controller.workspace = nil

            model.activate()

            #expect(harness.panels.isEmpty)
            #expect(harness.workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent == "main.py")
            harness.controller.workspace = harness.workspace
        }
    }

    @Test
    func losingKeyStatusClosesThePanelAndRunsItsCloseHandler() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            ShowUsagesPanelHost.shared.showMessage("No usages found", in: harness.controller)
            let panel = try #require(harness.panels.first)

            panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))

            #expect(harness.panels.isEmpty)
            #expect(panel.onClose == nil)
        }
    }

    @Test
    func modelCloseDismissesThePanelAndRestoresTheParentFirstResponder() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            let responderBefore = window.firstResponder
            ShowUsagesPanelHost.shared.showMessage("No usages found", in: harness.controller)
            let model = try #require(harness.panelModel)

            model.close()

            #expect(harness.panels.isEmpty)
            #expect(window.firstResponder === responderBefore)
        }
    }

    @Test
    func resolverFallsBackToEmptyTextWhenTheFileVanishedFromDisk() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 1, column: 3)
            let tab = try #require(harness.tab("main.py"))
            tab.file.fileDocument = nil
            try FileManager.default.removeItem(at: harness.url("main.py"))

            let result = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: harness.service)

            guard case .ready(let context) = result else {
                Issue.record("expected a ready context for a tab whose file is gone")
                return
            }
            #expect(context.documentText.isEmpty)
            #expect(context.lineText.isEmpty)
            #expect(context.symbol.isEmpty)
            #expect(context.position == Position(line: 0, character: 2))
        }
    }

    @Test
    func panelOriginPrefersBelowTheAnchorAndFlipsAboveWhenThereIsNoRoom() {
        let size = NSSize(width: 620, height: 300)
        let parent = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let roomy = NSRect(x: 100, y: 500, width: 2, height: 16)
        let cramped = NSRect(x: 100, y: 60, width: 2, height: 16)

        let below = ShowUsagesPanel.origin(size: size, parentFrame: parent, anchor: roomy, visibleFrame: visible)
        let above = ShowUsagesPanel.origin(size: size, parentFrame: parent, anchor: cramped, visibleFrame: visible)
        let centered = ShowUsagesPanel.origin(size: size, parentFrame: parent, anchor: nil, visibleFrame: nil)

        #expect(below == NSPoint(x: 100, y: 196))
        #expect(above == NSPoint(x: 100, y: 80))
        #expect(centered == NSPoint(x: 290, y: 408))
    }

    @Test
    func panelOriginWithoutAScreenMeasuresRoomBelowAgainstZeroAndSkipsClamping() {
        let size = NSSize(width: 620, height: 300)
        let parent = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let roomy = NSRect(x: 100, y: 500, width: 2, height: 16)
        let cramped = NSRect(x: 100, y: 50, width: 2, height: 16)

        let below = ShowUsagesPanel.origin(size: size, parentFrame: parent, anchor: roomy, visibleFrame: nil)
        let above = ShowUsagesPanel.origin(size: size, parentFrame: parent, anchor: cramped, visibleFrame: nil)

        #expect(below == NSPoint(x: 100, y: 196))
        #expect(above == NSPoint(x: 100, y: 70))
    }

    @Test
    func hostWithoutAWindowPresentsNothing() {
        let host = ShowUsagesPanelHost()
        let controller = DreamderWindowController(window: nil, workspace: nil)

        host.showMessage("No usages found", in: controller)
        host.show(rows: [], symbol: "helper", in: controller)

        let entries = Mirror(reflecting: host).children.first { $0.label == "entries" }
        #expect(entries.map { Mirror(reflecting: $0.value).children.count } == 0)
        #expect(controller.window == nil)
    }

    @Test
    func theKeyHandlerOfAPanelOutlivingItsModelLeavesKeysAlone() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            ShowUsagesPanelHost.shared.showMessage("No usages found", in: harness.controller)
            let panel = try #require(harness.panels.first)
            weak let weakModel: ShowUsagesViewModel? = harness.panelModel
            #expect(weakModel != nil)

            panel.close()
            panel.contentView = nil
            try await eventually { weakModel == nil }

            #expect(panel.onKeyEvent?(try harness.keyEvent(53)) == false)
        }
    }
}
