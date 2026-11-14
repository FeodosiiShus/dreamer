import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalSecondaryHoldTests {
    private func shell(_ command: String) -> ProcessSpawn {
        ProcessSpawn(
            executable: "/bin/sh",
            arguments: ["-c", command],
            environment: ["PATH=/usr/bin:/bin"],
            executableName: "sh",
            currentDirectory: nil
        )
    }

    @Test
    func aRunningShellHoldsItsTerminalAndReleasesItWhenTheShellExits() async throws {
        let view = terminalCoverageView()
        let delegate = TerminalCoverageDelegate()
        view.processDelegate = delegate

        #expect(view.secondaryHold == nil)
        #expect(view.spawn(shell("read line; echo released-$((40+2)); exit 3")))
        #expect(view.secondaryHold != nil)

        view.send(source: view, data: Array("go\n".utf8)[...])

        try await eventually(timeout: .seconds(60)) { !delegate.exits.isEmpty }
        #expect(delegate.exits == [.exited(code: 3)])
        #expect(view.secondaryHold == nil)
        try await eventually(timeout: .seconds(60)) { terminalCoverageText(view).contains("released-42") }
    }

    @Test
    func aShellThatDidNotStartHoldsNothing() {
        let view = terminalCoverageView()
        view.spawnProcess = { _, _ in }

        #expect(view.spawn(shell("true")) == false)
        #expect(view.secondaryHold == nil)
    }
}
