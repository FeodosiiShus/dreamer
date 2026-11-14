import AppKit
import Foundation

extension MergeAutomation {
    static func exactWorkspace(at path: String) -> WorkspaceDocument? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return NSDocumentController.shared.documents.lazy
            .compactMap { $0 as? WorkspaceDocument }
            .first { $0.sourceControlManager?.workspaceURL.standardizedFileURL.path == target }
    }

    static func targetWorkspace() -> WorkspaceDocument? {
        targetPath.isEmpty ? nil : exactWorkspace(at: targetPath)
    }

    static func openingWorkspace() -> WorkspaceDocument? {
        targetPath.isEmpty ? workspace(for: "") : exactWorkspace(at: targetPath)
    }

    static func commandWorkspace(path: String) -> WorkspaceDocument? {
        path.isEmpty ? openingWorkspace() : workspace(for: path)
    }

    static var targetConflictsModel: MergeConflictsViewModel? {
        targetWorkspace().flatMap { MergeToolPresenter.conflictsModel(for: $0) }
    }

    static var targetConflictsWindow: NSWindow? {
        targetWorkspace().flatMap { MergeToolPresenter.conflictsWindow(for: $0) }
    }

    static var targetRevisionsModel: MergeRevisionsViewModel? {
        targetWorkspace().flatMap { MergeToolPresenter.revisionsModel(for: $0, path: revisionsPath) }
    }

    static var targetRevisionsWindow: NSWindow? {
        targetWorkspace().flatMap { MergeToolPresenter.revisionsWindow(for: $0, path: revisionsPath) }
    }
}
