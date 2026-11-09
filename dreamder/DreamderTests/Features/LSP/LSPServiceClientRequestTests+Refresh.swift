import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@MainActor
extension LSPServiceClientRequestTests {
    @Test
    func semanticTokenRefreshRequestsTokensAndSurvivesServerFailures() async throws {
        fixture.capabilities.semanticTokensProvider = .optionA(.init(legend: .init(tokenTypes: [], tokenModifiers: [])))
        try await running(["a.ts": "let a = 1\n", "b.ts": "let b = 2\n"]) { service, workspace, key, created in
            let attached = try workspace.document("a.ts")
            let detached = try workspace.document("b.ts")
            service.openDocument(attached)
            service.openDocument(detached)
            await service.waitForDocumentOperations()
            let textView = TextView(string: "let a = 1\n")
            attached.languageServerObjects.highlightProvider.setUp(textView: textView, codeLanguage: .swift)
            try await eventually(timeout: .seconds(30)) {
                created.connection.requestCount(.textDocumentSemanticTokensFull) >= 1
            }
            let initial = created.connection.requestCount(.textDocumentSemanticTokensFull)

            await service.refresh(.semanticTokens, for: key)
            #expect(created.connection.requestCount(.textDocumentSemanticTokensFull) == initial + 1)

            created.connection.failRequests([.textDocumentSemanticTokensFull])
            await service.refresh(.semanticTokens, for: key)
            #expect(created.connection.requestCount(.textDocumentSemanticTokensFull) == initial + 2)
            withExtendedLifetime(textView) {}
        }
    }

    @Test
    func inlayHintRefreshPostsANotificationForTheWorkspace() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            let posted = LSPServiceReplyRecorder<String>()
            let kindKey = LSPService.refreshKindUserInfoKey
            let pathKey = LSPService.refreshWorkspacePathUserInfoKey
            let observer = NotificationCenter.default.addObserver(
                forName: LSPService.refreshRequestedNotification,
                object: service,
                queue: nil
            ) { notification in
                let kind = notification.userInfo?[kindKey] as? String ?? ""
                let path = notification.userInfo?[pathKey] as? String ?? ""
                posted.append("\(kind)|\(path)")
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            await service.refresh(.inlayHint, for: key)
            await service.refresh(.inlayHint, for: LSPService.ClientKey(.typescript, "/not-running"))

            #expect(posted.values == ["inlayHint|\(workspace.path)"])
        }
    }

    @Test
    func diagnosticsRefreshSurvivesAFailingPullRequest() async throws {
        fixture.capabilities.diagnosticProvider = .optionA(
            DiagnosticOptions(identifier: nil, interFileDependencies: false, workspaceDiagnostics: false)
        )
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            try created.connection.script(.textDocumentDiagnostic, DocumentDiagnosticReport(kind: .full, items: []))
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let opened = created.connection.requestCount(.textDocumentDiagnostic)
            #expect(opened >= 1)

            created.connection.failRequests([.textDocumentDiagnostic])
            await service.refresh(.diagnostics, for: key)

            #expect(created.connection.requestCount(.textDocumentDiagnostic) == opened + 1)
        }
    }

    @Test
    func aFailingServerSyncStillAppliesTheEditToTheOpenDocument() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let client = try #require(service.languageClients[key])
            created.connection.failNotifications([.textDocumentDidChange])

            let result = await service.applyWorkspaceEdit(
                replaceEdit(workspace.uri("a.ts"), from: 4, to: 5, with: "b"),
                via: client
            )

            #expect(result.applied)
            #expect(document.content?.string == "let b = 1\n")
            #expect(created.connection.notificationCount(.textDocumentDidChange) >= 1)
        }
    }

    @Test
    func aFailingCloseNotificationDoesNotBlockTheNextOpen() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, _, created in
            let document = try workspace.document("a.ts")
            let url = try #require(document.fileURL)
            service.openDocument(document)
            await service.waitForDocumentOperations()
            created.connection.failNotifications([.textDocumentDidClose])

            service.closeDocument(url)
            await service.waitForDocumentOperations()

            #expect(created.connection.notificationCount(.textDocumentDidClose) == 1)
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) == nil)

            created.connection.failNotifications([])
            service.openDocument(document)
            await service.waitForDocumentOperations()

            #expect(created.connection.notificationCount(.textDocumentDidOpen) == 2)
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) != nil)
        }
    }

    @Test
    func aFailingOpenNotificationIsLoggedAndLaterOpensStillWork() async throws {
        try await running(["a.ts": "let a = 1\n", "b.ts": "let b = 2\n"]) { service, workspace, _, created in
            created.connection.failNotifications([.textDocumentDidOpen])
            service.openDocument(try workspace.document("a.ts"))
            await service.waitForDocumentOperations()
            #expect(created.connection.notificationCount(.textDocumentDidOpen) == 1)

            created.connection.failNotifications([])
            service.openDocument(try workspace.document("b.ts"))
            await service.waitForDocumentOperations()

            #expect(created.connection.notificationCount(.textDocumentDidOpen) == 2)
            #expect(created.server.openFiles.document(for: workspace.uri("b.ts")) != nil)
        }
    }

    @Test
    func killingAllServersTerminatesTheirProcesses() async throws {
        let language = LSPLanguage(rawValue: "ruby")
        let binary = LanguageServerBinary(
            execPath: "/bin/sh",
            args: ["-c", canonicalInitializeServerScript],
            env: ["PATH": "/usr/bin:/bin"]
        )
        let server = try await withTimeout(duration: .seconds(60)) {
            try await Client.createServer(for: language, with: binary, workspacePath: "/tmp")
        }
        _ = try #require(server.pid > 0 ? server.pid : nil)
        let service = fixture.makeService()
        service.languageClients[LSPService.ClientKey(language, "/tmp")] = server
        let terminations = server.terminationEvents

        service.killAllServers()

        let fired = try await withTimeout(duration: .seconds(60)) {
            for await _ in terminations {
                return true
            }
            return false
        }
        #expect(fired)
    }
}
