import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

private enum DiagnosticCodeActionGateError: Error {
    case unsupported
}

private final class DiagnosticCodeActionGateConnection: ServerConnection, Sendable {
    let eventSequence: EventSequence
    private let codeActionCount = Mutex(0)
    private let responseDelay: Duration

    init(responseDelay: Duration) {
        let (sequence, _) = EventSequence.makeStream()
        eventSequence = sequence
        self.responseDelay = responseDelay
    }

    var codeActionRequests: Int {
        codeActionCount.withLock { $0 }
    }

    func sendNotification(_ notif: ClientNotification) async throws {}

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        switch request {
        case .initialize:
            return try Self.decode(InitializationResponse(capabilities: ServerCapabilities(), serverInfo: nil))
        case .codeAction:
            codeActionCount.withLock { $0 += 1 }
            try await Task.sleep(for: responseDelay)
            let edit = WorkspaceEdit(changes: [:], documentChanges: nil)
            let quickFix = CodeActionsHarness.Response([
                .optionB(CodeAction(title: "Fix it", kind: "quickfix", edit: edit))
            ])
            return try Self.decode(quickFix)
        default:
            throw DiagnosticCodeActionGateError.unsupported
        }
    }

    private static func decode<Response: Decodable, Payload: Encodable>(_ payload: Payload) throws -> Response {
        try JSONDecoder().decode(Response.self, from: JSONEncoder().encode(payload))
    }
}

@MainActor
@Suite("DiagnosticHighlightCoordinatorBranches", .serialized, .uiGate)
struct DiagnosticHighlightBranchTests {
    private static let source = "let alpha = 1\nlet beta = 2\nlet gamma = 3\n"

    private func makeCoordinators(
        for fixture: HostedSourceEditorFixture,
        service: LSPService?
    ) -> [TextViewCoordinator] {
        [
            fixture.document.contentCoordinator,
            DiagnosticHighlightCoordinator(
                codeFile: fixture.document,
                intentionDelay: .milliseconds(5),
                tooltipDelay: .milliseconds(5),
                lspService: { service }
            )
        ]
    }

    private func diagnostic(at url: URL, line: Int) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: url,
            startLine: line,
            startColumn: 4,
            endLine: line,
            endColumn: 9,
            severity: .error,
            message: "problem on \(line)",
            source: "swift",
            code: "E\(line)"
        )
    }

    private func makeGatedServer(
        in directory: URL,
        connection: DiagnosticCodeActionGateConnection
    ) async throws -> LSPService.LanguageServerType {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(
            TextDocumentSyncOptions(
                openClose: true,
                change: .incremental,
                willSave: false,
                willSaveWaitUntil: false,
                save: nil
            )
        )
        capabilities.codeActionProvider = .optionA(true)
        let server = LSPService.LanguageServerType(
            languageId: .swift,
            binary: .init(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LSPService.LanguageServerType.getInitParams(workspacePath: directory.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: directory,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    @Test
    func withoutAWorkspaceTheTooltipHasNoModelAndASecondDestroyIsHarmless() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                makeCoordinators(for: fixture, service: nil)
            }
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: DiagnosticHighlightCoordinator.self))

            coordinator.tooltip.hover(line: 0, column: 4, anchor: .zero)
            #expect(coordinator.tooltip.pendingModel == nil)
            #expect(coordinator.tooltip.popover == nil)

            coordinator.destroy()
            coordinator.destroy()
            #expect(session.hosted.views(ofType: ErrorStripeView.self).isEmpty)
            #expect(session.hosted.views(ofType: IntentionPopupBulbView.self).isEmpty)
            #expect(!coordinator.intentionAvailable(line: 0))
        }
    }

    @Test
    func withoutACaretSelectionTheBulbIsCleared() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(
                in: directory,
                contents: Self.source,
                withWorkspace: true
            ) { fixture in
                makeCoordinators(for: fixture, service: nil)
            }
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: DiagnosticHighlightCoordinator.self))

            session.textView.selectionManager.setSelectedRanges([])
            #expect(session.textView.selectionManager.textSelections.isEmpty)
            coordinator.bulb.show(line: 0)
            #expect(coordinator.bulb.line == 0)
            coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])

            try await eventually { coordinator.bulb.line == nil }
            #expect(!coordinator.intentionAvailable(line: 0))
        }
    }

    @Test
    func aSelectionChangeWhileTheCodeActionsAreInFlightCancelsTheStaleRequest() async throws {
        try await withTempDir { directory in
            let connection = DiagnosticCodeActionGateConnection(responseDelay: .milliseconds(300))
            let lspFixture = LSPServiceFixture()
            let service = lspFixture.makeService()
            let session = try await DecorationsCoverageHost.open(
                in: directory,
                contents: Self.source,
                withWorkspace: true
            ) { fixture in
                makeCoordinators(for: fixture, service: service)
            }
            defer { session.close() }
            let coordinator = try #require(session.hosted.coordinator(ofType: DiagnosticHighlightCoordinator.self))
            let workspace = try #require(session.workspace)
            let server = try await makeGatedServer(in: directory, connection: connection)
            try await server.openDocument(session.fixture.document)
            service.languageClients[LSPService.ClientKey(.swift, directory.path() + "/")] = server
            session.textView.selectionManager.setSelectedRange(NSRange(location: 0, length: 0))

            workspace.diagnosticsStore.replace([diagnostic(at: session.fileURL, line: 0)], for: session.fileURL)
            try await eventually { connection.codeActionRequests >= 1 }
            let before = connection.codeActionRequests
            coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])

            try await eventually { coordinator.intentionAvailable(line: 0) }
            #expect(connection.codeActionRequests > before)
            #expect(coordinator.bulb.line == 0)
            service.languageClients[LSPService.ClientKey(.swift, directory.path() + "/")] = nil
        }
    }
}
