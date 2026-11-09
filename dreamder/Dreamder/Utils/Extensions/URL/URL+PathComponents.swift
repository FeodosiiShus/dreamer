import Foundation

nonisolated extension URL {
    func containsSubPath(_ other: URL) -> Bool {
        other.absoluteString.starts(with: absoluteString)
            && other.pathComponents.count > pathComponents.count
    }

    func sharedComponents(_ other: URL) -> Int {
        var count = 0
        for (component, otherComponent) in zip(pathComponents, other.pathComponents) {
            if component == otherComponent {
                count += 1
            } else {
                return count
            }
        }
        return count
    }
}
