import Foundation

extension DreamderHeadless {
    static let enabledArgumentValues: Set<String> = ["yes", "true", "1"]

    static let isEnabled = resolveIsEnabled(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments
    )

    static func resolveIsEnabled(environment: [String: String], arguments: [String]) -> Bool {
        if environment[environmentKey] == "1" {
            return true
        }
        guard let flag = arguments.firstIndex(of: "-" + argumentKey),
              let value = arguments.dropFirst(flag + 1).first else {
            return false
        }
        return enabledArgumentValues.contains(value.lowercased())
    }
}
