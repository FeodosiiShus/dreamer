import SwiftUI
import Combine

struct ToolbarBranchPicker: View {
    private let sourceControlManager: SourceControlManager?
    private let settings: Settings
    private let hover: MainToolbarHoverState

    init(
        sourceControlManager: SourceControlManager?,
        settings: Settings = .shared,
        hover: MainToolbarHoverState = MainToolbarHoverState()
    ) {
        self.sourceControlManager = sourceControlManager
        self.settings = settings
        self.hover = hover
    }

    var body: some View {
        if let sourceControlManager {
            ToolbarBranchPickerContent(sourceControlManager: sourceControlManager, settings: settings, hover: hover)
        }
    }
}

private struct ToolbarBranchPickerContent: View {
    let sourceControlManager: SourceControlManager
    let settings: Settings
    @Environment(WorkspaceDocument.self) private var workspace

    @State private var anchor = ToolbarPopupAnchor()
    @State private var hover: MainToolbarHoverState

    init(sourceControlManager: SourceControlManager, settings: Settings, hover: MainToolbarHoverState) {
        self.sourceControlManager = sourceControlManager
        self.settings = settings
        _hover = State(initialValue: hover)
    }

    var body: some View {
        if sourceControlManager.isGitRepository {
            Button(action: presentBranches) {
                label
            }
            .buttonStyle(.actionButton(look: .mainToolbarDropdown, isHovering: hover.isHovering))
            .onHover(perform: hover.setHovering)
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
        MainToolbarDropdownLabel(text: sourceControlManager.currentBranch?.name ?? "No branch") {
            Image("vcs/branch")
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        }
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
