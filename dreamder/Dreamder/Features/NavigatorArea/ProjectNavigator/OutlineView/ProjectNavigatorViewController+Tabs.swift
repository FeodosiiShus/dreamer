import Foundation
import DequeModule
import OrderedCollections

extension ProjectNavigatorViewController {
    static func normalizedPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func url(_ url: URL, isWithin ancestor: URL) -> Bool {
        let path = normalizedPath(url)
        let ancestorPath = normalizedPath(ancestor)
        return path == ancestorPath || path.hasPrefix(ancestorPath == "/" ? "/" : ancestorPath + "/")
    }

    func closeTabs(under url: URL) {
        guard let editorManager = workspace?.editorManager else { return }
        let files = editorManager.editorLayout.gatherOpenFiles().filter { Self.url($0.url, isWithin: url) }
        for file in files {
            for editor in editorManager.getFlattened() where
                editor.tabs.contains(where: { $0.file == file }) || editor.temporaryTab?.file == file {
                editor.closeTab(file: file)
            }
        }
    }

    func retargetTabs(from oldURL: URL, to newURL: URL) {
        guard let workspace, let editorManager = workspace.editorManager,
              let fileManager = workspace.workspaceFileManager else { return }
        let oldPath = Self.normalizedPath(oldURL)
        let newPath = Self.normalizedPath(newURL)

        func replacement(for file: CEWorkspaceFile) -> CEWorkspaceFile? {
            let suffix = String(Self.normalizedPath(file.url).dropFirst(oldPath.count))
            return fileManager.getFile(newPath + suffix, createIfNotFound: true)
        }

        for editor in editorManager.getFlattened() {
            let selectedFile = editor.selectedTab?.file
            let temporaryFile = editor.temporaryTab?.file
            var rebuilt: [Editor.Tab] = []
            var replacements: [CEWorkspaceFile: CEWorkspaceFile] = [:]
            var affected = false
            for tab in editor.tabs {
                guard Self.url(tab.file.url, isWithin: oldURL) else {
                    rebuilt.append(tab)
                    continue
                }
                affected = true
                guard let newFile = replacement(for: tab.file) else { continue }
                transferDocument(from: tab.file, to: newFile)
                replacements[tab.file] = newFile
                rebuilt.append(Editor.Tab(workspace: workspace, file: newFile))
            }
            guard affected else { continue }
            editor.tabs = OrderedSet(rebuilt)
            if let selectedFile, let mapped = replacements[selectedFile] {
                editor.setSelectedTab(mapped)
            }
            if let temporaryFile, let mapped = replacements[temporaryFile] {
                editor.temporaryTab = editor.tabs.first { $0.file == mapped }
            }
            editor.history = Deque(editor.history.compactMap { file in
                Self.url(file.url, isWithin: oldURL) ? replacement(for: file) : file
            })
        }
    }

    private func transferDocument(from oldFile: CEWorkspaceFile, to newFile: CEWorkspaceFile) {
        guard let document = oldFile.fileDocument, newFile.fileDocument == nil else { return }
        document.fileURL = newFile.resolvedURL
        newFile.fileDocument = document
        oldFile.fileDocument = nil
    }
}
