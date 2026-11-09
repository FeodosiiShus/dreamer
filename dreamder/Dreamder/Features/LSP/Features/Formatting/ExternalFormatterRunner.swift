import Foundation

nonisolated enum ExternalFormatterOutcome: Sendable, Equatable {
    case formatted(String)
    case failed(String)
}

nonisolated struct ExternalFormatterRunner: Sendable {
    static let defaultTimeout: Duration = .seconds(30)

    let runner: any ProcessRunning
    var environment: [String: String] = [:]
    var timeout: Duration = Self.defaultTimeout

    func invocation(for formatter: ExternalFormatter, text: String) -> ProcessInvocation {
        ProcessInvocation(
            executable: formatter.executable,
            arguments: formatter.arguments,
            workingDirectory: formatter.root,
            environment: environment,
            standardInput: Data(text.utf8),
            timeout: timeout
        )
    }

    func format(_ formatter: ExternalFormatter, text: String) async -> ExternalFormatterOutcome {
        do {
            let output = try await runner.run(invocation(for: formatter, text: text))
            guard output.succeeded else {
                return .failed(Self.failureMessage(for: formatter, output: output))
            }
            return .formatted(output.standardOutputText)
        } catch {
            return .failed("\(formatter.kind.binaryName): \(error)")
        }
    }

    private static func failureMessage(for formatter: ExternalFormatter, output: ProcessOutput) -> String {
        let stderr = output.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stderr.isEmpty else { return stderr }
        return "\(formatter.kind.binaryName) exited with code \(output.exitCode)"
    }
}
