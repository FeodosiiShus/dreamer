import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService document operations", .serialized, .uiGate)
struct LSPServiceDocumentOperationsTests {
    let fixture = LSPServiceFixture()

    @Test
    func finishedOperationsAreForgottenForEveryDistinctDocument() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let names = (0..<12).map { "file\($0).ts" }
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: Dictionary(uniqueKeysWithValues: names.map { ($0, "let value = 1\n") })
            )
            defer { workspace.close() }
            let documents = try names.map { try workspace.document($0) }

            for document in documents {
                service.openDocument(document)
            }
            #expect(service.documentOperations.count == names.count)
            await service.waitForDocumentOperations()
            #expect(service.documentOperations.isEmpty)

            for name in names {
                service.closeDocument(workspace.directory.appending(path: name))
            }
            await service.waitForDocumentOperations()

            #expect(service.documentOperations.isEmpty)
            #expect(fixture.created.count == 1)
            #expect(service.languageClients.values.allSatisfy { $0.openFiles.uris.isEmpty })
        }
    }

    @Test
    func aSuccessorOperationKeepsTheEntryUntilItFinishesToo() async throws {
        try await withTempDir { dir in
            let gate = LSPServiceGate()
            fixture.createGate = gate
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let document = try workspace.document("a.ts")
            let uri = workspace.uri("a.ts")

            service.openDocument(document)
            let first = try #require(service.documentOperations[uri])
            service.closeDocument(workspace.directory.appending(path: "a.ts"))
            let second = try #require(service.documentOperations[uri])
            try await eventually(timeout: .seconds(20)) { gate.waiterCount == 1 }

            #expect(first.id != second.id)
            #expect(service.documentOperations.count == 1)
            #expect(service.documentOperations[uri]?.id == second.id)

            gate.open()
            await first.task.value
            await second.task.value

            #expect(service.documentOperations.isEmpty)
        }
    }

    @Test
    func aDocumentClosedWhileItsServerFailsToStartIsNotKeptForARestart() async throws {
        try await withTempDir { dir in
            let gate = LSPServiceGate()
            fixture.createGate = gate
            fixture.createFailure = LSPServiceFixtureFailure.creation
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.py": "x = 1\n", "b.py": "y = 2\n"])
            defer { workspace.close() }
            let key = workspace.key(.python)
            service.openDocument(try workspace.document("a.py"))
            service.openDocument(try workspace.document("b.py"))
            service.closeDocument(workspace.directory.appending(path: "a.py"))
            try await eventually(timeout: .seconds(20)) { gate.waiterCount == 1 }

            gate.open()
            await service.waitForDocumentOperations()

            #expect(service.pendingDocuments[key]?.keys.sorted() == [workspace.uri("b.py")])
            #expect(service.openDocumentURIs[key]?.isEmpty ?? true)
            #expect(service.serverStates[key] == .failed("creation failed"))
        }
    }

    @Test
    func closingAnUnknownDocumentLeavesNoEntryBehind() async {
        let service = fixture.makeService()

        service.closeDocument(URL(fileURLWithPath: "/nowhere/unknown.ts"))
        #expect(service.documentOperations.count == 1)
        await service.waitForDocumentOperations()

        #expect(service.documentOperations.isEmpty)
    }
}
