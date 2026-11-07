import AppKit
import CodeEditSourceEditor
import CodeEditTextView

final class MarkdownTypingCoordinator: TextViewCoordinator {
    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76
    private static let deleteKeyCode: UInt16 = 51

    private weak var controller: TextViewController?
    private weak var codeFile: CodeFileDocument?
    private var monitor: Any?
    var settings = MarkdownTypingSettings()

    var isMonitoringKeyEvents: Bool {
        monitor != nil
    }

    init(codeFile: CodeFileDocument) {
        self.codeFile = codeFile
    }

    isolated deinit {
        removeMonitor()
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        self.controller = controller
        installMonitor()
    }

    func controllerDidDisappear(controller: TextViewController) {
        removeMonitor()
    }

    func destroy() {
        removeMonitor()
        controller = nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
              let controller,
              let textView = controller.textView,
              let window = textView.window,
              event.window === window,
              window.firstResponder === textView,
              controller.isEditable,
              textView.isEditable,
              !textView.hasMarkedText(),
              MarkdownPreviewLayoutStore.isMarkdownFile(codeFile?.fileURL) else { return event }

        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch event.keyCode {
        case Self.returnKeyCode, Self.keypadEnterKeyCode:
            guard modifiers.isEmpty || modifiers == .shift else { return event }
            let handled = perform(in: controller, textView: textView, shift: modifiers == .shift, backspace: false)
            return handled ? nil : event
        case Self.deleteKeyCode:
            guard modifiers.isEmpty else { return event }
            let handled = perform(in: controller, textView: textView, shift: false, backspace: true)
            return handled ? nil : event
        default:
            return event
        }
    }

    private func perform(in controller: TextViewController, textView: TextView, shift: Bool, backspace: Bool) -> Bool {
        let selections = textView.selectionManager.textSelections.map(\.range)
        guard selections.count == 1, let selection = selections.first, selection.length == 0 else { return false }
        let units = Array(textView.string.utf16)
        let caret = selection.location
        var effective = settings
        effective.tabWidth = controller.tabWidth
        let edit = backspace
            ? MarkdownListEnter.edit(forBackspaceIn: units, caret: caret, settings: effective)
            : MarkdownListEnter.edit(forEnterIn: units, caret: caret, shift: shift, settings: effective)
        guard let edit else { return false }

        let expectedLength = units.count - edit.range.length + edit.replacement.utf16.count
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        if !edit.isCaretOnly {
            textView.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        undoManager?.endUndoGrouping()
        guard textView.textStorage.length == expectedLength else { return false }
        controller.setCursorPositions(
            [CursorPosition(range: NSRange(location: edit.caretOffset, length: 0))],
            scrollToVisible: true
        )
        return true
    }
}
