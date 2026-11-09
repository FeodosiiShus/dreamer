import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension ScriptedServerConnection {
    var formattingParams: [DocumentFormattingParams] {
        requests.compactMap { request in
            guard case let .formatting(params, _) = request else { return nil }
            return params
        }
    }

    var rangeFormattingParams: [DocumentRangeFormattingParams] {
        requests.compactMap { request in
            guard case let .rangeFormatting(params, _) = request else { return nil }
            return params
        }
    }

    var onTypeFormattingParams: [DocumentOnTypeFormattingParams] {
        requests.compactMap { request in
            guard case let .onTypeFormatting(params, _) = request else { return nil }
            return params
        }
    }
}

@MainActor
final class FormattingRecorder {
    var failures: [String] = []
    var unavailableCount = 0
}

struct FormattingTestRunner: ProcessRunning {
    let beforeReturning: @Sendable () async -> Void
    let output: ProcessOutput

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        await beforeReturning()
        return output
    }
}

@MainActor
struct FormattingHarness {
    let fixture: LSPServiceFixture
    let service: LSPService
    let workspace: LSPServiceWorkspace
    let document: CodeFileDocument
    let client: LSPService.LanguageServerType
    let connection: ScriptedServerConnection
    let hosted: HostedSourceEditor
    let textView: TextView
    let fileName: String

    var directory: URL { workspace.directory }
    var uri: String { workspace.uri(fileName) }
    var text: String { textView.string }

    static func capabilities(
        formatting: Bool = true,
        rangeFormatting: Bool = true,
        onType: DocumentOnTypeFormattingOptions? = nil,
        codeActions: Bool = false
    ) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.documentFormattingProvider = formatting ? .optionA(true) : nil
        capabilities.documentRangeFormattingProvider = rangeFormatting ? .optionA(true) : nil
        capabilities.documentOnTypeFormattingProvider = onType
        capabilities.codeActionProvider = codeActions ? .optionA(true) : nil
        return capabilities
    }

    static func make(
        in directory: URL,
        fileName: String = "main.swift",
        text: String = "let  x = 1\n",
        capabilities: ServerCapabilities = FormattingHarness.capabilities(),
        extraCoordinators: (CodeFileDocument, LSPService) -> [TextViewCoordinator] = { _, _ in [] }
    ) async throws -> FormattingHarness {
        let fixture = LSPServiceFixture()
        fixture.capabilities = capabilities
        let service = fixture.makeService()
        let workspace = try LSPServiceWorkspace(directory: directory, files: [fileName: text])
        let document = try workspace.document(fileName)
        service.openDocument(document)
        await service.waitForDocumentOperations()
        let created = try #require(fixture.created.first)
        let fileURL = try #require(document.fileURL)
        let client = try #require(service.languageClient(forDocument: fileURL))
        let editorFixture = HostedSourceEditorFixture(
            document: document,
            editorInstance: EditorInstance(workspace: nil, file: CEWorkspaceFile(url: fileURL))
        )
        let hosted = editorFixture.host(
            coordinators: [
                document.contentCoordinator,
                document.textViewBinder,
                document.languageServerObjects.textCoordinator
            ] + extraCoordinators(document, service),
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { document.attachedTextView != nil }
        let textView = try #require(document.attachedTextView)
        return FormattingHarness(
            fixture: fixture,
            service: service,
            workspace: workspace,
            document: document,
            client: client,
            connection: created.connection,
            hosted: hosted,
            textView: textView,
            fileName: fileName
        )
    }

    func close() {
        hosted.close()
        workspace.close()
    }

    func formattingService(
        runner: any ProcessRunning = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) },
        existing: Set<String> = [],
        trusted: Bool = true,
        environment: [String: String] = [:],
        recorder: FormattingRecorder = FormattingRecorder()
    ) -> FormattingService {
        let root = directory
        let sharedService = service
        return FormattingService(
            lspService: { sharedService },
            runner: runner,
            fileExists: { existing.contains($0) },
            workspaceRoot: { _ in root },
            isWorkspaceTrusted: { _ in trusted },
            processEnvironment: { environment },
            reportFailure: { recorder.failures.append($0) },
            reportUnavailable: { recorder.unavailableCount += 1 }
        )
    }

    func binaryPath(_ name: String) -> String {
        directory
            .appending(path: "node_modules", directoryHint: .isDirectory)
            .appending(path: ".bin", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .notDirectory)
            .path(percentEncoded: false)
    }

    func select(_ range: NSRange) {
        textView.selectionManager.setSelectedRange(range)
    }

    func scriptFormatting(_ method: ClientRequest.Method, edits: [TextEdit]) throws {
        try connection.script(method, edits)
    }

    func spacesEdit() -> TextEdit {
        TextEdit(range: LSPRange(startPair: (0, 3), endPair: (0, 5)), newText: " ")
    }
}
