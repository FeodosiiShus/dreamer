import Foundation

nonisolated enum GoTaskDiscovery {
    private static let manifestName = "go.mod"

    static func group(in directory: ScannedDirectory) -> DiscoveredTaskGroup? {
        guard directory.fileNames.contains(manifestName) else { return nil }
        return directory.group(
            kind: .go,
            manifestName: manifestName,
            entries: [TaskEntry(command: "go run ."), TaskEntry(command: "go test ./...")]
        )
    }
}
