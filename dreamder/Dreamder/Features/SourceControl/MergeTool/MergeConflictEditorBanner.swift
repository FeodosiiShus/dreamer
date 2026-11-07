import AppKit
import SwiftUI

struct MergeConflictEditorBanner: View {
    @Environment(WorkspaceDocument.self) private var workspace
    private let center = MergeConflictsCenter.shared
    private static let stripHeight: CGFloat = 30

    let fileURL: URL

    var body: some View {
        Group {
            if let entry, isVisible(entry) {
                HStack(spacing: 8) {
                    Image("general/warningDialog")
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text("File has unresolved merge conflicts")
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.foreground)
                    Button {
                        resolve(entry)
                    } label: {
                        Text("Resolve conflicts…")
                            .font(Islands.smallFont)
                            .foregroundStyle(Islands.link)
                    }
                    .buttonStyle(.plain)
                    .help("Open the Merge Revisions window for \(entry.path)")
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 12)
                .frame(height: Self.stripHeight)
                .glassPopup(radius: Self.stripHeight / 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .task(id: fileURL) {
            guard let manager = workspace.sourceControlManager else { return }
            let center = MergeConflictsCenter.shared
            center.monitor(manager)
            let state = center.state(for: manager.workspaceURL)
            if state == nil || !(state?.entries.isEmpty ?? true) {
                await center.refresh(manager: manager)
            }
        }
        .onChange(of: entry?.path, initial: true) { _, path in
            guard let entry, isVisible(entry), path != nil else {
                MergeAutomation.registerBanner(path: nil, action: nil)
                return
            }
            MergeAutomation.registerBanner(path: entry.path) {
                resolve(entry)
            }
        }
    }

    private func resolve(_ entry: MergeConflictEntry) {
        MergeToolPresenter.showMergeRevisions(workspace: workspace, path: entry.path)
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
