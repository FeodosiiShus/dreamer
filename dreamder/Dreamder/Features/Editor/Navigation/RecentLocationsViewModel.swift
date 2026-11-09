import AppKit
import Observation

nonisolated enum RecentLocationsTextLoader {
    @concurrent
    static func read(_ urls: [URL]) async -> [URL: String] {
        var texts: [URL: String] = [:]
        for url in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                texts[url] = text
            }
        }
        return texts
    }
}

@MainActor
enum RecentLocationsTextSource {
    static func openTexts(for urls: [URL], workspace: WorkspaceDocument?) -> [URL: String] {
        guard let editorManager = workspace?.editorManager else { return [:] }
        let wanted = Set(urls)
        var texts: [URL: String] = [:]
        for editor in [editorManager.activeEditor] + editorManager.flattenedEditors {
            for tab in editor.tabs {
                let url = tab.file.url.standardizedFileURL
                if wanted.contains(url), texts[url] == nil, let content = tab.file.fileDocument?.content?.string {
                    texts[url] = content
                }
            }
        }
        return texts
    }
}

@MainActor
@Observable
final class RecentLocationsViewModel {
    typealias TextLoader = @Sendable ([URL]) async -> [URL: String]

    static let navigationTitle = "Recent Locations"
    static let changedTitle = "Recently Edited Locations"
    static let toggleTitle = "Show edited only"
    static let toggleShortcut = "\u{21E7}\u{2318}E"
    static let emptyText = "No recent locations found"
    static let emptyFileText = "Empty lines"

    private(set) var rows: [RecentLocationsRow] = []
    var selectedIndex = 0

    var showChangedOnly: Bool {
        didSet {
            selectedIndex = 0
            rebuild()
        }
    }

    @ObservationIgnored var dismiss: ((_ restoresFocus: Bool) -> Void)?

    @ObservationIgnored private let tracker: RecentLocationsTracker
    @ObservationIgnored private let workspacePath: String?
    @ObservationIgnored private var navigationPlaces: [EditorPlace] = []
    @ObservationIgnored private var changedPlaces: [EditorPlace] = []
    @ObservationIgnored private var texts: [URL: String] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(
        tracker: RecentLocationsTracker,
        workspace: WorkspaceDocument?,
        showChangedOnly: Bool = false,
        loadTexts: @escaping TextLoader = RecentLocationsTextLoader.read
    ) {
        self.tracker = tracker
        self.workspacePath = workspace?.fileURL?.absolutePath
        self.showChangedOnly = showChangedOnly
        tracker.removeInvalidPlaces()
        reloadPlaces()

        let urls = Array(Set((navigationPlaces + changedPlaces).map(\.fileURL)))
        texts = RecentLocationsTextSource.openTexts(for: urls, workspace: workspace)
        rebuild()

        let missing = urls.filter { texts[$0] == nil }
        guard !missing.isEmpty else { return }
        loadTask = Task { [weak self] in
            let loaded = await loadTexts(missing)
            guard !Task.isCancelled else { return }
            self?.merge(loaded)
        }
    }

    isolated deinit {
        loadTask?.cancel()
    }

    var title: String { showChangedOnly ? Self.changedTitle : Self.navigationTitle }

    var countText: String { "(\(rows.count))" }

    var selectedRow: RecentLocationsRow? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
    }

    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let count = rows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    func open(_ index: Int) {
        select(index)
        activate()
    }

    func activate() {
        guard let row = selectedRow else { return }
        dismiss?(false)
        tracker.navigate(to: row.place)
    }

    func removeSelected() {
        guard let row = selectedRow else { return }
        let index = selectedIndex
        tracker.remove(row.place, changed: showChangedOnly)
        reloadPlaces()
        rebuild()
        selectedIndex = min(index, max(rows.count - 1, 0))
    }

    func close() {
        dismiss?(true)
    }

    func handle(event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 53:
            close()
            return true
        case 126:
            moveSelection(-1)
            return true
        case 125:
            moveSelection(1)
            return true
        case 36, 76:
            activate()
            return true
        case 51, 117:
            removeSelected()
            return true
        default:
            return false
        }
    }

    private func reloadPlaces() {
        navigationPlaces = tracker.history.recentPlaces(changed: false)
        changedPlaces = tracker.history.recentPlaces(changed: true)
    }

    private func merge(_ loaded: [URL: String]) {
        for (url, text) in loaded {
            texts[url] = text
        }
        rebuild()
    }

    private func rebuild() {
        rows = RecentLocationsMapping.rows(
            places: showChangedOnly ? changedPlaces : navigationPlaces,
            texts: texts,
            workspacePath: workspacePath
        )
    }
}
