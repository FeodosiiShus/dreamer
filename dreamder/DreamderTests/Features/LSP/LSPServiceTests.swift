import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService", .uiGate)
struct LSPServiceTests {
    typealias Key = LSPService.ClientKey

    let fixture = LSPServiceFixture()

    @Test func clientKeysNormaliseToTheServerFamily() {
        let path = "/ws"
        #expect(Key(.typescript, path) == Key(.typescriptreact, path))
        #expect(Key(.typescript, path) == Key(.javascript, path))
        #expect(Key(.typescript, path) == Key(.javascriptreact, path))
        #expect(Key(.javascript, path) == Key(.typescriptreact, path))
        #expect(Key(.swift, path) == Key(.objc, path))
        #expect(Key(.c, path) == Key(.cpp, path))
        #expect(Key(.c, path) == Key(.objcpp, path))
        #expect(Key(.css, path) == Key(.scss, path))
        #expect(Key(.python, path) != Key(.go, path))
        #expect(Key(.typescript, path) != Key(.swift, path))
        #expect(Key(.typescript, "/a") != Key(.typescript, "/b"))
        #expect(Key(.javascriptreact, path).languageId == .typescript)
        #expect(Key(.python, path).workspacePath == path)
    }

    @Test func policyConstantsAndLiveDependencies() async {
        #expect(LSPService.maximumAutomaticRestarts == 1)
        #expect(LSPService.restartBackoff == .seconds(2))
        #expect(LSPService.watchedFilesMethod == "workspace/didChangeWatchedFiles")

        let live = LSPService.Dependencies.live
        #expect(live.restartBackoff == .seconds(2))
        #expect(live.observesDocumentNotifications)
        #expect(live.notifications() === NotificationManager.shared)
        let discovered = await live.discoverBinary(LSPLanguage(rawValue: "ruby"), "/tmp")
        #expect(discovered == nil)

        let unreachable = LanguageServerBinary(execPath: "/nonexistent/dreamder-language-server", args: [], env: nil)
        var failed = false
        do {
            _ = try await live.createServer(LSPLanguage(rawValue: "ruby"), unreachable, "/tmp")
        } catch {
            failed = true
        }
        #expect(failed)
    }

