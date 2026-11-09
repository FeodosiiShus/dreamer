import Foundation
import LanguageClient
import LanguageServerProtocol

extension LanguageServer {
    // MARK: - Get Init Params

    nonisolated static func textDocumentCapabilities() -> TextDocumentClientCapabilities {
        let markupKinds: [MarkupKind] = [.markdown, .plaintext]
        var capabilities = TextDocumentClientCapabilities(
            completion: completionCapabilities(),
            hover: HoverClientCapabilities(dynamicRegistration: false, contentFormat: markupKinds),
            signatureHelp: signatureHelpCapabilities(markupKinds: markupKinds),
            documentSymbol: DocumentSymbolClientCapabilities(
                dynamicRegistration: false,
                symbolKind: ValueSet<SymbolKind>.all,
                hierarchicalDocumentSymbolSupport: true
            ),
            codeAction: codeActionCapabilities(),
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
            semanticTokens: semanticTokensCapabilities()
        )
        capabilities.inlayHint = InlayHintClientCapabilities(dynamicRegistration: false)
        return capabilities
    }

    private nonisolated static func completionCapabilities() -> CompletionClientCapabilities {
        CompletionClientCapabilities(
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
        )
    }

    private nonisolated static func signatureHelpCapabilities(
        markupKinds: [MarkupKind]
    ) -> SignatureHelpClientCapabilities {
        SignatureHelpClientCapabilities(
            dynamicRegistration: false,
            signatureInformation: SignatureHelpClientCapabilities.SignatureInformation(
                documentationFormat: markupKinds,
                labelOffsetSupport: true,
                activeParameterSupport: true
            ),
            contextSupport: true
        )
    }

    private nonisolated static func codeActionCapabilities() -> CodeActionClientCapabilities {
        CodeActionClientCapabilities(
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
        )
    }

    private nonisolated static func semanticTokensCapabilities() -> SemanticTokensClientCapabilities {
        SemanticTokensClientCapabilities(
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
}
