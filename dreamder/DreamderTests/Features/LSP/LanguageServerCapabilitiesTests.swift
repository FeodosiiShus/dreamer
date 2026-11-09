import AppKit
import CodeEditLanguages
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("Language server client capabilities", .uiGate)
struct LanguageServerCapabilitiesTests {
    @MainActor
    final class CapabilitiesDocument: LanguageServerDocument {
        var content: NSTextStorage?
        var languageServerURI: String?
        var languageServerObjects: LanguageServerDocumentObjects<CapabilitiesDocument>

        init() {
            self.content = NSTextStorage(string: "")
            self.languageServerURI = nil
            self.languageServerObjects = .init()
        }

        func getLanguage() -> CodeLanguage {
            .swift
        }
    }

    typealias Server = LanguageServer<CapabilitiesDocument>

    private func encoded<T: Encodable>(_ value: T) throws -> NSDictionary {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? NSDictionary)
    }

    private func capabilities() throws -> NSDictionary {
        try encoded(Server.clientCapabilities())
    }

    private func sortedInts(_ value: Any?) -> [Int]? {
        (value as? [Int])?.sorted()
    }

    @Test func booleanCapabilitiesAreAdvertised() throws {
        let json = try capabilities()
        let expectations: [(String, Bool)] = [
            ("textDocument.completion.dynamicRegistration", true),
            ("textDocument.completion.contextSupport", true),
            ("textDocument.completion.completionItem.snippetSupport", true),
            ("textDocument.completion.completionItem.commitCharactersSupport", true),
            ("textDocument.completion.completionItem.deprecatedSupport", true),
            ("textDocument.completion.completionItem.preselectSupport", true),
            ("textDocument.completion.completionItem.insertReplaceSupport", true),
            ("textDocument.completion.completionItem.labelDetailsSupport", true),
            ("textDocument.hover.dynamicRegistration", false),
            ("textDocument.signatureHelp.dynamicRegistration", false),
            ("textDocument.signatureHelp.contextSupport", true),
            ("textDocument.signatureHelp.signatureInformation.parameterInformation.labelOffsetSupport", true),
            ("textDocument.signatureHelp.signatureInformation.activeParameterSupport", true),
            ("textDocument.documentSymbol.dynamicRegistration", false),
            ("textDocument.documentSymbol.hierarchicalDocumentSymbolSupport", true),
            ("textDocument.codeAction.dynamicRegistration", false),
            ("textDocument.codeAction.isPreferredSupport", true),
            ("textDocument.codeAction.disabledSupport", true),
            ("textDocument.codeAction.dataSupport", true),
            ("textDocument.codeAction.honorsChangeAnnotations", false),
            ("textDocument.rename.dynamicRegistration", false),
            ("textDocument.rename.prepareSupport", true),
            ("textDocument.rename.honorsChangeAnnotations", false),
            ("textDocument.publishDiagnostics.relatedInformation", true),
            ("textDocument.publishDiagnostics.versionSupport", true),
            ("textDocument.foldingRange.dynamicRegistration", false),
            ("textDocument.foldingRange.lineFoldingOnly", true),
            ("textDocument.semanticTokens.dynamicRegistration", false),
            ("textDocument.semanticTokens.requests.range", false),
            ("textDocument.semanticTokens.requests.full.delta", true),
            ("textDocument.semanticTokens.overlappingTokenSupport", true),
            ("textDocument.semanticTokens.multilineTokenSupport", true),
            ("textDocument.semanticTokens.serverCancelSupport", false),
            ("textDocument.semanticTokens.augmentsSyntaxTokens", true),
            ("textDocument.inlayHint.dynamicRegistration", false),
            ("workspace.applyEdit", true),
            ("workspace.workspaceFolders", true),
            ("workspace.configuration", true),
            ("workspace.didChangeConfiguration.dynamicRegistration", true),
            ("workspace.didChangeWatchedFiles.dynamicRegistration", true),
            ("workspace.executeCommand.dynamicRegistration", false),
            ("workspace.symbol.dynamicRegistration", true),
            ("workspace.fileOperations.dynamicRegistration", true),
            ("workspace.fileOperations.didCreate", true),
            ("workspace.fileOperations.willCreate", true),
            ("workspace.fileOperations.didRename", true),
            ("workspace.fileOperations.willRename", true),
            ("workspace.fileOperations.didDelete", true),
            ("workspace.fileOperations.willDelete", true),
            ("window.workDoneProgress", true),
            ("window.showMessage.messageActionItem.additionalPropertiesSupport", true),
            ("workspace.semanticTokens.refreshSupport", true),
            ("window.showDocument.support", true)
        ]
        for (keyPath, expected) in expectations {
            let actual = json.value(forKeyPath: keyPath) as? Bool
            #expect(actual == expected, "\(keyPath)")
        }
    }

    @Test func stringListCapabilitiesAreAdvertised() throws {
        let json = try capabilities()
        let expectations: [(String, [String])] = [
            ("textDocument.hover.contentFormat", ["markdown", "plaintext"]),
            ("textDocument.signatureHelp.signatureInformation.documentationFormat", ["markdown", "plaintext"]),
            ("textDocument.completion.completionItem.documentationFormat", ["plaintext"]),
            (
                "textDocument.completion.completionItem.resolveSupport.properties",
                ["documentation", "detail", "additionalTextEdits"]
            ),
            ("textDocument.codeAction.resolveSupport.properties", ["edit"]),
            (
                "textDocument.codeAction.codeActionLiteralSupport.codeActionKind.valueSet",
                [
                    "quickfix",
                    "refactor",
                    "refactor.extract",
                    "refactor.inline",
                    "refactor.rewrite",
                    "source",
                    "source.organizeImports",
                    "source.fixAll"
                ]
            ),
            ("textDocument.semanticTokens.formats", ["relative"]),
            ("textDocument.semanticTokens.tokenTypes", SemanticTokenTypes.allStrings),
            ("textDocument.semanticTokens.tokenModifiers", SemanticTokenModifiers.allStrings)
        ]
        for (keyPath, expected) in expectations {
            #expect(json.value(forKeyPath: keyPath) as? [String] == expected, "\(keyPath)")
        }
    }

    @Test func integerListCapabilitiesAreAdvertised() throws {
        let json = try capabilities()
        let expectations: [(String, [Int])] = [
            ("textDocument.completion.completionItemKind.valueSet", Array(1...25)),
            ("textDocument.documentSymbol.symbolKind.valueSet", Array(1...26)),
            ("textDocument.publishDiagnostics.tagSupport.valueSet", [1, 2]),
            ("textDocument.completion.completionItem.tagSupport.valueSet", [1]),
            ("textDocument.completion.completionItem.insertTextModeSupport.valueSet", [2])
        ]
        for (keyPath, expected) in expectations {
            #expect(sortedInts(json.value(forKeyPath: keyPath)) == expected, "\(keyPath)")
        }
    }

    @Test func scalarCapabilitiesAreAdvertised() throws {
        let json = try capabilities()
        #expect(json.value(forKeyPath: "textDocument.rename.prepareSupportDefaultBehavior") as? Int == 1)
        #expect(json.value(forKeyPath: "textDocument.completion.insertTextMode") as? Int == 1)
    }

    @Test func inlayHintSurvivesDespiteThePackageInitDroppingIt() throws {
        let textDocument = Server.textDocumentCapabilities()
        #expect(textDocument.inlayHint == InlayHintClientCapabilities(dynamicRegistration: false))
        let json = try capabilities()
        #expect(json.value(forKeyPath: "textDocument.inlayHint") != nil)
    }

    @Test func workspaceCapabilitiesAreExposedSeparately() throws {
        let workspace = Server.workspaceCapabilities()
        #expect(workspace.workspaceFolders == true)
        #expect(workspace.didChangeWatchedFiles == DidChangeWatchedFilesClientCapabilities(dynamicRegistration: true))
        #expect(workspace.executeCommand == GenericDynamicRegistration(dynamicRegistration: false))
        #expect(workspace.semanticTokens == SemanticTokensWorkspaceClientCapabilities(refreshSupport: true))
        #expect(workspace.codeLens == nil)
        #expect(Server.clientCapabilities().workspace == workspace)
        #expect(Server.clientCapabilities().textDocument == Server.textDocumentCapabilities())
    }

    @Test func omittedSectionsStayAbsent() throws {
        let json = try capabilities()
        #expect(json["general"] == nil)
        #expect(json["experimental"] == nil)
        #expect(json.value(forKeyPath: "workspace.workspaceEdit") == nil)
        #expect(json.value(forKeyPath: "workspace.codeLens") == nil)
        #expect(json.value(forKeyPath: "workspace.inlayHint") == nil)
        #expect(json.value(forKeyPath: "workspace.diagnostics") == nil)
    }

    @Test func initializeParamsPercentEncodeTheRootUriAndListTheFolder() throws {
        let params = Server.initializeParams(workspacePath: "/Users/me/My Project", initializationOptions: nil)
        #expect(params.rootUri == "file:///Users/me/My%20Project")
        #expect(params.rootPath == nil)
        #expect(params.processId == nil)
        #expect(params.workspaceFolders == [
            WorkspaceFolder(uri: "file:///Users/me/My%20Project", name: "My Project")
        ])
        #expect(params.capabilities == Server.clientCapabilities())

        let json = try encoded(params)
        #expect(json["rootUri"] as? String == "file:///Users/me/My%20Project")
        let folders = try #require(json["workspaceFolders"] as? [[String: String]])
        #expect(folders == [["uri": "file:///Users/me/My%20Project", "name": "My Project"]])
    }

    @Test func initializationOptionsDefaultToAnEmptyArray() throws {
        let params = Server.initializeParams(workspacePath: "/w", initializationOptions: nil)
        #expect(params.initializationOptions == [])
        let json = try encoded(params)
        #expect((json["initializationOptions"] as? [Any])?.isEmpty == true)
    }

    @Test func initializationOptionsPassThrough() {
        let options: LSPAny = .hash(["tsserver": .hash(["path": .string("/x/tsserver.js")])])
        let params = Server.initializeParams(workspacePath: "/w", initializationOptions: options)
        #expect(params.initializationOptions == options)
    }

    @Test func initParamsProviderReturnsTheSameParamsWhenAwaited() async throws {
        let options: LSPAny = .hash(["a": .string("b")])
        let provider = Server.getInitParams(workspacePath: "/Users/me/My Project", initializationOptions: options)
        let awaited = try await provider()
        #expect(awaited == Server.initializeParams(workspacePath: "/Users/me/My Project", initializationOptions: options))

        let defaulted = try await Server.getInitParams(workspacePath: "/w")()
        #expect(defaulted == Server.initializeParams(workspacePath: "/w", initializationOptions: nil))
    }
}

