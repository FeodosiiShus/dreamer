import Foundation

nonisolated struct KeymapDefaultsEntry: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let group: String
    let shortcuts: [String]
}

nonisolated enum KeymapDefaultsExport {
    static var entries: [KeymapDefaultsEntry] {
        KeymapCommand.allCases.map {
            KeymapDefaultsEntry(
                id: $0.id,
                title: $0.title,
                group: $0.group.title,
                shortcuts: $0.defaultShortcuts.map(\.text)
            )
        }
    }

    static func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(entries)
    }
}
