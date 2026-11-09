import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("Trust Project restarts language servers", .serialized, .uiGate)
struct LSPTrustProjectRestartTests {
    let fixture = LSPServiceFixture()

    @MainActor
    final class RestartRecorder {
        var paths: [String] = []
    }

    @Test
    func aDocumentOpenedWhileUntrustedGetsItsServerAfterTrustIsGranted() async throws {
        let fixture = fixture
        try await withIsolatedDefaults { defaults in
            try await withTempDir { directory in
                fixture.workspaceTrusted = false
                let service = fixture.makeService()
                let workspace = try LSPServiceWorkspace(directory: directory, files: ["a.py": "x = 1\n"])
                defer { workspace.close() }
                workspace.workspace.makeWindowControllers()
                let controller = try #require(workspace.workspace.windowControllers.first as? DreamderWindowController)
                let window = try #require(controller.window)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                service.openDocument(try workspace.document("a.py"))
                await service.waitForDocumentOperations()
                #expect(fixture.created.isEmpty)
                let recorder = RestartRecorder()
                let trust = WorkspaceTrust(defaults: defaults, confirm: { _ in
                    fixture.workspaceTrusted = true
                    return true
                })

                let granted = await controller.requestProjectTrust(using: trust, restartingServers: { path in
                    recorder.paths.append(path)
                    await service.restartServers(inWorkspace: path)
                })

                #expect(granted)
                #expect(recorder.paths == [workspace.path])
                let created = try #require(fixture.created.first)
                #expect(created.connection.lspServiceOpens.map(\.uri) == [workspace.uri("a.py")])
                #expect(service.serverStates[workspace.key(.python)] == .running)
            }
        }
    }

    @Test
    func decliningTrustRestartsNothing() async throws {
        let fixture = fixture
        try await withIsolatedDefaults { defaults in
            try await withTempDir { directory in
                fixture.workspaceTrusted = false
                let service = fixture.makeService()
                let workspace = try LSPServiceWorkspace(directory: directory, files: ["a.py": "x = 1\n"])
                defer { workspace.close() }
                workspace.workspace.makeWindowControllers()
                let controller = try #require(workspace.workspace.windowControllers.first as? DreamderWindowController)
                let window = try #require(controller.window)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                service.openDocument(try workspace.document("a.py"))
                await service.waitForDocumentOperations()
                let recorder = RestartRecorder()
                let trust = WorkspaceTrust(defaults: defaults, confirm: { _ in false })

                let granted = await controller.requestProjectTrust(using: trust, restartingServers: { path in
                    recorder.paths.append(path)
                })

                #expect(!granted)
                #expect(recorder.paths.isEmpty)
                #expect(fixture.created.isEmpty)
            }
        }
    }
}
