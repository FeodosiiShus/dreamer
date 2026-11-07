import AppKit
import SwiftUI

struct GitToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var viewModel = GitLogViewModel()
    @State private var branchesWidth: CGFloat = 210
    @State private var detailsWidth: CGFloat = 320
    @State private var showsConsole = false

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(
                title: "Git",
                tabs: {
                    ToolWindowTab(title: viewModel.tabTitle, isSelected: !showsConsole) {
                        showsConsole = false
                    }
                    GitConsoleTab(
                        log: GitConsoleLog.log(for: sourceControlManager.repositoryURL),
                        isSelected: $showsConsole
                    )
                },
                actions: {
                    ToolWindowActionButton(icon: "general/refresh", help: "Refresh") {
                        Task {
                            await refresh()
                        }
                    }
                    ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                        workspace.toolWindowManager.hide(ToolWindowID.git.anchor)
                    }
                }
            )

            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)

            if showsConsole {
                GitConsoleView(log: GitConsoleLog.log(for: sourceControlManager.repositoryURL))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sourceControlManager.isGitRepository {
                content
            } else {
                Text("Not a git repository")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task {
            await refresh()
        }
        .onChange(of: sourceControlManager.isGitRepository) { _, isRepository in
            guard isRepository else { return }
            Task {
                await refresh()
            }
        }
        .onChange(of: sourceControlManager.currentBranch) { _, _ in
            guard sourceControlManager.isGitRepository else { return }
            Task {
                await viewModel.load(manager: sourceControlManager)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            GitLogBranchesPane(viewModel: viewModel)
                .frame(width: branchesWidth)

            GitPaneDivider(width: $branchesWidth, range: 150...420)

            VStack(spacing: 0) {
                GitLogFilterField(text: $viewModel.searchText)
                GitLogCommitTable(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GitPaneDivider(width: $detailsWidth, range: 220...620, inverted: true)

            GitLogDetailsPane(viewModel: viewModel)
                .frame(width: detailsWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func refresh() async {
        await sourceControlManager.refreshBranches()
        await sourceControlManager.refreshCurrentBranch()
        await viewModel.load(manager: sourceControlManager)
    }
}

struct GitPaneDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    var inverted = false

    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(width: 1)
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil {
                            startWidth = width
                        }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        width = min(max(base + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        startWidth = nil
                    }
            )
    }
}
