import Foundation

nonisolated enum CargoTaskDiscovery {
    private static let manifestName = "Cargo.toml"
    private static let packageCommands = ["cargo run", "cargo test", "cargo build"]
    private static let workspaceCommands = ["cargo build --workspace", "cargo test --workspace"]

    static func group(in directory: ScannedDirectory) -> DiscoveredTaskGroup? {
        guard directory.fileNames.contains(manifestName),
              let text = try? String(contentsOf: directory.fileURL(manifestName), encoding: .utf8) else { return nil }
        let headers = Set(text.split(whereSeparator: \.isNewline).map { line in
            line.prefix(while: { $0 != "#" }).trimmingCharacters(in: .whitespaces)
        })
        var commands: [String] = []
        if headers.contains("[package]") {
            commands += packageCommands
        }
        if headers.contains("[workspace]") {
            commands += workspaceCommands
        }
        return directory.group(
            kind: .cargo,
            manifestName: manifestName,
            entries: commands.map { TaskEntry(command: $0) }
        )
    }
}
