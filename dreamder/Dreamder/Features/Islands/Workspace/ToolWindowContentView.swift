import SwiftUI

struct ToolWindowContentView: View {
    let id: ToolWindowID

    var body: some View {
        switch id {
        case .project:
            ProjectToolWindow()
        case .commit:
            CommitToolWindow()
        case .structure:
            StructureToolWindow()
        case .run:
            RunToolWindow()
        case .find:
            FindToolWindow()
        case .terminal:
            TerminalToolWindow()
        case .problems:
            ProblemsToolWindow()
        case .git:
            GitToolWindow()
        case .languageServices:
            LanguageServicesToolWindow()
        }
    }
}
