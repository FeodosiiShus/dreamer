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

struct ProjectToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(ToolWindowManager.self) private var toolWindowManager

    @State private var controllerReference = ProjectNavigatorControllerReference()
    @State private var viewMode: ProjectToolWindowViewMode = .project
    @FocusState private var filterFocused: Bool
    @State private var clearedInitialFocus = false

    init() {}

    var body: some View {
        @Bindable var workspace = workspace
        VStack(spacing: 0) {
            ToolWindowHeader(title: viewMode.title) {
                Menu {
                    ForEach(ProjectToolWindowViewMode.allCases) { mode in
                        Toggle(mode.title, isOn: selectionBinding(for: mode))
                    }
                } label: {
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
                if viewMode == .project {
                    ToolWindowActionButton(icon: "general/locate", help: "Select Opened File") {
                        controllerReference.controller?.revealFile(nil)
                    }
                    ToolWindowActionButton(icon: "general/expandAll", help: "Expand All") {
                        controllerReference.controller?.expandAll(nil)
                    }
                    ToolWindowActionButton(icon: "general/collapseAll", help: "Collapse All") {
                        controllerReference.controller?.collapseAll(nil)
                    }
                }
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.left)
                }
            }

            if viewMode == .project {
                IslandSearchField("Search", text: $workspace.navigatorFilter, focus: $filterFocused)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                ProjectNavigatorOutlineView(controllerReference: controllerReference)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProjectNavigatorOpenFilesView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
        .onAppear {
            DispatchQueue.main.async {
                controllerReference.controller?.clearSearchFieldFocus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard !clearedInitialFocus else { return }
            clearedInitialFocus = true
            DispatchQueue.main.async {
                controllerReference.controller?.clearSearchFieldFocus()
            }
        }
        .onChange(of: viewMode) { _, mode in
            guard mode == .project else { return }
            DispatchQueue.main.async {
                controllerReference.controller?.clearSearchFieldFocus()
            }
        }
    }

    private func selectionBinding(for mode: ProjectToolWindowViewMode) -> Binding<Bool> {
        Binding(
            get: { viewMode == mode },
            set: { isSelected in
                if isSelected {
                    viewMode = mode
                }
            }
        )
    }
}
