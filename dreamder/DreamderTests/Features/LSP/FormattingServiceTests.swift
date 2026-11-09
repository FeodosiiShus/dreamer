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

@MainActor
@Suite("FormattingService", .uiGate)
struct FormattingServiceTests {
    private static let original = "let  x = 1\n"
    private static let formatted = "let x = 1\n"

    @Test
    func wholeDocumentFormattingSendsTheOptionsAndAppliesTheEditsAsOneUndoStep() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            harness.document.indentOption = SettingsData.TextEditingSettings.IndentOption(
                indentType: .spaces,
                spaceCount: 2
            )
            try harness.scriptFormatting(.textDocumentFormatting, edits: [harness.spacesEdit()])

            let outcome = await harness.formattingService().formatDocument(harness.document)

            #expect(outcome == .applied)
            #expect(harness.text == Self.formatted)
            #expect(harness.document.content?.string == Self.formatted)
            let params = try #require(harness.connection.formattingParams.first)
            #expect(harness.connection.formattingParams.count == 1)
            #expect(params.textDocument.uri == harness.uri)
            #expect(params.options == FormattingOptions(tabSize: 2, insertSpaces: true))
            #expect(harness.connection.rangeFormattingParams.isEmpty)

            harness.textView.undoManager?.undo()

            #expect(harness.text == Self.original)
        }
    }

    @Test
    func reformatCodeWithASelectionSendsRangeFormattingWithTheSelectionRange() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            harness.select(NSRange(location: 4, length: 5))
            try harness.scriptFormatting(.textDocumentRangeFormatting, edits: [harness.spacesEdit()])

            let outcome = await harness.formattingService().reformatCode(harness.document)

            #expect(outcome == .applied)
            #expect(harness.text == Self.formatted)
            let params = try #require(harness.connection.rangeFormattingParams.first)
            #expect(harness.connection.rangeFormattingParams.count == 1)
            #expect(params.range == LSPRange(startPair: (0, 4), endPair: (0, 9)))
            #expect(params.textDocument.uri == harness.uri)
            #expect(harness.connection.formattingParams.isEmpty)
        }
    }

    @Test
    func reformatCodeWithACaretFormatsTheWholeDocument() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            harness.select(NSRange(location: 4, length: 0))
            try harness.scriptFormatting(.textDocumentFormatting, edits: [harness.spacesEdit()])

            let outcome = await harness.formattingService().reformatCode(harness.document)

            #expect(outcome == .applied)
            #expect(harness.connection.formattingParams.count == 1)
            #expect(harness.connection.rangeFormattingParams.isEmpty)
        }
    }

    @Test
    func aServerWithoutFormattingCapabilityIsNeverCalled() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(
                in: directory,
                capabilities: FormattingHarness.capabilities(formatting: false, rangeFormatting: false)
            )
            defer { harness.close() }
            let recorder = FormattingRecorder()
            let service = harness.formattingService(recorder: recorder)

            let document = await service.formatDocument(harness.document)
            let reformat = await service.reformatCode(harness.document)

            #expect(document == .unavailable)
            #expect(reformat == .unavailable)
            #expect(!service.canFormatDocument(harness.document))
            #expect(recorder.unavailableCount == 1)
            #expect(harness.connection.formattingParams.isEmpty)
            #expect(harness.connection.rangeFormattingParams.isEmpty)
            #expect(harness.text == Self.original)
        }
    }

    @Test
    func rangeFormattingNeedsItsOwnCapability() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(
                in: directory,
                capabilities: FormattingHarness.capabilities(formatting: true, rangeFormatting: false)
            )
            defer { harness.close() }
            harness.select(NSRange(location: 4, length: 5))
            let recorder = FormattingRecorder()

            let outcome = await harness.formattingService(recorder: recorder).reformatCode(harness.document)

            #expect(outcome == .unavailable)
            #expect(recorder.unavailableCount == 1)
            #expect(harness.connection.rangeFormattingParams.isEmpty)
            #expect(harness.connection.formattingParams.isEmpty)
        }
    }

    @Test
    func dynamicallyRegisteredFormattingEnablesTheFormatter() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(
                in: directory,
                capabilities: FormattingHarness.capabilities(formatting: false, rangeFormatting: false)
            )
            defer { harness.close() }
            let service = harness.formattingService()
            #expect(!service.canFormatDocument(harness.document))

            harness.client.dynamicCapabilities.register([
                Registration(id: "format", method: "textDocument/formatting")
            ])

            #expect(service.canFormatDocument(harness.document))
        }
    }

    @Test
    func prettierInTheWorkspaceIsPreferredOverTheServerAndItsOutputBecomesAMinimalUndoableEdit() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }
            let service = harness.formattingService(
                runner: runner,
                existing: [harness.binaryPath("prettier")],
                environment: ["PATH": "/opt/node/bin"]
            )
            harness.select(NSRange(location: 3, length: 0))

            let outcome = await service.reformatCode(harness.document)

            #expect(outcome == .applied)
            #expect(harness.text == "let x = 1;\n")
            let invocation = try #require(runner.invocations.first)
            #expect(runner.invocations.count == 1)
            #expect(invocation.executable.path(percentEncoded: false) == harness.binaryPath("prettier"))
            let filePath = try #require(harness.document.fileURL).path(percentEncoded: false)
            #expect(invocation.arguments == ["--stdin-filepath", filePath])
            #expect(invocation.workingDirectory == harness.directory)
            #expect(invocation.standardInput == Data("let  x=1\n".utf8))
            #expect(invocation.environment == ["PATH": "/opt/node/bin"])
            #expect(invocation.timeout == Duration.seconds(30))
            #expect(harness.connection.formattingParams.isEmpty)
            #expect(harness.connection.rangeFormattingParams.isEmpty)

            harness.textView.undoManager?.undo()

            #expect(harness.text == "let  x=1\n")
        }
    }

    @Test
    func prettierReceivesTheSelectionAsUTF16RangeFlags() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("prettier")])
            harness.select(NSRange(location: 4, length: 3))

            let outcome = await service.reformatCode(harness.document)

            #expect(outcome == .applied)
            let arguments = try #require(runner.invocations.first).arguments
            #expect(Array(arguments.suffix(4)) == ["--range-start", "4", "--range-end", "7"])
        }
    }

    @Test
    func aFailingExternalFormatterLeavesTheTextUntouchedAndReportsStderr() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let recorder = FormattingRecorder()
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("garbage", stderr: "bad syntax\n", exitCode: 2) }
            let service = harness.formattingService(
                runner: runner,
                existing: [harness.binaryPath("prettier")],
                recorder: recorder
            )

            let outcome = await service.formatDocument(harness.document)

            #expect(outcome == .failed)
            #expect(harness.text == "let  x=1\n")
            #expect(recorder.failures == ["bad syntax"])
            #expect(harness.connection.formattingParams.isEmpty)
        }
    }

    @Test
    func biomeCannotFormatASelectionSoTheServerRangeFormatterIsUsed() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("never used") }
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("biome")])
            harness.select(NSRange(location: 4, length: 3))
            try harness.scriptFormatting(.textDocumentRangeFormatting, edits: [harness.spacesEdit()])

            let outcome = await service.reformatCode(harness.document)

            #expect(outcome == .applied)
            #expect(runner.invocations.isEmpty)
            #expect(harness.connection.rangeFormattingParams.count == 1)
        }
    }

    @Test
    func biomeFormatsTheWholeFileThroughStdin() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("biome")])

            let outcome = await service.formatDocument(harness.document)

            #expect(outcome == .applied)
            let filePath = try #require(harness.document.fileURL).path(percentEncoded: false)
            #expect(try #require(runner.invocations.first).arguments == ["format", "--stdin-file-path=\(filePath)"])
        }
    }

    @Test
    func identicalExternalOutputAndEmptyServerAnswersChangeNothing() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let x = 1\n")
            defer { harness.close() }
            let external = harness.formattingService(
                runner: FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1\n") },
                existing: [harness.binaryPath("prettier")]
            )
            let server = harness.formattingService()

            let fromFormatter = await external.formatDocument(harness.document)
            let fromServerWithoutAnswer = await server.formatDocument(harness.document)
            try harness.scriptFormatting(.textDocumentFormatting, edits: [])
            let fromServerWithNoEdits = await server.formatDocument(harness.document)

            #expect(fromFormatter == .unchanged)
            #expect(fromServerWithoutAnswer == .unchanged)
            #expect(fromServerWithNoEdits == .unchanged)
            #expect(harness.text == "let x = 1\n")
        }
    }

    @Test
    func aFailingServerRequestAndInvalidEditsAreReportedAndLeaveTheTextAlone() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            let recorder = FormattingRecorder()
            let service = harness.formattingService(recorder: recorder)
            try harness.connection.script(.textDocumentFormatting, "not edits")

            let malformed = await service.formatDocument(harness.document)

            let outOfRange = TextEdit(range: LSPRange(startPair: (9, 0), endPair: (9, 1)), newText: "x")
            try harness.scriptFormatting(.textDocumentFormatting, edits: [outOfRange])
            let invalid = await service.formatDocument(harness.document)

            #expect(malformed == .failed)
            #expect(invalid == .failed)
            #expect(recorder.failures.count == 2)
            #expect(harness.text == Self.original)
        }
    }

    @Test
    func anEditorThatIsNotEditableCannotBeFormatted() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            harness.textView.isEditable = false
            let service = harness.formattingService()

            #expect(!service.canFormatDocument(harness.document))
            #expect(await service.formatDocument(harness.document) == .unavailable)
            #expect(harness.connection.formattingParams.isEmpty)
        }
    }

    @Test
    func aDocumentWithoutAnEditorOrAFileIsUnavailable() async throws {
        let service = FormattingService(lspService: { nil }, fileExists: { _ in false }, workspaceRoot: { _ in nil })

        #expect(await service.formatDocument(CodeFileDocument()) == .unavailable)
    }

    @Test
    func textChangedWhileTheFormatterRanIsNotOverwritten() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory, fileName: "app.ts", text: "let  x=1\n")
            defer { harness.close() }
            let textView = harness.textView
            let runner = FormattingTestRunner(
                beforeReturning: {
                    await MainActor.run {
                        textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// typed\n")
                    }
                },
                output: FakeProcessRunner.output("let x = 1;\n")
            )
            let service = harness.formattingService(runner: runner, existing: [harness.binaryPath("prettier")])

            let outcome = await service.formatDocument(harness.document)

            #expect(outcome == .failed)
            #expect(harness.text == "// typed\nlet  x=1\n")
        }
    }

    @Test
    func aCancelledFormatNeverAppliesItsResult() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            try harness.scriptFormatting(.textDocumentFormatting, edits: [harness.spacesEdit()])
            let service = harness.formattingService()
            let document = harness.document

            let task = Task { await service.formatDocument(document) }
            task.cancel()
            let outcome = await task.value

            #expect(outcome == .failed)
            #expect(harness.text == Self.original)
        }
    }

    @Test
    func formattingOptionsFollowTheEffectiveIndent() {
        let spaces = CodeFileDocument()
        spaces.indentOption = SettingsData.TextEditingSettings.IndentOption(indentType: .spaces, spaceCount: 3)
        let tabs = CodeFileDocument()
        tabs.indentOption = SettingsData.TextEditingSettings.IndentOption(indentType: .tab)
        tabs.defaultTabWidth = 8

        #expect(spaces.formattingOptions == FormattingOptions(tabSize: 3, insertSpaces: true))
        #expect(tabs.formattingOptions == FormattingOptions(tabSize: 8, insertSpaces: false))
    }

    @Test
    func defaultCollaboratorsTalkToTheSharedServicesAndTheFileSystem() async throws {
        try await withTempDir { directory in
            let harness = try await FormattingHarness.make(in: directory)
            defer { harness.close() }
            let service = FormattingService()
            let root = try #require(service.workspaceRoot(harness.document))

            #expect(service.fileExists("/bin/sh"))
            #expect(!service.fileExists(directory.appending(path: "missing").path(percentEncoded: false)))
            #expect(root.resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path)
            #expect(service.externalTimeout == Duration.seconds(30))
            _ = service.lspService()
            service.reportFailure("a formatter failed")
            service.reportUnavailable()
        }
    }
}
