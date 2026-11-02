//
//  LanguageServerDocument.swift
//  Dreamder
//
//  Created by Khan Winter on 2/12/25.
//

import AppKit
import CodeEditLanguages

/// A set of properties a language server sets when a document is registered.
struct LanguageServerDocumentObjects<DocumentType: LanguageServerDocument> {
    var textCoordinator: LSPContentCoordinator<DocumentType> = LSPContentCoordinator()
    // swiftlint:disable:next line_length
    var highlightProvider: SemanticTokenHighlightProvider<SemanticTokenStorage, DocumentType> = SemanticTokenHighlightProvider()
    var completionDelegate: LSPCompletionDelegate<DocumentType>?
    var jumpToDefinitionDelegate: LSPJumpToDefinitionDelegate<DocumentType>?

    @MainActor
    mutating func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        textCoordinator.setUp(server: server, document: document)
        highlightProvider.setUp(server: server, document: document)

        let completion = completionDelegate ?? LSPCompletionDelegate()
        completion.setUp(server: server, document: document)
        completionDelegate = completion

        let jump = jumpToDefinitionDelegate ?? LSPJumpToDefinitionDelegate()
        jump.setUp(server: server, document: document)
        jumpToDefinitionDelegate = jump
    }

    @MainActor
    func tearDown() {
        completionDelegate?.reset()
        jumpToDefinitionDelegate?.reset()
    }
}

/// A protocol that allows a language server to register objects on a text document.
protocol LanguageServerDocument: AnyObject {
    var content: NSTextStorage? { get }
    var languageServerURI: String? { get }
    var languageServerObjects: LanguageServerDocumentObjects<Self> { get set }
    func getLanguage() -> CodeLanguage
}
