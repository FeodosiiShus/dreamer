import AppKit
import CodeEditSourceEditor
import CodeEditTextView

@MainActor
final class SnippetSession {
    private struct PendingEdit {
        let range: NSRange
        let newLength: Int
    }

    private static let tabKeyCode: UInt16 = 48
    private static let escapeKeyCode: UInt16 = 53

    private weak var controller: TextViewController?
    private weak var textView: TextView?
    private var tracker: SnippetRangeTracker
    private var activePosition: Int
    private var pendingEdits: [PendingEdit] = []
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var isMovingSelection = false
    private var isSyncingMirrors = false
    private var isGroupingUndo = false
    private var onEnd: (() -> Void)?
    private(set) var isActive = true

    var activeStopIndex: Int {
        tracker.stops[activePosition].index
    }

    var isMonitoringKeyEvents: Bool {
        keyMonitor != nil
    }

    init?(controller: TextViewController, template: SnippetTemplate, origin: Int, onEnd: @escaping () -> Void) {
        guard let textView = controller.textView, !template.tabStops.isEmpty else { return nil }
        self.controller = controller
        self.textView = textView
        self.onEnd = onEnd
        let tracker = SnippetRangeTracker(template: template, origin: origin)
        self.tracker = tracker
        self.activePosition = tracker.firstPosition()
        install(on: textView)
        activate(activePosition)
    }

    isolated deinit {
        tearDown()
    }

    func next() {
        flushEdits()
        guard isActive else { return }
        let target = tracker.nextPosition(after: activePosition)
        if target == tracker.finalPosition {
            moveSelection(to: NSRange(location: tracker.finalCaret, length: 0))
            end()
        } else {
            activate(target)
        }
    }

    func previous() {
        flushEdits()
        guard isActive else { return }
        activate(tracker.previousPosition(before: activePosition) ?? activePosition)
    }

    func cancel() {
        end()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard isActive,
              event.type == .keyDown,
              let textView,
              let window = textView.window,
              event.window === window,
              window.firstResponder === textView,
              !textView.hasMarkedText() else { return event }
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch event.keyCode {
        case Self.tabKeyCode:
            guard modifiers.isEmpty || modifiers == .shift else { return event }
            if modifiers == .shift {
                previous()
            } else {
                next()
            }
            return nil
        case Self.escapeKeyCode:
            guard modifiers.isEmpty else { return event }
            cancel()
            return nil
        default:
            return event
        }
    }

