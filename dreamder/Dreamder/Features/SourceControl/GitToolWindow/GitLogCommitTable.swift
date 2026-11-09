import SwiftUI

struct GitLogCommitTable: View {
    @Environment(WorkspaceDocument.self) private var workspace: WorkspaceDocument?
    @Environment(SourceControlManager.self) private var sourceControlManager: SourceControlManager?
    @Environment(\.gitLogCommitSeams) private var seams
    let viewModel: GitLogViewModel

    var body: some View {
        let visible = viewModel.visibleCommits
        return Group {
            if viewModel.commits.isEmpty {
                Text(placeholder)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text("No matching commits")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { commit in
                            GitLogCommitRow(
                                commit: commit,
                                graphRow: viewModel.graphRows[commit.hash],
                                laneCount: viewModel.laneCount,
                                isSelected: commit.hash == viewModel.selectedHash,
                                action: selectionAction(hash: commit.hash),
                                actions: commitActions
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func selectionAction(hash: String) -> () -> Void {
        {
            Task {
                await viewModel.select(hash: hash)
            }
        }
    }

    var commitActions: GitLogCommitActions? {
        guard let workspace, let sourceControlManager else { return nil }
        return GitLogCommitActions(
            workspace: workspace,
            manager: sourceControlManager,
            viewModel: viewModel,
            seams: seams
        )
    }

    var placeholder: String {
        if viewModel.isLoading {
            return "Loading commits…"
        }
        if let errorMessage = viewModel.errorMessage {
            return errorMessage
        }
        return "No commits"
    }
}

struct GitLogCommitRow: View {
    let commit: GitLogCommit
    let graphRow: GitLogGraphRow?
    let laneCount: Int
    let isSelected: Bool
    let action: () -> Void
    var actions: GitLogCommitActions?

    @State private var isHovering = false

    private var laneWidth: CGFloat { 12 }

    var body: some View {
        HStack(spacing: 8) {
            if let graphRow {
                GitLogGraphRowView(
                    row: graphRow,
                    laneCount: laneCount,
                    laneWidth: laneWidth,
                    rowHeight: Islands.listRowHeight
                )
            } else {
                Color.clear
                    .frame(width: CGFloat(laneCount) * laneWidth, height: Islands.listRowHeight)
            }

            HStack(spacing: 4) {
                Text(commit.subject)
                    .font(Islands.uiFont)
                    .foregroundStyle(commit.isMerge ? Islands.secondaryForeground : Islands.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                ForEach(commit.refs) { ref in
                    GitLogRefChip(ref: ref)
                }
            }

            Spacer(minLength: 8)

            Text(commit.authorName)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Text(GitLogRelativeDate.string(for: commit.date))
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: Islands.listRowHeight)
        .background(Self.background(isSelected: isSelected, isHovering: isHovering))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .contextMenu {
            if let actions {
                GitLogCommitMenuItems(actions: actions, commit: commit)
            }
        }
        .onHover(perform: setHovering)
        .help(commit.subject)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    static func background(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected { return Islands.selection }
        return isHovering ? Islands.hover : Color.clear
    }
}

struct GitLogRefChip: View {
    let ref: GitLogRef

    var body: some View {
        Text(ref.name)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(background)
            )
    }

    private var foreground: Color {
        switch ref.kind {
        case .head, .branch:
            return Islands.link
        case .remote:
            return Islands.secondaryForeground
        case .tag:
            return Islands.warningForeground
        }
    }

    private var background: Color {
        switch ref.kind {
        case .head, .branch:
            return Islands.tabSelectedBackground
        case .remote:
            return Islands.actionHover
        case .tag:
            return Islands.warningForeground.opacity(0.16)
        }
    }
}