@Suite("LSP workspace folders")
struct LSPWorkspaceFoldersTests {
    private static let uriCases: [(String, String)] = [
        ("/Users/me/project", "file:///Users/me/project"),
        ("/Users/me/My Project", "file:///Users/me/My%20Project"),
        ("/tmp/a#b", "file:///tmp/a%23b"),
        ("/tmp/100%", "file:///tmp/100%25"),
        ("/tmp/a?b", "file:///tmp/a%3Fb"),
        ("/tmp/проект", "file:///tmp/%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82"),
        ("/tmp/日本", "file:///tmp/%E6%97%A5%E6%9C%AC")
    ]

    @Test(arguments: uriCases)
    func uriIsPercentEncoded(path: String, expected: String) {
        #expect(LSPWorkspaceFolders.uri(forWorkspacePath: path) == expected)
    }

    @Test func trailingSlashDoesNotChangeTheFolderName() {
        let uri = LSPWorkspaceFolders.uri(forWorkspacePath: "/tmp/dir/")
        #expect(uri.hasPrefix("file:///tmp/dir"))
        #expect(LSPWorkspaceFolders.folder(forWorkspacePath: "/tmp/dir/").name == "dir")
        #expect(LSPWorkspaceFolders.folder(forWorkspacePath: "/tmp/dir/").uri == uri)
    }

    @Test func folderUsesTheEncodedUriAndTheLastComponentAsName() {
        let folder = LSPWorkspaceFolders.folder(forWorkspacePath: "/Users/me/My Project #1")
        #expect(folder == WorkspaceFolder(uri: "file:///Users/me/My%20Project%20%231", name: "My Project #1"))
    }
}
