import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension LSPServiceCrashRestartTests {
    @Test
    func intentionalStopDoesNotRestart() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await service.stopServer(forLanguage: .typescriptreact, workspacePath: workspace.path)

            #expect(service.serverStates[key] == .stopped)
            #expect(service.languageClients[key] == nil)
            #expect(service.openDocumentURIs[key] == nil)
            #expect(service.watchedFilesForwarder(for: key) == nil)
            #expect(Array(fixture.created[0].connection.log.suffix(2)) == ["shutdown", "exit"])
            fixture.created[0].terminate()
            await service.waitForAutomaticRestarts()
            try await assertNoFurtherServers(count: 1)
            #expect(service.serverStates[key] == .stopped)
        }
    }

    @Test
    func stoppingAnUnknownServerThrows() async {
        let service = fixture.makeService()
        var thrown: LSPServiceError?
        do {
            try await service.stopServer(forLanguage: .go, workspacePath: "/nowhere")
        } catch let error as LSPServiceError {
            thrown = error
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        guard case .serverNotFound? = thrown else {
            Issue.record("Expected serverNotFound")
            return
        }
    }

    @Test
    func closingTheWorkspaceDoesNotRestart() async throws {
        try await withOpenDocuments { service, workspace, key in
            service.closeWorkspace(workspace.path)
            #expect(service.watchedFilesForwarder(for: key) == nil)
            try await eventually { service.languageClients.isEmpty && service.serverStates[key] == nil }

            #expect(service.openDocumentURIs[key] == nil)
            await service.waitForAutomaticRestarts()
            try await assertNoFurtherServers(count: 1)
            #expect(service.serverStates[key] == nil)
        }
    }

    @Test
    func closingAnotherWorkspaceKeepsTheServerRunning() async throws {
        try await withOpenDocuments { service, _, key in
            service.closeWorkspace("/some/other/workspace")
            await lspServiceFlushMainQueue()
            #expect(service.languageClients[key] != nil)
            #expect(service.serverStates[key] == .running)
        }
    }

    @Test
    func closingTheWorkspaceCancelsTheRestartOfACrashedServer() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            fixture.created[0].terminate()
            try await eventually { service.serverStates[key] == .failed(crashMessage) }

            service.closeWorkspace(workspace.path)
            await service.waitForAutomaticRestarts()

            #expect(service.serverStates[key] == nil)
            #expect(service.languageClients[key] == nil)
            try await assertNoFurtherServers(count: 1)
        }
    }

    @Test
    func closingTheWorkspaceForgetsTheDocumentsOfAFailedServer() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await crashedTwice(service, key: key)

            service.closeWorkspace(workspace.path)
            try await service.restartServer(key)

            #expect(fixture.created.count == 3)
            #expect(fixture.created[2].connection.lspServiceOpens.isEmpty)
        }
    }

    @Test
    func aWorkspaceReopenedWhileTheOldServerShutsDownKeepsItsNewServer() async throws {
        let gate = LSPServiceGate()
        try await withOpenDocuments(shutdownGate: gate) { service, workspace, key in
            service.closeWorkspace(workspace.path)
            #expect(service.languageClients[key] == nil)
            #expect(service.serverStates[key] == nil)
            for name in ["a.ts", "b.tsx"] {
                service.openDocument(try #require(workspace.documents[name]))
            }
            await service.waitForDocumentOperations()
            #expect(fixture.created.count == 2)

            gate.open()
            try await eventually { fixture.created[0].connection.log.contains("exit") }
            await lspServiceFlushMainQueue()

            #expect(service.languageClients[key] === fixture.created[1].server)
            #expect(service.serverStates[key] == .running)
            #expect(service.openDocumentURIs[key]?.count == 2)
            #expect(service.watchedFilesForwarder(for: key) != nil)
            #expect(service.eventListeningTasks[key] != nil)
            let reopened = Set(["a.ts", "b.tsx"].map(workspace.uri))
            #expect(Set(fixture.created[1].connection.lspServiceOpens.map(\.uri)) == reopened)
        }
    }

    @Test
    func aStopThatFinishesAfterTheWorkspaceWasReopenedKeepsTheNewServer() async throws {
        let gate = LSPServiceGate()
        try await withOpenDocuments(shutdownGate: gate) { service, workspace, key in
            let stopping = Task {
                try? await service.stopServer(forLanguage: .typescript, workspacePath: workspace.path)
            }
            try await eventually { gate.waiterCount == 1 }
            service.closeWorkspace(workspace.path)
            for name in ["a.ts", "b.tsx"] {
                service.openDocument(try #require(workspace.documents[name]))
            }
            await service.waitForDocumentOperations()
            #expect(fixture.created.count == 2)

            gate.open()
            await stopping.value
            try await eventually { fixture.created[0].connection.log.contains("exit") }
            await lspServiceFlushMainQueue()

            #expect(service.languageClients[key] === fixture.created[1].server)
            #expect(service.serverStates[key] == .running)
            #expect(service.openDocumentURIs[key]?.count == 2)
        }
    }

    @Test
    func stoppingAllServersDoesNotRestart() async throws {
        try await withOpenDocuments { service, _, key in
            await service.stopAllServers()

            #expect(service.serverStates[key] == .stopped)
            #expect(service.languageClients.isEmpty)
            #expect(service.openDocumentURIs.isEmpty)
            #expect(service.watchedFilesForwarder(for: key) == nil)
            #expect(service.eventListeningTasks.isEmpty)
            await service.waitForAutomaticRestarts()
            try await assertNoFurtherServers(count: 1)
            #expect(service.serverStates[key] == .stopped)
        }
    }

    @Test
    func aFailingShutdownKeepsTheClientOnStop() async throws {
        try await withOpenDocuments(shutdownFailure: LSPServiceFixtureFailure.shutdown) { service, workspace, key in
            var thrown: LSPServiceFixtureFailure?
            do {
                try await service.stopServer(forLanguage: .typescript, workspacePath: workspace.path)
            } catch let error as LSPServiceFixtureFailure {
                thrown = error
            }
            guard case .shutdown? = thrown else {
                Issue.record("Expected the shutdown failure to propagate")
                return
            }
            #expect(service.languageClients[key] != nil)
            #expect(service.serverStates[key] == .running)
        }
    }

    @Test
    func aFailingShutdownDoesNotBlockClosingTheWorkspace() async throws {
        try await withOpenDocuments(shutdownFailure: LSPServiceFixtureFailure.shutdown) { service, workspace, key in
            service.closeWorkspace(workspace.path)
            try await eventually { service.languageClients.isEmpty && service.serverStates[key] == nil }
        }
    }

    @Test
    func aFailingShutdownDoesNotBlockStoppingAllServers() async throws {
        try await withOpenDocuments(shutdownFailure: LSPServiceFixtureFailure.shutdown) { service, _, key in
            await service.stopAllServers()
            #expect(service.languageClients.isEmpty)
            #expect(service.serverStates[key] == .stopped)
        }
    }

    @Test
    func forwardedWatchedFilesReachTheServerUntilItStops() async throws {
        try await withOpenDocuments { service, workspace, key in
            let created = fixture.created[0]
            created.server.dynamicCapabilities.register([
                Registration(
                    id: "watch",
                    method: "workspace/didChangeWatchedFiles",
                    registerOptions: ["watchers": [["globPattern": "**/*.ts"]]]
                )
            ])
            let forwarder = try #require(service.watchedFilesForwarder(for: key))
            await forwarder.settle()

            let newFile = workspace.directory.appending(path: "new.ts")
            try "export {}\n".write(to: newFile, atomically: true, encoding: .utf8)
            try "x\n".write(to: workspace.directory.appending(path: "ignored.md"), atomically: true, encoding: .utf8)
            try workspace.fileManager.rebuildFiles(fromItem: workspace.fileManager.workspaceItem)
            workspace.fileManager.notifyObservers(updatedItems: [workspace.fileManager.workspaceItem])
            await forwarder.settle()

            let batches = created.connection.lspServiceWatchedChanges
            #expect(batches.count == 1)
            #expect(batches.first?.changes.map(\.type) == [.created])
            #expect(batches.first?.changes.first?.uri.hasSuffix("/new.ts") == true)

            try await service.stopServer(forLanguage: .typescript, workspacePath: workspace.path)
            #expect(service.watchedFilesForwarder(for: key) == nil)
            try FileManager.default.removeItem(at: newFile)
            try workspace.fileManager.rebuildFiles(fromItem: workspace.fileManager.workspaceItem)
            workspace.fileManager.notifyObservers(updatedItems: [workspace.fileManager.workspaceItem])
            await forwarder.settle()
            #expect(created.connection.lspServiceWatchedChanges.count == 1)
        }
    }
}
