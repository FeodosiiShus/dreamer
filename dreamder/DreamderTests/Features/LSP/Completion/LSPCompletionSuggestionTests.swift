import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor @Suite("LSP completion suggestion", .uiGate)
struct LSPCompletionSuggestionTests {
    private func range(_ start: Int, _ end: Int) -> LSPRange {
        LSPRange(start: Position(line: 0, character: start), end: Position(line: 0, character: end))
    }

    @Test func carriesTheItemData() {
        let item = CompletionItem(
            label: "print",
            kind: .function,
            detail: "func print()",
            documentation: .optionA("prints"),
            deprecated: true,
            preselect: true,
            sortText: "01",
            filterText: "pr",
            commitCharacters: ["("]
        )
        let suggestion = LSPCompletionSuggestion(item: item, defaultCommitCharacters: [";"])
        #expect(suggestion.label == "print")
        #expect(suggestion.kind == .function)
        #expect(suggestion.detail == "func print()")
        #expect(suggestion.documentation == "prints")
        #expect(suggestion.deprecated)
        #expect(suggestion.preselect)
        #expect(suggestion.sortText == "01")
        #expect(suggestion.filterText == "pr")
        #expect(suggestion.commitCharacters == ["("])
        #expect(suggestion.pathComponents == nil)
        #expect(suggestion.targetPosition == nil)
        #expect(suggestion.sourcePreview == nil)
        #expect(suggestion.imageColor == SwiftUI.Color.clear)
        _ = suggestion.image
        #expect(suggestion.item == item)
    }

    @Test func fallsBackToTheLabelAndTheDefaultCommitCharacters() {
        let suggestion = LSPCompletionSuggestion(
            item: CompletionItem(label: "name"),
            defaultCommitCharacters: [".", ";"]
        )
        #expect(suggestion.filterText == "name")
        #expect(suggestion.sortText == nil)
        #expect(!suggestion.deprecated)
        #expect(!suggestion.preselect)
        #expect(suggestion.documentation == nil)
        #expect(suggestion.commitCharacters == [".", ";"])
        #expect(suggestion.commits(on: "."))
        #expect(!suggestion.commits(on: ","))
    }

    @Test func exposesTheInsertOrReplaceRange() {
        let plain = LSPCompletionSuggestion(item: CompletionItem(label: "a"))
        #expect(plain.replacementRange == nil)
        let edit = LSPCompletionSuggestion(
            item: CompletionItem(label: "a", textEdit: .optionA(TextEdit(range: range(1, 2), newText: "a")))
        )
        #expect(edit.replacementRange == range(1, 2))
        let insertReplace = LSPCompletionSuggestion(
            item: CompletionItem(
                label: "a",
                textEdit: .optionB(InsertReplaceEdit(newText: "a", insert: range(1, 2), replace: range(1, 5)))
            )
        )
        #expect(insertReplace.replacementRange == range(1, 2))
    }

    @Test func resolutionMergesTheLazyPropertiesOnce() async {
        let item = CompletionItem(
            label: "foo",
            kind: .method,
            detail: "old",
            sortText: "1",
            insertText: "foo()",
            additionalTextEdits: nil,
            commitCharacters: ["."]
        )
        let state = LSPCompletionItemState(item: item)
        let resolved = CompletionItem(
            label: "ignored",
            detail: "new",
            documentation: .optionA("docs"),
            additionalTextEdits: [TextEdit(range: range(0, 0), newText: "import Foo\n")]
        )
        var calls = 0
        #expect(state.needsResolution)
        await state.resolve { _ in
            calls += 1
            return resolved
        }
        await state.resolve { _ in
            calls += 1
            return resolved
        }
        #expect(calls == 1)
        #expect(state.isResolved)
        #expect(!state.needsResolution)
        #expect(state.item.label == "foo")
        #expect(state.item.kind == .method)
        #expect(state.item.detail == "new")
        #expect(state.item.sortText == "1")
        #expect(state.item.insertText == "foo()")
        #expect(state.item.commitCharacters == ["."])
        #expect(LSPCompletionMapping.documentation(from: state.item.documentation) == "docs")
        #expect(state.item.additionalTextEdits?.first?.newText == "import Foo\n")
    }

    @Test func aFailedResolutionKeepsTheItemAndIsNotRetried() async {
        let item = CompletionItem(label: "foo", detail: "old")
        let state = LSPCompletionItemState(item: item)
        await state.resolve { _ in nil }
        #expect(state.item == item)
        #expect(state.isResolved)
    }

    @Test func concurrentResolutionsShareOneRequest() async {
        let state = LSPCompletionItemState(item: CompletionItem(label: "foo"))
        var calls = 0
        let first = Task { @MainActor in
            await state.resolve { item in
                calls += 1
                try? await Task.sleep(for: .milliseconds(50))
                return item
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
        #expect(!state.needsResolution)
        await state.resolve { _ in
            calls += 1
            return nil
        }
        await first.value
        #expect(calls == 1)
        #expect(state.isResolved)
    }

    @Test func itemsCanBeMarkedResolvedWithoutAServer() async {
        let state = LSPCompletionItemState(item: CompletionItem(label: "foo"))
        state.markResolved()
        var calls = 0
        await state.resolve { _ in
            calls += 1
            return nil
        }
        #expect(calls == 0)
        #expect(!state.needsResolution)
    }
}
