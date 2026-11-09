import AppKit
import CodeEditSourceEditor
import Foundation

extension SearchEverywhereViewModel {
    func fileItem(
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

    func symbolItem(_ hit: SearchEverywhereSymbolHit, classesOnly: Bool) -> SearchEverywhereItem {
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

    func buildActionItems(text: String, limit: Int) -> [SearchEverywhereItem] {
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

    func buildRecentItems(text: String, limit: Int) -> [SearchEverywhereItem] {
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

    func textItem(for match: SearchEverywhereTextMatch) -> SearchEverywhereItem {
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

    func ranked(_ items: [SearchEverywhereItem], limit: Int) -> [SearchEverywhereItem] {
        let order = SearchEverywhereRanking.rank(items.map(\.rankingCandidate), limitPerProvider: limit)
        return order.map { items[$0] }
    }
}
