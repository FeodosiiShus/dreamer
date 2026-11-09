import SwiftUI

struct GitLogBranchesPane: View {
    @Environment(SourceControlManager.self) private var sourceControlManager
    let viewModel: GitLogViewModel

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
                    isSelected: viewModel.filters.branch == nil,
                    action: selectionAction(nil)
                )

                if !localBranches.isEmpty {
                    groupHeader("Local")
                    ForEach(localBranches) { branch in
                        GitLogBranchRow(
                            title: branch.name,
                            subtitle: branch.upstream,
                            icon: "vcs/branch",
                            isSelected: viewModel.filters.branch == .fromBranch(branch.logFilterName),
                            action: selectionAction(.fromBranch(branch.logFilterName))
                        )
                    }
                }

                if !remoteBranches.isEmpty {
                    groupHeader("Remote")
                    ForEach(remoteBranches) { branch in
                        GitLogBranchRow(
                            title: branch.name,
                            subtitle: nil,
                            icon: "vcs/branch",
                            isSelected: viewModel.filters.branch == .fromBranch(branch.logFilterName),
                            action: selectionAction(.fromBranch(branch.logFilterName))
                        )
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

    func selectionAction(_ filter: GitLogBranchFilter?) -> () -> Void {
        {
            Task {
                await viewModel.setBranchFilter(filter)
            }
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
                .fill(Self.background(isSelected: isSelected, isHovering: isHovering))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover(perform: setHovering)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    static func background(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected { return Islands.actionHover }
        return isHovering ? Islands.hover : Color.clear
    }
}

extension GitBranch {
    var logFilterName: String {
        let remotePrefix = "refs/remotes/"
        guard isRemote, longName.hasPrefix(remotePrefix) else { return name }
        return String(longName.dropFirst(remotePrefix.count))
    }
}
