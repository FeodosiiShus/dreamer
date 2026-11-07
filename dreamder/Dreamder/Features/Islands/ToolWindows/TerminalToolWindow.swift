import SwiftUI

struct TerminalToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(UtilityAreaViewModel.self) private var utilityAreaViewModel
    @Environment(ToolWindowManager.self) private var toolWindowManager

    init() {}

    private var selectedTerminal: UtilityAreaTerminal? {
        if let id = utilityAreaViewModel.selectedTerminals.first,
           let terminal = utilityAreaViewModel.terminals.first(where: { $0.id == id }) {
            return terminal
        }
        return utilityAreaViewModel.terminals.first
    }

    private func tabTitle(_ terminal: UtilityAreaTerminal) -> String {
        let lastComponent = terminal.url.lastPathComponent
        let folderName = lastComponent.isEmpty ? terminal.url.path : lastComponent
        let shellName = terminal.shell?.rawValue
            ?? URL(fileURLWithPath: Shell.autoDetectDefaultShell()).lastPathComponent
        return "\(folderName) — \(shellName)"
    }

    private func addTerminal() {
        utilityAreaViewModel.addTerminal(rootURL: workspace.fileURL)
    }

    private func ensureTerminal() {
        guard let workspaceURL = workspace.fileURL else { return }
        utilityAreaViewModel.initializeTerminals(workspaceURL: workspaceURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Terminal") {
                ForEach(utilityAreaViewModel.terminals) { terminal in
                    ToolWindowTab(
                        title: tabTitle(terminal),
                        icon: "toolwindows/terminal",
                        isSelected: terminal.id == selectedTerminal?.id,
                        onClose: {
                            utilityAreaViewModel.removeTerminals([terminal.id])
                        },
                        action: {
                            utilityAreaViewModel.selectedTerminals = [terminal.id]
                        }
                    )
                }
            } actions: {
                ToolWindowActionButton(icon: "general/add", help: "New Terminal") {
                    addTerminal()
                }
                Menu {
                    ForEach(utilityAreaViewModel.terminals) { terminal in
                        Button {
                            utilityAreaViewModel.selectedTerminals = [terminal.id]
                        } label: {
                            Text(tabTitle(terminal))
                        }
                    }
                    if !utilityAreaViewModel.terminals.isEmpty {
                        Divider()
                    }
                    Button("New Terminal") {
                        addTerminal()
                    }
                } label: {
                    Image("general/chevronDown")
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show Terminals")
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.bottom)
                }
            }

            terminalContent
        }
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
        .onAppear(perform: ensureTerminal)
    }

    @ViewBuilder private var terminalContent: some View {
        if let terminal = selectedTerminal {
            TerminalEmulatorView(
                url: terminal.url,
                terminalID: terminal.id,
                shellType: terminal.shell,
                onTitleChange: { newTitle in
                    DispatchQueue.main.async {
                        utilityAreaViewModel.updateTerminal(terminal.id, title: newTitle)
                    }
                }
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
