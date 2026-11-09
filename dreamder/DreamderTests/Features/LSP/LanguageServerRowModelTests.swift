import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerRowModelTests {
    @Test
    func statesWithoutClientsMapToStatusesAndMessages() {
        let starting = LSPService.ClientKey(.swift, "/p")
        let failed = LSPService.ClientKey(.python, "/p")
        let stopped = LSPService.ClientKey(.go, "/p")
        let otherWorkspace = LSPService.ClientKey(.rust, "/other")
        let rows = LanguageServerRowModel.rows(
            states: [
                starting: .starting,
                failed: .failed("binary crashed"),
                stopped: .stopped,
                otherWorkspace: .running
            ],
            clients: [:],
            workspacePath: "/p"
        )
        #expect(rows.map(\.key.languageId) == [.go, .python, .swift])
        #expect(rows.map(\.status) == [.stopped, .failed, .starting])
        #expect(rows.first { $0.key == failed }?.message == "binary crashed")
        #expect(rows.allSatisfy { !$0.canStop })
    }

    @Test
    func runningStateWithoutClientIsShownAsStopped() {
        let key = LSPService.ClientKey(.swift, "/p")
        let rows = LanguageServerRowModel.rows(states: [key: .running], clients: [:], workspacePath: nil)
        #expect(rows.map(\.status) == [.stopped])
    }

    @Test
    func memoryFootprintOfThisProcessIsPositive() throws {
        let bytes = try #require(LanguageServerRowModel.memoryFootprint(pid: getpid()))
        #expect(bytes > 0)
        #expect(LanguageServerRowModel.memoryFootprint(pid: -1) == nil)
    }
}
