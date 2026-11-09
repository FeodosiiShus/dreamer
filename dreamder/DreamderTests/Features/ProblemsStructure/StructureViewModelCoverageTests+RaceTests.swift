import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension StructureViewModelCoverageTests {
    @Test
    func aNodeBuilderFinishingAfterTheActiveFileChangedNeverReplacesTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            _ = try open("Model.swift", in: workspace, dir: dir)
            let probe = StructureBuilderProbe()
            let model = StructureViewModel(
                defaults: try IsolatedDefaults.require(),
                buildNodes: { text, _ in await probe.build(text) }
            )
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { probe.texts.count == 1 }
            let staleRequest = try #require(model.requestTask)

            _ = try open("Other.swift", in: workspace, dir: dir)
            try await eventually { probe.texts.count == 2 }
            #expect(staleRequest.isCancelled)

            probe.release()
            await staleRequest.value
            try await eventually { model.nodes.map(\.name) == ["enum Other {"] }

            #expect(probe.texts.first?.hasPrefix("struct Outer") == true)
            #expect(model.fileURL?.lastPathComponent == "Other.swift")
        }
    }

    @Test
    func aCancelledServerRequestNeverTouchesTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(
                root: dir,
                reply: documentSymbols(["Stale"]),
                isGated: true
            )
            harness.attach(document)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())
            model.start(workspace: workspace, lspService: harness.service)
            try await eventually { model.isLoading }
            let staleRequest = try #require(model.requestTask)

            _ = try open("Other.swift", in: workspace, dir: dir)
            try await eventually { staleRequest.isCancelled }
            harness.connection.release()
            await staleRequest.value
            try await eventually { model.nodes.map(\.name) == ["Other"] }

            #expect(model.usesLanguageServer == false)
            #expect(model.fileURL?.lastPathComponent == "Other.swift")
        }
    }

    @Test
    func aDocumentWithoutAFileURLIsRequestedByTheTabURL() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(root: dir, reply: documentSymbols(["Remote"]))
            harness.attach(document)
            let originalURL = document.fileURL
            document.fileURL = nil
            defer { document.fileURL = originalURL }
            #expect(document.languageServerURI == nil)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())

            model.start(workspace: workspace, lspService: harness.service)
            try await eventually { model.nodes.map(\.name) == ["Remote"] }

            #expect(model.usesLanguageServer)
        }
    }

    @Test
    func activatingALeafWithoutAFileOpensNothing() throws {
        try withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())
            let node = StructureNode(
                id: "x",
                name: "x",
                detail: nil,
                kind: .function,
                line: 4,
                column: 2,
                children: []
            )

            model.activate(node, workspace: workspace)

            #expect(model.selection == "x")
            #expect(model.focusRequests == 1)
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)
        }
    }
}
