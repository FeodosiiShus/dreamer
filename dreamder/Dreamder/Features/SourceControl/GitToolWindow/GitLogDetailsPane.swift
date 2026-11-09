import SwiftUI

struct GitLogDetailsPane: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager
    let viewModel: GitLogViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let commit = viewModel.selectedCommit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        changedFilesSection(commit)
                        Rectangle()
                            .fill(Islands.separator)
                            .frame(height: 1)
                        detailsSection(commit)
                    }
                }
            } else {
                Text("Select a commit to view details")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func changedFilesSection(_ commit: GitLogCommit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fileSectionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.horizontal, 10)
                .frame(height: Islands.listRowHeight, alignment: .leading)

            ForEach(viewModel.selectedFiles) { file in
                GitLogChangedFileRow(
                    file: file,
                    directory: file.gitRelativeDirectory(from: sourceControlManager.repositoryURL),
                    onShowDiff: { showDiff(file, in: commit) },
                    onOpen: { open(file) },
                    onOpenInNewWindow: { openInNewWindow(file) },
                    onReveal: { revealInProject(file) }
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var fileSectionTitle: String {
        let count = viewModel.selectedFiles.count
        switch count {
        case 0: return "No changed files"
        case 1: return "1 file"
        default: return "\(count) files"
        }
    }

    private func detailsSection(_ commit: GitLogCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.refs) { ref in
                        GitLogRefChip(ref: ref)
                    }
                }
            }

            Text(commit.shortHash)
                .font(Islands.codeFont)
                .foregroundStyle(Islands.secondaryForeground)
                .textSelection(.enabled)

            Text(commit.authorName)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)

            Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)

            Text(viewModel.selectedMessage)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.editorForeground)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private func showDiff(_ file: GitChangedFile, in commit: GitLogCommit) {
        DiffViewerPresenter.showCommitFileDiff(
            workspace: workspace,
            commitHash: commit.hash,
            parentHash: commit.parents.first,
            path: DiffPath.relativePath(of: file.fileURL, from: sourceControlManager.repositoryURL)
        )
    }

    private func workspaceFile(for file: GitChangedFile) -> CEWorkspaceFile? {
        guard file.status != .deleted else { return nil }
        return workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true)
    }

    private func open(_ file: GitChangedFile) {
        guard let ceFile = workspaceFile(for: file) else { return }
        Task { @MainActor in
            workspace.editorManager?.openTab(item: ceFile, asTemporary: true)
        }
    }

    private func openInNewWindow(_ file: GitChangedFile) {
        guard let ceFile = workspaceFile(for: file) else { return }
        if ceFile.fileDocument == nil {
            try? ceFile.loadCodeFile()
        }
        guard let document = ceFile.fileDocument else { return }
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }
        document.showWindows()
    }

    private func revealInProject(_ file: GitChangedFile) {
        guard let ceFile = workspaceFile(for: file) else { return }
        workspace.toolWindowManager.show(.project)
        workspace.listenerModel.highlightedFileItem = ceFile
    }
}

struct GitLogChangedFileRow: View {
    let file: GitChangedFile
    let directory: String
    let onShowDiff: () -> Void
    let onOpen: () -> Void
    let onOpenInNewWindow: () -> Void
    let onReveal: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(IntelliJIcon.fileIcon(for: file.fileURL.lastPathComponent))
                .resizable()
                .frame(width: 16, height: 16)
            Text(file.fileURL.lastPathComponent)
                .font(Islands.uiFont)
                .foregroundStyle(file.anyStatus().fileStatusColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Text(directory)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.disabledForeground)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.listRowHeight)
        .background(Self.background(isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover(perform: setHovering)
        .onTapGesture(count: 2, perform: onShowDiff)
        .contextMenu {
            Button("Show Diff", action: onShowDiff)
            Button("Open File", action: onOpen)
            Button("Open in New Window", action: onOpenInNewWindow)
            Divider()
            Button("Reveal in Project Navigator", action: onReveal)
        }
        .help(file.fileURL.relativePath)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    static func background(isHovering: Bool) -> Color {
        isHovering ? Islands.hover : Color.clear
    }
}
