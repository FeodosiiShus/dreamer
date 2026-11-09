import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI

final class LSPCompletionItemState {
    private(set) var item: CompletionItem
    private(set) var isResolved = false
    private var task: Task<Void, Never>?

    init(item: CompletionItem) {
        self.item = item
    }

    var needsResolution: Bool {
        !isResolved && task == nil
    }

    func markResolved() {
        isResolved = true
    }

    func resolve(using resolver: @escaping (CompletionItem) async -> CompletionItem?) async {
        if isResolved { return }
        if let task {
            await task.value
            return
        }
        let original = item
        let task = Task { [weak self] in
            let resolved = await resolver(original)
            self?.finish(with: resolved)
        }
        self.task = task
        await task.value
    }

    private func finish(with resolved: CompletionItem?) {
        if let resolved {
            item = Self.merge(item, resolved: resolved)
        }
        isResolved = true
        task = nil
    }

    private static func merge(_ item: CompletionItem, resolved: CompletionItem) -> CompletionItem {
        CompletionItem(
            label: item.label,
            kind: item.kind,
            detail: resolved.detail ?? item.detail,
            documentation: resolved.documentation ?? item.documentation,
            deprecated: item.deprecated,
            preselect: item.preselect,
            sortText: item.sortText,
            filterText: item.filterText,
            insertText: item.insertText,
            insertTextFormat: item.insertTextFormat,
            textEdit: item.textEdit,
            additionalTextEdits: resolved.additionalTextEdits ?? item.additionalTextEdits,
            commitCharacters: item.commitCharacters,
            command: item.command,
            data: item.data
        )
    }
}

struct LSPCompletionSuggestion: CodeSuggestionEntry {
    let state: LSPCompletionItemState
    let commitCharacters: [String]

    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var image: Image { Image(LSPCompletionMapping.iconName(for: kind)) }
    var imageColor: SwiftUI.Color { .clear }

    var item: CompletionItem { state.item }
    var label: String { item.label }
    var detail: String? { item.detail }
    var documentation: String? { LSPCompletionMapping.documentation(from: item.documentation) }
    var deprecated: Bool { item.deprecated ?? false }
    var kind: CompletionItemKind? { item.kind }
    var sortText: String? { item.sortText }
    var filterText: String { item.filterText ?? item.label }
    var preselect: Bool { item.preselect ?? false }

    var replacementRange: LSPRange? {
        switch item.textEdit {
        case .some(.optionA(let edit)):
            return edit.range
        case .some(.optionB(let edit)):
            return edit.insert
        case .none:
            return nil
        }
    }

    init(item: CompletionItem, defaultCommitCharacters: [String] = []) {
        self.state = LSPCompletionItemState(item: item)
        self.commitCharacters = item.commitCharacters ?? defaultCommitCharacters
    }

    func commits(on character: String) -> Bool {
        commitCharacters.contains(character)
    }
}
