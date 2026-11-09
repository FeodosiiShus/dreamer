import AppKit
import Foundation

nonisolated enum MarkdownPreviewLinkAction: Equatable, Sendable {
    case openExternally(URL)
    case openInEditor(URL)
    case refuse
}

nonisolated enum MarkdownPreviewLinkPolicy {
    static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    static func action(for url: URL, workspaceRoot: URL?) -> MarkdownPreviewLinkAction {
        guard let scheme = url.scheme?.lowercased() else { return .refuse }
        if externalSchemes.contains(scheme) {
            return .openExternally(url)
        }
        guard scheme == "file", isLocal(url), let workspaceRoot else { return .refuse }
        let target = URL(fileURLWithPath: url.path).standardizedFileURL
        let targetPath = canonicalPath(of: target)
        let rootPath = canonicalPath(of: workspaceRoot.standardizedFileURL)
        let rootPrefix = rootPath == "/" ? rootPath : rootPath + "/"
        return targetPath != rootPath && targetPath.hasPrefix(rootPrefix) ? .openInEditor(target) : .refuse
    }

    private static func canonicalPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func isLocal(_ url: URL) -> Bool {
        let host = url.host() ?? ""
        return host.isEmpty || host.lowercased() == "localhost"
    }
}

struct MarkdownPreviewLinks {
    let workspaceRoot: URL?
    let openExternal: @MainActor (URL) -> Void
    let openInEditor: @MainActor (URL) -> Void

    func handle(_ url: URL) {
        switch MarkdownPreviewLinkPolicy.action(for: url, workspaceRoot: workspaceRoot) {
        case .openExternally(let external):
            openExternal(external)
        case .openInEditor(let file):
            openInEditor(file)
        case .refuse:
            break
        }
    }

    static func live(workspace: WorkspaceDocument?) -> MarkdownPreviewLinks {
        MarkdownPreviewLinks(
            workspaceRoot: workspace?.workspaceFileManager?.folderUrl,
            openExternal: { _ = NSWorkspace.shared.open($0) },
            openInEditor: { [weak workspace] url in
                if let workspace {
                    openFile(url, in: workspace)
                }
            }
        )
    }

    static func openFile(_ url: URL, in workspace: WorkspaceDocument) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let editorManager = workspace.editorManager else { return }
        let file = workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true)
            ?? CEWorkspaceFile(url: url)
        editorManager.openTab(item: file)
    }
}
