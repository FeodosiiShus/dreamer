import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class FindFormSubmitCounter {
    var submissions = 0
    var field: FindMultilineField?
}

@MainActor
struct FindFormMultilineHarness: View {
    let state: WorkspaceDocument.SearchState
    let counter: FindFormSubmitCounter
    let modifiers: NSEvent.ModifierFlags
    @FocusState private var focused: Bool

    var body: some View {
        makeField()
    }

    private func makeField() -> FindMultilineField {
        let field = FindMultilineField(
            placeholder: "Find",
            text: Bindable(state).searchQuery,
            focus: $focused,
            onSubmit: { counter.submissions += 1 },
            currentModifiers: { modifiers }
        )
        counter.field = field
        return field
    }
}

@MainActor
struct FindFormDefaultModifiersHarness: View {
    let state: WorkspaceDocument.SearchState
    let counter: FindFormSubmitCounter
    @FocusState private var focused: Bool

    var body: some View {
        makeField()
    }

    private func makeField() -> FindMultilineField {
        let field = FindMultilineField(
            placeholder: "Find",
            text: Bindable(state).searchQuery,
            focus: $focused,
            onSubmit: { counter.submissions += 1 }
        )
        counter.field = field
        return field
    }
}
