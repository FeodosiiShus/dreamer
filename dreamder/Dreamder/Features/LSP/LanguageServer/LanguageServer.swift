//
//  LanguageServer.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import JSONRPC
import Foundation
import LanguageClient
import LanguageServerProtocol
import OSLog

/// A client for language servers.
class LanguageServer<DocumentType: LanguageServerDocument> {
    let logger: Logger

    /// Identifies which language the server belongs to
    let languageId: LSPLanguage
    /// Holds information about the language server binary
    let binary: LanguageServerBinary
    /// A cache to hold responses from the server, to minimize duplicate server requests
    let lspCache = LSPCache()

    let dynamicCapabilities = LSPDynamicCapabilityRegistry()
    let workDoneProgress = LSPWorkDoneProgressTracker()

    /// Tracks documents and their associated objects.
    /// Use this property when adding new objects that need to track file data, or have a state associated with the
    /// language server and a document. For example, the content coordinator.
    let openFiles: LanguageServerFileMap<DocumentType>

    let terminationEvents: AsyncStream<Void>

    let connectionGate: InitializationGatedConnection?

    /// Maps the language server's highlight config to one Dreamder can read. See ``SemanticTokenMap``.
    let highlightMap: SemanticTokenMap?

    /// The configuration options this server supports.
    var serverCapabilities: ServerCapabilities

    var logContainer: LanguageServerLogContainer

    /// An instance of a language server, that may or may not be initialized
    private(set) var lspInstance: InitializingServer
    /// The path to the root of the project
    private(set) var rootPath: URL
    /// The PID of the running language server process.
    private(set) var pid: pid_t
    var serverInfo: ServerInfo?

