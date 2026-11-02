import SwiftUI

struct GitLogBranchesPane: View {
    @EnvironmentObject private var sourceControlManager: SourceControlManager
    @ObservedObject var viewModel: GitLogViewModel

    private var localBranches: [GitBranch] {
        sourceControlManager.orderedLocalBranches
    }

    private var remoteBranches: [GitBranch] {
        sourceControlManager.branches
            .filter { $0.isRemote }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GitLogBranchRow(
                    title: "HEAD",
                    subtitle: sourceControlManager.currentBranch?.name,
                    icon: "vcs/currentBranchLabel",
                    isSelected: viewModel.branchFilter.ref == nil
                ) {
                    select(.all)
                }

                if !localBranches.isEmpty {
                    groupHeader("Local")
                    ForEach(localBranches) { branch in
                        GitLogBranchRow(
                            title: branch.name,
                            subtitle: branch.upstream,
                            icon: "vcs/branch",
                            isSelected: viewModel.branchFilter.ref == branch.longName
                        ) {
                            select(GitLogBranchFilter(ref: branch.longName, title: branch.name))
                        }
                    }
                }

                if !remoteBranches.isEmpty {
                    groupHeader("Remote")
                    ForEach(remoteBranches) { branch in
                        GitLogBranchRow(
                            title: branch.name,
                            subtitle: nil,
                            icon: "vcs/branch",
                            isSelected: viewModel.branchFilter.ref == branch.longName
                        ) {
                            select(GitLogBranchFilter(ref: branch.longName, title: branch.name))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Islands.secondaryForeground)
            .padding(.horizontal, 10)
            .frame(height: Islands.listRowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func select(_ filter: GitLogBranchFilter) {
        Task {
            await viewModel.setBranchFilter(filter)
        }
    }
}

struct GitLogBranchRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(icon)
                .resizable()
                .frame(width: 14, height: 14)
            Text(title)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle {
                Text(subtitle)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.actionHover : (isHovering ? Islands.hover : Color.clear))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
    }
}
