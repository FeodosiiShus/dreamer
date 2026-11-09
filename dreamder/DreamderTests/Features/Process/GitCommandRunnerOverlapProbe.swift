import Foundation
import Synchronization
@testable import Dreamder

nonisolated final class OverlapProbe: ProcessRunning, Sendable {
    private struct State {
        var active = 0
        var maximum = 0
        var completed = 0
    }

    private let state = Mutex(State())
    private let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    var maximumConcurrency: Int {
        state.withLock { $0.maximum }
    }

    var completedRuns: Int {
        state.withLock { $0.completed }
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        state.withLock { state in
            state.active += 1
            state.maximum = max(state.maximum, state.active)
        }
        try await Task.sleep(for: delay)
        state.withLock { state in
            state.active -= 1
            state.completed += 1
        }
        return FakeProcessRunner.output("")
    }
}

nonisolated final class GatedProbe: ProcessRunning, Sendable {
    private let completed = Mutex(0)
    private let startContinuation: AsyncStream<Void>.Continuation
    private let releaseContinuation: AsyncStream<Void>.Continuation
    private let releaseGate: AsyncStream<Void>
    let starts: AsyncStream<Void>

    init() {
        let started = AsyncStream<Void>.makeStream()
        starts = started.stream
        startContinuation = started.continuation
        let release = AsyncStream<Void>.makeStream()
        releaseGate = release.stream
        releaseContinuation = release.continuation
    }

    var completedRuns: Int {
        completed.withLock { $0 }
    }

    func release() {
        releaseContinuation.finish()
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        startContinuation.yield()
        for await _ in releaseGate {}
        completed.withLock { $0 += 1 }
        return FakeProcessRunner.output("")
    }
}