    private static func observer(
        for name: Notification.Name,
        object: Any?,
        session: SnippetSession,
        handler: @escaping @MainActor (SnippetSession) -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak session] _ in
            MainActor.assumeIsolated {
                guard let session else { return }
                handler(session)
            }
        }
    }

    private func install(on textView: TextView) {
        observers = [
            Self.observer(
                for: NSTextStorage.didProcessEditingNotification,
                object: textView.textStorage,
                session: self
            ) { $0.recordEdit() },
            Self.observer(for: TextView.textWillChangeNotification, object: textView, session: self) {
                $0.willChange()
            },
            Self.observer(for: TextView.textDidChangeNotification, object: textView, session: self) {
                $0.flushEdits()
            },
            Self.observer(
                for: TextSelectionManager.selectionChangedNotification,
                object: textView.selectionManager,
                session: self
            ) { $0.selectionChanged() },
            Self.observer(for: .NSUndoManagerWillUndoChange, object: textView.undoManager, session: self) {
                $0.end()
            },
            Self.observer(for: .NSUndoManagerWillRedoChange, object: textView.undoManager, session: self) {
                $0.end()
            }
        ]
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
    }

    private func tearDown() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func end() {
        guard isActive else { return }
        isActive = false
        tearDown()
        endUndoGrouping()
        let callback = onEnd
        onEnd = nil
        callback?()
    }

    private var currentSelection: NSRange? {
        guard let selections = textView?.selectionManager.textSelections, selections.count == 1 else { return nil }
        return selections.first?.range
    }

    private func activate(_ position: Int) {
        guard let range = tracker.primaryRange(of: position) else { return }
        activePosition = position
        moveSelection(to: range)
    }

    private func moveSelection(to range: NSRange) {
        isMovingSelection = true
        controller?.setCursorPositions([CursorPosition(range: range)], scrollToVisible: true)
        isMovingSelection = false
    }

    private func recordEdit() {
        guard isActive,
              let storage = textView?.textStorage,
              storage.editedMask.contains(.editedCharacters) else { return }
        let edited = storage.editedRange
        pendingEdits.append(
            PendingEdit(
                range: NSRange(location: edited.location, length: edited.length - storage.changeInLength),
                newLength: edited.length
            )
        )
    }

    private func willChange() {
        guard isActive,
              !isGroupingUndo,
              !isSyncingMirrors,
              let undoManager = textView?.undoManager,
              tracker.stops[activePosition].slots.filter(\.isAlive).count > 1,
              let selection = currentSelection,
              tracker.contains(selection: selection, in: activePosition) else { return }
        undoManager.beginUndoGrouping()
        isGroupingUndo = true
    }

    private func endUndoGrouping() {
        guard isGroupingUndo else { return }
        isGroupingUndo = false
        textView?.undoManager?.endUndoGrouping()
    }

    private func selectionChanged() {
        flushEdits()
        guard isActive, !isMovingSelection, !isSyncingMirrors else { return }
        if let selection = currentSelection, tracker.contains(selection: selection, in: activePosition) {
            return
        }
        end()
    }

    private func flushEdits() {
        guard isActive, !isSyncingMirrors else { return }
        defer { endUndoGrouping() }
        let edits = pendingEdits
        pendingEdits.removeAll()
        guard !edits.isEmpty else { return }
        var changedSlot: Int?
        for edit in edits {
            guard let slot = tracker.slot(containing: edit.range, in: activePosition) else {
                end()
                return
            }
            tracker.apply(edit: edit.range, newLength: edit.newLength, stop: activePosition, slot: slot)
            changedSlot = slot
        }
        if let changedSlot {
            syncMirrors(from: changedSlot)
        }
    }

    private func syncMirrors(from slot: Int) {
        guard let textView else { return }
        let mirrors = tracker.mirrorSlots(of: activePosition, excluding: slot)
        guard !mirrors.isEmpty else { return }
        let storage: NSTextStorage = textView.textStorage
        let sourceRange = clamped(tracker.range(of: activePosition, slot: slot), in: storage)
        let content = storage.attributedSubstring(from: sourceRange).string
        let contentLength = content.utf16.count
        let selection = currentSelection
        let caretOffset = selection.map { $0.location - sourceRange.location }
        isSyncingMirrors = true
        defer { isSyncingMirrors = false }
        let descending = mirrors.sorted {
            let lhs = tracker.range(of: activePosition, slot: $0)
            let rhs = tracker.range(of: activePosition, slot: $1)
            return lhs.location > rhs.location
        }
        for mirror in descending {
            let range = clamped(tracker.range(of: activePosition, slot: mirror), in: storage)
            guard storage.attributedSubstring(from: range).string != content else { continue }
            let lengthBefore = storage.length
            textView.replaceCharacters(in: range, with: content)
            pendingEdits.removeAll()
            guard storage.length == lengthBefore - range.length + contentLength else {
                end()
                return
            }
            tracker.apply(edit: range, newLength: contentLength, stop: activePosition, slot: mirror)
        }
        if let selection, let caretOffset {
            let updated = tracker.range(of: activePosition, slot: slot)
            isMovingSelection = true
            controller?.setCursorPositions(
                [CursorPosition(range: NSRange(location: updated.location + caretOffset, length: selection.length))]
            )
            isMovingSelection = false
        }
    }

    private func clamped(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
    }
}
