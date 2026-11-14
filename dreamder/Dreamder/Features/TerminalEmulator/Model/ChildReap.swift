import Darwin

nonisolated enum ChildReap: Sendable, Equatable {
    case exited(waitStatus: Int32)
    case pending
    case unavailable

    static func nonBlocking(_ processIdentifier: pid_t) -> ChildReap {
        var status: Int32 = 0
        let reaped = waitpid(processIdentifier, &status, WNOHANG)
        if reaped == processIdentifier {
            return .exited(waitStatus: status)
        }
        return reaped == 0 ? .pending : .unavailable
    }
}
