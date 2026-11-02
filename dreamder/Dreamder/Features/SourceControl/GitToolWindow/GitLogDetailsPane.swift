import SwiftUI

struct GitLogDetailsPane: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @EnvironmentObject private var sourceControlManager: SourceControlManager
    @ObservedObject var viewModel: GitLogViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let commit = viewModel.selectedCommit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        changedFilesSection
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

    private var changedFilesSection: some View {
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
                    onShowDiff: { showDiff(file) },
                    onOpen: { open(file) }
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

    private func showDiff(_ file: GitChangedFile) {
        guard let commit = viewModel.selectedCommit else { return }
        let path = DiffPath.relativePath(of: file.fileURL, from: sourceControlManager.repositoryURL)
        guard !path.isEmpty else { return }
        DiffViewerPresenter.showCommitFileDiff(
            workspace: workspace,
            commitHash: commit.hash,
            parentHash: commit.parents.first,
            path: path
        )
    }

    private func open(_ file: GitChangedFile) {
        guard file.status != .deleted else { return }
        guard let ceFile = workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        DispatchQueue.main.async {
            workspace.editorManager?.openTab(item: ceFile, asTemporary: true)
        }
    }
}

struct GitLogChangedFileRow: View {
    let file: GitChangedFile
    let directory: String
    let onShowDiff: () -> Void
    let onOpen: () -> Void

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
        .background(isHovering ? Islands.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onShowDiff)
        .contextMenu {
            Button("Open File", action: onOpen)
        }
        .help(file.fileURL.relativePath)
    }
}
