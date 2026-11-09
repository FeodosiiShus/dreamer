import Foundation
import os

nonisolated final class MainThreadStallSampler: Sendable {
    static let environmentKey = "DREAMDER_STALL_SAMPLE_DIR"
    static let samplerExecutable = URL(fileURLWithPath: "/usr/bin/sample")

    private struct State {
        var lastBeat: ContinuousClock.Instant = .now
        var monitor: Task<Void, Never>?
        var samples: [URL] = []
    }

    private let directory: URL
    private let threshold: Duration
    private let interval: Duration
    private let executable: URL
    private let runner: ProcessRunner
    private let state = OSAllocatedUnfairLock(initialState: State())

    typealias Heartbeat = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let heartbeat: Heartbeat

    static let mainActorHeartbeat: Heartbeat = { beat in
        Task { @MainActor in beat() }
    }

    init(
        directory: URL,
        threshold: Duration = .seconds(3),
        interval: Duration = .milliseconds(250),
        executable: URL = MainThreadStallSampler.samplerExecutable,
        runner: ProcessRunner = ProcessRunner(slots: ProcessSlotPool(limit: 1)),
        heartbeat: @escaping Heartbeat = MainThreadStallSampler.mainActorHeartbeat
    ) {
        self.directory = directory
        self.threshold = threshold
        self.interval = interval
        self.executable = executable
        self.runner = runner
        self.heartbeat = heartbeat
    }

    static func installFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MainThreadStallSampler? {
        guard let path = environment[environmentKey], !path.isEmpty else { return nil }
        let sampler = MainThreadStallSampler(directory: URL(fileURLWithPath: path, isDirectory: true))
        sampler.start()
        return sampler
    }

    var recordedSamples: [URL] {
        state.withLock { $0.samples }
    }

    func start() {
        state.withLock { current in
            guard current.monitor == nil else { return }
            current.lastBeat = .now
            current.monitor = Task(priority: .utility) { [self] in
                await monitor()
            }
        }
    }

    func stop() {
        state.withLock { current in
            current.monitor?.cancel()
            current.monitor = nil
        }
    }

    @concurrent
    private func monitor() async {
        var reported = false
        while !Task.isCancelled {
            heartbeat { [state] in
                state.withLock { $0.lastBeat = .now }
            }
            try? await Task.sleep(for: interval)
            let age = ContinuousClock.now - state.withLock { $0.lastBeat }
            if age > threshold {
                if !reported {
                    reported = true
                    await sample(after: age)
                }
            } else {
                reported = false
            }
        }
    }

    private func sample(after age: Duration) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let milliseconds = age.components.seconds * 1000 + age.components.attoseconds / 1_000_000_000_000_000
        let stamp = Int(Date().timeIntervalSince1970)
        let file = directory.appendingPathComponent("stall-\(stamp)-\(milliseconds)ms.txt")
        let invocation = ProcessInvocation(
            executable: executable,
            arguments: [
                String(ProcessInfo.processInfo.processIdentifier),
                "1",
                "-mayDie",
                "-file",
                file.path
            ],
            timeout: .seconds(60)
        )
        let output = try? await runner.run(invocation)
        if output?.succeeded != true, let output {
            try? output.standardErrorText.write(to: file, atomically: true, encoding: .utf8)
        }
        state.withLock { $0.samples.append(file) }
    }
}
