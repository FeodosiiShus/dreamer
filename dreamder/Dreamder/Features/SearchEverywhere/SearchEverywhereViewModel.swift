import AppKit
import Observation
import CodeEditSourceEditor
import Foundation

@Observable
@MainActor
final class SearchEverywhereViewModel {
    private(set) var tab: SearchEverywhereTab
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    private(set) var sections: [SearchEverywhereSection] = []
    private(set) var selection: Int = 0
    private(set) var preview: SearchEverywherePreview?
    var showsPreview: Bool {
        didSet {
            defaults.set(showsPreview, forKey: Self.previewDefaultsKey)
        }
    }

    var symbolIndex: SearchEverywhereSymbolIndex? { workspace?.symbolIndex }
    let mode: SearchEverywhereMode
    @ObservationIgnored weak var workspace: WorkspaceDocument?
    private let defaults: UserDefaults
    private let recentFiles: SearchEverywhereRecentFilesStore
    private let actionsProvider: @MainActor () -> [SearchEverywhereAction]
    @ObservationIgnored var dismiss: (() -> Void)?

    private static let previewDefaultsKey = "dreamder.searchEverywhere.showPreview"

    @ObservationIgnored private var pools: [SearchEverywhereSectionKind: [SearchEverywhereItem]] = [:]
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var changesObservation: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var textTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var symbolsObservation: Task<Void, Never>?
    @ObservationIgnored private var currentText = ""

    init(
        workspace: WorkspaceDocument?,
        mode: SearchEverywhereMode = .everywhere,
        defaults: UserDefaults = .standard,
        recentFiles: SearchEverywhereRecentFilesStore = .shared,
        actions: @escaping @MainActor () -> [SearchEverywhereAction] = SearchEverywhereActionProvider.actions
    ) {
        self.workspace = workspace
        self.mode = mode
        self.defaults = defaults
        self.recentFiles = recentFiles
        self.actionsProvider = actions
        self.tab = .all
        self.showsPreview = (defaults.object(forKey: Self.previewDefaultsKey) as? Bool ?? true)
            && mode == .everywhere

        let symbolIndex = workspace?.symbolIndex
        symbolsObservation = Task { [weak self] in
            var isInitialValue = true
            for await _ in Observations({ symbolIndex?.symbols }) {
                if isInitialValue {
                    isInitialValue = false
                    continue
                }
                self?.scheduleSearch()
            }
        }

        if let changes = workspace?.fileScope?.changes() {
            changesObservation = Task { [weak self] in
                for await _ in changes {
                    guard let self else { return }
                    if !self.query.isEmpty {
                        self.scheduleSearch()
                    }
                }
            }
        }
    }

