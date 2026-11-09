import AppKit
import SwiftUI

struct MergeConflictEditorBanner: View {
    @Environment(WorkspaceDocument.self) private var workspace
    private let center = MergeConflictsCenter.shared

    let fileURL: URL
    let registerAutomation: @MainActor (String?, (() -> Void)?) -> Void
    let showMergeRevisions: @MainActor (WorkspaceDocument, String) -> Void

    init(fileURL: URL) {
        self.init(
            fileURL: fileURL,
            registerAutomation: MergeAutomation.registerBanner,
            showMergeRevisions: MergeToolPresenter.showMergeRevisions
        )
    }

    init(
        fileURL: URL,
        registerAutomation: @escaping @MainActor (String?, (() -> Void)?) -> Void,
        showMergeRevisions: @escaping @MainActor (WorkspaceDocument, String) -> Void
    ) {
        self.fileURL = fileURL
        self.registerAutomation = registerAutomation
        self.showMergeRevisions = showMergeRevisions
    }

    var body: some View {
        Group {
            if let entry, isVisible(entry) {
                strip(for: entry)
            }
        }
        .task(id: fileURL) {
            guard let manager = workspace.sourceControlManager else { return }
            let center = MergeConflictsCenter.shared
            center.monitor(manager)
            let hasNoConflicts = center.state(for: manager.workspaceURL)?.entries.isEmpty
            if hasNoConflicts != true {
                await center.refresh(manager: manager)
            }
        }
        .onChange(of: entry?.path, initial: true) { _, path in
            guard let entry, isVisible(entry), path != nil else {
                registerAutomation(nil, nil)
                return
            }
            let resolver = strip(for: entry)
            registerAutomation(entry.path) {
                resolver.resolve()
            }
        }
    }

    private func strip(for entry: MergeConflictEntry) -> MergeConflictBannerStrip {
        MergeConflictBannerStrip(
            workspace: workspace,
            path: entry.path,
            showMergeRevisions: showMergeRevisions
        )
    }

    private var entry: MergeConflictEntry? {
        guard let manager = workspace.sourceControlManager else { return nil }
        let path = DiffPath.relativePath(of: fileURL, from: manager.repositoryURL)
        guard !path.isEmpty else { return nil }
        return center.entries(for: manager.workspaceURL).first { $0.path == path }
    }

    private func isVisible(_ entry: MergeConflictEntry) -> Bool {
        guard !entry.isBothDeleted else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }
}

struct MergeConflictBannerStrip: View {
    static let height: CGFloat = 30

    let workspace: WorkspaceDocument
    let path: String
    let showMergeRevisions: @MainActor (WorkspaceDocument, String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image("general/warningDialog")
                .resizable()
                .frame(width: 16, height: 16)
            Text("File has unresolved merge conflicts")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.foreground)
            Button(action: resolve) {
                Text("Resolve conflicts…")
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.link)
            }
            .buttonStyle(.plain)
            .help("Open the Merge Revisions window for \(path)")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .glassPopup(radius: Self.height / 2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    func resolve() {
        showMergeRevisions(workspace, path)
    }
}
