import Combine
import Foundation

struct ExclusionRules: Sendable, Equatable {
    static let defaultExcludedNames: Set<String> = ["node_modules"]

    let rootPath: String
    var excluded: Set<String> = []
    var cancelledDefaults: Set<String> = []

    init(rootURL: URL, excluded: Set<String> = [], cancelledDefaults: Set<String> = []) {
        rootPath = Self.normalizedPath(rootURL)
        self.excluded = excluded
        self.cancelledDefaults = cancelledDefaults
    }

    func relativePath(of url: URL) -> String? {
        let path = Self.normalizedPath(url)
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    func isExclusionRoot(_ url: URL) -> Bool {
        guard let relative = relativePath(of: url) else { return false }
        if excluded.contains(relative) {
            return true
        }
        return Self.defaultExcludedNames.contains(url.lastPathComponent) && !cancelledDefaults.contains(relative)
    }

    func isExcluded(_ url: URL) -> Bool {
        guard let relative = relativePath(of: url) else { return false }
        var current = URL(fileURLWithPath: rootPath, isDirectory: true)
        for component in relative.split(separator: "/") {
            current.append(path: String(component))
            if isExclusionRoot(current) {
                return true
            }
        }
        return false
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

final class ExcludedDirectories: ObservableObject {
    static let excludedKeyPrefix = "dreamder.excludedDirectories."
    static let cancelledKeyPrefix = "dreamder.cancelledExclusions."

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registry: [String: ExclusionRules] = [:]

    static func rules(covering url: URL) -> ExclusionRules {
        let candidate = ExclusionRules(rootURL: url)
        lock.lock()
        defer { lock.unlock() }
        if let exact = registry[candidate.rootPath] {
            return exact
        }
        let enclosing = registry.values
            .filter { candidate.rootPath.hasPrefix($0.rootPath + "/") }
            .max { $0.rootPath.count < $1.rootPath.count }
        return enclosing ?? candidate
    }

    @Published private(set) var rules: ExclusionRules {
        didSet { Self.register(rules) }
    }

    private let defaults: UserDefaults

    init(rootURL: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let empty = ExclusionRules(rootURL: rootURL)
        rules = ExclusionRules(
            rootURL: rootURL,
            excluded: Set(defaults.stringArray(forKey: Self.excludedKeyPrefix + empty.rootPath) ?? []),
            cancelledDefaults: Set(defaults.stringArray(forKey: Self.cancelledKeyPrefix + empty.rootPath) ?? [])
        )
        Self.register(rules)
    }

    private static func register(_ rules: ExclusionRules) {
        lock.lock()
        registry[rules.rootPath] = rules
        lock.unlock()
    }

    func exclude(_ url: URL) {
        guard let relative = rules.relativePath(of: url) else { return }
        var updated = rules
        if ExclusionRules.defaultExcludedNames.contains(url.lastPathComponent) {
            updated.cancelledDefaults.remove(relative)
        } else {
            updated.excluded.insert(relative)
        }
        store(updated)
    }

    func cancelExclusion(_ url: URL) {
        guard let relative = rules.relativePath(of: url) else { return }
        var updated = rules
        updated.excluded.remove(relative)
        if ExclusionRules.defaultExcludedNames.contains(url.lastPathComponent) {
            updated.cancelledDefaults.insert(relative)
        }
        store(updated)
    }

    private func store(_ updated: ExclusionRules) {
        rules = updated
        defaults.set(Array(updated.excluded).sorted(), forKey: Self.excludedKeyPrefix + updated.rootPath)
        defaults.set(Array(updated.cancelledDefaults).sorted(), forKey: Self.cancelledKeyPrefix + updated.rootPath)
    }
}
