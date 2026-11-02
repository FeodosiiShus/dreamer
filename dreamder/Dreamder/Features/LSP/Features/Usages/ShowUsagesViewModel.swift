import AppKit
import Combine

@MainActor
final class ShowUsagesViewModel: ObservableObject {
    @Published private(set) var rows: [LSPUsageRow]
    @Published var selectedIndex: Int = 0

    let symbol: String
    let message: String?

    var dismiss: (() -> Void)?
    var openRow: ((LSPUsageRow) -> Void)?

    init(rows: [LSPUsageRow], symbol: String) {
        self.rows = rows
        self.symbol = symbol
        self.message = nil
    }

    init(message: String) {
        self.rows = []
        self.symbol = ""
        self.message = message
    }

    var isMessage: Bool { message != nil }

    var headerTitle: String {
        symbol.isEmpty ? "Usages" : "Usages of \(symbol)"
    }

    var countText: String {
        rows.count == 1 ? "1 usage" : "\(rows.count) usages"
    }

    var panelWidth: CGFloat { isMessage ? 380 : 620 }

    var preferredHeight: CGFloat {
        if isMessage {
            return 80
        }
        return min(CGFloat(rows.count) * 22 + 42, 420)
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
