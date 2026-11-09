import AppKit
import CodeEditSourceEditor
import CodeEditTextView

nonisolated extension EditorPlace.Caret {
    func advanced(byInserting text: String) -> EditorPlace.Caret {
        let units = text.utf16
        let newlines = units.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        guard newlines > 0 else {
            return EditorPlace.Caret(line: line, column: column + units.count)
        }
        let tail = units.reversed().prefix { $0 != 0x0A }.count
        return EditorPlace.Caret(line: line + newlines, column: tail + 1)
    }
}

final class RecentLocationsCoordinator: TextViewCoordinator, TextViewDelegate {
    private let editorInstance: EditorInstance
    private let workspaceProvider: @MainActor () -> WorkspaceDocument?
    private let isMousePress: (@MainActor () -> Bool)?
    private weak var tracker: RecentLocationsTracker?
    private var previousCarets: [EditorPlace.Caret] = []
    private var editStart: EditorPlace.Caret?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        workspaceProvider: (@MainActor () -> WorkspaceDocument?)? = nil,
        isMousePress: (@MainActor () -> Bool)? = nil
    ) {
        self.editorInstance = editorInstance
        if let workspaceProvider {
            self.workspaceProvider = workspaceProvider
        } else {
            self.workspaceProvider = { [weak codeFile] in codeFile?.findWorkspace() }
        }
        self.isMousePress = isMousePress
    }

    private func isMousePressInEditor(of controller: TextViewController) -> Bool {
        if let isMousePress {
            return isMousePress()
        }
        guard let event = NSApp.currentEvent, let window = controller.view.window else { return false }
        return event.type == .leftMouseDown && event.window === window
    }

    private var fileURL: URL { editorInstance.file.url }

    func prepareCoordinator(controller: TextViewController) {
        tracker = workspaceProvider().map { RecentLocationsStore.shared.history(for: $0) }
        previousCarets = EditorPlace(fileURL: fileURL, positions: editorInstance.cursorPositions).carets
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        let carets = EditorPlace(fileURL: fileURL, positions: newPositions).carets
        let previous = previousCarets
        previousCarets = carets
        guard isMousePressInEditor(of: controller), let tracker, previous.first?.line != carets.first?.line else {
            return
        }
        tracker.recordNavigation(from: EditorPlace(fileURL: fileURL, carets: previous))
    }

    func textView(_ textView: TextView, willReplaceContentsIn range: NSRange, with string: String) {
        guard let line = textView.layoutManager.textLineForOffset(range.location) else {
            editStart = nil
            return
        }
        editStart = EditorPlace.Caret(line: line.index + 1, column: range.location - line.range.location + 1)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        guard let start = editStart else { return }
        editStart = nil
        tracker?.recordChange(EditorPlace(fileURL: fileURL, carets: [start.advanced(byInserting: string)]))
    }

    func destroy() {
        tracker = nil
        editStart = nil
    }
}
