import AppKit
import SwiftUI

@MainActor
private final class RenameNameResolution {
    var result: String?
    private var continuation: CheckedContinuation<String?, Never>?

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func finish() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class RenamePanelHost {
    static let shared = RenamePanelHost()

    private struct Entry {
        weak var panel: ShowUsagesPanel?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func requestName(for target: RenameTarget, in controller: DreamderWindowController) async -> String? {
        await present(
            RenamePopupViewModel(target: target),
            anchor: LSPCaretAnchor.screenRect(in: controller.window),
            in: controller
        )
    }

    func present(
        _ model: RenamePopupViewModel,
        anchor: NSRect?,
        in controller: DreamderWindowController
    ) async -> String? {
        entries = entries.filter { $0.value.panel != nil }
        guard let window = controller.window else { return nil }
        let key = ObjectIdentifier(controller)
        entries[key]?.panel?.close()

        return await withCheckedContinuation { continuation in
            let size = NSSize(width: model.panelWidth, height: model.preferredHeight)
            let panel = ShowUsagesPanel(size: size)
            let hostingView = NSHostingView(rootView: RenamePopupView(model: model))
            hostingView.sizingOptions = []
            hostingView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hostingView

            let resolution = RenameNameResolution(continuation: continuation)
            model.onConfirm = { [weak panel] name in
                resolution.result = name
                panel?.close()
            }
            model.onCancel = { [weak panel] in
                panel?.close()
            }
            panel.onKeyEvent = { [weak model] event in
                model?.handle(event: event) ?? false
            }
            panel.onClose = { [weak self] in
                self?.entries.removeValue(forKey: key)
                resolution.finish()
            }

            entries[key] = Entry(panel: panel)

            window.addChildWindow(panel, ordered: .above)
            panel.place(in: window, below: anchor)
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class RenamePanelPresenter: RenamePresenting {
    private weak var controller: DreamderWindowController?

    init(controller: DreamderWindowController) {
        self.controller = controller
    }

    func showMessage(_ message: String) {
        guard let controller else { return }
        ShowUsagesPanelHost.shared.showMessage(message, in: controller)
    }

    func requestName(for target: RenameTarget) async -> String? {
        guard let controller else { return nil }
        return await RenamePanelHost.shared.requestName(for: target, in: controller)
    }
}
