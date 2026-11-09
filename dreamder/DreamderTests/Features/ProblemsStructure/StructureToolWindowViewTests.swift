import AppKit
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct StructureToolWindowViewTests {
    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"
            .write(to: dir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        try "// nothing to see\n".write(to: dir.appending(path: "Empty.swift"), atomically: true, encoding: .utf8)
        return try HostedViewFixture.makeWorkspace(in: dir)
    }

    private func open(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws -> CodeFileDocument {
        let target = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: target)
        return try #require(target.fileDocument)
    }

    private func range(_ line: Int, _ character: Int) -> LSPRange {
        LSPRange(
            start: Position(line: line, character: character),
            end: Position(line: line, character: character + 1)
        )
    }

    private func nestedReply() throws -> Data {
        let children = [
            DocumentSymbol(
                name: "described",
                detail: "Int",
                kind: .property,
                range: range(1, 4),
                selectionRange: range(1, 8),
                children: nil
            ),
            DocumentSymbol(
                name: "blankDetail",
                detail: "",
                kind: .method,
                range: range(2, 4),
                selectionRange: range(2, 9),
                children: nil
            ),
            DocumentSymbol(
                name: "plain",
                detail: nil,
                kind: .function,
                range: range(3, 4),
                selectionRange: range(3, 9),
                children: nil
            )
        ]
        let outer = DocumentSymbol(
            name: "Outer",
            detail: "struct",
            kind: .struct,
            range: range(0, 0),
            selectionRange: range(0, 7),
            children: children
        )
        return try StructureFakeServerConnection.encode(.some(.optionA([outer])))
    }

    private func host(_ workspace: WorkspaceDocument, model: StructureViewModel) throws -> HostedView {
        return try HostedViewFixture.hostInWorkspace(workspace) { StructureToolWindow(model: model) }
    }

    @Test
    func emptyStatesDescribeTheEditorState() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            let hosted = try host(workspace, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let noFile = hosted.snapshot()
            #expect(model.fileURL == nil)

            _ = try open("Empty.swift", in: workspace, dir: dir)
            try await eventually { model.fileURL?.lastPathComponent == "Empty.swift" }
            try await hosted.settle()
            #expect(model.rows.isEmpty)
            #expect(model.usesLanguageServer == false)
            #expect(HostedView.pixelsDiffer(noFile, hosted.snapshot()))
        }
    }

    @Test
    func loadingStateShowsWhileTheLanguageServerIsAnswering() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(root: dir, reply: nestedReply(), isGated: true)
            harness.attach(document)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: harness.service)
            let hosted = try host(workspace, model: model)
            defer { hosted.close() }
            try await eventually { model.isLoading }
            try await hosted.settle()
            let loading = hosted.snapshot()
            #expect(hosted.renders())

            harness.connection.release()
            try await eventually { !model.rows.isEmpty }
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(loading, hosted.snapshot()))
        }
    }

    @Test
    func aLanguageServerWithoutSymbolsOmitsTheMissingServerHint() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Empty.swift", in: workspace, dir: dir)
            let emptyReply = try StructureFakeServerConnection.encode(.some(.optionA([])))
            let harness = try await StructureLSPHarness.make(root: dir, reply: emptyReply)
            harness.attach(document)
            let withServer = StructureViewModel()
            withServer.start(workspace: workspace, lspService: harness.service)
            let withoutServer = StructureViewModel()
            withoutServer.start(workspace: workspace, lspService: LSPService())

            let serverHosted = try host(workspace, model: withServer)
            defer { serverHosted.close() }
            let plainHosted = try host(workspace, model: withoutServer)
            defer { plainHosted.close() }
            try await eventually { withServer.fileURL != nil && withServer.isLoading == false }
            try await eventually { withoutServer.fileURL != nil }
            try await serverHosted.settle()
            try await plainHosted.settle()

            #expect(withServer.usesLanguageServer)
            #expect(withoutServer.usesLanguageServer == false)
            #expect(withServer.rows.isEmpty)
            #expect(withoutServer.rows.isEmpty)
            #expect(HostedView.pixelsDiffer(serverHosted.snapshot(), plainHosted.snapshot()))
        }
    }

    @Test
    func treeRendersNestedSymbolsAndReactsToCollapseAndSelection() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(root: dir, reply: nestedReply())
            harness.attach(document)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: harness.service)
            let hosted = try host(workspace, model: model)
            defer { hosted.close() }
            try await eventually { model.rows.count == 4 }
            try await hosted.settle()
            #expect(hosted.renders())
            let expanded = hosted.snapshot()

            model.toggleCollapsed("0")
            #expect(model.rows.count == 1)
            try await hosted.settle()
            let collapsed = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(expanded, collapsed))

            model.toggleCollapsed("0")
            let child = try #require(model.rows.last?.node)
            model.activate(child, workspace: workspace)
            #expect(model.selection == child.id)
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(expanded, hosted.snapshot()))

            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(tab.cursorPositions.first?.start.line == 4)
            #expect(tab.cursorPositions.first?.start.column == 10)
        }
    }

    @Test
    func theToolWindowManagerShowsTheStructureWindowThatStartsItsOwnModel() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            _ = try open("Model.swift", in: workspace, dir: dir)
            let manager = workspace.toolWindowManager
            manager.show(.structure)
            #expect(manager.isVisible(.structure))
            let model = StructureViewModel()

            let hosted = try host(workspace, model: model)
            defer { hosted.close() }

            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }
            try await hosted.settle()
            #expect(hosted.renders())

            manager.hide(.structure)
            #expect(manager.isVisible(.structure) == false)
        }
    }
}
