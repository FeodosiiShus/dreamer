import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("FormattingCapabilities", .uiGate)
struct FormattingCapabilitiesTests {
    private func server(
        registering methods: [String] = [],
        configure: (inout ServerCapabilities) -> Void = { _ in }
    ) async throws -> SyncTestServer.Server {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        configure(&capabilities)
        let connection = ScriptedServerConnection(capabilities: capabilities)
        let server = try await SyncTestServer.makeServer(connection: connection, capabilities: capabilities)
        server.dynamicCapabilities.register(methods.map { Registration(id: $0, method: $0) })
        return server
    }

    @Test
    func documentFormattingFollowsTheStaticProviderAndFallsBackToDynamicRegistration() async throws {
        let none = try await server()
        let registered = try await server(registering: ["textDocument/formatting"])
        let enabled = try await server { $0.documentFormattingProvider = .optionA(true) }
        let disabled = try await server(registering: ["textDocument/formatting"]) {
            $0.documentFormattingProvider = .optionA(false)
        }
        let options = try await server { $0.documentFormattingProvider = .optionB(WorkDoneProgressOptions()) }

        #expect(!none.supportsDocumentFormatting)
        #expect(registered.supportsDocumentFormatting)
        #expect(enabled.supportsDocumentFormatting)
        #expect(!disabled.supportsDocumentFormatting)
        #expect(options.supportsDocumentFormatting)
    }

    @Test
    func rangeFormattingFollowsTheStaticProviderAndFallsBackToDynamicRegistration() async throws {
        let none = try await server(registering: ["textDocument/formatting"])
        let registered = try await server(registering: ["textDocument/rangeFormatting"])
        let enabled = try await server { $0.documentRangeFormattingProvider = .optionA(true) }
        let disabled = try await server(registering: ["textDocument/rangeFormatting"]) {
            $0.documentRangeFormattingProvider = .optionA(false)
        }
        let options = try await server { $0.documentRangeFormattingProvider = .optionB(WorkDoneProgressOptions()) }

        #expect(!none.supportsRangeFormatting)
        #expect(registered.supportsRangeFormatting)
        #expect(enabled.supportsRangeFormatting)
        #expect(!disabled.supportsRangeFormatting)
        #expect(options.supportsRangeFormatting)
    }

    @Test
    func onTypeOptionsComeFromTheStaticProviderOrADynamicRegistration() async throws {
        let none = try await server()
        let staticOptions = DocumentOnTypeFormattingOptions(firstTriggerCharacter: "}", moreTriggerCharacter: [";"])
        let fromCapabilities = try await server { $0.documentOnTypeFormattingProvider = staticOptions }
        let dynamic = try await server()
        dynamic.dynamicCapabilities.register([
            Registration(
                id: "typing",
                method: "textDocument/onTypeFormatting",
                registerOptions: ["firstTriggerCharacter": "\n", "moreTriggerCharacter": [")"]]
            )
        ])

        #expect(none.onTypeFormattingOptions == nil)
        #expect(fromCapabilities.onTypeFormattingOptions == staticOptions)
        #expect(dynamic.onTypeFormattingOptions == DocumentOnTypeFormattingOptions(
            firstTriggerCharacter: "\n",
            moreTriggerCharacter: [")"]
        ))
    }
}

@MainActor
@Suite("OnTypeFormattingCoordinator", .uiGate)
struct OnTypeFormattingCoordinatorTests {
    private static let text = "foo {\n    x\n"
    private static let endOfText = 12
    private static let triggers = DocumentOnTypeFormattingOptions(firstTriggerCharacter: "}", moreTriggerCharacter: [";"])

    private func makeHarness(
        in directory: URL,
        onType: DocumentOnTypeFormattingOptions? = OnTypeFormattingCoordinatorTests.triggers
    ) async throws -> FormattingHarness {
        let harness = try await FormattingHarness.make(
            in: directory,
            text: Self.text,
            capabilities: FormattingHarness.capabilities(onType: onType),
            extraCoordinators: { document, service in
                [OnTypeFormattingCoordinator(codeFile: document, lspService: { service })]
            }
        )
        harness.document.indentOption = SettingsData.TextEditingSettings.IndentOption(
            indentType: .spaces,
            spaceCount: 2
        )
        harness.select(NSRange(location: Self.endOfText, length: 0))
        return harness
    }

    private func type(_ string: String, in harness: FormattingHarness) {
        let end = harness.textView.textStorage.length
        harness.textView.replaceCharacters(in: NSRange(location: end, length: 0), with: string)
    }

    private func semicolonAfterTheBrace() -> TextEdit {
        TextEdit(range: LSPRange(startPair: (2, 1), endPair: (2, 1)), newText: ";")
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    @Test
    func typingTheTriggerCharacterSendsOneRequestWithPositionCharacterAndOptionsAndAppliesTheEdits() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentOnTypeFormatting, [semicolonAfterTheBrace()])

            type("}", in: harness)

