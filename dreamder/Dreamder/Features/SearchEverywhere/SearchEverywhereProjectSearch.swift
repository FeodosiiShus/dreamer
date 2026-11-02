import Foundation

enum SearchEverywhereFileScanner {
    static let ignoredDirectoryNames: Set<String> = [
        ".git",
        "node_modules",
        ".build",
        "build",
        "DerivedData"
    ]

    static let textFileExtensions: Set<String> = SymbolExtractor.textFileExtensions.union([
        "md", "txt", "json", "jsonc", "yaml", "yml", "html", "xml", "css", "sh", "zsh", "bash",
        "m", "mm", "h", "c", "cpp", "hpp", "cs", "rb", "php"
    ])

    static func urls(
        in root: URL,
        extensions: Set<String>? = nil,
        maxFileSize: Int? = nil,
        maxCount: Int = 20000
    ) async -> [URL] {
        scanURLs(in: root, extensions: extensions, maxFileSize: maxFileSize, maxCount: maxCount)
    }

    private static func scanURLs(
        in root: URL,
        extensions: Set<String>?,
        maxFileSize: Int?,
        maxCount: Int
    ) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        let exclusions = ExcludedDirectories.rules(covering: root)

        for case let url as URL in enumerator {
            if Task.isCancelled { break }

            let values = try? url.resourceValues(forKeys: Set(keys))

            if values?.isSymbolicLink == true {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if values?.isDirectory == true {
                if ignoredDirectoryNames.contains(url.lastPathComponent) || exclusions.isExclusionRoot(url) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }

            if let extensions, !extensions.contains(url.pathExtension.lowercased()) {
                continue
            }

            if let maxFileSize, let size = values?.fileSize, size > maxFileSize {
                continue
            }

            urls.append(url)

            if urls.count >= maxCount {
                break
            }
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
}

struct SearchEverywhereFileMatch {
    let score: Int
    let ranges: [NSRange]
}

struct SearchEverywhereTextMatch {
    let url: URL
    let line: Int
    let text: String
    let ranges: [NSRange]
}

struct SearchEverywherePreview: Equatable {
    struct Line: Identifiable, Equatable {
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

enum SearchEverywhereProjectSearch {
    static func matchFile(query: String, url: URL, root: URL) -> SearchEverywhereFileMatch? {
        let name = url.lastPathComponent

        guard query.contains("/") else {
            if let nameMatch = SearchEverywhereMatcher.match(query: query, in: name) {
                return SearchEverywhereFileMatch(score: nameMatch.score, ranges: nameMatch.ranges)
            }
            let relative = SearchEverywhereFileScanner.relativePath(of: url, from: root)
            if let pathMatch = SearchEverywhereMatcher.match(query: query, in: relative) {
                return SearchEverywhereFileMatch(score: pathMatch.score - 140, ranges: [])
            }
            return nil
        }

        let segments = query.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard let lastSegment = segments.last else { return nil }
        guard let nameMatch = SearchEverywhereMatcher.match(query: lastSegment, in: name) else { return nil }

        let components = SearchEverywhereFileScanner.relativePath(of: url, from: root)
            .components(separatedBy: "/")
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

    static func textMatches(
        pattern: String,
        caseSensitive: Bool,
        root: URL,
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
            in: root,
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

    static func preview(url: URL, targetLine: Int, context: Int = 6) async -> SearchEverywherePreview? {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = resourceValues?.fileSize, size > 4_000_000 {
            return nil
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let rawLines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard !rawLines.isEmpty else { return nil }

        let total = rawLines.count
        let target = min(max(targetLine, 1), total)
        let start = max(1, target - context)
        let end = min(total, target + context)

        var lines: [SearchEverywherePreview.Line] = []
        for number in start...end {
            let raw = String(rawLines[number - 1]).replacingOccurrences(of: "\r", with: "")
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

enum SearchEverywhereSymbolScanner {
    static func scan(root: URL, limit: Int = 12000) async -> [SearchEverywhereSymbol] {
        let urls = await SearchEverywhereFileScanner.urls(
            in: root,
            extensions: SymbolExtractor.textFileExtensions,
            maxFileSize: 400_000,
            maxCount: 8000
        )

        var symbols: [SearchEverywhereSymbol] = []
        for url in urls {
            if Task.isCancelled || symbols.count >= limit { break }
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
