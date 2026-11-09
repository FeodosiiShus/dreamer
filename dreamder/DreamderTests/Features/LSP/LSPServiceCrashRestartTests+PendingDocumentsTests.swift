import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension LSPServiceCrashRestartTests {
    func createdServer(_ index: Int) throws -> LSPServiceFixture.CreatedServer {
        try #require(fixture.created.dropFirst(index).first)
    }

    func writeDocument(_ name: String, in workspace: LSPServiceWorkspace) throws -> CodeFileDocument {
        try "let value = 1\n".write(to: workspace.directory.appending(path: name), atomically: true, encoding: .utf8)
        return try workspace.document(name)
    }

    func crashFirstServer(_ service: LSPService, key: Key) async throws {
        try createdServer(0).terminate()
        try await eventually(timeout: .seconds(20)) { service.serverStates[key] == .failed(crashMessage) }
    }

    @Test
    func aDocumentOpenedDuringTheBackoffStartsTheServerAndBringsTheCrashedDocumentsBack() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            try await crashFirstServer(service, key: key)
            let third = try writeDocument("c.ts", in: workspace)

            service.openDocument(third)
            await service.waitForDocumentOperations()

            let second = try createdServer(1)
            let expected = ["a.ts", "b.tsx", "c.ts"].map(workspace.uri)
            #expect(fixture.created.count == 2)
            #expect(second.connection.lspServiceOpens.map(\.uri) == expected)
            #expect(service.openDocumentURIs[key] == Set(expected))
            #expect(service.pendingDocuments[key]?.isEmpty ?? true)
            #expect(service.serverStates[key] == .running)
            #expect(service.languageClients[key] === second.server)
        }
    }

    @Test
    func aRestartThatWakesAfterAnotherStartLeavesEveryDocumentOpenedExactlyOnce() async throws {
        try await withOpenDocuments(backoff: .milliseconds(50)) { service, workspace, key in
            try await crashFirstServer(service, key: key)
            let third = try writeDocument("c.ts", in: workspace)

            service.openDocument(third)
            await service.waitForAutomaticRestarts()
            await service.waitForDocumentOperations()

            let second = try createdServer(1)
            #expect(fixture.created.count == 2)
            #expect(second.connection.lspServiceOpens.map(\.uri) == ["a.ts", "b.tsx", "c.ts"].map(workspace.uri))
            #expect(service.serverStates[key] == .running)
        }
    }

    @Test
    func aDocumentOpenedAfterTwoCrashesStartsTheServerWithTheLostDocuments() async throws {
        try await withOpenDocuments { service, workspace, key in
            try await crashedTwice(service, key: key)
            let third = try writeDocument("c.ts", in: workspace)

            service.openDocument(third)
            await service.waitForDocumentOperations()

            let restarted = try createdServer(2)
            #expect(fixture.created.count == 3)
            #expect(restarted.connection.lspServiceOpens.map(\.uri) == ["a.ts", "b.tsx", "c.ts"].map(workspace.uri))
            #expect(service.pendingDocuments[key]?.isEmpty ?? true)
            #expect(service.serverStates[key] == .running)
        }
    }

    @Test
    func openingACrashedDocumentAgainOpensItOnTheNewServerOnce() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            try await crashFirstServer(service, key: key)

            service.openDocument(try #require(workspace.documents["a.ts"]))
            await service.waitForDocumentOperations()

            let second = try createdServer(1)
            #expect(second.connection.lspServiceOpens.count == 2)
            #expect(Set(second.connection.lspServiceOpens.map(\.uri)) == Set(["a.ts", "b.tsx"].map(workspace.uri)))
            #expect(second.connection.lspServiceChanges.isEmpty)
            #expect(service.pendingDocuments[key]?.isEmpty ?? true)
        }
    }

    @Test
    func aDocumentClosedDuringTheBackoffIsNotReopened() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            try await crashFirstServer(service, key: key)

            service.closeDocument(workspace.directory.appending(path: "b.tsx"))
            await service.waitForDocumentOperations()
            try await service.restartServer(key)

            let second = try createdServer(1)
            #expect(second.connection.lspServiceDocumentLog == ["textDocument/didOpen"])
            #expect(second.connection.lspServiceOpens.map(\.uri) == [workspace.uri("a.ts")])
            #expect(second.server.openFiles.document(for: workspace.uri("b.tsx")) == nil)
            #expect(service.openDocumentURIs[key] == [workspace.uri("a.ts")])
        }
    }

    @Test
    func aDocumentClosedWhileTheAutomaticRestartRunsIsNeverLeftOpen() async throws {
        try await withOpenDocuments(backoff: .milliseconds(50)) { service, workspace, key in
            try await crashFirstServer(service, key: key)

            service.closeDocument(workspace.directory.appending(path: "b.tsx"))
            await service.waitForAutomaticRestarts()
            await service.waitForDocumentOperations()

            let second = try createdServer(1)
            #expect(second.server.openFiles.document(for: workspace.uri("b.tsx")) == nil)
            #expect(second.server.openFiles.document(for: workspace.uri("a.ts")) != nil)
            #expect(service.openDocumentURIs[key] == [workspace.uri("a.ts")])
            #expect(service.serverStates[key] == .running)
        }
    }

    @Test
    func documentsClosedWhileTheRestartIsOpeningThemAreClosedOrSkipped() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            let gate = LSPServiceGate()
            fixture.didOpenGate = gate
            try await crashFirstServer(service, key: key)
            let restarting = Task { try await service.restartServer(key) }
            try await eventually(timeout: .seconds(20)) { gate.waiterCount == 1 }

            service.closeDocument(workspace.directory.appending(path: "a.ts"))
            service.closeDocument(workspace.directory.appending(path: "b.tsx"))
            gate.open()
            try await restarting.value
            await service.waitForDocumentOperations()

            let second = try createdServer(1)
            #expect(second.connection.lspServiceDocumentLog == ["textDocument/didOpen", "textDocument/didClose"])
            #expect(second.connection.lspServiceOpens.map(\.uri) == [workspace.uri("a.ts")])
            #expect(second.server.openFiles.document(for: workspace.uri("a.ts")) == nil)
            #expect(service.openDocumentURIs[key]?.isEmpty ?? true)
            #expect(service.pendingDocuments[key]?.isEmpty ?? true)
        }
    }

    @Test
    func aServerThatCrashesWhileReopeningKeepsTheRemainingDocumentsForTheNextStart() async throws {
        try await withOpenDocuments(backoff: .seconds(60)) { service, workspace, key in
            let gate = LSPServiceGate()
            fixture.didOpenGate = gate
            try await crashFirstServer(service, key: key)
            let restarting = Task { try await service.restartServer(key) }
            try await eventually(timeout: .seconds(20)) { gate.waiterCount == 1 }

            try createdServer(1).terminate()
            try await eventually(timeout: .seconds(20)) { service.languageClients[key] == nil }
            gate.open()
            try await restarting.value

            let expected = ["a.ts", "b.tsx"].map(workspace.uri)
            #expect(service.pendingDocuments[key]?.keys.sorted() == expected)
            #expect(try createdServer(1).connection.lspServiceOpens.map(\.uri) == [workspace.uri("a.ts")])

            try await service.restartServer(key)

            let third = try createdServer(2)
            #expect(fixture.created.count == 3)
            #expect(third.connection.lspServiceOpens.map(\.uri) == expected)
            #expect(service.pendingDocuments[key]?.isEmpty ?? true)
            #expect(service.serverStates[key] == .running)
        }
    }
}
