import SwiftUI

enum ProjectToolWindowViewMode: String, CaseIterable, Identifiable {
    case project
    case openFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project: "Project"
        case .openFiles: "Open Files"
        }
    }
}

@Observable
final class ProjectToolWindowState {
    var viewMode: ProjectToolWindowViewMode
    @ObservationIgnored let controllerReference = ProjectNavigatorControllerReference()

    init(viewMode: ProjectToolWindowViewMode = .project) {
        self.viewMode = viewMode
    }

    func selectionBinding(for mode: ProjectToolWindowViewMode) -> Binding<Bool> {
        Binding(
            get: { self.viewMode == mode },
            set: { isSelected in
                if isSelected {
                    self.viewMode = mode
                }
            }
        )
    }
}

struct ProjectToolWindowActions {
    let state: ProjectToolWindowState

    func revealOpenedFile() {
        state.controllerReference.controller?.revealFile(nil)
    }

    func expandAll() {
        state.controllerReference.controller?.expandAll(nil)
    }

    func collapseAll() {
        state.controllerReference.controller?.collapseAll(nil)
    }

    func clearSearchFieldFocus() {
        Task { @MainActor in
            state.controllerReference.controller?.clearSearchFieldFocus()
        }
    }
}

struct ProjectToolWindowViewModeToggles: View {
    let state: ProjectToolWindowState

    var body: some View {
        ForEach(ProjectToolWindowViewMode.allCases) { mode in
            Toggle(mode.title, isOn: state.selectionBinding(for: mode))
        }
    }
}

struct ProjectToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(ToolWindowManager.self) private var toolWindowManager

    @State private var state: ProjectToolWindowState
    @FocusState private var filterFocused: Bool
    @State private var clearedInitialFocus = false

    init(state: ProjectToolWindowState = ProjectToolWindowState()) {
        _state = State(initialValue: state)
    }

    private var actions: ProjectToolWindowActions {
        ProjectToolWindowActions(state: state)
    }

    var body: some View {
        @Bindable var workspace = workspace
        VStack(spacing: 0) {
            ToolWindowHeader(title: state.viewMode.title) {
                Menu { ProjectToolWindowViewModeToggles(state: state) } label: {
                    Image("general/chevronDown")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 12, height: 12)
                        .opacity(0.8)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Views")
            } actions: {
                if state.viewMode == .project {
                    ToolWindowActionButton(
                        icon: "general/locate",
                        help: "Select Opened File",
                        action: actions.revealOpenedFile
                    )
                    ToolWindowActionButton(icon: "general/expandAll", help: "Expand All", action: actions.expandAll)
                    ToolWindowActionButton(
                        icon: "general/collapseAll",
                        help: "Collapse All",
                        action: actions.collapseAll
                    )
                }
                ToolWindowActionButton(
                    icon: "general/hide",
                    help: "Hide",
                    action: toolWindowManager.hideCallback(for: .project)
                )
            }

            if state.viewMode == .project {
                IslandSearchField("Search", text: $workspace.navigatorFilter, focus: $filterFocused)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                ProjectNavigatorOutlineView(controllerReference: state.controllerReference)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProjectNavigatorOpenFilesView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
        .onAppear(perform: actions.clearSearchFieldFocus)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard !clearedInitialFocus else { return }
            clearedInitialFocus = true
            actions.clearSearchFieldFocus()
        }
        .onChange(of: state.viewMode) { _, mode in
            guard mode == .project else { return }
            actions.clearSearchFieldFocus()
        }
    }
}