            try await eventually { harness.text == "foo {\n    x\n};" }
            let params = try #require(harness.connection.onTypeFormattingParams.first)
            #expect(harness.connection.onTypeFormattingParams.count == 1)
            #expect(params.ch == "}")
            #expect(params.position == Position(line: 2, character: 1))
            #expect(params.textDocument.uri == harness.uri)
            #expect(params.options == FormattingOptions(tabSize: 2, insertSpaces: true))
            #expect(harness.document.content?.string == "foo {\n    x\n};")
        }
    }

    @Test
    func theServerSeesTheTypedCharacterBeforeTheRequest() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }

            type("}", in: harness)

            try await eventually { harness.connection.onTypeFormattingParams.count == 1 }
            let order = harness.connection.log.filter {
                $0 == "textDocument/didChange" || $0 == "textDocument/onTypeFormatting"
            }
            #expect(order == ["textDocument/didChange", "textDocument/onTypeFormatting"])
        }
    }

    @Test
    func theSecondaryTriggerCharacterAlsoFires() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }

            type(";", in: harness)

            try await eventually { harness.connection.onTypeFormattingParams.count == 1 }
            #expect(harness.connection.onTypeFormattingParams.first?.ch == ";")
        }
    }

    @Test
    func nonTriggerCharactersAndPastesSendNothing() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }

            type("a", in: harness)
            harness.select(NSRange(location: harness.textView.textStorage.length, length: 0))
            type("}}", in: harness)
            harness.select(NSRange(location: harness.textView.textStorage.length, length: 0))
            type("a;", in: harness)
            try await settle()

            #expect(harness.connection.onTypeFormattingParams.isEmpty)
            #expect(harness.text == "foo {\n    x\na}}a;")
        }
    }

    @Test
    func aServerWithoutOnTypeFormattingIsNotAsked() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory, onType: nil)
            defer { harness.close() }

            type("}", in: harness)
            try await settle()

            #expect(harness.connection.onTypeFormattingParams.isEmpty)
        }
    }

    @Test
    func editsAwayFromTheCaretAreNotTypingAndSendNothing() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            harness.select(NSRange(location: 0, length: 0))

            type("}", in: harness)
            try await settle()

            #expect(harness.connection.onTypeFormattingParams.isEmpty)
        }
    }

    @Test
    func undoAndRedoDoNotTrigger() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            type("}", in: harness)
            try await eventually { harness.connection.onTypeFormattingParams.count == 1 }
            try await settle()

            harness.textView.undoManager?.undo()
            harness.textView.undoManager?.redo()
            try await settle()

            #expect(harness.connection.onTypeFormattingParams.count == 1)
        }
    }

    @Test
    func aResponseForTextThatChangedMeanwhileIsIgnored() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentOnTypeFormatting, [semicolonAfterTheBrace()])

            type("}", in: harness)
            harness.select(NSRange(location: harness.textView.textStorage.length, length: 0))
            type("x", in: harness)

            try await eventually { harness.connection.onTypeFormattingParams.count == 1 }
            try await settle()
            #expect(harness.text == "foo {\n    x\n}x")
        }
    }

    @Test
    func aNewerTriggerSupersedesAnInFlightOne() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            let bang = TextEdit(range: LSPRange(startPair: (2, 2), endPair: (2, 2)), newText: "!")
            try harness.connection.script(.textDocumentOnTypeFormatting, [bang])

            type("}", in: harness)
            type(";", in: harness)

            try await eventually { harness.text == "foo {\n    x\n};!" }
            try await settle()
            #expect(harness.text == "foo {\n    x\n};!")
        }
    }

    @Test
    func destroyingTheCoordinatorCancelsTheInFlightRequest() async throws {
        try await withTempDir { directory in
            let harness = try await makeHarness(in: directory)
            defer { harness.close() }
            let coordinator = try #require(harness.hosted.coordinator(ofType: OnTypeFormattingCoordinator.self))
            try harness.connection.script(.textDocumentOnTypeFormatting, [semicolonAfterTheBrace()])

            type("}", in: harness)
            coordinator.destroy()
            try await settle()

            #expect(harness.text == "foo {\n    x\n}")
        }
    }

    @Test
    func aCoordinatorWithoutAFileOrAServerIgnoresEdits() {
        let coordinator = OnTypeFormattingCoordinator(codeFile: CodeFileDocument(), lspService: { nil })
        let textView = TextView(string: "}")

        coordinator.storageDidEdit(in: textView, edited: NSRange(location: 0, length: 1))

        #expect(textView.string == "}")
    }

    @Test
    func theDefaultServiceLookupFindsNoServerForAnUnopenedFile() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "a.swift")
            try "}".write(to: url, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.swift-source")
            let coordinator = OnTypeFormattingCoordinator(codeFile: document)
            let textView = TextView(string: "}")

            coordinator.storageDidEdit(in: textView, edited: NSRange(location: 0, length: 1))

            #expect(textView.string == "}")
        }
    }
}
