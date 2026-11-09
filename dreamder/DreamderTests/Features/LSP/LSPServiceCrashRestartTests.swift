import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService crash handling", .uiGate)
struct LSPServiceCrashRestartTests {
    typealias Key = LSPService.ClientKey

    let fixture = LSPServiceFixture()

    let crashMessage = "The typescript language server terminated unexpectedly"

    func withOpenDocuments(
        backoff: Duration = .milliseconds(20),
        shutdownFailure: (any Error)? = nil,
        shutdownGate: LSPServiceGate? = nil,
        _ body: (LSPService, LSPServiceWorkspace, Key) async throws -> Void
    ) async throws {
        try await withTempDir { dir in
            fixture.restartBackoff = backoff
            fixture.shutdownFailure = shutdownFailure
            fixture.shutdownGate = shutdownGate
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

    func restartedOnce(_ service: LSPService, key: Key) async throws {
        fixture.created[0].terminate()
        try await eventually { fixture.created.count == 2 }
        await service.waitForAutomaticRestarts()
        #expect(service.serverStates[key] == .running)
    }

    func crashedTwice(_ service: LSPService, key: Key) async throws {
        try await restartedOnce(service, key: key)
        fixture.created[1].terminate()
        try await eventually { service.serverStates[key] == .failed(crashMessage) }
        await service.waitForAutomaticRestarts()
    }

    func assertNoFurtherServers(count: Int) async throws {
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.created.count == count)
    }

    @Test
    func crashMarksTheServerFailedAndClearsItsState() async throws {
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

    @Test
    func crashRestartsExactlyOnceAndReopensDocuments() async throws {
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

    @Test
    func aTerminationOfAReplacedServerIsIgnored() async throws {
        try await withOpenDocuments { service, _, key in
            try await restartedOnce(service, key: key)

            service.serverTerminated(fixture.created[0].server, key: key)

            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === fixture.created[1].server)
            #expect(fixture.created.count == 2)
        }
    }

    @Test
    func aSecondCrashStaysFailedAndNotifies() async throws {
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

    @Test
    func aFailedAutomaticRestartNotifies() async throws {
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
}
