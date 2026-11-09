import AppKit

@MainActor
enum LSPCompletionPreviewRefresher {
    static func refresh(parent window: NSWindow?) {
        for child in window?.childWindows ?? [] {
            guard let table = firstTableView(in: child.contentView), table.selectedRow >= 0 else { continue }
            NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: table)
        }
    }

    private static func firstTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView {
            return table
        }
        for subview in view.subviews {
            if let table = firstTableView(in: subview) {
                return table
            }
        }
        return nil
    }
}
