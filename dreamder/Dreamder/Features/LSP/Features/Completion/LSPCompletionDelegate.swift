import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

final class LSPCompletionDelegate<DocumentType: LanguageServerDocument>: CodeSuggestionDelegate {
    private weak var languageServer: LanguageServer<DocumentType>?
    private weak var activeController: TextViewController?
    private var documentURI: String?
    private var fileURL: URL?
    private var suggestions: [LSPCompletionSuggestion] = []
    private var requestContext: LSPCompletionRequestContext?
    private var isIncomplete = false
    private var incompletePrefix = ""
    private var selected: LSPCompletionSuggestion?
    private var observedCursor = 0
    private var observedLength = 0
    private var incompleteTask: Task<Void, Never>?
    private(set) var snippetSession: SnippetSession?

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        clearState()
        languageServer = server
        documentURI = document.languageServerURI
        fileURL = document.languageServerURI.flatMap { URL(string: $0) }
    }

    func reset() {
        clearState()
        languageServer = nil
        documentURI = nil
        fileURL = nil
    }

    private func clearState() {
        incompleteTask?.cancel()
        incompleteTask = nil
        snippetSession?.cancel()
        snippetSession = nil
        suggestions = []
        requestContext = nil
        isIncomplete = false
        incompletePrefix = ""
        selected = nil
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
        incompleteTask?.cancel()
        activeController = textView
        let requestOffset = currentCaret(in: textView) ?? cursorPosition.range.location
        guard let position = lspPosition(forOffset: requestOffset, in: textView.textView) else {
            suggestions = []
            return nil
        }
        let triggerCharacter = LSPCompletionMapping.triggerCharacter(
            in: textView.textView.string,
            before: requestOffset
        )
        do {
            let response = try await server.requestCompletion(
                for: documentURI,
                position: position,
                triggerCharacter: triggerCharacter
            )
            install(response, server: server, position: position)
            let caret = currentCaret(in: textView) ?? requestOffset
            incompletePrefix = LSPCompletionMapping.prefix(in: textView.textView.string, before: caret)
            observe(textView: textView, caret: caret)
            let entries = ranked(in: textView, caret: caret)
            guard !entries.isEmpty else { return nil }
            return (
                windowPosition: CursorPosition(range: NSRange(location: caret, length: 0)),
                items: entries.map { $0 as CodeSuggestionEntry }
            )
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
        let caret = cursorPosition.range.location
        let text = textView.textView.string
        if let committing = committingSuggestion(text: text, caret: caret) {
            Task { @MainActor in
                self.apply(committing, in: textView, caret: caret - 1, trailingCaretOffset: 1, allowsSnippet: false)
            }
            return nil
        }
        observe(textView: textView, caret: caret)
        let prefix = LSPCompletionMapping.prefix(in: text, before: caret)
        if isIncomplete, prefix != incompletePrefix {
            incompletePrefix = prefix
            refreshIncomplete(in: textView, caret: caret)
        }
        return ranked(in: textView, caret: caret).map { $0 as CodeSuggestionEntry }
    }

    @MainActor
    func completionWindowDidSelect(item: CodeSuggestionEntry) {
        guard let suggestion = item as? LSPCompletionSuggestion else { return }
        selected = suggestion
        guard suggestion.state.needsResolution else { return }
        guard let resolver = makeResolver() else {
            suggestion.state.markResolved()
            return
        }
        Task { @MainActor [weak self] in
            await suggestion.state.resolve(using: resolver)
            self?.didResolve(suggestion)
        }
    }

    @MainActor
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let suggestion = item as? LSPCompletionSuggestion else { return }
        guard let caret = cursorPosition?.range.location ?? currentCaret(in: textView) else { return }
        guard !suggestion.state.isResolved, let resolver = makeResolver() else {
            apply(suggestion, in: textView, caret: caret, trailingCaretOffset: 0, allowsSnippet: true)
            return
        }
        Task { @MainActor in
            await suggestion.state.resolve(using: resolver)
            let current = self.currentCaret(in: textView) ?? caret
            self.apply(suggestion, in: textView, caret: current, trailingCaretOffset: 0, allowsSnippet: true)
        }
    }

    @MainActor
    private func makeResolver() -> ((CompletionItem) async -> CompletionItem?)? {
        guard let server = languageServer, let documentURI, server.supportsCompletionResolve else { return nil }
        return { [weak server] item in
            try? await server?.resolveCompletionItem(item, for: documentURI)
        }
    }

    @MainActor
    private func didResolve(_ suggestion: LSPCompletionSuggestion) {
        guard selected?.state === suggestion.state else { return }
        LSPCompletionPreviewRefresher.refresh(parent: activeController?.view.window)
    }

    private func install(
        _ response: CompletionResponse,
        server: LanguageServer<DocumentType>,
        position: Position
    ) {
        let defaults = server.serverCapabilities.completionProvider?.allCommitCharacters ?? []
        suggestions = (response?.items ?? []).map {
            LSPCompletionSuggestion(item: $0, defaultCommitCharacters: defaults)
        }
        isIncomplete = response?.isIncomplete ?? false
        requestContext = LSPCompletionRequestContext(position: position)
        selected = nil
    }

    @MainActor
    private func observe(textView: TextViewController, caret: Int) {
        observedCursor = caret
        observedLength = textView.textView.textStorage.length
    }

    @MainActor
    private func committingSuggestion(text: String, caret: Int) -> LSPCompletionSuggestion? {
        guard let selected,
              caret == observedCursor + 1,
              (text as NSString).length == observedLength + 1,
              let typed = LSPCompletionMapping.triggerCharacter(in: text, before: caret),
              selected.commits(on: typed) else { return nil }
        return selected
    }

    @MainActor
    private func refreshIncomplete(in textView: TextViewController, caret: Int) {
        guard let server = languageServer,
              let documentURI,
              let position = lspPosition(forOffset: caret, in: textView.textView) else { return }
        incompleteTask?.cancel()
        incompleteTask = Task { @MainActor [weak self, weak textView] in
            let response = try? await server.requestCompletion(
                for: documentURI,
                position: position,
                incomplete: true
            )
            guard !Task.isCancelled, let self, let textView, let response else { return }
            self.install(response, server: server, position: position)
            textView.textView.selectionManager.notifyAfterEdit()
        }
    }

    @MainActor
    private func ranked(in textView: TextViewController, caret: Int) -> [LSPCompletionSuggestion] {
        let tv: TextView = textView.textView
        let text = tv.string
        let identifierPrefix = LSPCompletionMapping.prefix(in: text, before: caret)
        let current = lspPosition(forOffset: caret, in: tv)
        var rangePrefixes: [Position: String] = [:]
        let inputs = suggestions.map { suggestion -> LSPCompletionRankingInput in
            var prefix = identifierPrefix
            if let range = suggestion.replacementRange, let context = requestContext, let current {
                if let cached = rangePrefixes[range.start] {
                    prefix = cached
                } else {
                    let start = LSPCompletionEditPlanner.adjusted(
                        range.start,
                        isEnd: false,
                        context: context,
                        current: current
                    )
                    if let offset = LSPTextPositionConverter.offset(of: start, in: tv),
                       let rangePrefix = LSPCompletionMapping.filterPrefix(in: text, from: offset, to: caret) {
                        prefix = rangePrefix
                    }
                    rangePrefixes[range.start] = prefix
                }
            }
            return LSPCompletionRankingInput(
                filterText: suggestion.filterText,
                label: suggestion.label,
                sortText: suggestion.sortText,
                preselect: suggestion.preselect,
                prefix: prefix
            )
        }
        return LSPCompletionRanking.order(inputs).map { suggestions[$0] }
    }

    @MainActor
    private func apply(
        _ suggestion: LSPCompletionSuggestion,
        in controller: TextViewController,
        caret: Int,
        trailingCaretOffset: Int,
        allowsSnippet: Bool
    ) {
        let tv: TextView = controller.textView
        guard let current = lspPosition(forOffset: caret, in: tv) else { return }
        let context = requestContext ?? LSPCompletionRequestContext(position: current)
        let prefix = LSPCompletionMapping.prefix(in: tv.string, before: caret)
        let plan = LSPCompletionEditPlanner.plan(
            item: suggestion.item,
            context: context,
            current: current,
            fallbackRange: NSRange(location: caret - prefix.utf16.count, length: prefix.utf16.count),
            variables: LSPCompletionApplier.variables(for: controller, fileURL: fileURL),
            allowsSnippet: allowsSnippet,
            offsetOf: { LSPTextPositionConverter.offset(of: $0, in: tv) }
        )
        guard let plan else { return }
        snippetSession?.cancel()
        snippetSession = LSPCompletionApplier.apply(
            plan,
            to: controller,
            trailingCaretOffset: trailingCaretOffset
        ) { [weak self] in
            self?.snippetSession = nil
        }
    }

    @MainActor
    private func lspPosition(forOffset offset: Int, in textView: TextView) -> Position? {
        guard offset >= 0,
              offset <= textView.textStorage.length,
              let line = textView.layoutManager.textLineForOffset(offset) else { return nil }
        return Position(line: line.index, character: offset - line.range.location)
    }

    @MainActor
    private func currentCaret(in controller: TextViewController) -> Int? {
        controller.textView.selectionManager.textSelections.first?.range.location
    }
}
