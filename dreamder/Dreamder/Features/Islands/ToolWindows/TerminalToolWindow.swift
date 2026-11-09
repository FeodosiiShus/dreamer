import SwiftUI

struct TerminalToolWindowActions {
    let workspace: WorkspaceDocument
    let utilityAreaViewModel: UtilityAreaViewModel

    func tabTitle(_ terminal: UtilityAreaTerminal) -> String {
        let lastComponent = terminal.url.lastPathComponent
        let folderName = lastComponent.isEmpty ? terminal.url.path : lastComponent
        let shellName = terminal.shell?.rawValue
            ?? URL(fileURLWithPath: Shell.autoDetectDefaultShell()).lastPathComponent
        return "\(folderName) — \(shellName)"
    }

    func add() {
        utilityAreaViewModel.addTerminal(rootURL: workspace.fileURL)
    }

    func ensure() {
        guard let workspaceURL = workspace.fileURL else { return }
        utilityAreaViewModel.initializeTerminals(workspaceURL: workspaceURL)
    }

    func close(_ terminal: UtilityAreaTerminal) -> () -> Void {
        { utilityAreaViewModel.removeTerminals([terminal.id]) }
    }

    func select(_ terminal: UtilityAreaTerminal) -> () -> Void {
        { utilityAreaViewModel.selectedTerminals = [terminal.id] }
    }

    func titleChange(_ terminal: UtilityAreaTerminal) -> (String) -> Void {
        { newTitle in
            Task { @MainActor in
                utilityAreaViewModel.updateTerminal(terminal.id, title: newTitle)
            }
        }
    }
}

struct TerminalToolWindowMenuItems: View {
    let actions: TerminalToolWindowActions

    var body: some View {
        ForEach(actions.utilityAreaViewModel.terminals) { terminal in
            Button(action: actions.select(terminal)) {
                Text(actions.tabTitle(terminal))
            }
        }
        if !actions.utilityAreaViewModel.terminals.isEmpty {
            Divider()
        }
        Button("New Terminal", action: actions.add)
    }
}

struct TerminalToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(UtilityAreaViewModel.self) private var utilityAreaViewModel
    @Environment(ToolWindowManager.self) private var toolWindowManager

    init() {}

    private var actions: TerminalToolWindowActions {
        TerminalToolWindowActions(workspace: workspace, utilityAreaViewModel: utilityAreaViewModel)
    }

    private var selectedTerminal: UtilityAreaTerminal? {
        if let id = utilityAreaViewModel.selectedTerminals.first,
           let terminal = utilityAreaViewModel.terminals.first(where: { $0.id == id }) {
            return terminal
        }
        return utilityAreaViewModel.terminals.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Terminal") {
                ForEach(utilityAreaViewModel.terminals) { terminal in
                    ToolWindowTab(
                        title: actions.tabTitle(terminal),
                        icon: "toolwindows/terminal",
                        isSelected: terminal.id == selectedTerminal?.id,
                        onClose: actions.close(terminal),
                        action: actions.select(terminal)
                    )
                }
            } actions: {
                ToolWindowActionButton(icon: "general/add", help: "New Terminal", action: actions.add)
                Menu { TerminalToolWindowMenuItems(actions: actions) } label: {
                    Image("general/chevronDown")
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show Terminals")
                ToolWindowActionButton(
                    icon: "general/hide",
                    help: "Hide",
                    action: toolWindowManager.hideCallback(for: .terminal)
                )
            }

            terminalContent
        }
        .background(Color.clear)
        .onAppear(perform: actions.ensure)
    }

    @ViewBuilder private var terminalContent: some View {
        if let terminal = selectedTerminal {
            TerminalEmulatorView(
                url: terminal.url,
                terminalID: terminal.id,
                shellType: terminal.shell,
                onTitleChange: actions.titleChange(terminal)
            )
            .id(terminal.id)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No Terminal")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
