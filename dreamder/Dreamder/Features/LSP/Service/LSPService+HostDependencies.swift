import Foundation

extension LSPService.Dependencies {
    static let testHostEnvironmentKey = "XCTestConfigurationFilePath"

    static func forHost(environment: [String: String] = ProcessInfo.processInfo.environment) -> LSPService.Dependencies {
        var dependencies = LSPService.Dependencies.live
        if environment[testHostEnvironmentKey] != nil {
            dependencies.discoverBinary = { _, _ in nil }
        }
        return dependencies
    }
}
