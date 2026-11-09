import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService close workspace via controller", .serialized, .uiGate)
struct LSPCloseWorkspaceControllerTests {
    let fixture = LSPServiceFixture()

    @MainActor
    struct ControllerScope {
        let controller: DreamderDocumentController
        private let originalService: LSPService
        private let originalOpenDocuments: @MainActor () -> [NSDocument]

        init(controller: DreamderDocumentController, service: LSPService) {
            self.controller = controller
            originalService = controller.lspService
            originalOpenDocuments = controller.openDocuments
            controller.lspService = service
            controller.openDocuments = { [NSDocument()] }
        }

        func restore() {
            controller.lspService = originalService
            controller.openDocuments = originalOpenDocuments
        }
    }

    func openWorkspace(
        named name: String,
        in directory: URL,
        service: LSPService
    ) async throws -> (LSPServiceWorkspace, LSPService.ClientKey) {
        let projectDirectory = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let workspace = try LSPServiceWorkspace(directory: projectDirectory, files: ["a.ts": "let a = 1\n"])
        service.openDocument(try workspace.document("a.ts"))
        await service.waitForDocumentOperations()
        return (workspace, workspace.key(.typescript))
    }

    @Test
    func removingAWorkspaceWhosePathNeedsPercentEncodingStopsItsServers() async throws {
        try await withTempDir { directory in
            let service = fixture.makeService()
            let controller = try #require(DreamderDocumentController.shared as? DreamderDocumentController)
            let scope = ControllerScope(controller: controller, service: service)
            defer { scope.restore() }
            let (workspace, key) = try await openWorkspace(named: "my project é", in: directory, service: service)
            defer { workspace.close() }
            #expect(URL(fileURLWithPath: workspace.path).lastPathComponent == "my project é")
            #expect(service.languageClients[key] != nil)
            let created = try #require(fixture.created.first)

            controller.removeDocument(workspace.workspace)

            #expect(service.languageClients.isEmpty)
            #expect(service.serverStates[key] == nil)
            #expect(service.openDocumentURIs[key] == nil)
            #expect(service.watchedFilesForwarder(for: key) == nil)
            try await eventually(timeout: .seconds(20)) { created.connection.log.contains("exit") }
        }
    }

    @Test
    func removingAWorkspaceWithAPlainPathStillStopsItsServers() async throws {
        try await withTempDir { directory in
            let service = fixture.makeService()
            let controller = try #require(DreamderDocumentController.shared as? DreamderDocumentController)
            let scope = ControllerScope(controller: controller, service: service)
            defer { scope.restore() }
            let (workspace, key) = try await openWorkspace(named: "plain", in: directory, service: service)
            defer { workspace.close() }

            controller.removeDocument(workspace.workspace)

            #expect(service.languageClients.isEmpty)
            #expect(service.serverStates[key] == nil)
        }
    }

    @Test
    func removingAWorkspaceOnlyStopsTheServersOfThatWorkspace() async throws {
        try await withTempDir { directory in
            let service = fixture.makeService()
            let controller = try #require(DreamderDocumentController.shared as? DreamderDocumentController)
            let scope = ControllerScope(controller: controller, service: service)
            defer { scope.restore() }
            let (closing, closingKey) = try await openWorkspace(named: "my project", in: directory, service: service)
            defer { closing.close() }
            let (staying, stayingKey) = try await openWorkspace(named: "my project 2", in: directory, service: service)
            defer { staying.close() }

            controller.removeDocument(closing.workspace)

            #expect(service.languageClients[closingKey] == nil)
            #expect(service.languageClients[stayingKey] != nil)
            #expect(service.serverStates[stayingKey] == .running)
        }
    }
}
