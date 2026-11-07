import Foundation

nonisolated struct ProcessInvocation: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var workingDirectory: URL?
    var environment: [String: String]
    var standardInput: Data?
    var timeout: Duration?

    init(
        executable: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        standardInput: Data? = nil,
        timeout: Duration? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.standardInput = standardInput
        self.timeout = timeout
    }
}

nonisolated struct ProcessOutput: Sendable, Equatable {
    var exitCode: Int32
    var terminatedBySignal: Bool
    var standardOutput: Data
    var standardError: Data

    init(
        exitCode: Int32,
        terminatedBySignal: Bool = false,
        standardOutput: Data = Data(),
        standardError: Data = Data()
    ) {
        self.exitCode = exitCode
        self.terminatedBySignal = terminatedBySignal
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    var standardOutputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
    }

    var succeeded: Bool {
        exitCode == 0 && !terminatedBySignal
    }
}
