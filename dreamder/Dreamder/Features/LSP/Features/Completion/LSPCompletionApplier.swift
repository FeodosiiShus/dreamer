import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation

@MainActor
enum LSPCompletionApplier {
    static func apply(
        _ plan: LSPCompletionEditPlan,
        to controller: TextViewController,
        trailingCaretOffset: Int = 0,
        onSessionEnd: @escaping () -> Void
    ) -> SnippetSession? {
        guard let textView = controller.textView, textView.isEditable else { return nil }
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        for edit in plan.edits where NSMaxRange(edit.range) <= textView.textStorage.length {
            textView.replaceCharacters(in: edit.range, with: edit.text)
        }
        undoManager?.endUndoGrouping()
        if let template = plan.template,
           let session = SnippetSession(
               controller: controller,
               template: template,
               origin: plan.mainStart,
               onEnd: onSessionEnd
           ) {
            return session
        }
        let caret = (plan.template.map { plan.mainStart + $0.finalCaret } ?? plan.caret) + trailingCaretOffset
        controller.setCursorPositions(
            [CursorPosition(range: NSRange(location: min(caret, textView.textStorage.length), length: 0))],
            scrollToVisible: true
        )
        return nil
    }

    static func variables(for controller: TextViewController, fileURL: URL?) -> SnippetVariableContext {
        var context = SnippetVariableContext(fileURL: fileURL)
        guard let textView = controller.textView,
              let selection = textView.selectionManager.textSelections.first?.range else { return context }
        let storage: NSTextStorage = textView.textStorage
        guard selection.location + selection.length <= storage.length else { return context }
        context.selectedText = storage.attributedSubstring(from: selection).string
        context.currentWord = LSPCompletionMapping.prefix(in: textView.string, before: selection.location)
        if let line = textView.layoutManager.textLineForOffset(selection.location) {
            context.lineIndex = line.index
            context.currentLine = storage.attributedSubstring(from: line.range).string
                .trimmingCharacters(in: .newlines)
        }
        return context
    }
}
