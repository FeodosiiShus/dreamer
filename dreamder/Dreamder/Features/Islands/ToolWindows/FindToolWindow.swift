import SwiftUI

struct FindToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(ToolWindowManager.self) private var toolWindowManager

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Find") {
                EmptyView()
            } actions: {
                ToolWindowActionButton(
                    icon: "general/hide",
                    help: "Hide",
                    action: toolWindowManager.hideCallback(for: .find)
                )
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
