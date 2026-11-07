import Foundation
import Observation

struct SearchEverywhereRecentFileList {
    let limit: Int
    private(set) var urls: [URL] = []

    init(urls: [URL] = [], limit: Int = 50) {
        self.limit = limit
        var seen = Set<URL>()
        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized).inserted else { continue }
            self.urls.append(standardized)
            if self.urls.count >= limit { break }
        }
    }

    mutating func record(_ url: URL) {
        let standardized = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == standardized }
        urls.insert(standardized, at: 0)
        if urls.count > limit {
            urls.removeLast(urls.count - limit)
        }
    }
}

final class SearchEverywhereRecentFilesStore {
    static let shared = SearchEverywhereRecentFilesStore()

    private final class Entry {
        weak var workspace: WorkspaceDocument?
        var list: SearchEverywhereRecentFileList
        var observation: Task<Void, Never>?

        init(workspace: WorkspaceDocument, list: SearchEverywhereRecentFileList) {
            self.workspace = workspace
            self.list = list
        }

        isolated deinit {
            observation?.cancel()
        }
    }

    private var entries: [String: Entry] = [:]

    func recentFiles(for workspace: WorkspaceDocument) -> [URL] {
        entry(for: workspace).list.urls
    }

    func startTracking(for workspace: WorkspaceDocument) {
        _ = entry(for: workspace)
    }

    private func entry(for workspace: WorkspaceDocument) -> Entry {
        entries = entries.filter { $0.value.workspace != nil }
        let key = Self.key(for: workspace)
        if let entry = entries[key], entry.workspace === workspace {
            return entry
        }

        let entry = Entry(workspace: workspace, list: Self.storedList(for: key))
        entries[key] = entry
        attachTracking(entry, key: key, workspace: workspace)
        return entry
    }

    private func attachTracking(_ entry: Entry, key: String, workspace: WorkspaceDocument) {
        guard let editorManager = workspace.editorManager else { return }

        if entry.list.urls.isEmpty {
            seed(from: editorManager, into: entry, key: key)
        }

        entry.observation = Task { [weak self, weak entry, weak editorManager] in
            let selectedURL = Observations({ [weak editorManager] in
                editorManager?.activeEditor.selectedTab?.file.url
            })
            for await url in selectedURL {
                guard let self, let entry, let url else { continue }
                self.record(url, key: key, entry: entry)
            }
        }
    }

    private func seed(from editorManager: EditorManager, into entry: Entry, key: String) {
        var urls: [URL] = []
        if let selected = editorManager.activeEditor.selectedTab?.file.url {
            urls.append(selected)
        }
        urls.append(contentsOf: editorManager.activeEditor.tabs.map { $0.file.url })
        urls.append(contentsOf: editorManager.flattenedEditors.flatMap { $0.tabs.map { $0.file.url } })

        var list = entry.list
        for url in urls.reversed() {
            list.record(url)
        }
        entry.list = list
        Self.store(list.urls, for: key)
    }

    private func record(_ url: URL, key: String, entry: Entry) {
        let previous = entry.list.urls.first
        entry.list.record(url)
        guard entry.list.urls.first != previous else { return }
        Self.store(entry.list.urls, for: key)
    }

    private static func key(for workspace: WorkspaceDocument) -> String {
        workspace.fileURL?.standardizedFileURL.path ?? "untitled"
    }

    private static func defaultsKey(_ key: String) -> String {
        "dreamder.recentFiles.\(key)"
    }

    private static func storedList(for key: String) -> SearchEverywhereRecentFileList {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey(key)) ?? []
        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return SearchEverywhereRecentFileList(urls: urls)
    }

    private static func store(_ urls: [URL], for key: String) {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: defaultsKey(key))
    }
}
