import AppKit
import Observation

nonisolated enum IntentionPopupRow: Identifiable, Equatable, Sendable {
    case header(id: String, title: String)
    case action(IntentionAction)

    var id: String {
        switch self {
        case .header(let id, _): "header.\(id)"
        case .action(let action): "action.\(action.id)"
        }
    }

    var intention: IntentionAction? {
        if case .action(let action) = self { return action }
        return nil
    }
}

nonisolated extension IntentionCategory {
    var bulbIconName: String? {
        switch self {
        case .quickFix: "codeInsight/quickfixBulb"
        case .refactoring: "actions/refactoringBulb"
        case .source: nil
        }
    }
}

@MainActor
@Observable
final class IntentionPopupModel {
    static let actionRowHeight: CGFloat = 24
    static let headerRowHeight: CGFloat = 22
    static let listPadding: CGFloat = 4
    static let messageHeight: CGFloat = 48
    static let maximumHeight: CGFloat = 360
    static let listWidth: CGFloat = 360
    static let messageWidth: CGFloat = 380

    let rows: [IntentionPopupRow]
    private(set) var selectedIndex: Int

    let message: String?

    @ObservationIgnored
    var dismiss: (() -> Void)?
    @ObservationIgnored
    var onApply: ((IntentionAction) -> Void)?

    init(groups: [IntentionGroup]) {
        let rows = groups.filter { !$0.actions.isEmpty }.flatMap { group in
            [IntentionPopupRow.header(id: group.id, title: group.title)]
                + group.actions.map(IntentionPopupRow.action)
        }
        self.rows = rows
        self.message = nil
        self.selectedIndex = Self.initialSelection(in: rows)
    }

    init(message: String) {
        self.rows = []
        self.message = message
        self.selectedIndex = 0
    }

    var isMessage: Bool { message != nil }

    var panelWidth: CGFloat { isMessage ? Self.messageWidth : Self.listWidth }

    var preferredHeight: CGFloat {
        if isMessage {
            return Self.messageHeight
        }
        let content = rows.reduce(CGFloat(0)) { total, row in
            total + (row.intention == nil ? Self.headerRowHeight : Self.actionRowHeight)
        }
        return min(content + Self.listPadding * 2, Self.maximumHeight)
    }

    var selectedAction: IntentionAction? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex].intention : nil
    }

    var selectedRowID: String? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex].id : nil
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index), rows[index].intention != nil else { return }
        selectedIndex = index
    }

    func moveSelection(_ delta: Int) {
        let actionIndices = rows.indices.filter { rows[$0].intention != nil }
        guard let position = actionIndices.firstIndex(of: selectedIndex) else { return }
        let count = actionIndices.count
        selectedIndex = actionIndices[((position + delta) % count + count) % count]
    }

    func activate() {
        guard let action = selectedAction else { return }
        onApply?(action)
    }

    func close() {
        dismiss?()
    }

    func handle(event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 53:
            close()
            return true
        case 126:
            moveSelection(-1)
            return true
        case 125:
            moveSelection(1)
            return true
        case 36, 76:
            activate()
            return true
        default:
            return false
        }
    }

    private static func initialSelection(in rows: [IntentionPopupRow]) -> Int {
        let preferred = rows.firstIndex { $0.intention?.isPreferred == true }
        return preferred ?? rows.firstIndex { $0.intention != nil } ?? 0
    }
}
