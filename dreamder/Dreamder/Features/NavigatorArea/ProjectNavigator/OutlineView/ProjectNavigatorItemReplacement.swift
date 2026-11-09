import Foundation

nonisolated struct ProjectNavigatorFileOperations: Sendable {
    typealias Transfer = @Sendable (URL, URL) throws -> Void

    let move: Transfer
    let copy: Transfer
    let remove: @Sendable (URL) throws -> Void

    static let live = ProjectNavigatorFileOperations(
        move: { try FileManager.default.moveItem(at: $0, to: $1) },
        copy: { try FileManager.default.copyItem(at: $0, to: $1) },
        remove: { try FileManager.default.removeItem(at: $0) }
    )
}

nonisolated enum ProjectNavigatorItemReplacement {
    enum Mode: Sendable {
        case move
        case copy
    }

    static func setAside(_ destination: URL, using operations: ProjectNavigatorFileOperations) throws -> URL {
        let backup = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).replaced-\(UUID().uuidString)")
        try operations.move(destination, backup)
        return backup
    }

    static func restore(_ backup: URL, to destination: URL, using operations: ProjectNavigatorFileOperations) {
        try? operations.move(backup, destination)
    }

    static func discard(_ backup: URL, using operations: ProjectNavigatorFileOperations) {
        try? operations.remove(backup)
    }

    static func replace(
        _ destination: URL,
        with source: URL,
        mode: Mode,
        using operations: ProjectNavigatorFileOperations
    ) throws {
        let backup = try setAside(destination, using: operations)
        do {
            switch mode {
            case .move:
                try operations.move(source, destination)
            case .copy:
                try operations.copy(source, destination)
            }
        } catch {
            restore(backup, to: destination, using: operations)
            throw error
        }
        discard(backup, using: operations)
    }
}
