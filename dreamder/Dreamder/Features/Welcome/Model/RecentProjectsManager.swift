import Foundation
import Observation

@MainActor
@Observable
final class RecentProjectsManager {
    static let maxRecentProjects = 50
    static let storageKey = "dreamder.recentProjects"
    static let legacyBookmarksKey = "recentProjectBookmarks"
    static let shared = RecentProjectsManager()

    private(set) var allProjects: [RecentProject]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        allProjects = Self.loadStoredProjects(from: defaults)
    }

    var recentProjects: [RecentProject] {
        allProjects.filter { !$0.hidden }
    }

    var recentPaths: [String] {
        recentProjects.map(\.path)
    }

    func recentDirectoryURLs() -> [URL] {
        recentProjects.filter(\.isDirectory).map(\.url)
    }

    func recentFileURLs() -> [URL] {
        recentProjects.filter { !$0.isDirectory }.map(\.url)
    }

    func hasPath(_ path: String) -> Bool {
        allProjects.contains { $0.path == path }
    }

    func displayName(forPath path: String) -> String? {
        allProjects.first { $0.path == path }?.displayName
    }

    func markRecent(at url: URL, isDirectory: Bool) {
        let path = Self.normalizedPath(of: url)
        let hidden = allProjects.first { $0.path == path }?.hidden ?? false
        allProjects.removeAll { $0.path == path }
        allProjects.insert(
            RecentProject(
                path: path,
                displayName: RecentProject.displayName(forPath: path),
                projectOpenTimestamp: Int64(now().timeIntervalSince1970 * 1000),
                isDirectory: isDirectory,
                hidden: hidden
            ),
            at: 0
        )
        Self.trim(&allProjects)
        persist()
    }

    func removeRecentProject(path: String) {
        guard hasPath(path) else { return }
        allProjects.removeAll { $0.path == path }
        persist()
    }

    func setHidden(_ hidden: Bool, forPath path: String) {
        guard let index = allProjects.firstIndex(where: { $0.path == path }),
              allProjects[index].hidden != hidden else { return }
        allProjects[index].hidden = hidden
        persist()
    }

    func clear() {
        allProjects = []
        persist()
    }

    func validate() async {
        let snapshot = allProjects.map(\.path)
        let kinds = await Self.existingKinds(of: snapshot)
        applyValidation(kinds: kinds, checkedPaths: Set(snapshot))
    }

    func applyValidation(kinds: [String: Bool], checkedPaths: Set<String>) {
        var validated: [RecentProject] = []
        for project in allProjects {
            guard checkedPaths.contains(project.path) else {
                validated.append(project)
                continue
            }
            guard let isDirectory = kinds[project.path] else { continue }
            var updated = project
            updated.isDirectory = isDirectory
            validated.append(updated)
        }
        guard validated != allProjects else { return }
        allProjects = validated
        persist()
    }

    @concurrent
    static func existingKinds(of paths: [String]) async -> [String: Bool] {
        var kinds: [String: Bool] = [:]
        for path in paths {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                kinds[path] = isDirectory.boolValue
            }
        }
        return kinds
    }

    static func normalizedPath(of url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func trim(_ projects: inout [RecentProject]) {
        if projects.count > maxRecentProjects {
            projects.removeLast(projects.count - maxRecentProjects)
        }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(allProjects), forKey: Self.storageKey)
    }

    private static func loadStoredProjects(from defaults: UserDefaults) -> [RecentProject] {
        if let data = defaults.data(forKey: storageKey) {
            return (try? JSONDecoder().decode([RecentProject].self, from: data)) ?? []
        }
        guard let legacy = defaults.data(forKey: legacyBookmarksKey) else { return [] }
        let paths = (try? PropertyListDecoder().decode([LegacyBookmarkEntry].self, from: legacy))?.map(\.urlPath) ?? []
        var seen = Set<String>()
        var migrated = paths.filter { seen.insert($0).inserted }.map {
            RecentProject(
                path: $0,
                displayName: RecentProject.displayName(forPath: $0),
                projectOpenTimestamp: 0,
                isDirectory: true,
                hidden: false
            )
        }
        trim(&migrated)
        defaults.set(try? JSONEncoder().encode(migrated), forKey: storageKey)
        defaults.removeObject(forKey: legacyBookmarksKey)
        return migrated
    }
}

private nonisolated struct LegacyBookmarkEntry: Decodable {
    let urlPath: String
}