    isolated deinit {
        symbolsObservation?.cancel()
        changesObservation?.cancel()
        indexTask?.cancel()
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
        symbolIndex?.isBuilding ?? false
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
            recentFiles.startTracking(for: workspace)
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
        indexTask?.cancel()
        searchGeneration += 1

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
                newPools[.recent] = buildRecentItems(text: "", limit: providerLimit)
            }
            if kindSet.contains(.actions) {
                newPools[.actions] = buildActionItems(text: "", limit: kinds.count == 1 ? 300 : 8)
            }
        } else {
            for kind in [SearchEverywhereSectionKind.files, .classes, .symbols] where kindSet.contains(kind) {
                newPools[kind] = pools[kind] ?? []
            }
            if kindSet.contains(.actions) {
                newPools[.actions] = buildActionItems(text: text, limit: kinds.count == 1 ? 300 : 8)
            }
            if kindSet.contains(.text) {
                newPools[.text] = []
                startTextSearch(text)
            }
            startIndexSearch(text: text, parsed: parsed, kinds: kindSet)
        }

        pools = newPools
        rebuildSections()
    }

    private func startIndexSearch(
        text: String,
        parsed: SearchEverywhereQuery,
        kinds: Set<SearchEverywhereSectionKind>
    ) {
        guard let workspace, let root = workspace.fileURL else { return }
        let wantsFiles = kinds.contains(.files)
        let wantsClasses = kinds.contains(.classes)
        let wantsSymbols = kinds.contains(.symbols)
        guard wantsFiles || wantsClasses || wantsSymbols else { return }

        let scope = workspace.fileScope
        let index = workspace.symbolIndex
        if wantsClasses || wantsSymbols {
            index?.ensureIndexed()
        }
        let symbols = index?.symbols ?? []
        let generation = searchGeneration
        indexTask = Task { [weak self] in
            if wantsFiles, let scope {
                let urls = await scope.enumerateFiles(limit: nil)
                let hits = await SearchEverywhereProjectSearch.rankedFileHits(
                    text: text,
                    urls: urls,
                    root: root,
                    limit: 200
                )
                guard !Task.isCancelled else { return }
                self?.publish(.files, generation: generation) { model in
                    hits.map { model.fileItem($0, line: parsed.line, column: parsed.column) }
                }
            }
            if wantsClasses {
                let hits = await SearchEverywhereProjectSearch.rankedSymbolHits(
                    text: text,
                    symbols: symbols,
                    root: root,
                    classesOnly: true,
                    limit: 300
                )
                guard !Task.isCancelled else { return }
                self?.publish(.classes, generation: generation) { model in
                    hits.map { model.symbolItem($0, classesOnly: true) }
                }
            }
            if wantsSymbols {
                let hits = await SearchEverywhereProjectSearch.rankedSymbolHits(
                    text: text,
                    symbols: symbols,
                    root: root,
                    classesOnly: false,
                    limit: 300
                )
                guard !Task.isCancelled else { return }
                self?.publish(.symbols, generation: generation) { model in
                    hits.map { model.symbolItem($0, classesOnly: false) }
                }
            }
        }
    }

    private func publish(
        _ kind: SearchEverywhereSectionKind,
        generation: Int,
        items: (SearchEverywhereViewModel) -> [SearchEverywhereItem]
    ) {
        guard generation == searchGeneration, tab.sections.contains(kind) else { return }
        pools[kind] = items(self)
        rebuildSections()
    }

    private func fileItem(
        _ hit: SearchEverywhereFileHit,
        line: Int?,
        column: Int?
    ) -> SearchEverywhereItem {
        let name = hit.url.lastPathComponent
        return SearchEverywhereItem(
            id: "file:\(hit.relative)",
            section: .files,
            kind: .file,
            title: name,
            detail: (hit.relative as NSString).deletingLastPathComponent,
            iconName: IntelliJIcon.fileIcon(for: name),
            ranges: hit.match.ranges,
            url: hit.url,
            line: line,
            column: column,
            action: nil,
            weight: SearchEverywhereComposedWeight(hit.match.score),
            isExactMatch: hit.isExactMatch,
            equalityKey: "file:\(hit.relative)"
        )
    }

    private func symbolItem(_ hit: SearchEverywhereSymbolHit, classesOnly: Bool) -> SearchEverywhereItem {
        let symbol = hit.symbol
        return SearchEverywhereItem(
            id: "\(classesOnly ? "class" : "symbol"):\(hit.relative):\(symbol.line):\(symbol.name)",
            section: classesOnly ? .classes : .symbols,
            kind: classesOnly ? .classSymbol : .symbol,
            title: symbol.name,
            detail: "\(hit.relative):\(symbol.line)",
            iconName: symbol.kind.iconName,
            ranges: hit.match.ranges,
            url: symbol.url,
            line: symbol.line,
            column: nil,
            action: nil,
            weight: SearchEverywhereComposedWeight(hit.match.score),
            isExactMatch: hit.isExactMatch,
            equalityKey: "symbol:\(hit.relative):\(symbol.line):\(symbol.name)"
        )
    }

    private func buildActionItems(text: String, limit: Int) -> [SearchEverywhereItem] {
        var items: [SearchEverywhereItem] = []
        for action in actionsProvider() {
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
                weight: SearchEverywhereComposedWeight(match.score),
                isExactMatch: false,
                equalityKey: action.equalityKey
            ))
        }
        return ranked(items, limit: limit)
    }

    private func buildRecentItems(text: String, limit: Int) -> [SearchEverywhereItem] {
        guard let workspace else { return [] }
        let urls = recentFiles.recentFiles(for: workspace)
        guard !urls.isEmpty else { return [] }

        let root = workspace.fileURL
        var items: [SearchEverywhereItem] = []
        for (position, url) in urls.enumerated() {
            let filename = url.lastPathComponent
            let relative = root.map { SearchEverywhereFileScanner.relativePath(of: url, from: $0) } ?? filename
            let match: SearchEverywhereMatch?
            if text.isEmpty {
                match = SearchEverywhereMatch(score: 0, ranges: [])
            } else if let root {
                let fileMatch = SearchEverywhereProjectSearch.matchFile(query: text, url: url, root: root)
                match = fileMatch.map { SearchEverywhereMatch(score: $0.score, ranges: $0.ranges) }
            } else {
                match = SearchEverywhereMatcher.match(query: text, in: filename)
            }
            guard let match else { continue }
            items.append(SearchEverywhereItem(
                id: "recent:\(relative)",
                section: .recent,
                kind: .file,
                title: filename,
                detail: (relative as NSString).deletingLastPathComponent,
                iconName: IntelliJIcon.fileIcon(for: filename),
                ranges: match.ranges,
                url: url,
                line: nil,
                column: nil,
                action: nil,
                weight: SearchEverywhereComposedWeight(match: match.score, recency: urls.count - position),
                isExactMatch: !text.isEmpty && SearchEverywhereRanking.isExactMatch(
                    degree: match.score,
                    presentableText: filename,
                    inputQuery: text,
                    isFile: true
                ),
                equalityKey: "file:\(relative)"
            ))
        }

        return ranked(items, limit: limit)
    }

    private func startTextSearch(_ text: String) {
        guard let scope = workspace?.fileScope else { return }
        let searchState = workspace?.searchState
        let pattern = searchState?.getRegexPattern(text) ?? NSRegularExpression.escapedPattern(for: text)
        let caseSensitive = searchState?.caseSensitive ?? false
        let query = text
        textTask = Task { [weak self] in
            let matches = await SearchEverywhereProjectSearch.textMatches(
                pattern: pattern,
                caseSensitive: caseSensitive,
                scope: scope
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
            weight: SearchEverywhereComposedWeight(0),
            isExactMatch: false,
            equalityKey: nil
        )
    }

    private func ranked(_ items: [SearchEverywhereItem], limit: Int) -> [SearchEverywhereItem] {
        let order = SearchEverywhereRanking.rank(items.map(\.rankingCandidate), limitPerProvider: limit)
        return order.map { items[$0] }
    }

    private func rebuildSections() {
        let previousID = selectedItem?.id

        let merged = tab.sections.flatMap { pools[$0] ?? [] }
        let items = ranked(merged, limit: providerLimit)
        sections = SearchEverywhereRanking.contiguousRuns(items.map(\.section)).map { run in
            SearchEverywhereSection(kind: run.element, items: Array(items[run.range]))
        }

        let flat = flatItems
        if let previousID, let index = flat.firstIndex(where: { $0.id == previousID }) {
            selection = index
        } else if flat.isEmpty {
            selection = 0
        } else {
            selection = min(max(selection, 0), flat.count - 1)
        }

        updatePreview()
    }

    private var providerLimit: Int {
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
