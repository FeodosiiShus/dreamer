import AppKit
import Observation

@MainActor
@Observable
final class DefinitionChooserViewModel {
    let rows: [LSPUsageRow]
    var selectedIndex: Int = 0

    let title: String
    let message: String?

    @ObservationIgnored
    var dismiss: (() -> Void)?
    @ObservationIgnored
    var openRow: ((LSPUsageRow) -> Void)?

    init(rows: [LSPUsageRow], kind: LSPNavigationKind) {
        self.rows = rows
        self.title = kind.chooserTitle
        self.message = nil
    }

    init(message: String, title: String) {
        self.rows = []
        self.title = title
        self.message = message
    }

    var isMessage: Bool { message != nil }

    var panelWidth: CGFloat { isMessage ? 380 : 620 }

    var preferredHeight: CGFloat {
        if isMessage {
            return 80
        }
        return min(CGFloat(rows.count) * 24 + 42, 420)
    }

    var selectedRow: LSPUsageRow? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
    }

    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let count = rows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    func activate() {
        guard let row = selectedRow else { return }
        openRow?(row)
    }

    func open(_ index: Int) {
        select(index)
        activate()
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
}
