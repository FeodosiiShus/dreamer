import AppKit
import CodeEditSourceEditor
import SwiftUI

@MainActor
final class DefinitionChooserPanelHost {
    static let shared = DefinitionChooserPanelHost()

    private struct Entry {
        weak var panel: ShowUsagesPanel?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func show(rows: [LSPUsageRow], kind: LSPNavigationKind, in controller: DreamderWindowController) {
        present(DefinitionChooserViewModel(rows: rows, kind: kind), in: controller)
    }

    func showMessage(_ message: String, title: String, in controller: DreamderWindowController) {
        present(DefinitionChooserViewModel(message: message, title: title), in: controller)
    }

    private func present(_ model: DefinitionChooserViewModel, in controller: DreamderWindowController) {
        guard let window = controller.window else { return }
        let key = ObjectIdentifier(controller)
        entries[key]?.panel?.close()

        let size = NSSize(width: model.panelWidth, height: model.preferredHeight)
        let panel = ShowUsagesPanel(size: size)
        let hostingView = NSHostingView(rootView: DefinitionChooserView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        model.dismiss = { [weak panel] in
            panel?.close()
        }
        model.openRow = { [weak panel, weak controller] row in
            panel?.restoresFocusOnClose = false
            panel?.close()
            guard let workspace = controller?.workspace else { return }
            LSPDefinitionNavigator.jump(
                url: row.fileURL,
                position: CursorPosition(line: row.line + 1, column: row.column + 1),
                in: workspace
            )
        }
        panel.onKeyEvent = { event in
            model.handle(event: event)
        }
        panel.onClose = { [weak self] in
            self?.entries.removeValue(forKey: key)
        }

        entries[key] = Entry(panel: panel)

        window.addChildWindow(panel, ordered: .above)
        panel.place(in: window, below: LSPCaretAnchor.screenRect(in: window))
        panel.makeKeyAndOrderFront(nil)
    }
}
