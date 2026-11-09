import Foundation

nonisolated enum TaskSourceKind: String, Sendable, CaseIterable {
    case npm
    case cargo
    case go
    case python
    case swiftPackage
    case make

    var title: String {
        switch self {
        case .npm: "npm"
        case .cargo: "Cargo"
        case .go: "Go"
        case .python: "Python"
        case .swiftPackage: "Swift Package"
        case .make: "Makefile"
        }
    }
}

nonisolated struct DiscoveredTask: Sendable, Hashable {
    let kind: TaskSourceKind
    let name: String
    let command: String
    let workingDirectory: String
    let manifest: String
}

nonisolated struct DiscoveredTaskGroup: Sendable, Hashable, Identifiable {
    let kind: TaskSourceKind
    let directory: String
    let manifest: String
    let tasks: [DiscoveredTask]

    var id: String {
        "\(kind.rawValue):\(directory)"
    }

    var title: String {
        directory.isEmpty ? kind.title : "\(kind.title) — \(directory)"
    }
}
