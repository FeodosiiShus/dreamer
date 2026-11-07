import Foundation
import Synchronization
@testable import Dreamder

nonisolated final class FakeProcessRunner: ProcessRunning, Sendable {
    typealias Handler = @Sendable (ProcessInvocation) throws -> ProcessOutput

    private let handler: Handler
    private let recorded = Mutex<[ProcessInvocation]>([])

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var invocations: [ProcessInvocation] {
        recorded.withLock { $0 }
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        recorded.withLock { $0.append(invocation) }
        return try handler(invocation)
    }

    static func output(_ stdout: String, stderr: String = "", exitCode: Int32 = 0) -> ProcessOutput {
        ProcessOutput(
            exitCode: exitCode,
            terminatedBySignal: false,
            standardOutput: Data(stdout.utf8),
            standardError: Data(stderr.utf8)
        )
    }
}
