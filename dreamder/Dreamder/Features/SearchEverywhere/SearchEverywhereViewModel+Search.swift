import AppKit
import CodeEditSourceEditor
import Foundation

extension SearchEverywhereViewModel {
    func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.performSearch()
        }
    }

    func performSearch() {
        let parsed = SearchEverywhereQuery.parse(query)
        let text = parsed.text.trimmingCharacters(in: .whitespaces)
        currentText = text
        textTask?.cancel()
        indexTask?.cancel()

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

    func startIndexSearch(
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
        let store = index?.store ?? SearchEverywhereSymbolStore()
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
                self?.publish(.files) { model in
                    hits.map { model.fileItem($0, line: parsed.line, column: parsed.column) }
                }
            }
            if wantsClasses || wantsSymbols {
                let symbols = await store.flattened()
                for classesOnly in [true, false] where classesOnly ? wantsClasses : wantsSymbols {
                    let hits = await SearchEverywhereProjectSearch.rankedSymbolHits(
                        text: text,
                        symbols: symbols,
                        root: root,
                        classesOnly: classesOnly,
                        limit: 300
                    )
                    guard !Task.isCancelled else { return }
                    self?.publishSymbolHits(hits, classesOnly: classesOnly)
                }
            }
        }
    }

    private func publishSymbolHits(_ hits: [SearchEverywhereSymbolHit], classesOnly: Bool) {
        publish(classesOnly ? .classes : .symbols) { model in
            hits.map { model.symbolItem($0, classesOnly: classesOnly) }
        }
    }

    func publish(
        _ kind: SearchEverywhereSectionKind,
        items: (SearchEverywhereViewModel) -> [SearchEverywhereItem]
    ) {
        pools[kind] = items(self)
        rebuildSections()
    }

    func startTextSearch(_ text: String) {
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

    func rebuildSections() {
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

    var providerLimit: Int {
        tab == .all ? 8 : 300
    }

    func updatePreview() {
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

    func openFile(_ url: URL, line: Int?, column: Int?) {
        guard let workspace, let editorManager = workspace.editorManager else { return }
        let file = workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true)
            ?? CEWorkspaceFile(url: url)
        editorManager.openTab(item: file)

        guard let line else { return }
        let position = CursorPosition(line: max(line, 1), column: max(column ?? 1, 1))
        let editor = editorManager.activeEditor
        let target = file.url.standardizedFileURL
        if let instance = editor.tabs.first(where: { $0.file.url.standardizedFileURL == target }) {
            instance.cursorPositions = [position]
        }
        editor.selectedTab?.cursorPositions = [position]
    }
}
