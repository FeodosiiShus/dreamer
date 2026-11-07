import Foundation

nonisolated struct ShellResult: Sendable, Equatable {
    var exitCode: Int32
    var terminatedBySignal: Bool
    var standardOutput: String
    var standardError: String

    init(
        exitCode: Int32,
        terminatedBySignal: Bool = false,
        standardOutput: String = "",
        standardError: String = ""
    ) {
        self.exitCode = exitCode
        self.terminatedBySignal = terminatedBySignal
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    var succeeded: Bool {
        exitCode == 0 && !terminatedBySignal
    }
}

nonisolated protocol ShellRunning: Sendable {
    func run(_ command: String) async throws -> ShellResult
    func runAsync(_ command: String) -> AsyncThrowingStream<String, any Error>
}
