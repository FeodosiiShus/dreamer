import Foundation
import OSLog

nonisolated enum EditorLogging {
    static let fallbackSubsystem = "dev.dreamder.Dreamder"

    static func subsystem(of bundle: Bundle) -> String {
        bundle.bundleIdentifier ?? fallbackSubsystem
    }

    static func logger(category: String, bundle: Bundle = .main) -> Logger {
        Logger(subsystem: subsystem(of: bundle), category: category)
    }
}
