import AppKit
import SwiftUI

struct StructurePopupView: View {
    static let size = NSSize(width: 460, height: 420)

    let model: StructureViewModel
    let workspace: WorkspaceDocument
    var dismiss: () -> Void = {}

    private var lspService: LSPService { .shared }

    var body: some View {
        VStack(spacing: 0) {
            Text("File Structure")
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: Islands.popupHeaderHeight)
            StructureFilterField(
                model: model,
                workspace: workspace,
                onSubmit: model.submission(workspace: workspace, then: dismiss)
            )
            if model.rows.isEmpty {
                Text(model.isLoading ? "Loading Symbols…" : "No symbols found")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StructureTreeView(model: model, workspace: workspace, activatesOnClick: true, onActivate: dismiss)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .glassPopup()
        .accessibilityIdentifier("StructurePopup")
        .onAppear { model.start(workspace: workspace, lspService: lspService) }
    }
}

@MainActor
final class StructurePopupHost {
    static let shared = StructurePopupHost()

    private struct WeakPanel {
        weak var panel: ShowUsagesPanel?
    }

    private static let escapeKeyCode: UInt16 = 53
    private static let downArrowKeyCode: UInt16 = 125
    private static let upArrowKeyCode: UInt16 = 126

    private var panels: [ObjectIdentifier: WeakPanel] = [:]

    func show(in controller: DreamderWindowController) {
        panels = panels.filter { $0.value.panel != nil }
        guard let window = controller.window, let workspace = controller.workspace else { return }
        let key = ObjectIdentifier(controller)
        panels[key]?.panel?.close()

        let model = StructureViewModel()
        let panel = ShowUsagesPanel(size: StructurePopupView.size)
        let view = StructurePopupView(model: model, workspace: workspace) { [weak panel] in
            panel?.restoresFocusOnClose = false
            panel?.close()
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: StructurePopupView.size)
        panel.contentView = hostingView
        panel.onKeyEvent = { [weak panel, model] event in
            switch event.keyCode {
            case Self.escapeKeyCode:
                panel?.close()
            case Self.downArrowKeyCode:
                model.moveSelection(by: 1, workspace: workspace)
            case Self.upArrowKeyCode:
                model.moveSelection(by: -1, workspace: workspace)
            default:
                return false
            }
            return true
        }
        panel.onClose = { [weak self] in
            self?.panels.removeValue(forKey: key)
        }
        panels[key] = WeakPanel(panel: panel)

        window.addChildWindow(panel, ordered: .above)
        panel.place(in: window, below: nil)
        panel.makeKeyAndOrderFront(nil)
    }
}

extension DreamderWindowController {
    @IBAction func showFileStructure(_ sender: Any?) {
        StructurePopupHost.shared.show(in: self)
    }
}
