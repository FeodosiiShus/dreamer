import Foundation

nonisolated enum TestHost {
    static let environmentKey = "XCTestConfigurationFilePath"

    static func isActive(in environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[environmentKey] != nil
    }
}