    @Test func openingTypeScriptFamilyDocumentsCreatesOneServer() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: ["a.ts": "let a = 1\n", "b.tsx": "let b = 2\n", "c.js": "let c = 3\n", "d.jsx": "let d = 4\n"]
            )
            defer { workspace.close() }
            let documents = try ["a.ts", "b.tsx", "c.js", "d.jsx"].map { try workspace.document($0) }

            for document in documents {
                service.openDocument(document)
            }
            await service.waitForDocumentOperations()

            #expect(fixture.created.count == 1)
            #expect(fixture.discoveries.count == 1)
            #expect(service.languageClients.count == 1)
            #expect(service.serverStates[workspace.key(.typescript)] == .running)
            let opens = try #require(fixture.created.first?.connection.lspServiceOpens)
            #expect(Set(opens.map(\.languageId)) == ["typescript", "typescriptreact", "javascript", "javascriptreact"])
            #expect(Set(opens.map(\.uri)) == Set(["a.ts", "b.tsx", "c.js", "d.jsx"].map(workspace.uri)))
            #expect(service.openDocumentURIs[workspace.key(.typescript)]?.count == 4)
            #expect(service.server(for: .javascriptreact, workspacePath: workspace.path) != nil)
            #expect(service.languageClient(for: .typescriptreact, workspacePath: workspace.path) != nil)
            let firstURL = try #require(documents.first?.fileURL)
            #expect(service.languageClient(forDocument: firstURL) != nil)
            #expect(service.languageClient(for: .python, workspacePath: workspace.path) == nil)
            #expect(service.server(for: .python, workspacePath: workspace.path) == nil)
        }
    }

    @Test func documentsWithoutLanguageOrWorkspaceAreIgnored() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["notes.txt": "plain\n"])
            defer { workspace.close() }
            let plain = try workspace.document("notes.txt")
            service.openDocument(plain)

            let outsideDirectory = dir.deletingLastPathComponent().appending(path: "lsp-outside-\(UUID().uuidString).ts")
            try "let x = 1\n".write(to: outsideDirectory, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: outsideDirectory) }
            let outside = try CodeFileDocument(
                for: outsideDirectory,
                withContentsOf: outsideDirectory,
                ofType: "public.plain-text"
            )
            service.openDocument(outside)
            await service.waitForDocumentOperations()

            #expect(fixture.created.isEmpty)
            #expect(service.openDocumentURIs.isEmpty)
        }
    }

    @Test func startServerReturnsTheExistingClient() async throws {
        let service = fixture.makeService()
        let first = try await service.startServer(for: .python, workspacePath: "/ws")
        let second = try await service.startServer(for: .python, workspacePath: "/ws")
        #expect(first === second)
        #expect(fixture.created.count == 1)
        #expect(fixture.discoveries.count == 1)
        #expect(service.serverStates[Key(.python, "/ws")] == .running)
        #expect(service.languageClient(for: .python, workspacePath: "/ws") === first)
        #expect(service.server(for: .python, workspacePath: "/ws") != nil)
    }

    @Test func concurrentStartsShareOneLaunch() async throws {
        let gate = LSPServiceGate()
        fixture.discoveryGate = gate
        let service = fixture.makeService()
        let key = Key(.python, "/ws")

        let first = Task { try await service.startServer(for: .python, workspacePath: "/ws") }
        let second = Task { try await service.startServer(for: .python, workspacePath: "/ws") }
        try await eventually { gate.waiterCount == 1 }
        #expect(service.serverStates[key] == .starting)
        gate.open()

        let firstServer = try await first.value
        let secondServer = try await second.value
        #expect(firstServer === secondServer)
        #expect(fixture.created.count == 1)
        #expect(fixture.discoveries.count == 1)
        #expect(service.serverStates[key] == .running)
    }

    @Test func startingStateIsVisibleWhileDiscoveryRuns() async throws {
        let gate = LSPServiceGate()
        fixture.discoveryGate = gate
        let service = fixture.makeService()
        let key = Key(.go, "/ws")

        let start = Task { try await service.startServer(for: .go, workspacePath: "/ws") }
        try await eventually { gate.waiterCount == 1 }
        #expect(service.serverStates[key] == .starting)
        #expect(service.languageClients[key] == nil)
        gate.open()
        _ = try await start.value
        #expect(service.serverStates[key] == .running)
    }

    @Test func missingBinaryFailsVisiblyAndNotifiesOncePerLanguage() async throws {
        fixture.binary = nil
        let service = fixture.makeService()
        let key = Key(LSPLanguage(rawValue: "ruby"), "/ws")

        for _ in 0..<2 {
            var thrown: LSPError?
            do {
                _ = try await service.startServer(for: LSPLanguage(rawValue: "ruby"), workspacePath: "/ws")
            } catch let error as LSPError {
                thrown = error
            }
            #expect(thrown == .binaryNotFound)
            #expect(service.serverStates[key] == .failed("No language server found for ruby"))
            #expect(service.languageClients[key] == nil)
        }
        #expect(fixture.created.isEmpty)

        do {
            _ = try await service.startServer(for: .python, workspacePath: "/ws")
        } catch {
            #expect(error as? LSPError == .binaryNotFound)
        }
        await lspServiceFlushMainQueue()

        #expect(fixture.notificationCount(titled: "Install Ruby Language Server") == 1)
        #expect(fixture.notificationCount(titled: "Install Python Language Server") == 1)
        #expect(fixture.notificationManager.notifications.count == 2)
    }

    @Test func missingBinaryNotificationOpensSettings() async throws {
        fixture.binary = nil
        let service = fixture.makeService()
        _ = try? await service.startServer(for: .python, workspacePath: "/ws")
        await lspServiceFlushMainQueue()

        let notification = try #require(fixture.notificationManager.notifications.first)
        #expect(notification.title == "Install Python Language Server")
        #expect(notification.actionButtonTitle == "Open Settings")
        notification.action()
        try await eventually { fixture.openSettingsCount == 1 }
    }

    @Test func aSecondServiceDoesNotRepeatAnExistingInstallNotification() async throws {
        fixture.binary = nil
        let first = fixture.makeService()
        let second = fixture.makeService()
        _ = try? await first.startServer(for: .python, workspacePath: "/ws")
        await lspServiceFlushMainQueue()
        _ = try? await second.startServer(for: .python, workspacePath: "/other")
        await lspServiceFlushMainQueue()

        #expect(fixture.notificationCount(titled: "Install Python Language Server") == 1)
        #expect(second.serverStates[Key(.python, "/other")] == .failed("No language server found for python"))
    }

    @Test func createServerFailureIsRecordedAndCanBeRetried() async throws {
        fixture.createFailure = LSPServiceFixtureFailure.creation
        let service = fixture.makeService()
        let key = Key(.rust, "/ws")

        var thrown: LSPServiceFixtureFailure?
        do {
            _ = try await service.startServer(for: .rust, workspacePath: "/ws")
        } catch let error as LSPServiceFixtureFailure {
            thrown = error
        }
        guard case .creation? = thrown else {
            Issue.record("Expected the creation failure to propagate")
            return
        }
        #expect(service.serverStates[key] == .failed("creation failed"))
        #expect(service.languageClients[key] == nil)

        fixture.createFailure = nil
        _ = try await service.startServer(for: .rust, workspacePath: "/ws")
        #expect(service.serverStates[key] == .running)
    }

    @Test func configuredBinaryWinsOverDiscovery() async throws {
        let service = fixture.makeService()
        let configured = LanguageServerBinary(execPath: "/configured/pylsp", args: ["--configured"], env: nil)
        service.languageConfigs[.python] = configured

        _ = try await service.startServer(for: .python, workspacePath: "/ws")

        let created = try #require(fixture.created.first)
        #expect(created.binary.execPath == "/configured/pylsp")
        #expect(created.binary.args == ["--configured"])
        #expect(fixture.discoveries.isEmpty)
    }

    @Test func discoveredBinariesAreNotCached() async throws {
        let service = fixture.makeService()
        _ = try await service.startServer(for: .go, workspacePath: "/one")
        _ = try await service.startServer(for: .go, workspacePath: "/two")

        #expect(fixture.discoveries.map(\.workspacePath) == ["/one", "/two"])
        #expect(service.languageConfigs[.go] == nil)
        #expect(fixture.created.map(\.binary.execPath) == ["/fake/language-server", "/fake/language-server"])
        #expect(fixture.created.map(\.language) == [.go, .go])
    }

    @Test func reopeningAnOpenDocumentSendsAFullTextChange() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let document = try workspace.document("a.ts")

            service.openDocument(document)
            await service.waitForDocumentOperations()
            let connection = try #require(fixture.created.first?.connection)

            workspace.setText("a.ts", "let changed = 2\n")
            service.openDocument(document)
            await service.waitForDocumentOperations()

            #expect(fixture.created.count == 1)
            #expect(connection.notificationCount(.textDocumentDidOpen) == 1)
            #expect(connection.lspServiceDocumentLog == ["textDocument/didOpen", "textDocument/didChange"])
            let change = try #require(connection.lspServiceChanges.first)
            #expect(change.textDocument.version == 1)
            #expect(change.textDocument.uri == workspace.uri("a.ts"))
            #expect(change.contentChanges.map(\.text) == ["let changed = 2\n"])
            #expect(change.contentChanges.first?.range == nil)

            workspace.setText("a.ts", "let again = 3\n")
            service.openDocument(document)
            await service.waitForDocumentOperations()

            #expect(connection.notificationCount(.textDocumentDidOpen) == 1)
            #expect(connection.lspServiceChanges.map(\.textDocument.version) == [1, 2])
        }
    }

    @Test func closingThenOpeningOpensAgain() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let document = try workspace.document("a.ts")
            let url = try #require(document.fileURL)
            let key = workspace.key(.typescript)

            service.openDocument(document)
            await service.waitForDocumentOperations()
            let created = try #require(fixture.created.first)
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) != nil)

            service.closeDocument(url)
            #expect(service.openDocumentURIs[key]?.contains(workspace.uri("a.ts")) != true)
            await service.waitForDocumentOperations()
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) == nil)

            service.openDocument(document)
            await service.waitForDocumentOperations()

            #expect(created.connection.lspServiceDocumentLog == [
                "textDocument/didOpen", "textDocument/didClose", "textDocument/didOpen"
            ])
            #expect(created.connection.lspServiceChanges.isEmpty)
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) != nil)
            #expect(fixture.created.count == 1)
        }
    }

    @Test func closeIsChainedBehindAPendingOpen() async throws {
        try await withTempDir { dir in
            let gate = LSPServiceGate()
            fixture.createGate = gate
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let document = try workspace.document("a.ts")
            let url = try #require(document.fileURL)

            service.openDocument(document)
            service.closeDocument(url)
            try await eventually { gate.waiterCount == 1 }
            #expect(fixture.created.isEmpty)
            gate.open()
            await service.waitForDocumentOperations()

            let created = try #require(fixture.created.first)
            #expect(created.connection.lspServiceDocumentLog == ["textDocument/didOpen", "textDocument/didClose"])
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) == nil)
            #expect(service.openDocumentURIs[workspace.key(.typescript)]?.isEmpty ?? true)
        }
    }

    @Test func closingAnUnknownDocumentDoesNothing() async {
        let service = fixture.makeService()
        service.closeDocument(URL(fileURLWithPath: "/nowhere/unknown.ts"))
        await service.waitForDocumentOperations()
        #expect(fixture.created.isEmpty)
    }

    @Test func openingFailsGracefullyWhenTheServerCannotStart() async throws {
        try await withTempDir { dir in
            fixture.createFailure = LSPServiceFixtureFailure.creation
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.py": "x = 1\n"])
            defer { workspace.close() }
            let document = try workspace.document("a.py")

            service.openDocument(document)
            await service.waitForDocumentOperations()

            #expect(service.serverStates[workspace.key(.python)] == .failed("creation failed"))
            #expect(service.openDocumentURIs[workspace.key(.python)]?.isEmpty ?? true)
            let url = try #require(document.fileURL)
            #expect(service.languageClient(forDocument: url) == nil)
        }
    }

    @Test func documentNotificationsDriveOpenAndClose() async throws {
        try await withTempDir { dir in
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.py": "x = 1\n"])
            defer { workspace.close() }
            let service = fixture.makeService(observesDocumentNotifications: true)
            let key = workspace.key(.python)

            NotificationCenter.default.post(name: CodeFileDocument.didOpenNotification, object: "not a document")
            NotificationCenter.default.post(name: CodeFileDocument.didCloseNotification, object: 7)

            let document = try workspace.document("a.py")
            let url = try #require(document.fileURL)
            try await eventually { service.openDocumentURIs[key]?.contains(workspace.uri("a.py")) == true }
            await service.waitForDocumentOperations()
            #expect(service.languageClient(forDocument: url) != nil)

            NotificationCenter.default.post(name: CodeFileDocument.didCloseNotification, object: url)
            try await eventually { service.openDocumentURIs[key]?.contains(workspace.uri("a.py")) != true }
            await service.waitForDocumentOperations()
            #expect(service.languageClient(forDocument: url) == nil)
        }
    }

    @Test func explicitRestartReopensDocumentsOnANewServer() async throws {
        try await withTempDir { dir in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            let document = try workspace.document("a.ts")
            let key = workspace.key(.typescript)

            service.openDocument(document)
            await service.waitForDocumentOperations()
            try await service.restartServer(key)

            #expect(fixture.created.count == 2)
            #expect(fixture.created[0].connection.log.contains("shutdown"))
            #expect(fixture.created[1].connection.lspServiceOpens.map(\.uri) == [workspace.uri("a.ts")])
            #expect(service.languageClients[key] === fixture.created[1].server)
            #expect(service.serverStates[key] == .running)
            #expect(service.openDocumentURIs[key] == [workspace.uri("a.ts")])
        }
    }
}

@MainActor
@Suite("LSPService settings", .serialized, .uiGate)
struct LSPServiceSettingsTests {
    let fixture = LSPServiceFixture()

    @Test func settingsConfiguredBinaryAppliesToTheWholeServerFamily() async throws {
        try await withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            settings.preferences.developerSettings.lspBinaries = ["scss": "~/bin/css-server", "unknown-language": "/x"]

            let service = fixture.makeService(settings: settings)
            let expanded = ("~/bin/css-server" as NSString).expandingTildeInPath
            #expect(service.languageConfigs[.css]?.execPath == expanded)

            _ = try await service.startServer(for: .less, workspacePath: "/ws")

            let created = try #require(fixture.created.first)
            #expect(created.binary.execPath == expanded)
            #expect(fixture.discoveries.isEmpty)
            #expect(service.languageConfigs[.css]?.execPath == expanded)
        }
    }
}
