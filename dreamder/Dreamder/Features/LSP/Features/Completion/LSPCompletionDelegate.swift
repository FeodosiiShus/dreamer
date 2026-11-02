import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

final class LSPCompletionDelegate<DocumentType: LanguageServerDocument>: CodeSuggestionDelegate {
    private weak var languageServer: LanguageServer<DocumentType>?
    private var documentURI: String?
    private var suggestions: [LSPCompletionSuggestion] = []

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
        suggestions = []
    }

    func reset() {
        languageServer = nil
        documentURI = nil
        suggestions = []
    }

    @MainActor
    func completionTriggerCharacters() -> Set<String> {
        guard let provider = languageServer?.serverCapabilities.completionProvider else {
            return []
        }
        guard let triggerCharacters = provider.triggerCharacters, !triggerCharacters.isEmpty else {
            return [".", "\"", "(", "[", "<", "/", "'"]
        }
        return Set(triggerCharacters)
    }

    @MainActor
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let server = languageServer, let documentURI else {
            suggestions = []
            return nil
        }
        let position = Position(
            line: max(cursorPosition.start.line, 1) - 1,
            character: max(cursorPosition.start.column, 1) - 1
        )
        let triggerCharacter = LSPCompletionMapping.triggerCharacter(
            in: textView.textView.string,
            before: cursorPosition.range.location
        )
        do {
            let response = try await server.requestCompletion(
                for: documentURI,
                position: position,
                triggerCharacter: triggerCharacter
            )
            let items = LSPCompletionMapping.sorted(response?.items ?? [])
            suggestions = LSPCompletionMapping.suggestions(from: items)
            guard !suggestions.isEmpty else { return nil }
            return (windowPosition: cursorPosition, items: suggestions.map { $0 as CodeSuggestionEntry })
        } catch {
            suggestions = []
            return nil
        }
    }

    @MainActor
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard !suggestions.isEmpty else { return nil }
        let prefix = LSPCompletionMapping.prefix(
            in: textView.textView.string,
            before: cursorPosition.range.location
        )
        return LSPCompletionMapping.filtered(suggestions, prefix: prefix)
            .map { $0 as CodeSuggestionEntry }
    }

    @MainActor
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let suggestion = item as? LSPCompletionSuggestion else { return }
        let replacementRange = suggestion.replacementRange
            .flatMap { LSPTextPositionConverter.nsRange(from: $0, in: textView.textView) }
            ?? prefixRange(textView: textView, cursorPosition: cursorPosition)
        textView.textView.replaceCharacters(in: replacementRange, with: suggestion.insertionText)
    }

    @MainActor
    private func prefixRange(textView: TextViewController, cursorPosition: CursorPosition?) -> NSRange {
        let location = cursorPosition?.range.location
            ?? textView.cursorPositions.first?.range.location
            ?? textView.textView.string.utf16.count
        let prefix = LSPCompletionMapping.prefix(in: textView.textView.string, before: location)
        return NSRange(location: location - prefix.utf16.count, length: prefix.utf16.count)
    }
}
