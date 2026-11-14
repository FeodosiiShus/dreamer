import Foundation

extension LSPService.Dependencies {
    static func forHost(environment: [String: String] = ProcessInfo.processInfo.environment) -> LSPService.Dependencies {
        var dependencies = LSPService.Dependencies.live
        if TestHost.isActive(in: environment) {
            dependencies.discoverBinary = { _, _ in nil }
        }
        return dependencies
    }
}
