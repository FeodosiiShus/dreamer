import Foundation

nonisolated enum TestShard {
    static let environmentKey = "DREAMDER_SHARD"

    static func identifier(in environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let value = environment[environmentKey], !value.isEmpty else { return nil }
        return value
    }

    static var suiteFragment: String {
        identifier().map { "s\($0)." } ?? ""
    }
}
