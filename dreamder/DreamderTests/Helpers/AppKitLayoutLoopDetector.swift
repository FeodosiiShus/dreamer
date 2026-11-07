import Foundation
import OSLog

nonisolated enum AppKitLayoutLoopDetector {
    struct Diagnostic: Sendable {
        let date: Date
        let message: String
    }

    static let signatures = [
        "has continued for",
        "Update Constraints in Window passes",
        "Layout Window passes",
        "kept the layout or constraints dirty"
    ]

    @concurrent
    static func diagnostics(since start: Date) async throws -> [Diagnostic] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@", "com.apple.AppKit")
        return try store.getEntries(at: store.position(date: start), matching: predicate).compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }
            let message = log.composedMessage
            guard signatures.contains(where: message.contains) else { return nil }
            return Diagnostic(date: log.date, message: message)
        }
    }

    static func describe(_ diagnostics: [Diagnostic], steps: [(date: Date, name: String)]) -> String {
        diagnostics.map { diagnostic in
            let step = steps.last { $0.date <= diagnostic.date }?.name ?? "setup"
            return "after \(step): \(diagnostic.message)"
        }
        .joined(separator: "\n")
    }
}
