import AppKit
import Combine
import CodeEditSourceEditor
import Foundation

@MainActor
final class SearchEverywhereViewModel: ObservableObject {
    @Published private(set) var tab: SearchEverywhereTab
    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var sections: [SearchEverywhereSection] = []
    @Published private(set) var selection: Int = 0
    @Published private(set) var preview: SearchEverywherePreview?
    @Published var showsPreview: Bool {
        didSet {
            UserDefaults.standard.set(showsPreview, forKey: Self.previewDefaultsKey)
        }
    }

    let symbolIndex = SearchEverywhereSymbolIndex()
    let mode: SearchEverywhereMode
    weak var workspace: WorkspaceDocument?
    var dismiss: (() -> Void)?

    private static let previewDefaultsKey = "dreamder.searchEverywhere.showPreview"

    private var pools: [SearchEverywhereSectionKind: [SearchEverywhereItem]] = [:]
    private var fileURLs: [URL] = []
    private var filesRoot: URL?
    private var hasLoadedFiles = false
    private var loadFilesTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var textTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var currentText = ""
    private var cancellables = Set<AnyCancellable>()

    init(workspace: WorkspaceDocument?, mode: SearchEverywhereMode = .everywhere) {
        self.workspace = workspace
        self.mode = mode
        self.tab = .all
        self.showsPreview = (UserDefaults.standard.object(forKey: Self.previewDefaultsKey) as? Bool ?? true)
            && mode == .everywhere

        symbolIndex.$symbols
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSearch()
            }
            .store(in: &cancellables)
    }

    var flatItems: [SearchEverywhereItem] {
        sections.flatMap(\.items)
    }

    var selectedItem: SearchEverywhereItem? {
        let items = flatItems
        guard items.indices.contains(selection) else { return nil }
        return items[selection]
    }

    var isIndexing: Bool {
        symbolIndex.isBuilding
    }

    var panelWidth: CGFloat {
        mode == .recentFiles ? 560 : 670
    }

    var panelHeight: CGFloat {
        mode == .recentFiles ? 400 : 520
    }

    func start(on tab: SearchEverywhereTab) {
        self.tab = mode == .recentFiles ? .files : tab
        query = ""
        pools = [:]
        selection = 0
        if let workspace {
            SearchEverywhereRecentFilesStore.shared.startTracking(for: workspace)
        }
        performSearch()
    }

    func selectTab(_ tab: SearchEverywhereTab) {
        guard mode == .everywhere else {
            performSearch()
            return
        }
        guard tab != self.tab else {
            performSearch()
            return
        }
        self.tab = tab
        selection = 0
        performSearch()
    }

    func select(_ item: SearchEverywhereItem) {
        guard let index = flatItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard index != selection else { return }
        selection = index
        updatePreview()
    }

    func moveSelection(by delta: Int) {
        let count = flatItems.count
        guard count > 0 else { return }
        let next = min(max(selection + delta, 0), count - 1)
        guard next != selection else { return }
        selection = next
        updatePreview()
    }

    func cycleTab(by delta: Int) {
        let tabs = SearchEverywhereTab.allCases
        guard let index = tabs.firstIndex(of: tab), !tabs.isEmpty else { return }
        let next = (index + delta + tabs.count) % tabs.count
        selectTab(tabs[next])
    }

    func togglePreview() {
        showsPreview.toggle()
        updatePreview()
    }

    func openSelected() {
        let items = flatItems
        guard items.indices.contains(selection) else { return }
        let item = items[selection]

        switch item.kind {
        case .action:
            item.action?.perform()
        default:
            if let url = item.url {
                openFile(url, line: item.line, column: item.column)
            }
        }

        dismiss?()
    }

    func handle(event: NSEvent) -> Bool {
        let flags = event.modifierFlags

        switch event.keyCode {
        case 53:
            dismiss?()
            return true
        case 36, 76:
            openSelected()
            return true
        case 48:
            cycleTab(by: flags.contains(.shift) ? -1 : 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        case 125:
            moveSelection(by: 1)
            return true
        case 116:
            moveSelection(by: -10)
            return true
        case 121:
            moveSelection(by: 10)
            return true
        case 115:
            moveSelection(by: -flatItems.count)
            return true
        case 119:
            moveSelection(by: flatItems.count)
            return true
        case 35 where flags.contains(.option):
            togglePreview()
            return true
        default:
            return false
        }
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.performSearch()
        }
    }

    private func performSearch() {
        let parsed = SearchEverywhereQuery.parse(query)
        let text = parsed.text.trimmingCharacters(in: .whitespaces)
        currentText = text
        textTask?.cancel()

        let kinds = tab.sections
        let kindSet = Set(kinds)
        var newPools: [SearchEverywhereSectionKind: [SearchEverywhereItem]] = [:]

        if mode == .recentFiles {
            pools = [.recent: buildRecentItems(text: text, limit: 300)]
            rebuildSections()
            return
        }

        if text.isEmpty {
            if kindSet.contains(.recent) {
                newPools[.recent] = buildRecentItems(text: "", limit: limit(for: .recent))
            }
            if kindSet.contains(.actions) {
                newPools[.actions] = buildActionItems(text: "", limit: kinds.count == 1 ? 300 : 8)
            }
        } else {
            if kindSet.contains(.files) {
                ensureFilesLoaded()
                newPools[.files] = buildFileItems(text: text, line: parsed.line, column: parsed.column)
            }
            if kindSet.contains(.classes) || kindSet.contains(.symbols) {
                ensureSymbolsLoaded()
                if kindSet.contains(.classes) {
                    newPools[.classes] = buildSymbolItems(text: text, classesOnly: true)
                }
                if kindSet.contains(.symbols) {
                    newPools[.symbols] = buildSymbolItems(text: text, classesOnly: false)
                }
            }
            if kindSet.contains(.actions) {
                newPools[.actions] = buildActionItems(text: text, limit: kinds.count == 1 ? 300 : 8)
            }
            if kindSet.contains(.text) {
                newPools[.text] = []
                startTextSearch(text)
            }
        }

        pools = newPools
        rebuildSections()
    }

    private func ensureFilesLoaded() {
        guard let root = workspace?.fileURL else { return }
        if hasLoadedFiles, filesRoot == root { return }
        guard loadFilesTask == nil else { return }

        filesRoot = root
        loadFilesTask = Task { [weak self] in
            let urls = await SearchEverywhereFileScanner.urls(in: root, maxFileSize: 2_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.fileURLs = urls
            self.hasLoadedFiles = true
            self.loadFilesTask = nil
            self.performSearch()
        }
    }

    private func ensureSymbolsLoaded() {
        guard let root = workspace?.fileURL else { return }
        symbolIndex.ensureIndexed(root: root)
    }

    private func buildFileItems(text: String, line: Int?, column: Int?) -> [SearchEverywhereItem] {
        guard let root = workspace?.fileURL, !fileURLs.isEmpty else { return [] }

        var items: [SearchEverywhereItem] = []
        for url in fileURLs {
            guard let match = SearchEverywhereProjectSearch.matchFile(query: text, url: url, root: root) else {
                continue
            }
            let relative = SearchEverywhereFileScanner.relativePath(of: url, from: root)
            let directory = (relative as NSString).deletingLastPathComponent
            items.append(SearchEverywhereItem(
                id: "file:\(relative)",
                section: .files,
                kind: .file,
                title: url.lastPathComponent,
                detail: directory,
                iconName: IntelliJIcon.fileIcon(for: url.lastPathComponent),
                ranges: match.ranges,
                url: url,
                line: line,
                column: column,
                action: nil,
                score: match.score
            ))
        }
        return ranked(items, limit: 200)
    }

    private func buildSymbolItems(text: String, classesOnly: Bool) -> [SearchEverywhereItem] {
        guard let root = workspace?.fileURL else { return [] }

        var items: [SearchEverywhereItem] = []
        for symbol in symbolIndex.symbols {
            if classesOnly && !symbol.kind.isType { continue }
            guard let match = SearchEverywhereMatcher.match(query: text, in: symbol.name) else { continue }
            let relative = SearchEverywhereFileScanner.relativePath(of: symbol.url, from: root)
            items.append(SearchEverywhereItem(
                id: "\(classesOnly ? "class" : "symbol"):\(relative):\(symbol.line):\(symbol.name)",
                section: classesOnly ? .classes : .symbols,
                kind: classesOnly ? .classSymbol : .symbol,
                title: symbol.name,
                detail: "\(relative):\(symbol.line)",
                iconName: symbol.kind.iconName,
                ranges: match.ranges,
                url: symbol.url,
                line: symbol.line,
                column: nil,
                action: nil,
                score: match.score
            ))
        }
        return ranked(items, limit: 300)
    }

    private func buildActionItems(text: String, limit: Int) -> [SearchEverywhereItem] {
        var items: [SearchEverywhereItem] = []
        for action in SearchEverywhereActionProvider.actions() {
            let candidate = action.menuPath.isEmpty
                ? action.title
                : "\(action.menuPath) | \(action.title)"
            let match: SearchEverywhereMatch?
            if text.isEmpty {
                match = SearchEverywhereMatch(score: 0, ranges: [])
            } else {
                match = SearchEverywhereMatcher.match(query: text, in: candidate)
            }
            guard let match else { continue }
            items.append(SearchEverywhereItem(
                id: "action:\(action.identity)",
                section: .actions,
                kind: .action,
                title: action.title,
                detail: action.menuPath,
                iconName: "general/runAnything",
                ranges: SearchEverywhereMatcher.match(query: text, in: action.title)?.ranges ?? [],
                url: nil,
                line: nil,
                column: nil,
                action: action,
                score: match.score
            ))
        }
        return ranked(items, limit: limit)
    }

    private func buildRecentItems(text: String, limit: Int) -> [SearchEverywhereItem] {
        guard let workspace else { return [] }
        let urls = SearchEverywhereRecentFilesStore.shared.recentFiles(for: workspace)
        guard !urls.isEmpty else { return [] }

        let root = workspace.fileURL
        var items: [SearchEverywhereItem] = []
        for url in urls {
            let filename = url.lastPathComponent
            let relative = root.map { SearchEverywhereFileScanner.relativePath(of: url, from: $0) } ?? filename
            let match: SearchEverywhereMatch?
            if text.isEmpty {
                match = SearchEverywhereMatch(score: 0, ranges: [])
            } else {
                match = SearchEverywhereMatcher.match(query: text, in: relative)
                    ?? SearchEverywhereMatcher.match(query: text, in: filename)
            }
            guard let match else { continue }
            items.append(SearchEverywhereItem(
                id: "recent:\(relative)",
                section: .recent,
                kind: .file,
                title: filename,
                detail: (relative as NSString).deletingLastPathComponent,
                iconName: IntelliJIcon.fileIcon(for: filename),
                ranges: SearchEverywhereMatcher.match(query: text, in: filename)?.ranges ?? [],
                url: url,
                line: nil,
                column: nil,
                action: nil,
                score: match.score
            ))
        }

        guard !text.isEmpty else { return Array(items.prefix(limit)) }
        return ranked(items, limit: limit)
    }

    private func startTextSearch(_ text: String) {
        guard let root = workspace?.fileURL else { return }
        let searchState = workspace?.searchState
        let pattern = searchState?.getRegexPattern(text) ?? NSRegularExpression.escapedPattern(for: text)
        let caseSensitive = searchState?.caseSensitive ?? false
        let query = text
        textTask = Task { [weak self] in
            let matches = await SearchEverywhereProjectSearch.textMatches(
                pattern: pattern,
                caseSensitive: caseSensitive,
                root: root
            )
            guard !Task.isCancelled else { return }
            guard let self, self.currentText == query, self.tab.sections.contains(.text) else { return }
            self.pools[.text] = matches.map { self.textItem(for: $0) }
            self.rebuildSections()
        }
    }

    private func textItem(for match: SearchEverywhereTextMatch) -> SearchEverywhereItem {
        let relative: String
        if let root = workspace?.fileURL {
            relative = SearchEverywhereFileScanner.relativePath(of: match.url, from: root)
        } else {
            relative = match.url.lastPathComponent
        }
        return SearchEverywhereItem(
            id: "text:\(match.url.path):\(match.line)",
            section: .text,
            kind: .text,
            title: match.text,
            detail: "\(relative):\(match.line)",
            iconName: IntelliJIcon.fileIcon(for: match.url.lastPathComponent),
            ranges: match.ranges,
            url: match.url,
            line: match.line,
            column: nil,
            action: nil,
            score: 0
        )
    }

    private func ranked(_ items: [SearchEverywhereItem], limit: Int) -> [SearchEverywhereItem] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    private func rebuildSections() {
        let previousID = selectedItem?.id

        sections = tab.sections.compactMap { kind in
            let items = pools[kind] ?? []
            guard !items.isEmpty else { return nil }
            return SearchEverywhereSection(kind: kind, items: Array(items.prefix(limit(for: kind))))
        }

        let items = flatItems
        if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            selection = index
        } else if items.isEmpty {
            selection = 0
        } else {
            selection = min(max(selection, 0), items.count - 1)
        }

        updatePreview()
    }

    private func limit(for kind: SearchEverywhereSectionKind) -> Int {
        tab == .all ? 8 : 300
    }

    private func updatePreview() {
        previewTask?.cancel()
        previewTask = nil

        guard showsPreview, let item = selectedItem, let url = item.url else {
            preview = nil
            return
        }

        let targetLine = item.line ?? 1
        let itemID = item.id
        previewTask = Task { [weak self] in
            let built = await SearchEverywhereProjectSearch.preview(url: url, targetLine: targetLine, context: 5)
            guard !Task.isCancelled else { return }
            guard let self, self.selectedItem?.id == itemID else { return }
            self.preview = built
        }
    }

    private func openFile(_ url: URL, line: Int?, column: Int?) {
        guard let workspace, let editorManager = workspace.editorManager else { return }
        let file = workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true)
            ?? CEWorkspaceFile(url: url)
        editorManager.openTab(item: file)

        guard let line else { return }
        let position = CursorPosition(line: max(line, 1), column: max(column ?? 1, 1))
        let editor = editorManager.activeEditor
        if let instance = editor.tabs.first(where: { $0.file.url.standardizedFileURL == file.url.standardizedFileURL }) {
            instance.cursorPositions = [position]
        }
        editor.selectedTab?.cursorPositions = [position]
    }
}
