import AppKit
import CodeEditSourceEditor
import CodeEditTextView

enum EditorCommentOutcome: Equatable {
    case applied
    case unsupported(String)
    case unchanged
}

final class EditorActionCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private let file: CEWorkspaceFile?
    private let interceptor: EditorInputInterceptor
    let goToLinePresenter = GoToLinePopupPresenter()
    private var occurrencePrimary: NSRange?

    init(file: CEWorkspaceFile? = nil, interceptor: EditorInputInterceptor = EditorInputInterceptor()) {
        self.file = file
        self.interceptor = interceptor
    }

    var isMonitoringInput: Bool {
        interceptor.installedMonitorCount == 3
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        interceptor.attach(controller: controller)
        interceptor.installEarlyKeyMonitor()
    }

    func controllerDidAppear(controller: TextViewController) {
        self.controller = controller
        interceptor.attach(controller: controller)
        interceptor.installLateKeyMonitor()
        interceptor.installMouseMonitor()
    }

    func destroy() {
        interceptor.detach()
        goToLinePresenter.dismiss()
        controller = nil
    }

    func duplicateLineOrSelection() {
        edit { DuplicateLines.perform(in: $0, selections: $1) }
    }

    func deleteLine() {
        edit { DeleteLines.perform(in: $0, selections: $1) }
    }

    func joinLines() {
        let prefix = CommentLanguage.forFile(url: file?.url).linePrefix
        edit { JoinLines.perform(in: $0, selections: $1, lineCommentPrefix: prefix) }
    }

    func moveLines(up: Bool) {
        edit { MoveLines.perform(in: $0, selections: $1, up: up) }
    }

    func selectNextOccurrence() {
        selectOccurrences { OccurrenceSelection.selectNext(in: $0, selections: $1, primary: $2) }
    }

    func selectAllOccurrences() {
        selectOccurrences { OccurrenceSelection.selectAll(in: $0, selections: $1, primary: $2) }
    }

    func unselectLastOccurrence() {
        selectOccurrences { OccurrenceSelection.unselectLast(selections: $1, primary: $2) }
    }

    func cloneCaret(above: Bool) {
        guard let textView = controller?.textView else { return }
        let text = NSString(string: textView.string)
        guard let cloned = CloneCaret.perform(in: text, selections: currentSelections(in: textView), above: above) else {
            return
        }
        select(cloned, in: textView)
    }

    func toggleLineComment() -> EditorCommentOutcome {
        toggleComment { LineCommenter.toggle(in: $0, selections: $1, language: $2) }
    }

    func toggleBlockComment() -> EditorCommentOutcome {
        toggleComment { BlockCommenter.toggle(in: $0, selections: $1, language: $2) }
    }

    func indentSelection() {
        guard let controller, controller.textView.isEditable else { return }
        controller.handleIndent()
    }

    func unindentSelection() {
        guard let controller, controller.textView.isEditable else { return }
        controller.handleIndent(inwards: true)
    }

    func toggleSoftWraps() -> Bool? {
        guard let controller else { return nil }
        let wraps = !controller.wrapLines
        controller.configuration.appearance.wrapLines = wraps
        return wraps
    }

    func goToLine(line: Int, column: Int?) {
        guard let textView = controller?.textView else { return }
        let index = EditorLineIndex(NSString(string: textView.string))
        let target = index.lines[min(max(line, 1), index.count) - 1]
        let columnOffset = min(max((column ?? 1) - 1, 0), target.contentLength)
        select([NSRange(location: target.start + columnOffset, length: 0)], in: textView)
    }

    func showGoToLine() {
        guard let textView = controller?.textView else { return }
        let index = EditorLineIndex(NSString(string: textView.string))
        guard let caret = currentSelections(in: textView).last?.location else { return }
        let caretLine = index.line(containing: caret)
        let model = GoToLinePopupModel(
            lineCount: index.count,
            currentLine: caretLine.index + 1,
            currentColumn: caret - caretLine.start + 1,
            onSubmit: { [weak self] target in
                self?.goToLine(line: target.line, column: target.column)
            },
            onDismiss: { [weak self] in
                self?.goToLinePresenter.dismiss()
            }
        )
        let visible = textView.visibleRect
        let anchor = NSRect(x: visible.midX, y: visible.minY, width: 1, height: 1)
        goToLinePresenter.present(model: model, relativeTo: anchor, of: textView)
    }

    private func edit(_ compute: (NSString, [NSRange]) -> EditorCommandResult?) {
        guard let textView = controller?.textView, textView.isEditable else { return }
        let text = NSString(string: textView.string)
        guard let result = compute(text, currentSelections(in: textView)) else { return }
        apply(result, to: textView)
    }

    private func toggleComment(
        _ toggle: (NSString, [NSRange], CommentLanguage) -> LineCommenter.Outcome
    ) -> EditorCommentOutcome {
        guard let textView = controller?.textView, textView.isEditable else { return .unchanged }
        let text = NSString(string: textView.string)
        let language = CommentLanguage.forFile(url: file?.url)
        switch toggle(text, currentSelections(in: textView), language) {
        case .edit(let result):
            apply(result, to: textView)
            return .applied
        case .unsupported(let reason):
            return .unsupported(reason)
        case .unchanged:
            return .unchanged
        }
    }

    private func selectOccurrences(
        _ compute: (NSString, [NSRange], NSRange?) -> OccurrenceSelectionResult?
    ) {
        guard let textView = controller?.textView else { return }
        let selections = currentSelections(in: textView)
        let primary = occurrencePrimary.flatMap { selections.contains($0) ? $0 : nil }
        guard let result = compute(NSString(string: textView.string), selections, primary) else { return }
        occurrencePrimary = result.primary
        select(result.selections, in: textView)
    }

    private func currentSelections(in textView: TextView) -> [NSRange] {
        textView.selectionManager.textSelections.map(\.range).sorted { $0.location < $1.location }
    }

    private func apply(_ result: EditorCommandResult, to textView: TextView) {
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            textView.replaceCharacters(in: edit.range, with: edit.replacement, skipUpdateSelection: true)
        }
        undoManager?.endUndoGrouping()
        select(result.selections, in: textView)
    }

    private func select(_ ranges: [NSRange], in textView: TextView) {
        textView.selectionManager.setSelectedRanges(ranges)
        textView.selectionManager.notifyAfterEdit(force: true)
        textView.scrollSelectionToVisible()
    }
}
