import SwiftUI
import Combine

struct ToolbarBranchPicker: View {
    private let sourceControlManager: SourceControlManager?
    private let settings: Settings

    init(sourceControlManager: SourceControlManager?, settings: Settings = .shared) {
        self.sourceControlManager = sourceControlManager
        self.settings = settings
    }

    var body: some View {
        if let sourceControlManager {
            ToolbarBranchPickerContent(sourceControlManager: sourceControlManager, settings: settings)
        }
    }
}

private struct ToolbarBranchPickerContent: View {
    let sourceControlManager: SourceControlManager
    let settings: Settings
    @Environment(WorkspaceDocument.self) private var workspace

    @State private var anchor = ToolbarPopupAnchor()
    @State private var isHovering = false

    var body: some View {
        if sourceControlManager.isGitRepository {
            Button(action: presentBranches) {
                label
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(sourceControlManager.currentBranch?.name ?? "No branch")
            .background(ToolbarPopupAnchorView(anchor: anchor))
            .task {
                if settings.preferences.sourceControl.general.sourceControlIsEnabled {
                    await sourceControlManager.refreshCurrentBranch()
                    await sourceControlManager.refreshBranches()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showGitBranchesPopup)) { notification in
                if (notification.object as? WorkspaceDocument) === workspace {
                    presentBranches()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Git Branch")
            .accessibilityValue(sourceControlManager.currentBranch?.name ?? "No branch")
            .accessibilityAddTraits(.isButton)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image("vcs/branch")
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(sourceControlManager.currentBranch?.name ?? "No branch")
                .font(Islands.uiFont)
                .foregroundColor(Islands.foreground)
                .lineLimit(1)
            Image("general/chevronDown")
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 6)
        .frame(height: Islands.toolbarControlHeight)
        .background {
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(isHovering ? Islands.actionHover : Color.clear)
        }
        .contentShape(Rectangle())
    }

    private func presentBranches() {
        guard let anchorView = anchor.view else { return }
        BranchesPopupPanelHost.shared.show(
            sourceControlManager: sourceControlManager,
            workspace: workspace,
            anchoredTo: anchorView
        )
    }
}
