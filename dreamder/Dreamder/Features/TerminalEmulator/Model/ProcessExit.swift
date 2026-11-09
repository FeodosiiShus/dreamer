import Foundation

nonisolated enum ProcessExit: Equatable, Sendable {
    case exited(code: Int32)
    case signaled(signal: Int32)

    private static let signalMask: Int32 = 0x7f
    private static let exitCodeShift: Int32 = 8
    private static let exitCodeMask: Int32 = 0xff

    init(waitStatus: Int32) {
        let terminatingSignal = waitStatus & Self.signalMask
        if terminatingSignal == 0 {
            self = .exited(code: (waitStatus >> Self.exitCodeShift) & Self.exitCodeMask)
        } else {
            self = .signaled(signal: terminatingSignal)
        }
    }

    var summary: String {
        switch self {
        case .exited(let code):
            "Exit code: \(code)"
        case .signaled(let signal):
            "Terminated by signal \(signal)"
        }
    }
}
