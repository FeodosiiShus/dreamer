import Foundation

nonisolated enum TestFileClassifier {
    private static let testMarkers: Set<Substring> = ["spec", "test"]

    static func isTestFile(_ url: URL) -> Bool {
        if url.pathComponents.dropLast().contains("__tests__") {
            return true
        }
        let parts = url.lastPathComponent.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts[1..<(parts.count - 1)].contains { testMarkers.contains($0) }
    }
}
