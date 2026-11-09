import Foundation
import Synchronization

nonisolated final class GitignoreMatcher: Sendable {
    struct Level: Sendable {
        let depth: Int
        let rules: GitignoreRuleSet
    }

    struct Chain: Sendable {
        fileprivate(set) var levels: [Level]

        func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
            guard !levels.isEmpty else { return false }
            let scalars = Array(relativePath.unicodeScalars)
            var starts = [0]
            for (index, scalar) in scalars.enumerated() where scalar == "/" {
                starts.append(index + 1)
            }
            let name = scalars[starts[starts.count - 1]...]
            for level in levels.reversed() {
                guard level.depth < starts.count else { continue }
                let relative = scalars[starts[level.depth]...]
                if let verdict = level.rules.verdict(relativePath: relative, name: name, isDirectory: isDirectory) {
                    return verdict
                }
            }
            return false
        }
    }

    private static let ignoreFileName = ".gitignore"

    private let rootURL: URL
    private let rootPath: String
    private let cache = Mutex<[String: GitignoreRuleSet]>([:])

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        var path = self.rootURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        self.rootPath = path
    }

    func reset() {
        cache.withLock { $0.removeAll() }
    }

    func rootChain() -> Chain {
        let info = rules(at: rootURL.appending(path: ".git/info/exclude"), cacheKey: "info/exclude")
        let root = rules(at: rootURL.appending(path: Self.ignoreFileName), cacheKey: "dir:")
        return Chain(levels: Self.levels(depth: 0, rules: [info, root]))
    }

    func descend(_ chain: Chain, into relativeDirectory: String) -> Chain {
        let depth = relativeDirectory.split(separator: "/").count
        let file = rootURL.appending(path: relativeDirectory + "/" + Self.ignoreFileName)
        let loaded = rules(at: file, cacheKey: "dir:" + relativeDirectory)
        guard !loaded.isEmpty else { return chain }
        var next = chain
        next.levels.append(Level(depth: depth, rules: loaded))
        return next
    }

    func isIgnored(_ url: URL, isDirectory: Bool) -> Bool {
        guard let relative = relativePath(of: url), !relative.isEmpty else { return false }
        return isIgnored(relativePath: relative, isDirectory: isDirectory)
    }

    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }
        var chain = rootChain()
        var prefix = ""
        for (index, component) in components.enumerated() {
            let current = prefix.isEmpty ? component : prefix + "/" + component
            let isLast = index == components.count - 1
            if chain.isIgnored(relativePath: current, isDirectory: !isLast || isDirectory) { return true }
            if !isLast { chain = descend(chain, into: current) }
            prefix = current
        }
        return false
    }

    func relativePath(of url: URL) -> String? {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == rootPath { return "" }
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func levels(depth: Int, rules: [GitignoreRuleSet]) -> [Level] {
        rules.filter { !$0.isEmpty }.map { Level(depth: depth, rules: $0) }
    }

    private func rules(at file: URL, cacheKey: String) -> GitignoreRuleSet {
        if let cached = cache.withLock({ $0[cacheKey] }) { return cached }
        let loaded: GitignoreRuleSet
        if let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) {
            loaded = GitignoreRuleSet(text: text)
        } else {
            loaded = .empty
        }
        cache.withLock { $0[cacheKey] = loaded }
        return loaded
    }
}
