import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService crash handling", .uiGate)
struct LSPServiceCrashRestartTests {
    typealias Key = LSPService.ClientKey

    let fixture = LSPServiceFixture()

    private let crashMessage = "The typescript language server terminated unexpectedly"

    private func withOpenDocuments(
        backoff: Duration = .milliseconds(20),
        shutdownFailure: (any Error)? = nil,
        _ body: (LSPService, LSPServiceWorkspace, Key) async throws -> Void
    ) async throws {
        try await withTempDir { dir in
            fixture.restartBackoff = backoff
            fixture.shutdownFailure = shutdownFailure
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: ["a.ts": "let a = 1\n", "b.tsx": "let b = 2\n"]
            )
            defer { workspace.close() }
            for name in ["a.ts", "b.tsx"] {
                let document = try workspace.document(name)
                service.openDocument(document)
            }
            await service.waitForDocumentOperations()
            try await body(service, workspace, workspace.key(.typescript))
        }
    }

    private func restartedOnce(_ service: LSPService, key: Key) async throws {
        fixture.created[0].terminate()
        try await eventually { fixture.created.count == 2 }
        await service.waitForAutomaticRestarts()
        #expect(service.serverStates[key] == .running)
    }

    private func crashedTwice(_ service: LSPService, key: Key) async throws {
        try await restartedOnce(service, key: key)
        fixture.created[1].terminate()
        try await eventually { service.serverStates[key] == .failed(crashMessage) }
        await service.waitForAutomaticRestarts()
    }

    private func assertNoFurtherServers(count: Int) async throws {
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.created.count == count)
    }

    @Test func crashMarksTheServerFailedAndClearsItsState() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            #expect(service.watchedFilesForwarder(for: key) != nil)
            #expect(service.eventListeningTasks[key] != nil)
            #expect(service.openDocumentURIs[key]?.count == 2)

            fixture.created[0].terminate()
            try await eventually { service.serverStates[key] == .failed(crashMessage) }

            #expect(service.languageClients[key] == nil)
            #expect(service.server(for: .typescript, workspacePath: workspace.path) == nil)
            #expect(service.openDocumentURIs[key] == nil)
            #expect(service.watchedFilesForwarder(for: key) == nil)
            #expect(service.eventListeningTasks[key] == nil)
            #expect(fixture.created.count == 1)

            await service.stopAllServers()
            await service.waitForAutomaticRestarts()
            #expect(fixture.created.count == 1)
        }
    }

    @Test func crashRestartsExactlyOnceAndReopensDocuments() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await restartedOnce(service, key: key)

            #expect(fixture.created.count == 2)
            #expect(fixture.discoveries.count == 2)
            let second = fixture.created[1]
            #expect(service.languageClients[key] === second.server)
            let expected = Set(["a.ts", "b.tsx"].map(workspace.uri))
            #expect(Set(second.connection.lspServiceOpens.map(\.uri)) == expected)
            #expect(service.openDocumentURIs[key] == expected)
            #expect(service.watchedFilesForwarder(for: key) != nil)
            #expect(service.eventListeningTasks[key] != nil)
            await lspServiceFlushMainQueue()
            #expect(fixture.notificationCount(titled: "Language server stopped") == 0)
        }
    }

    @Test func aTerminationOfAReplacedServerIsIgnored() async throws {
        try await withOpenDocuments { service, _, key in
            try await restartedOnce(service, key: key)

            service.serverTerminated(fixture.created[0].server, key: key)

            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === fixture.created[1].server)
            #expect(fixture.created.count == 2)
        }
    }

    @Test func aSecondCrashStaysFailedAndNotifies() async throws {
        try await withOpenDocuments { service, _, key in
            try await crashedTwice(service, key: key)
            await lspServiceFlushMainQueue()

            #expect(fixture.created.count == 2)
            #expect(service.languageClients[key] == nil)
            #expect(fixture.notificationCount(titled: "Language server stopped") == 1)
            let notification = try #require(fixture.notificationManager.notifications.first)
            #expect(notification.description.contains("typescript"))
            #expect(notification.actionButtonTitle == "Open Settings")
            notification.action()
            try await eventually { fixture.openSettingsCount == 1 }
            try await assertNoFurtherServers(count: 2)
        }
    }

    @Test func aFailedAutomaticRestartNotifies() async throws {
        try await withOpenDocuments { service, _, key in
            fixture.createFailure = LSPServiceFixtureFailure.creation
            fixture.created[0].terminate()
            try await eventually { service.serverStates[key] == .failed("creation failed") }
            await service.waitForAutomaticRestarts()
            await lspServiceFlushMainQueue()

            #expect(service.languageClients[key] == nil)
            #expect(fixture.notificationCount(titled: "Language server stopped") == 1)
            #expect(fixture.created.count == 1)
        }
    }

    @Test func explicitRestartResetsTheAutomaticRestartCounter() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await restartedOnce(service, key: key)

            try await service.restartServer(key)
            #expect(fixture.created.count == 3)
            #expect(service.serverStates[key] == .running)
            #expect(Set(fixture.created[2].connection.lspServiceOpens.map(\.uri)) == Set(["a.ts", "b.tsx"].map(workspace.uri)))

            fixture.created[2].terminate()
            try await eventually { fixture.created.count == 4 }
            await service.waitForAutomaticRestarts()
            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === fixture.created[3].server)
            await lspServiceFlushMainQueue()
            #expect(fixture.notificationCount(titled: "Language server stopped") == 0)
        }
    }

    @Test func explicitRestartRecoversAFailedServer() async throws {
        try await withOpenDocuments { service, _, key in
            try await crashedTwice(service, key: key)

            try await service.restartServer(key)

            #expect(fixture.created.count == 3)
            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === fixture.created[2].server)
        }
    }

    @Test func intentionalStopDoesNotRestart() async throws {
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

    @Test func stoppingAnUnknownServerThrows() async {
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

    @Test func closingTheWorkspaceDoesNotRestart() async throws {
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

    @Test func closingAnotherWorkspaceKeepsTheServerRunning() async throws {
        try await withOpenDocuments { service, _, key in
            service.closeWorkspace("/some/other/workspace")
            await lspServiceFlushMainQueue()
            #expect(service.languageClients[key] != nil)
            #expect(service.serverStates[key] == .running)
        }
    }

    @Test func stoppingAllServersDoesNotRestart() async throws {
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

    @Test func aFailingShutdownKeepsTheClientOnStop() async throws {
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

    @Test func aFailingShutdownDoesNotBlockClosingTheWorkspace() async throws {
        try await withOpenDocuments(shutdownFailure: LSPServiceFixtureFailure.shutdown) { service, workspace, key in
            service.closeWorkspace(workspace.path)
            try await eventually { service.languageClients.isEmpty && service.serverStates[key] == nil }
        }
    }

    @Test func aFailingShutdownDoesNotBlockStoppingAllServers() async throws {
        try await withOpenDocuments(shutdownFailure: LSPServiceFixtureFailure.shutdown) { service, _, key in
            await service.stopAllServers()
            #expect(service.languageClients.isEmpty)
            #expect(service.serverStates[key] == .stopped)
        }
    }

    @Test func forwardedWatchedFilesReachTheServerUntilItStops() async throws {
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

            try "export {}\n".write(to: workspace.directory.appending(path: "new.ts"), atomically: true, encoding: .utf8)
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
            try FileManager.default.removeItem(at: workspace.directory.appending(path: "new.ts"))
            try workspace.fileManager.rebuildFiles(fromItem: workspace.fileManager.workspaceItem)
            workspace.fileManager.notifyObservers(updatedItems: [workspace.fileManager.workspaceItem])
            await forwarder.settle()
            #expect(created.connection.lspServiceWatchedChanges.count == 1)
        }
    }
}