    init(
        languageId: LSPLanguage,
        binary: LanguageServerBinary,
        lspInstance: InitializingServer,
        lspPid: pid_t,
        serverCapabilities: ServerCapabilities,
        rootPath: URL,
        logContainer: LanguageServerLogContainer,
        terminationEvents: AsyncStream<Void> = AsyncStream<Void>.makeStream().stream,
        connectionGate: InitializationGatedConnection? = nil
    ) {
        self.terminationEvents = terminationEvents
        self.connectionGate = connectionGate
        self.languageId = languageId
        self.binary = binary
        self.lspInstance = lspInstance
        self.pid = lspPid
        self.serverCapabilities = serverCapabilities
        self.rootPath = rootPath
        self.openFiles = LanguageServerFileMap()
        self.logContainer = logContainer
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "",
            category: "LanguageServer.\(languageId.rawValue)"
        )
        if let semanticTokensProvider = serverCapabilities.semanticTokensProvider {
            self.highlightMap = SemanticTokenMap(semanticCapability: semanticTokensProvider)
        } else {
            self.highlightMap = nil // Server doesn't support semantic highlights
        }
    }

    /// Creates and initializes a language server.
    /// - Parameters:
    ///   - languageId: The id of the language to create.
    ///   - binary: The binary where the language server is stored.
    ///   - workspacePath: The path of the workspace being opened.
    /// - Returns: An initialized language server.
    static func createServer(
        for languageId: LSPLanguage,
        with binary: LanguageServerBinary,
        workspacePath: String
    ) async throws -> LanguageServer {
        let executionParams = Process.ExecutionParameters(
            path: binary.execPath,
            arguments: binary.args,
            environment: binary.env
        )

        let logContainer = LanguageServerLogContainer(languageID: languageId.rawValue)
        let (terminations, terminationContinuation) = AsyncStream<Void>.makeStream()
        let (connection, process) = try makeLocalServerConnection(
            languageId: languageId,
            executionParams: executionParams,
            logContainer: logContainer,
            onTermination: {
                terminationContinuation.yield()
                terminationContinuation.finish()
            }
        )
        let gate = InitializationGatedConnection(connection)
        let initializationOptions = await LanguageServerDiscovery.resolvedInitializationOptions(
            for: languageId,
            workspacePath: workspacePath,
            searchPaths: LSPProcessEnvironment.shared.searchPaths,
            inlayHints: Settings[\.textEditing].inlayHints
        )
        let server = InitializingServer(
            server: gate,
            initializeParamsProvider: getInitParams(
                workspacePath: workspacePath,
                initializationOptions: initializationOptions
            )
        )
        let initializationResponse = try await server.initializeIfNeeded()
        gate.open()

        let languageServer = LanguageServer(
            languageId: languageId,
            binary: binary,
            lspInstance: server,
            lspPid: process.processIdentifier,
            serverCapabilities: initializationResponse.capabilities,
            rootPath: URL(filePath: workspacePath),
            logContainer: logContainer,
            terminationEvents: terminations,
            connectionGate: gate
        )
        languageServer.serverInfo = initializationResponse.serverInfo
        return languageServer
    }

    // MARK: - Make Local Server Connection

    /// Creates a data channel for sending and receiving data with an LSP.
    /// - Parameters:
    ///   - languageId: The ID of the language to create the channel for.
    ///   - executionParams: The parameters for executing the local process.
    /// - Returns: A new connection to the language server.
    static func makeLocalServerConnection(
        languageId: LSPLanguage,
        executionParams: Process.ExecutionParameters,
        logContainer: LanguageServerLogContainer,
        onTermination: @escaping @Sendable () -> Void
    ) throws -> (connection: JSONRPCServerConnection, process: Process) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "LanguageServer")
        do {
            let (channel, process) = try DataChannel.localProcessChannel(
                parameters: executionParams,
                terminationHandler: { [weak logContainer] in
                    logger.debug("Terminated data channel for \(languageId.rawValue)")
                    Task { @MainActor in
                        logContainer?.appendLog(
                            LogMessageParams(type: .error, message: "Data Channel Terminated Unexpectedly")
                        )
                    }
                    onTermination()
                }
            )
            return (JSONRPCServerConnection(dataChannel: channel), process)
        } catch {
            logger.warning("Failed to initialize data channel for \(languageId.rawValue)")
            throw error
        }
    }

    // MARK: - Get Init Params

    nonisolated static func textDocumentCapabilities() -> TextDocumentClientCapabilities {
        let markupKinds: [MarkupKind] = [.markdown, .plaintext]
        var capabilities = TextDocumentClientCapabilities(
            completion: CompletionClientCapabilities(
                dynamicRegistration: true,
                completionItem: CompletionClientCapabilities.CompletionItem(
                    snippetSupport: true,
                    commitCharactersSupport: true,
                    documentationFormat: [MarkupKind.plaintext],
                    deprecatedSupport: true,
                    preselectSupport: true,
                    tagSupport: ValueSet(valueSet: [CompletionItemTag.deprecated]),
                    insertReplaceSupport: true,
                    resolveSupport: CompletionClientCapabilities.CompletionItem.ResolveSupport(
                        properties: ["documentation", "detail", "additionalTextEdits"]
                    ),
                    insertTextModeSupport: ValueSet(valueSet: [InsertTextMode.adjustIndentation]),
                    labelDetailsSupport: true
                ),
                completionItemKind: ValueSet<CompletionItemKind>.all,
                contextSupport: true,
                insertTextMode: InsertTextMode.asIs
            ),
            hover: HoverClientCapabilities(dynamicRegistration: false, contentFormat: markupKinds),
            signatureHelp: SignatureHelpClientCapabilities(
                dynamicRegistration: false,
                signatureInformation: SignatureHelpClientCapabilities.SignatureInformation(
                    documentationFormat: markupKinds,
                    labelOffsetSupport: true,
                    activeParameterSupport: true
                ),
                contextSupport: true
            ),
            documentSymbol: DocumentSymbolClientCapabilities(
                dynamicRegistration: false,
                symbolKind: ValueSet<SymbolKind>.all,
                hierarchicalDocumentSymbolSupport: true
            ),
            codeAction: CodeActionClientCapabilities(
                dynamicRegistration: false,
                codeActionLiteralSupport: CodeActionClientCapabilities.CodeActionLiteralSupport(
                    codeActionKind: ValueSet(valueSet: [
                        CodeActionKind.Quickfix,
                        CodeActionKind.Refactor,
                        CodeActionKind.RefactorExtract,
                        CodeActionKind.RefactorInline,
                        CodeActionKind.RefactorRewrite,
                        CodeActionKind.Source,
                        CodeActionKind.SourceOrganizeImports,
                        CodeActionKind.SourceFixAll
                    ])
                ),
                isPreferredSupport: true,
                disabledSupport: true,
                dataSupport: true,
                resolveSupport: CodeActionClientCapabilities.ResolveSupport(properties: ["edit"]),
                honorsChangeAnnotations: false
            ),
            rename: RenameClientCapabilities(
                dynamicRegistration: false,
                prepareSupport: true,
                prepareSupportDefaultBehavior: .Identifier,
                honorsChangeAnnotations: false
            ),
            publishDiagnostics: PublishDiagnosticsClientCapabilities(
                relatedInformation: true,
                tagSupport: ValueSet(valueSet: [DiagnosticTag.unnecessary, DiagnosticTag.deprecated]),
                versionSupport: true
            ),
            foldingRange: FoldingRangeClientCapabilities(dynamicRegistration: false, lineFoldingOnly: true),
            semanticTokens: SemanticTokensClientCapabilities(
                dynamicRegistration: false,
                requests: .init(range: false, delta: true),
                tokenTypes: SemanticTokenTypes.allStrings,
                tokenModifiers: SemanticTokenModifiers.allStrings,
                formats: [.relative],
                overlappingTokenSupport: true,
                multilineTokenSupport: true,
                serverCancelSupport: false,
                augmentsSyntaxTokens: true
            )
        )
        capabilities.inlayHint = InlayHintClientCapabilities(dynamicRegistration: false)
        return capabilities
    }

    nonisolated static func workspaceCapabilities() -> ClientCapabilities.Workspace {
        ClientCapabilities.Workspace(
            applyEdit: true,
            workspaceEdit: nil,
            didChangeConfiguration: DidChangeConfigurationClientCapabilities(dynamicRegistration: true),
            didChangeWatchedFiles: DidChangeWatchedFilesClientCapabilities(dynamicRegistration: true),
            symbol: WorkspaceSymbolClientCapabilities(
                dynamicRegistration: true,
                symbolKind: nil,
                tagSupport: nil,
                resolveSupport: []
            ),
            executeCommand: GenericDynamicRegistration(dynamicRegistration: false),
            workspaceFolders: true,
            configuration: true,
            semanticTokens: SemanticTokensWorkspaceClientCapabilities(refreshSupport: true),
            codeLens: nil,
            fileOperations: ClientCapabilities.Workspace.FileOperations(
                dynamicRegistration: true,
                didCreate: true,
                willCreate: true,
                didRename: true,
                willRename: true,
                didDelete: true,
                willDelete: true
            )
        )
    }

    nonisolated static func clientCapabilities() -> ClientCapabilities {
        ClientCapabilities(
            workspace: workspaceCapabilities(),
            textDocument: textDocumentCapabilities(),
            window: WindowClientCapabilities(
                workDoneProgress: true,
                showMessage: ShowMessageRequestClientCapabilities(
                    messageActionItem: ShowMessageRequestClientCapabilities.MessageActionItemCapabilities(
                        additionalPropertiesSupport: true
                    )
                ),
                showDocument: ShowDocumentClientCapabilities(
                    support: true
                )
            ),
            general: nil,
            experimental: nil
        )
    }

    nonisolated static func initializeParams(
        workspacePath: String,
        initializationOptions: LSPAny?
    ) -> InitializeParams {
        InitializeParams(
            processId: nil,
            locale: nil,
            rootPath: nil,
            rootUri: LSPWorkspaceFolders.uri(forWorkspacePath: workspacePath),
            initializationOptions: initializationOptions ?? [],
            capabilities: clientCapabilities(),
            trace: nil,
            workspaceFolders: [LSPWorkspaceFolders.folder(forWorkspacePath: workspacePath)]
        )
    }

    static func getInitParams(
        workspacePath: String,
        initializationOptions: LSPAny? = nil
    ) -> InitializingServer.InitializeParamsProvider {
        let params = initializeParams(workspacePath: workspacePath, initializationOptions: initializationOptions)
        let provider: InitializingServer.InitializeParamsProvider = { params }
        return provider
    }

    // MARK: - Shutdown

    /// Shuts down the language server and exits it.
    public func shutdown() async throws {
        self.logger.info("Shutting down language server")
        connectionGate?.close()
        workDoneProgress.shutDown()
        dynamicCapabilities.removeAll()
        try await self.lspInstance.shutdownAndExit()
    }
}

/// Represents a language server binary.
nonisolated struct LanguageServerBinary: Codable, Sendable {
    /// The path to the language server binary.
    let execPath: String
    /// The arguments to pass to the language server binary.
    let args: [String]
    /// The environment variables to pass to the language server binary.
    let env: [String: String]?
}

enum LSPError: Error {
    case binaryNotFound
}
