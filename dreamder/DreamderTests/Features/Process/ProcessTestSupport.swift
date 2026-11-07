import Foundation
@testable import Dreamder

nonisolated enum ProcessTestSupport {
    static let minimalEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    static func shell(
        _ script: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = minimalEnvironment,
        standardInput: Data? = nil,
        timeout: Duration? = .seconds(60)
    ) -> ProcessInvocation {
        ProcessInvocation(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "sh"] + arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            standardInput: standardInput,
            timeout: timeout
        )
    }

    static func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @Sendable () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    static func readProcessIdentifier(from file: URL) -> Int32? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isAlive(_ processIdentifier: Int32) -> Bool {
        kill(processIdentifier, 0) == 0
    }
}
