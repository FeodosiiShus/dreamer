import Foundation

nonisolated enum ProjectNavigatorExclusion: Sendable, Equatable {
    case included
    case excludedRoot
    case excludedContent

    var isExcluded: Bool {
        self != .included
    }

    static func resolve(
        url: URL,
        isFolder: Bool,
        parentURL: URL?,
        scope: WorkspaceFileScope?
    ) -> ProjectNavigatorExclusion {
        guard let scope, scope.isExcluded(url, isDirectory: isFolder) else { return .included }
        if let parentURL, scope.isExcluded(parentURL, isDirectory: true) {
            return .excludedContent
        }
        return .excludedRoot
    }
}
