import Foundation

nonisolated enum RecentProjectsFilter {
    static func searchName(for project: RecentProject, home: String) -> String {
        var path = project.path
        if path == home || path.hasPrefix(home + "/") {
            path = String(path.dropFirst(home.count))
        }
        return " \(path) \(project.displayName)"
    }

    static func filter(_ projects: [RecentProject], query: String, home: String) -> [RecentProject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return projects }
        let matcher = MinusculeMatcher(pattern: "*" + trimmed, mode: .ignoreCase)
        return projects.filter { matcher.matches(searchName(for: $0, home: home)) }
    }
}
