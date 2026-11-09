import Foundation
import Testing
@testable import Dreamder

struct ProcessExitTests {
    @Test(arguments: [Int32(0), 3, 130, 255])
    func aZeroSignalFieldDecodesTheExitCodeFromTheHighByte(_ code: Int32) {
        #expect(ProcessExit(waitStatus: code << 8) == .exited(code: code))
    }

    @Test(arguments: [Int32(2), 9, 15])
    func aNonZeroSignalFieldDecodesTheTerminatingSignal(_ signal: Int32) {
        #expect(ProcessExit(waitStatus: signal) == .signaled(signal: signal))
    }

    @Test
    func theCoreDumpFlagDoesNotChangeTheSignal() {
        #expect(ProcessExit(waitStatus: 11 | 0x80) == .signaled(signal: 11))
    }

    @Test
    func theRawStatusOfAnExitIsNeverTakenForAnExitCode() {
        #expect(ProcessExit(waitStatus: 3 << 8) != .exited(code: 768))
        #expect(ProcessExit(waitStatus: 130 << 8) != .signaled(signal: 2))
    }

    @Test
    func summariesNameTheExitCodeOrTheSignal() {
        #expect(ProcessExit.exited(code: 3).summary == "Exit code: 3")
        #expect(ProcessExit.signaled(signal: 15).summary == "Terminated by signal 15")
    }
}
