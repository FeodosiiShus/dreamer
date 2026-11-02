import SwiftUI

struct FindToolWindow: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @EnvironmentObject private var toolWindowManager: ToolWindowManager

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Find") {
                EmptyView()
            } actions: {
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.bottom)
                }
            }
            FindNavigatorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .onAppear {
            workspace.searchState?.shouldFocusSearchField = true
        }
    }
}
