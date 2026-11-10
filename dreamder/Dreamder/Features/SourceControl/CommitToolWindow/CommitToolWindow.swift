import AppKit
import SwiftUI

struct CommitToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(SourceControlManager.self) private var sourceControlManager

    @State private var viewModel: CommitToolWindowViewModel

    let makeAlert: @MainActor () -> NSAlert

    init() {
        self.init(viewModel: CommitToolWindowViewModel(), makeAlert: NSAlert.init)
    }

    init(viewModel: CommitToolWindowViewModel, makeAlert: @escaping @MainActor () -> NSAlert) {
        _viewModel = State(initialValue: viewModel)
        self.makeAlert = makeAlert
    }

    private var files: [GitChangedFile] {
        sourceControlManager.changedFiles
    }

    private var versionedFiles: [GitChangedFile] {
        viewModel.versionedFiles(in: files)
    }

    private var unversionedFiles: [GitChangedFile] {
        viewModel.unversionedFiles(in: files)
    }

    private var actions: CommitToolWindowActions {
        CommitToolWindowActions(
            workspace: workspace,
            sourceControlManager: sourceControlManager,
            viewModel: viewModel,
            makeAlert: makeAlert
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(
                title: "Commit",
                tabs: { EmptyView() },
                actions: {
                    ToolWindowActionButton(icon: "general/refresh", help: "Refresh", action: actions.startRefresh)
                    ToolWindowActionButton(icon: "vcs/revert", help: "Rollback", action: actions.rollbackIncluded)
                    ToolWindowActionButton(icon: "vcs/update", help: "Fetch", action: actions.startFetch)
                    ToolWindowActionButton(icon: "general/hide", help: "Hide", action: actions.hide)
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
            await actions.refresh()
        }
        .task {
            await actions.refreshHunksOnChanges()
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
                                fileBlock(for: file)
                            }
                        }
                        if !unversionedFiles.isEmpty {
                            groupHeader("Unversioned Files", count: unversionedFiles.count)
                            ForEach(unversionedFiles) { file in
                                fileBlock(for: file)
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
                Toggle(isOn: Binding(get: { viewModel.amend }, set: { actions.startSetAmend($0) })) {
                    Text("Amend")
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                Button(action: actions.startCommit) {
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

                Button(action: actions.startCommitAndPush) {
                    Text("Commit and Push…")
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: Islands.controlRadius)
                                .fill(Islands.islandRaised.opacity(0.8))
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

    private func fileBlock(for file: GitChangedFile) -> some View {
        let fileActions = actions.actions(for: file)
        return VStack(alignment: .leading, spacing: 0) {
            CommitChangedFileRow(
                file: file,
                directory: file.gitRelativeDirectory(from: sourceControlManager.workspaceURL),
                isIncluded: viewModel.isIncluded(file),
                onToggle: fileActions.setIncluded,
                onShowDiff: fileActions.showDiff,
                onOpen: fileActions.open,
                onRollback: fileActions.rollback,
                onShowInProject: fileActions.showInProject,
                isPartiallyIncluded: viewModel.isPartiallyIncluded(file),
                isExpandable: viewModel.canExpand(file),
                isExpanded: viewModel.isExpanded(file),
                onToggleExpansion: fileActions.toggleExpansion
            )
            if viewModel.isExpanded(file) {
                ForEach(viewModel.hunks(for: file)) { hunk in
                    CommitHunkRow(
                        hunk: hunk,
                        isIncluded: viewModel.isHunkIncluded(hunk, in: file),
                        onToggle: { fileActions.setHunkIncluded(hunk, $0) },
                        onShowDiff: fileActions.showDiff
                    )
                }
            }
        }
    }
}

struct CommitToolWindowActions {
    let workspace: WorkspaceDocument
    let sourceControlManager: SourceControlManager
    let viewModel: CommitToolWindowViewModel
    let makeAlert: @MainActor () -> NSAlert

    var includedFiles: [GitChangedFile] {
        sourceControlManager.changedFiles.filter { viewModel.isIncluded($0) }
    }

    func actions(for file: GitChangedFile) -> CommitFileActions {
        CommitFileActions(file: file, owner: self)
    }

    func startRefresh() {
        Task { await refresh() }
    }

    func startFetch() {
        Task { await fetch() }
    }

    func startCommit() {
        Task { await viewModel.commit(using: sourceControlManager, andPush: false) }
    }

    func startCommitAndPush() {
        Task { await viewModel.commit(using: sourceControlManager, andPush: true) }
    }

    func hide() {
        workspace.toolWindowManager.hide(.commit)
    }

    func rollbackIncluded() {
        let targets = includedFiles
        guard !targets.isEmpty else { return }
        let message = targets.count == 1
            ? "Discard local changes to \"\(targets[0].fileURL.lastPathComponent)\"?"
            : "Discard local changes to \(targets.count) files?"
        guard confirmRollback(message) else { return }
        Task { await viewModel.rollback(targets, using: sourceControlManager) }
    }

    func confirmRollback(_ message: String) -> Bool {
        let alert = makeAlert()
        alert.messageText = message
        alert.informativeText = "Local changes will be discarded. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Rollback")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func refresh() async {
        if !sourceControlManager.isGitRepository {
            await sourceControlManager.validate()
        }
        await sourceControlManager.refreshAllChangedFiles()
    }

    func startSetAmend(_ enabled: Bool) {
        Task { await viewModel.setAmend(enabled, using: sourceControlManager) }
    }

    func refreshHunksOnChanges() async {
        let manager = sourceControlManager
        for await _ in Observations({ manager.changedFiles }) {
            await viewModel.refreshHunks(using: manager)
        }
    }

    func fetch() async {
        do {
            try await sourceControlManager.fetch()
        } catch {
            await sourceControlManager.showAlertForError(title: "Failed to fetch", error: error)
        }
        await sourceControlManager.refreshBranches()
        await sourceControlManager.refreshCurrentBranch()
    }
}

struct CommitFileActions {
    let file: GitChangedFile
    let owner: CommitToolWindowActions

    func setIncluded(_ included: Bool) {
        owner.viewModel.setIncluded(included, for: file)
    }

    func showDiff() {
        DiffViewerPresenter.showFileDiff(workspace: owner.workspace, fileURL: file.fileURL, against: "HEAD")
    }

    func open() {
        guard let ceFile = owner.workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        owner.workspace.editorManager?.openTab(item: ceFile, asTemporary: true)
    }

    func rollback() {
        let message = "Discard local changes to \"\(file.fileURL.lastPathComponent)\"?"
        guard owner.confirmRollback(message) else { return }
        let target = file
        Task { await owner.viewModel.rollback([target], using: owner.sourceControlManager) }
    }

    func showInProject() {
        guard let ceFile = owner.workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        owner.workspace.toolWindowManager.show(.project)
        owner.workspace.listenerModel.highlightedFileItem = ceFile
    }

    func toggleExpansion() {
        let target = file
        Task { await owner.viewModel.toggleExpansion(of: target, using: owner.sourceControlManager) }
    }

    func setHunkIncluded(_ hunk: PartialCommitHunk, _ included: Bool) {
        owner.viewModel.setHunkIncluded(included, hunk, in: file)
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
                    .fill(Islands.islandRaised.opacity(0.6))
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
    var isPartiallyIncluded = false
    var isExpandable = false
    var isExpanded = false
    var onToggleExpansion: () -> Void = {}

    @State private var isHovering = false

    private var checkboxState: CommitCheckboxState {
        if isPartiallyIncluded {
            return .mixed
        }
        return isIncluded ? .on : .off
    }

    var body: some View {
        HStack(spacing: 6) {
            expansionControl

            CommitCheckbox(
                state: checkboxState,
                label: "Include \(file.fileURL.lastPathComponent)",
                onChange: onToggle
            )

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
        .background(CommitRowBackground.color(isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover(perform: setHovering)
        .onTapGesture(count: 2, perform: onShowDiff)
        .contextMenu { menuItems }
        .help(file.fileURL.relativePath)
    }

    @ViewBuilder
    var menuItems: some View {
        Button("Open File", action: onOpen)
        Button("Rollback", action: onRollback)
        Button("Show in Project", action: onShowInProject)
    }

    @ViewBuilder
    private var expansionControl: some View {
        if isExpandable {
            Button(action: onToggleExpansion) {
                Image(isExpanded ? "general/chevronDown" : "general/chevronRight")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide Changes" : "Show Changes")
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}

struct CommitHunkRow: View {
    let hunk: PartialCommitHunk
    let isIncluded: Bool
    let onToggle: (Bool) -> Void
    let onShowDiff: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            CommitCheckbox(
                state: isIncluded ? .on : .off,
                label: "Include lines \(hunk.rangeTitle)",
                onChange: onToggle
            )

            Text(hunk.rangeTitle)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)

            Text(hunk.preview)
                .font(Islands.codeFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)
        }
        .padding(.leading, 40)
        .padding(.trailing, 8)
        .frame(height: Islands.listRowHeight)
        .background(CommitRowBackground.color(isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover(perform: setHovering)
        .onTapGesture(count: 2, perform: onShowDiff)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}

enum CommitRowBackground {
    static func color(isHovering: Bool) -> Color {
        isHovering ? Islands.hover : Color.clear
    }
}

enum CommitCheckboxState: Equatable {
    case on
    case off
    case mixed
}

struct CommitCheckbox: NSViewRepresentable {
    let state: CommitCheckboxState
    let label: String
    let onChange: (Bool) -> Void

    final class Coordinator: NSObject {
        var state: CommitCheckboxState
        var onChange: (Bool) -> Void

        init(state: CommitCheckboxState, onChange: @escaping (Bool) -> Void) {
            self.state = state
            self.onChange = onChange
            super.init()
        }

        @objc func clicked(_ sender: NSButton) {
            let included = state != .on
            sender.state = included ? .on : .off
            onChange(included)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onChange: onChange)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: "",
            target: context.coordinator,
            action: #selector(Coordinator.clicked(_:))
        )
        button.allowsMixedState = true
        button.controlSize = .small
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.state = state
        context.coordinator.onChange = onChange
        button.setAccessibilityLabel(label)
        switch state {
        case .on: button.state = .on
        case .off: button.state = .off
        case .mixed: button.state = .mixed
        }
    }
}
