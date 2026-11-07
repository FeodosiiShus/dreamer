import Foundation

nonisolated enum ProcessEnvironment {
    static let strippedPrefixes = ["DYLD_", "__XPC_DYLD_"]

    static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment.filter { entry in
            !strippedPrefixes.contains { entry.key.hasPrefix($0) }
        }
    }
}
