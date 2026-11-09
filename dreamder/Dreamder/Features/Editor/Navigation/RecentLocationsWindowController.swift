import AppKit
import SwiftUI

@MainActor
final class RecentLocationsPanelHost {
    static let shared = RecentLocationsPanelHost()
    static let panelSize = NSSize(width: 700, height: 530)

    private struct Entry {
        weak var panel: ShowUsagesPanel?
        let model: RecentLocationsViewModel
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func show(in controller: DreamderWindowController) {
        entries = entries.filter { $0.value.panel != nil }
        let key = ObjectIdentifier(controller)
        if let existing = entries[key] {
            existing.model.showChangedOnly.toggle()
            return
        }
        guard let workspace = controller.workspace, let window = controller.window else { return }

        let model = RecentLocationsViewModel(
            tracker: RecentLocationsStore.shared.history(for: workspace),
            workspace: workspace
        )
        let panel = ShowUsagesPanel(size: Self.panelSize)
        let hostingView = NSHostingView(rootView: RecentLocationsView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hostingView

        model.dismiss = { [weak panel] restoresFocus in
            panel?.restoresFocusOnClose = restoresFocus
            panel?.close()
        }
        panel.onKeyEvent = { [weak model] event in
            guard let model else { return false }
            return model.handle(event: event)
        }
        panel.onClose = { [weak self] in
            self?.entries.removeValue(forKey: key)
        }

        entries[key] = Entry(panel: panel, model: model)

        window.addChildWindow(panel, ordered: .above)
        panel.place(in: window, below: nil)
        panel.makeKeyAndOrderFront(nil)
    }
}

extension DreamderWindowController {
    @IBAction func showRecentLocations(_ sender: Any?) {
        RecentLocationsPanelHost.shared.show(in: self)
    }
}
