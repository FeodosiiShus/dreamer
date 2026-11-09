import SwiftUI

struct ProblemsCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandMenu("Problems") {
            ProblemsMenuContent(workspace: windowController?.workspace)
        }
    }
}

struct ProblemsMenuContent: View {
    let workspace: WorkspaceDocument?

    var body: some View {
        Button("Next Problem") {
            ProblemsNavigator.navigate(.next, workspace: workspace)
        }
        .keymapShortcut(.nextProblem)
        .disabled(!ProblemsNavigator.hasProblems(workspace: workspace))

        Button("Previous Problem") {
            ProblemsNavigator.navigate(.previous, workspace: workspace)
        }
        .keymapShortcut(.previousProblem)
        .disabled(!ProblemsNavigator.hasProblems(workspace: workspace))
    }
}
