import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension LSPServiceCrashRestartTests {
    @Test
    func explicitRestartResetsTheAutomaticRestartCounter() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await restartedOnce(service, key: key)

            try await service.restartServer(key)
            #expect(fixture.created.count == 3)
            #expect(service.serverStates[key] == .running)
            let reopened = Set(["a.ts", "b.tsx"].map(workspace.uri))
            #expect(Set(fixture.created[2].connection.lspServiceOpens.map(\.uri)) == reopened)

            fixture.created[2].terminate()
            try await eventually { fixture.created.count == 4 }
            await service.waitForAutomaticRestarts()
            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === fixture.created[3].server)
            await lspServiceFlushMainQueue()
            #expect(fixture.notificationCount(titled: "Language server stopped") == 0)
        }
    }

    @Test
    func explicitRestartRecoversAFailedServer() async throws {
        try await withOpenDocuments { service, _, key in
            try await crashedTwice(service, key: key)

            try await service.restartServer(key)

            #expect(fixture.created.count == 3)
            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === fixture.created[2].server)
        }
    }

    @Test
    func restartingAFailedRowInTheToolWindowReopensItsDocuments() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await crashedTwice(service, key: key)
            let model = LanguageServicesModel(lspService: service)
            #expect(model.rows(workspacePath: workspace.path).map(\.status) == [.failed])

            await model.restart([key])

            let reopened = Set(["a.ts", "b.tsx"].map(workspace.uri))
            #expect(Set(fixture.created[2].connection.lspServiceOpens.map(\.uri)) == reopened)
            #expect(model.rows(workspacePath: workspace.path).map(\.status) == [.running])
        }
    }

    @Test
    func explicitRestartReopensTheDocumentsOfAServerThatCrashedTwice() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await crashedTwice(service, key: key)
            #expect(service.languageClients[key] == nil)

            try await service.restartServer(key)

            let expected = Set(["a.ts", "b.tsx"].map(workspace.uri))
            #expect(Set(fixture.created[2].connection.lspServiceOpens.map(\.uri)) == expected)
            #expect(service.openDocumentURIs[key] == expected)
            #expect(service.watchedFilesForwarder(for: key) != nil)
        }
    }

    @Test
    func explicitRestartReopensTheDocumentsOfAServerWhoseAutomaticRestartFailed() async throws {
        try await withOpenDocuments { service, workspace, key in
            fixture.createFailure = LSPServiceFixtureFailure.creation
            fixture.created[0].terminate()
            try await eventually { service.serverStates[key] == .failed("creation failed") }
            await service.waitForAutomaticRestarts()
            fixture.createFailure = nil

            try await service.restartServer(key)

            #expect(fixture.created.count == 2)
            let reopened = Set(["a.ts", "b.tsx"].map(workspace.uri))
            #expect(Set(fixture.created[1].connection.lspServiceOpens.map(\.uri)) == reopened)
        }
    }

    @Test
    func explicitRestartOfAFailedServerSkipsDocumentsClosedInTheMeantime() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await crashedTwice(service, key: key)

            service.closeDocument(workspace.directory.appending(path: "a.ts"))
            await service.waitForDocumentOperations()
            try await service.restartServer(key)

            #expect(fixture.created[2].connection.lspServiceOpens.map(\.uri) == [workspace.uri("b.tsx")])
        }
    }
}
