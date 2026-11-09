import Foundation

nonisolated enum SearchEverywhereFileScanner {
    static let textFileExtensions: Set<String> = SymbolExtractor.textFileExtensions.union([
        "md", "txt", "json", "jsonc", "yaml", "yml", "html", "xml", "css", "sh", "zsh", "bash",
        "m", "mm", "h", "c", "cpp", "hpp", "cs", "rb", "php"
    ])

    @concurrent
    static func urls(
        scope: WorkspaceFileScope,
        extensions: Set<String>? = nil,
        maxFileSize: Int? = nil,
        maxCount: Int? = nil
    ) async -> [URL] {
        let all = await scope.enumerateFiles(limit: nil)
        guard extensions != nil || maxFileSize != nil || maxCount != nil else { return all }
        var urls: [URL] = []
        for url in all {
            if Task.isCancelled { break }
            if let extensions, !extensions.contains(url.pathExtension.lowercased()) { continue }
            if let maxFileSize, let size = fileSize(of: url), size > maxFileSize { continue }
            urls.append(url)
            if let maxCount, urls.count >= maxCount { break }
        }
        return urls
    }

    static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }
        var relative = String(path.dropFirst(rootPath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    private static func fileSize(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
}

nonisolated struct SearchEverywhereRelativePaths: Sendable {
    private let root: URL
    private let prefix: String

    init(root: URL) {
        self.root = root
        prefix = root.workspacePathKey + "/"
    }

    func relative(_ url: URL) -> String {
        let path = url.workspacePathKey
        guard path.hasPrefix(prefix) else {
            return SearchEverywhereFileScanner.relativePath(of: url, from: root)
        }
        return String(path.dropFirst(prefix.count))
    }
}

nonisolated struct SearchEverywhereFileMatch: Sendable {
    let score: Int
    let ranges: [NSRange]
}

nonisolated struct SearchEverywhereTextMatch: Sendable {
    let url: URL
    let line: Int
    let text: String
    let ranges: [NSRange]
}

nonisolated struct SearchEverywhereFileHit: Sendable {
    let url: URL
    let relative: String
    let match: SearchEverywhereFileMatch
    let isExactMatch: Bool
}

nonisolated struct SearchEverywhereSymbolHit: Sendable {
    let symbol: SearchEverywhereSymbol
    let relative: String
    let match: SearchEverywhereMatch
    let isExactMatch: Bool
}

nonisolated struct SearchEverywherePreview: Equatable, Sendable {
    struct Line: Identifiable, Equatable, Sendable {
        let number: Int
        let text: String
        let isTarget: Bool

        var id: Int { number }
    }

    let url: URL
    let title: String
    let subtitle: String
    let lines: [Line]
}

nonisolated enum SearchEverywhereProjectSearch {
    static func matchFile(query: String, url: URL, root: URL) -> SearchEverywhereFileMatch? {
        matchFile(
            query: query,
            name: url.lastPathComponent,
            relative: SearchEverywhereFileScanner.relativePath(of: url, from: root)
        )
    }

    static func matchFile(
        query: String,
        name: String,
        relative: @autoclosure () -> String
    ) -> SearchEverywhereFileMatch? {
        guard query.contains("/") else {
            if let nameMatch = SearchEverywhereMatcher.match(query: query, in: name) {
                return SearchEverywhereFileMatch(score: nameMatch.score, ranges: nameMatch.ranges)
            }
            if let pathMatch = SearchEverywhereMatcher.match(query: query, in: relative()) {
                return SearchEverywhereFileMatch(score: pathMatch.score - 140, ranges: [])
            }
            return nil
        }

        let segments = query.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard let lastSegment = segments.last else { return nil }
        guard let nameMatch = SearchEverywhereMatcher.match(query: lastSegment, in: name) else { return nil }

        let components = relative().components(separatedBy: "/")
        let directoryComponents = Array(components.dropLast())
        var cursor = 0

        for segment in segments.dropLast() {
            var found = false
            while cursor < directoryComponents.count {
                if SearchEverywhereMatcher.match(query: segment, in: directoryComponents[cursor]) != nil {
                    found = true
                    cursor += 1
                    break
                }
                cursor += 1
            }
            guard found else { return nil }
        }

        return SearchEverywhereFileMatch(score: nameMatch.score + 20, ranges: nameMatch.ranges)
    }

    @concurrent
    static func rankedFileHits(
        text: String,
        urls: [URL],
        root: URL,
        limit: Int
    ) async -> [SearchEverywhereFileHit] {
        let paths = SearchEverywhereRelativePaths(root: root)
        let provider = SearchEverywhereSectionKind.files.provider
        var hits: [SearchEverywhereFileHit] = []
        var candidates: [SearchEverywhereCandidate] = []
        for (offset, url) in urls.enumerated() {
            if offset % 2048 == 0, Task.isCancelled { return [] }
            let name = url.lastPathComponent
            guard let match = matchFile(query: text, name: name, relative: paths.relative(url)) else { continue }
            let relative = paths.relative(url)
            let isExact = SearchEverywhereRanking.isExactMatch(
                degree: match.score,
                presentableText: name,
                inputQuery: text,
                isFile: true
            )
            hits.append(SearchEverywhereFileHit(url: url, relative: relative, match: match, isExactMatch: isExact))
            candidates.append(SearchEverywhereCandidate(
                id: "file:\(relative)",
                provider: provider,
                title: name,
                weight: SearchEverywhereComposedWeight(match.score),
                isExactMatch: isExact,
                equalityKey: "file:\(relative)"
            ))
        }
        return SearchEverywhereRanking.rank(candidates, limitPerProvider: limit).map { hits[$0] }
    }

    @concurrent
    static func rankedSymbolHits(
        text: String,
        symbols: [SearchEverywhereSymbol],
        root: URL,
        classesOnly: Bool,
        limit: Int
    ) async -> [SearchEverywhereSymbolHit] {
        let paths = SearchEverywhereRelativePaths(root: root)
        let provider = (classesOnly ? SearchEverywhereSectionKind.classes : .symbols).provider
        let idPrefix = classesOnly ? "class" : "symbol"
        var hits: [SearchEverywhereSymbolHit] = []
        var candidates: [SearchEverywhereCandidate] = []
        for (offset, symbol) in symbols.enumerated() {
            if offset % 2048 == 0, Task.isCancelled { return [] }
            if classesOnly && !symbol.kind.isType { continue }
            guard let match = SearchEverywhereMatcher.match(query: text, in: symbol.name) else { continue }
            let relative = paths.relative(symbol.url)
            let isExact = SearchEverywhereRanking.isExactMatch(
                degree: match.score,
                presentableText: symbol.name,
                inputQuery: text,
                isFile: false
            )
            hits.append(SearchEverywhereSymbolHit(
                symbol: symbol,
                relative: relative,
                match: match,
                isExactMatch: isExact
            ))
            candidates.append(SearchEverywhereCandidate(
                id: "\(idPrefix):\(relative):\(symbol.line):\(symbol.name)",
                provider: provider,
                title: symbol.name,
                weight: SearchEverywhereComposedWeight(match.score),
                isExactMatch: isExact,
                equalityKey: "symbol:\(relative):\(symbol.line):\(symbol.name)"
            ))
        }
        return SearchEverywhereRanking.rank(candidates, limitPerProvider: limit).map { hits[$0] }
    }

    @concurrent
    static func textMatches(
        pattern: String,
        caseSensitive: Bool,
        scope: WorkspaceFileScope,
        limit: Int = 120,
        perFileLimit: Int = 5
    ) async -> [SearchEverywhereTextMatch] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: caseSensitive ? [] : .caseInsensitive
        ) else {
            return []
        }

        let urls = await SearchEverywhereFileScanner.urls(
            scope: scope,
            extensions: SearchEverywhereFileScanner.textFileExtensions,
            maxFileSize: 512_000,
            maxCount: 6000
        )

        var matches: [SearchEverywhereTextMatch] = []

        for url in urls {
            if Task.isCancelled || matches.count >= limit { break }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            var perFile = 0
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, rawLine) in lines.enumerated() {
                if perFile >= perFileLimit || matches.count >= limit { break }
                let line = String(rawLine).replacingOccurrences(of: "\r", with: "")
                let display = displayLine(from: line)
                guard !display.isEmpty else { continue }

                let range = NSRange(location: 0, length: (display as NSString).length)
                guard let match = regex.firstMatch(in: display, options: [], range: range) else { continue }

                matches.append(SearchEverywhereTextMatch(
                    url: url,
                    line: index + 1,
                    text: display,
                    ranges: [match.range]
                ))
                perFile += 1
            }
        }

        return matches
    }

    @concurrent
    static func preview(url: URL, targetLine: Int, context: Int = 6) async -> SearchEverywherePreview? {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = resourceValues?.fileSize, size > WorkspaceFileScope.maxIndexableTextSize {
            return nil
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let rawLines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        let total = rawLines.count
        let target = min(max(targetLine, 1), total)
        let start = max(1, target - context)
        let end = min(total, target + context)

        var lines: [SearchEverywherePreview.Line] = []
        for number in start...end {
            let raw = String(rawLines[number - 1])
            let text = raw.count > 240 ? String(raw.prefix(240)) : raw
            lines.append(SearchEverywherePreview.Line(number: number, text: text, isTarget: number == target))
        }

        return SearchEverywherePreview(
            url: url,
            title: url.lastPathComponent,
            subtitle: "Line \(target) of \(total)",
            lines: lines
        )
    }

    private static func displayLine(from line: String) -> String {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.count > 200 else { return String(trimmed) }
        return String(trimmed.prefix(200))
    }
}

