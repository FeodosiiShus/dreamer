import AppKit
import Foundation
import CodeEditTextView

extension CodeFileDocument {
    var modifiedLines: IndexSet {
        modifiedLineTracker.lines
    }

    func isInUse(outside workspace: WorkspaceDocument?) -> Bool {
        guard windowControllers.isEmpty else { return true }
        return DreamderDocumentController.shared.documents.contains { other in
            guard let other = other as? WorkspaceDocument, other !== workspace else { return false }
            return other.isShowing(self)
        }
    }

    static func currentSaveActionSettings() -> SaveActionSettings {
        Settings[\.textEditing].saveActionSettings
    }

    func trackWillReplace(range: NSRange, in textView: TextView) {
        guard !isApplyingSaveActions else { return }
        let storage = textView.textStorage
        guard let storage,
              case let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length)),
              clamped.length > 0 else {
            pendingRemovedLineBreaks = 0
            return
        }
        pendingRemovedLineBreaks = ModifiedLineTracker.lineBreakCount(
            in: storage.mutableString.substring(with: clamped)
        )
    }

    func trackDidReplace(range: NSRange, with string: String, in textView: TextView) {
        guard !isApplyingSaveActions else { return }
        let removed = pendingRemovedLineBreaks
        pendingRemovedLineBreaks = 0
        guard range.length > 0 || !string.isEmpty else { return }
        modifiedLineTracker.replace(
            startLine: textView.layoutManager.textLineForOffset(range.location)?.index ?? 0,
            removedLineBreaks: removed,
            addedLineBreaks: ModifiedLineTracker.lineBreakCount(in: string)
        )
    }

    @discardableResult
    func applySaveActions(settings: SaveActionSettings = CodeFileDocument.currentSaveActionSettings()) -> Bool {
        guard !contentState.isReadOnly, let content else { return false }
        let textView = attachedTextView.flatMap { $0.textStorage === content && $0.isEditable ? $0 : nil }
        let selections = textView?.selectionManager.textSelections.map(\.range) ?? []
        let plan = SaveActions(editorConfig: editorConfig, settings: settings).plan(
            for: content.string,
            modifiedLines: modifiedLines,
            caretOffsets: selections.map(\.upperBound)
        )
        retainedModifiedLines = plan.deferredLines
        guard !plan.edits.isEmpty else { return false }
        isApplyingSaveActions = true
        defer { isApplyingSaveActions = false }
        if let textView {
            for edit in plan.edits {
                textView.replaceCharacters(in: edit.range, with: edit.replacement, skipUpdateSelection: true)
            }
            textView.selectionManager.setSelectedRanges(
                selections.map { SaveActions.map($0, through: plan.edits) }
            )
        } else {
            content.beginEditing()
            for edit in plan.edits {
                content.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            content.endEditing()
        }
        return true
    }
}
