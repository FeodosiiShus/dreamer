import Foundation

nonisolated enum SwiftPackageTaskDiscovery {
    private static let manifestName = "Package.swift"

    static func group(in directory: ScannedDirectory) -> DiscoveredTaskGroup? {
        guard directory.fileNames.contains(manifestName) else { return nil }
        return directory.group(
            kind: .swiftPackage,
            manifestName: manifestName,
            entries: [TaskEntry(command: "swift build"), TaskEntry(command: "swift test")]
        )
    }
}