nonisolated enum SearchEverywhereSymbolScanner {
    static let maxFileSize = 400_000
    static let maxFileCount = 8000

    @concurrent
    static func scan(scope: WorkspaceFileScope, limit: Int = 12000) async -> [SearchEverywhereSymbol] {
        let urls = await SearchEverywhereFileScanner.urls(
            scope: scope,
            extensions: SymbolExtractor.textFileExtensions,
            maxFileSize: maxFileSize,
            maxCount: maxFileCount
        )
        return symbols(in: urls, limit: limit)
    }

    @concurrent
    static func symbols(inChanged urls: [URL], scope: WorkspaceFileScope) async -> [SearchEverywhereSymbol] {
        let candidates = urls.filter { url in
            SymbolExtractor.textFileExtensions.contains(url.pathExtension.lowercased())
                && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) <= maxFileSize
                && scope.isIndexableText(url)
        }
        return symbols(in: candidates, limit: nil)
    }

    private static func symbols(in urls: [URL], limit: Int?) -> [SearchEverywhereSymbol] {
        var symbols: [SearchEverywhereSymbol] = []
        for url in urls {
            if Task.isCancelled { break }
            if let limit, symbols.count >= limit { break }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let extracted = SymbolExtractor.symbols(in: content, fileExtension: url.pathExtension)
            for symbol in extracted {
                symbols.append(SearchEverywhereSymbol(
                    name: symbol.name,
                    kind: symbol.kind,
                    url: url,
                    line: symbol.line
                ))
            }
        }
        return symbols
    }
}
