import Darwin
import Foundation
import Testing
@testable import Dreamder

nonisolated private func spawnChild(_ executable: String, _ arguments: [String]) throws -> pid_t {
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    let envp = [strdup("PATH=/usr/bin:/bin"), nil]
    defer {
        argv.forEach { free($0) }
        envp.forEach { free($0) }
    }
    var processIdentifier: pid_t = 0
    try #require(posix_spawn(&processIdentifier, executable, nil, nil, argv, envp) == 0)
    return processIdentifier
}

nonisolated private func reapEventually(_ processIdentifier: pid_t) async throws -> ChildReap {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(60))
    var result = ChildReap.nonBlocking(processIdentifier)
    while result == .pending, clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
        result = ChildReap.nonBlocking(processIdentifier)
    }
    return result
}

struct ChildReapTests {
    @Test
    func aRunningChildIsPendingAndKeepsItsStatusForLater() async throws {
        let child = try spawnChild("/bin/sleep", ["600"])

        #expect(ChildReap.nonBlocking(child) == .pending)

        kill(child, SIGKILL)
        let reaped = try await reapEventually(child)
        #expect(reaped == .exited(waitStatus: SIGKILL))
    }

    @Test
    func anExitedChildIsReapedOnceWithItsWaitStatus() async throws {
        let child = try spawnChild("/bin/sh", ["-c", "exit 7"])

        let reaped = try await reapEventually(child)
        #expect(reaped == .exited(waitStatus: 7 << 8))
        #expect(ChildReap.nonBlocking(child) == .unavailable)
    }

    @Test
    func aProcessThatIsNotAChildIsUnavailable() {
        #expect(ChildReap.nonBlocking(1) == .unavailable)
    }
}
