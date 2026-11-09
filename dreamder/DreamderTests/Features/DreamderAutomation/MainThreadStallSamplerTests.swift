import Foundation
import os
import Testing
@testable import Dreamder

@Suite(.serialized)
struct MainThreadStallSamplerTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stall-sampler-\(UUID().uuidString)", isDirectory: true)
    }

    @Test
    func nothingIsInstalledWithoutTheEnvironmentVariable() {
        #expect(MainThreadStallSampler.installFromEnvironment([:]) == nil)
        #expect(MainThreadStallSampler.installFromEnvironment([MainThreadStallSampler.environmentKey: ""]) == nil)
    }

    @Test
    func theEnvironmentVariableInstallsARunningSampler() throws {
        let directory = temporaryDirectory()
        let sampler = try #require(
            MainThreadStallSampler.installFromEnvironment([MainThreadStallSampler.environmentKey: directory.path])
        )
        sampler.stop()
        #expect(sampler.recordedSamples.isEmpty)
    }

    private final class MainThreadBeats: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (count: 0, allOnMainThread: true))

        func record() {
            let onMainThread = Thread.isMainThread
            state.withLock {
                $0.count += 1
                $0.allOnMainThread = $0.allOnMainThread && onMainThread
            }
        }

        var snapshot: (count: Int, allOnMainThread: Bool) {
            state.withLock { $0 }
        }
    }

    @Test
    func theDefaultHeartbeatRunsEveryBeatOnTheMainThread() async throws {
        let beats = MainThreadBeats()

        MainThreadStallSampler.mainActorHeartbeat { beats.record() }
        MainThreadStallSampler.mainActorHeartbeat { beats.record() }

        for _ in 0..<400 where beats.snapshot.count < 2 {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(beats.snapshot.count == 2)
        #expect(beats.snapshot.allOnMainThread)
    }

    private final class HeartbeatSwitch: Sendable {
        private struct State {
            var delivering = true
            var delivered = 0
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        var deliveredCount: Int {
            state.withLock { $0.delivered }
        }

        func set(_ delivers: Bool) {
            state.withLock { $0.delivering = delivers }
        }

        func deliver(_ beat: @escaping @Sendable () -> Void) {
            let delivers = state.withLock { state in
                if state.delivering {
                    state.delivered += 1
                }
                return state.delivering
            }
            if delivers {
                beat()
            }
        }
    }

    private func makeSampler(
        in directory: URL,
        executable: String,
        heartbeat: HeartbeatSwitch
    ) -> MainThreadStallSampler {
        MainThreadStallSampler(
            directory: directory,
            threshold: .milliseconds(400),
            interval: .milliseconds(10),
            executable: URL(fileURLWithPath: executable),
            heartbeat: { heartbeat.deliver($0) }
        )
    }

    private func waitForSamples(_ sampler: MainThreadStallSampler, count: Int) async throws {
        for _ in 0..<1200 where sampler.recordedSamples.count < count {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForDeliveredBeats(_ heartbeat: HeartbeatSwitch, after baseline: Int, count: Int) async throws {
        for _ in 0..<1200 where heartbeat.deliveredCount < baseline + count {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test
    func aStalledHeartbeatIsSampledOncePerStallAndTheFailureOutputIsKept() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let heartbeat = HeartbeatSwitch()
        let sampler = makeSampler(in: directory, executable: "/usr/bin/false", heartbeat: heartbeat)
        sampler.start()
        sampler.start()
        defer { sampler.stop() }

        heartbeat.set(false)
        try await waitForSamples(sampler, count: 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(sampler.recordedSamples.count == 1)

        let baseline = heartbeat.deliveredCount
        heartbeat.set(true)
        try await waitForDeliveredBeats(heartbeat, after: baseline, count: 5)
        heartbeat.set(false)
        try await waitForSamples(sampler, count: 2)

        let samples = sampler.recordedSamples
        #expect(samples.count == 2)
        let file = try #require(samples.first)
        #expect(file.lastPathComponent.hasPrefix("stall-"))
        #expect(file.lastPathComponent.hasSuffix("ms.txt"))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func aSuccessfulSamplerRunLeavesItsOwnOutputInPlace() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let heartbeat = HeartbeatSwitch()
        let sampler = makeSampler(in: directory, executable: "/usr/bin/true", heartbeat: heartbeat)
        sampler.start()
        defer { sampler.stop() }

        heartbeat.set(false)
        try await waitForSamples(sampler, count: 1)

        let file = try #require(sampler.recordedSamples.first)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }
}
