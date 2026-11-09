import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService untrusted workspaces", .serialized, .uiGate)
struct LSPServiceUntrustedWorkspaceTests {
    typealias Key = LSPService.ClientKey

    let fixture = LSPServiceFixture()
    let fakeExecutable = "/fake/language-server"

    func report(_ workspacePath: String) -> UntrustedNoticeRecorder.Report {
        UntrustedNoticeRecorder.Report(workspacePath: workspacePath, executable: fakeExecutable)
    }

    @Test
    func startingADeniedServerThrowsAndRecordsTheSafeModeState() async throws {
        fixture.workspaceTrusted = false
        let service = fixture.makeService()
        let key = Key(.rust, "/ws")

        var thrown: UntrustedWorkspaceServerError?
        do {
            _ = try await service.startServer(for: .rust, workspacePath: "/ws")
        } catch let error as UntrustedWorkspaceServerError {
            thrown = error
        }

        #expect(thrown == UntrustedWorkspaceServerError(language: .rust))
        #expect(service.serverStates[key] == .failed(
            UntrustedWorkspaceServerPolicy.failureMessage(forExecutable: fakeExecutable)
        ))
        #expect(service.languageClients.isEmpty)
        #expect(fixture.created.isEmpty)
        #expect(fixture.untrustedNotices.reports == [report("/ws")])
    }

    @Test
    func aDeniedServerIsReportedOncePerWorkspace() async {
        fixture.workspaceTrusted = false
        let service = fixture.makeService()

        for language in [LSPLanguage.rust, .go, .python] {
            _ = try? await service.startServer(for: language, workspacePath: "/ws")
        }
        _ = try? await service.startServer(for: .go, workspacePath: "/other")

        #expect(fixture.untrustedNotices.reports == [report("/ws"), report("/other")])
        #expect(fixture.created.isEmpty)
    }

    @Test
    func aMissingServerBinaryIsReportedAsMissingNotAsSafeMode() async {
        fixture.workspaceTrusted = false
        fixture.binary = nil
        let service = fixture.makeService()
        let ruby = LSPLanguage(rawValue: "ruby")

        var thrown: LSPError?
        do {
            _ = try await service.startServer(for: ruby, workspacePath: "/ws")
        } catch let error as LSPError {
            thrown = error
        } catch {
            thrown = nil
        }

        #expect(thrown == .binaryNotFound)
        #expect(service.serverStates[Key(ruby, "/ws")] == .failed("No language server found for ruby"))
        #expect(fixture.untrustedNotices.reports.isEmpty)
    }

    @Test
    func aConfiguredServerBinaryDoesNotBypassTheTrustPolicy() async {
        fixture.workspaceTrusted = false
        let service = fixture.makeService()
        let configured = "/configured/rust-analyzer"
        service.languageConfigs[.rust] = LanguageServerBinary(execPath: configured, args: [], env: nil)

        _ = try? await service.startServer(for: .rust, workspacePath: "/ws")

        #expect(fixture.created.isEmpty)
        #expect(service.languageClients.isEmpty)
        #expect(fixture.untrustedNotices.reports == [
            UntrustedNoticeRecorder.Report(workspacePath: "/ws", executable: configured)
        ])
    }

    @Test
    func vtslsIsDeniedInAnUntrustedWorkspaceEvenForTypeScript() async {
        fixture.workspaceTrusted = false
        fixture.binary = LanguageServerBinary(execPath: "/opt/node/bin/vtsls", args: ["--stdio"], env: nil)
        let service = fixture.makeService()

        _ = try? await service.startServer(for: .typescript, workspacePath: "/ws")

        #expect(fixture.created.isEmpty)
        #expect(service.serverStates[Key(.typescript, "/ws")]
            == .failed(UntrustedWorkspaceServerPolicy.failureMessage(forExecutable: "vtsls")))
        #expect(fixture.untrustedNotices.reports == [
            UntrustedNoticeRecorder.Report(workspacePath: "/ws", executable: "/opt/node/bin/vtsls")
        ])
    }

    @Test
    func theTypeScriptLanguageServerStillStartsInAnUntrustedWorkspace() async throws {
        try await withTempDir { dir in
            fixture.workspaceTrusted = false
            fixture.binary = LanguageServerBinary(
                execPath: "/opt/node/bin/typescript-language-server",
                args: ["--stdio"],
                env: nil
            )
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: ["a.ts": "let a = 1\n", "b.tsx": "let b = 2\n", "c.js": "let c = 3\n", "d.jsx": "let d = 4\n"]
            )
            defer { workspace.close() }
            for name in ["a.ts", "b.tsx", "c.js", "d.jsx"] {
                service.openDocument(try workspace.document(name))
            }
            await service.waitForDocumentOperations()

            #expect(fixture.created.count == 1)
            #expect(service.serverStates[workspace.key(.typescript)] == .running)
            #expect(fixture.untrustedNotices.reports.isEmpty)
            let opens = try #require(fixture.created.first?.connection.lspServiceOpens)
            #expect(opens.count == 4)
        }
    }

    @Test
    func aTrustedWorkspaceStartsServersOutsideTheAllowlist() async throws {
        let service = fixture.makeService()

        for language in [LSPLanguage.rust, .python, .swift, .go] {
            _ = try await service.startServer(for: language, workspacePath: "/ws")
        }

        #expect(fixture.created.map(\.language) == [.rust, .python, .swift, .go])
        #expect(fixture.untrustedNotices.reports.isEmpty)
    }

    @Test
    func documentsOpenedInAnUntrustedWorkspaceWaitForATrustedStart() async throws {
        try await withTempDir { dir in
            fixture.workspaceTrusted = false
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.py": "x = 1\n", "b.py": "y = 2\n"])
            defer { workspace.close() }
            let key = workspace.key(.python)
            for name in ["a.py", "b.py"] {
                service.openDocument(try workspace.document(name))
            }
            await service.waitForDocumentOperations()

            #expect(fixture.created.isEmpty)
            #expect(service.openDocumentURIs[key]?.isEmpty ?? true)
            #expect(service.pendingDocuments[key]?.keys.sorted() == ["a.py", "b.py"].map(workspace.uri))
            #expect(fixture.untrustedNotices.reports == [report(workspace.path)])

            fixture.workspaceTrusted = true
            await service.restartServers(inWorkspace: workspace.path)

            let created = try #require(fixture.created.first)
            #expect(fixture.created.count == 1)
            #expect(Set(created.connection.lspServiceOpens.map(\.uri)) == Set(["a.py", "b.py"].map(workspace.uri)))
            #expect(created.connection.lspServiceOpens.count == 2)
            #expect(service.serverStates[key] == .running)
            #expect(service.pendingDocuments[key]?.isEmpty ?? true)
        }
    }

    @Test
    func aDocumentClosedWhileItsServerWasDeniedIsNotStartedAfterTrust() async throws {
        try await withTempDir { dir in
            fixture.workspaceTrusted = false
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.py": "x = 1\n", "b.py": "y = 2\n"])
            defer { workspace.close() }
            let key = workspace.key(.python)
            for name in ["a.py", "b.py"] {
                service.openDocument(try workspace.document(name))
            }
            await service.waitForDocumentOperations()

            service.closeDocument(workspace.directory.appending(path: "a.py"))
            fixture.workspaceTrusted = true
            await service.restartServers(inWorkspace: workspace.path)

            let created = try #require(fixture.created.first)
            #expect(created.connection.lspServiceOpens.map(\.uri) == [workspace.uri("b.py")])
            #expect(service.openDocumentURIs[key] == [workspace.uri("b.py")])
        }
    }

    @Test
    func theSafeModeNotificationOffersTrustAndStartsTheDeniedServers() async throws {
        let fixture = fixture
        try await withIsolatedDefaults { defaults in
            try await withTempDir { dir in
                fixture.workspaceTrusted = false
                let box = LSPServiceBox()
                let manager = fixture.notificationManager
                let trust = WorkspaceTrust(defaults: defaults, confirm: { _ in
                    fixture.workspaceTrusted = true
                    return true
                })
                let notifier = SafeModeNotifier(
                    notifications: { manager },
                    trust: { trust },
                    restartServers: { path in
                        if let service = box.service {
                            await service.restartServers(inWorkspace: path)
                        }
                    }
                )
                fixture.untrustedNotice = UntrustedWorkspaceServerNotice(
                    report: UntrustedWorkspaceServerNotice.makeReport(notifier: { notifier })
                )
                let service = fixture.makeService()
                box.service = service
                let workspace = try LSPServiceWorkspace(directory: dir, files: ["lib.rs": "fn main() {}\n"])
                defer { workspace.close() }
                service.openDocument(try workspace.document("lib.rs"))
                await service.waitForDocumentOperations()
                try await eventually(timeout: .seconds(20)) { manager.notifications.count == 1 }

                let notification = try #require(manager.notifications.first)
                #expect(notification.title == SafeModeNotifier.title)
                #expect(notification.description.contains("language-server"))
                #expect(fixture.created.isEmpty)

                notification.action()
                try await eventually(timeout: .seconds(20)) {
                    fixture.created.first?.connection.lspServiceOpens.map(\.uri) == [workspace.uri("lib.rs")]
                }

                #expect(service.serverStates[workspace.key(.rust)] == .running)
                #expect(trust.isTrusted(URL(fileURLWithPath: workspace.path)))
            }
        }
    }

    @Test
    func theLiveDependenciesConsultTheSharedTrustAndTheSharedDiscoveryNotice() {
        let live = LSPService.Dependencies.live

        #expect(live.untrustedNotice === LanguageServerDiscovery.untrustedNotice)
        #expect(!live.isWorkspaceTrusted("/dreamder-tests/never-trusted-\(UUID().uuidString)"))
    }
}
