import Darwin
import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated private enum PrimaryRead: Equatable {
    case bytes(Int)
    case endOfFile
    case wouldBlock
    case failed(Int32)
}

nonisolated private func readPrimary(_ primary: Int32, into buffer: inout [UInt8]) -> PrimaryRead {
    var chunk = [UInt8](repeating: 0, count: 4096)
    let received = read(primary, &chunk, chunk.count)
    if received > 0 {
        buffer.append(contentsOf: chunk[0..<received])
        return .bytes(received)
    }
    if received == 0 {
        return .endOfFile
    }
    return errno == EAGAIN ? .wouldBlock : .failed(errno)
}

nonisolated private final class OpenRequests: Sendable {
    private let recorded = Mutex<[String]>([])

    func record(_ request: String) {
        recorded.withLock { $0.append(request) }
    }

    var values: [String] {
        recorded.withLock { $0 }
    }
}

nonisolated private func makeNonBlockingPrimary() throws -> Int32 {
    let primary = posix_openpt(O_RDWR | O_NOCTTY)
    try #require(primary >= 0)
    try #require(grantpt(primary) == 0)
    try #require(unlockpt(primary) == 0)
    try #require(fcntl(primary, F_SETFL, fcntl(primary, F_GETFL) | O_NONBLOCK) == 0)
    return primary
}

nonisolated private struct ShellOnPty {
    let processIdentifier: pid_t
    let primary: Int32

    static func start(command: String) throws -> ShellOnPty {
        let executable = strdup("/bin/sh")
        let arguments = [strdup("sh"), strdup("-c"), strdup(command), nil]
        let environment = [strdup("PATH=/usr/bin:/bin"), nil]
        defer {
            free(executable)
            arguments.forEach { free($0) }
            environment.forEach { free($0) }
        }
        var primary: Int32 = -1
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let processIdentifier = arguments.withUnsafeBufferPointer { argv -> pid_t in
            environment.withUnsafeBufferPointer { envp -> pid_t in
                let child = forkpty(&primary, nil, nil, &size)
                if child == 0 {
                    execve(executable, argv.baseAddress, envp.baseAddress)
                    _exit(111)
                }
                return child
            }
        }
        try #require(processIdentifier > 0)
        try #require(fcntl(primary, F_SETFL, fcntl(primary, F_GETFL) | O_NONBLOCK) == 0)
        return ShellOnPty(processIdentifier: processIdentifier, primary: primary)
    }

    func readUntilEndOfFile(timeout: Duration) async throws -> String {
        var received: [UInt8] = []
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            switch readPrimary(primary, into: &received) {
            case .bytes:
                continue
            case .wouldBlock:
                try await Task.sleep(for: .milliseconds(10))
            case .endOfFile, .failed:
                return String(bytes: received, encoding: .utf8) ?? ""
            }
        }
        return String(bytes: received, encoding: .utf8) ?? ""
    }

    func sendLine() {
        _ = "go\n".withCString { write(primary, $0, 3) }
    }

    func reap(timeout: Duration) async throws -> ChildReap {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var result = ChildReap.nonBlocking(processIdentifier)
        while result == .pending, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            result = ChildReap.nonBlocking(processIdentifier)
        }
        return result
    }
}

struct PtySecondaryHoldTests {
    @Test
    func aHoldKeepsTheTerminalConnectedUntilItIsReleased() async throws {
        let primary = try makeNonBlockingPrimary()
        defer { close(primary) }
        var unused: [UInt8] = []

        var hold = PtySecondaryHold(primary: primary)
        #expect(hold != nil)
        let whileHeld = readPrimary(primary, into: &unused)
        #expect(whileHeld == .wouldBlock)

        hold = nil
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        var afterRelease = readPrimary(primary, into: &unused)
        while afterRelease == .wouldBlock, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            afterRelease = readPrimary(primary, into: &unused)
        }
        #expect(afterRelease == .endOfFile)
    }

    @Test
    func theHeldDescriptorIsClosedOnExecSoChildrenDoNotInheritIt() throws {
        let primary = try makeNonBlockingPrimary()
        defer { close(primary) }

        let hold = try #require(PtySecondaryHold(primary: primary))

        #expect(fcntl(hold.descriptor, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
        #expect(fcntl(hold.descriptor, F_GETFL) & O_ACCMODE == O_RDWR)
    }

    @Test
    func aDescriptorThatIsNotATerminalPrimaryCannotBeHeld() throws {
        let file = open("/dev/null", O_RDONLY)
        try #require(file >= 0)
        defer { close(file) }

        #expect(PtySecondaryHold(primary: -1) == nil)
        #expect(PtySecondaryHold(primary: file) == nil)
    }

    @Test
    func aSecondaryThatCannotBeOpenedLeavesNoHold() throws {
        let primary = try makeNonBlockingPrimary()
        defer { close(primary) }
        let requests = OpenRequests()
        var unused: [UInt8] = []

        let hold = PtySecondaryHold(primary: primary) { path, flags in
            requests.record("\(String(cString: path)) \(flags)")
            return -1
        }

        #expect(hold == nil)
        let recorded = requests.values
        #expect(recorded.count == 1)
        #expect(recorded.first?.hasPrefix("/dev/ttys") == true)
        #expect(recorded.first?.hasSuffix(" \(O_RDWR | O_NOCTTY | O_CLOEXEC)") == true)
        let afterFailure = readPrimary(primary, into: &unused)
        #expect(afterFailure == .wouldBlock)
    }

    @Test
    func outputOfAShellThatAlreadyExitedSurvivesAReaderThatComesLate() async throws {
        let shell = try ShellOnPty.start(command: "read line; echo held-$((40+2))")
        defer { close(shell.primary) }
        let hold = PtySecondaryHold(primary: shell.primary)
        #expect(hold != nil)
        shell.sendLine()

        try await Task.sleep(for: .milliseconds(1500))
        let output = try await shell.readUntilEndOfFile(timeout: .seconds(60))
        let exit = try await shell.reap(timeout: .seconds(60))

        #expect(output.contains("held-42"))
        #expect(exit == .exited(waitStatus: 0))
        withExtendedLifetime(hold) {}
    }

    @Test
    func aShellKilledBeforeItsOutputWasReadStillDeliversIt() async throws {
        let shell = try ShellOnPty.start(command: "read line; echo killed-$((40+2)); sleep 600")
        defer { close(shell.primary) }
        let hold = PtySecondaryHold(primary: shell.primary)
        #expect(hold != nil)
        shell.sendLine()

        try await Task.sleep(for: .milliseconds(500))
        kill(shell.processIdentifier, SIGKILL)
        try await Task.sleep(for: .milliseconds(1000))
        let output = try await shell.readUntilEndOfFile(timeout: .seconds(60))
        let exit = try await shell.reap(timeout: .seconds(60))

        #expect(output.contains("killed-42"))
        #expect(exit == .exited(waitStatus: SIGKILL))
        withExtendedLifetime(hold) {}
    }
}
