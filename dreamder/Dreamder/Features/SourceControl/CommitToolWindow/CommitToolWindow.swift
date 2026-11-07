import AppKit
import SwiftUI

struct CommitToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var viewModel = CommitToolWindowViewModel()

    private var files: [GitChangedFile] {
        sourceControlManager.changedFiles
    }

    private var versionedFiles: [GitChangedFile] {
        viewModel.versionedFiles(in: files)
    }

    private var unversionedFiles: [GitChangedFile] {
        viewModel.unversionedFiles(in: files)
    }

    private var includedFiles: [GitChangedFile] {
        files.filter { viewModel.isIncluded($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(
                title: "Commit",
                tabs: { EmptyView() },
                actions: {
                    ToolWindowActionButton(icon: "general/refresh", help: "Refresh") {
                        Task {
                            await refresh()
                        }
                    }
                    ToolWindowActionButton(icon: "vcs/revert", help: "Rollback") {
                        rollback()
                    }
                    ToolWindowActionButton(icon: "vcs/update", help: "Fetch") {
                        Task {
                            await fetch()
                        }
                    }
                    ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                        workspace.toolWindowManager.hide(ToolWindowID.commit.anchor)
                    }
                }
            )

            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)

            if sourceControlManager.isGitRepository {
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
    }

    private var content: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                Text("No changes")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !versionedFiles.isEmpty {
                            groupHeader("Changes", count: versionedFiles.count)
                            ForEach(versionedFiles) { file in
                                row(for: file)
                            }
                        }
                        if !unversionedFiles.isEmpty {
                            groupHeader("Unversioned Files", count: unversionedFiles.count)
                            ForEach(unversionedFiles) { file in
                                row(for: file)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)

            commitArea
        }
    }

    private var commitArea: some View {
        VStack(spacing: 8) {
            CommitMessageEditor(text: $viewModel.message)
                .frame(height: 84)

            HStack(spacing: 8) {
                Toggle(isOn: $viewModel.amend) {
                    Text("Amend")
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                Button {
                    Task {
                        await viewModel.commit(using: sourceControlManager, andPush: false)
                    }
                } label: {
                    Text("Commit")
                        .font(Islands.uiFont.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: Islands.controlRadius)
                                .fill(Islands.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
                .opacity(canCommit ? Double(1) : Double(0.45))

                Button {
                    Task {
                        await viewModel.commit(using: sourceControlManager, andPush: true)
                    }
                } label: {
                    Text("Commit and Push…")
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: Islands.controlRadius)
                                .fill(Islands.islandRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Islands.controlRadius)
                                .strokeBorder(Islands.componentBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
                .opacity(canCommit ? Double(1) : Double(0.45))
            }
        }
        .padding(10)
    }

    private var canCommit: Bool {
        viewModel.canCommit(in: files)
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Islands.secondaryForeground)
            Text(count == 1 ? "1 file" : "\(count) files")
                .font(.system(size: 11))
                .foregroundStyle(Islands.disabledForeground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Islands.listRowHeight)
    }

    private func row(for file: GitChangedFile) -> some View {
        CommitChangedFileRow(
            file: file,
            directory: file.gitRelativeDirectory(from: sourceControlManager.workspaceURL),
            isIncluded: viewModel.isIncluded(file),
            onToggle: { viewModel.setIncluded($0, for: file) },
            onShowDiff: { showDiff(file) },
            onOpen: { open(file) },
            onRollback: { rollback(file) },
            onShowInProject: { showInProject(file) }
        )
    }

    private func rollback() {
        let targets = includedFiles
        guard !targets.isEmpty else { return }
        let message = targets.count == 1
            ? "Discard local changes to \"\(targets[0].fileURL.lastPathComponent)\"?"
            : "Discard local changes to \(targets.count) files?"
        guard confirmRollback(message) else { return }
        Task {
            await viewModel.rollback(targets, using: sourceControlManager)
        }
    }

    private func rollback(_ file: GitChangedFile) {
        let message = "Discard local changes to \"\(file.fileURL.lastPathComponent)\"?"
        guard confirmRollback(message) else { return }
        Task {
            await viewModel.rollback([file], using: sourceControlManager)
        }
    }

    private func confirmRollback(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Local changes will be discarded. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Rollback")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showDiff(_ file: GitChangedFile) {
        DiffViewerPresenter.showFileDiff(workspace: workspace, fileURL: file.fileURL, against: "HEAD")
    }

    private func open(_ file: GitChangedFile) {
        guard let ceFile = workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        workspace.editorManager?.openTab(item: ceFile, asTemporary: true)
    }

    private func showInProject(_ file: GitChangedFile) {
        guard let ceFile = workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        workspace.toolWindowManager.show(.project)
        workspace.listenerModel.highlightedFileItem = ceFile
    }

    @MainActor
    private func refresh() async {
        if !sourceControlManager.isGitRepository {
            try? await sourceControlManager.validate()
        }
        await sourceControlManager.refreshAllChangedFiles()
    }

    @MainActor
    private func fetch() async {
        do {
            try await sourceControlManager.fetch()
        } catch {
            await sourceControlManager.showAlertForError(title: "Failed to fetch", error: error)
        }
        await sourceControlManager.refreshBranches()
        await sourceControlManager.refreshCurrentBranch()
    }
}

struct CommitMessageEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(Islands.codeFont)
            .foregroundStyle(Islands.foreground)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(3)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Commit Message")
                        .font(Islands.codeFont)
                        .foregroundStyle(Islands.disabledForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(Islands.islandRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .strokeBorder(Islands.componentBorder, lineWidth: 1)
            )
    }
}

struct CommitChangedFileRow: View {
    let file: GitChangedFile
    let directory: String
    let isIncluded: Bool
    let onToggle: (Bool) -> Void
    let onShowDiff: () -> Void
    let onOpen: () -> Void
    let onRollback: () -> Void
    let onShowInProject: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isIncluded },
                    set: { onToggle($0) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)

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
        .padding(.horizontal, 8)
        .frame(height: Islands.listRowHeight)
        .background(isHovering ? Islands.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onShowDiff)
        .contextMenu {
            Button("Open File", action: onOpen)
            Button("Rollback", action: onRollback)
            Button("Show in Project", action: onShowInProject)
        }
        .help(file.fileURL.relativePath)
    }
}
