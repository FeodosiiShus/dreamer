import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalExitReportTests {
    private struct ShellTab {
        let id: UUID
        let view: CELocalShellTerminalView
        let coordinator: TerminalEmulatorView.Coordinator
    }

    private func makeShellTab() -> ShellTab {
        let id = UUID()
        let view = terminalCoverageView()
        TerminalCache.shared.cacheTerminalView(for: id, view: view)
        let coordinator = TerminalEmulatorView.Coordinator(
            terminalID: id,
            mode: .shell(shellType: .zsh)
        ) { _ in }
        view.processDelegate = coordinator
        return ShellTab(id: id, view: view, coordinator: coordinator)
    }

    @Test
    func shellTabsPrintTheDecodedExitInsteadOfTheRawWaitStatus() {
        let tab = makeShellTab()
        defer { TerminalCache.shared.removeCachedView(tab.id) }

        tab.view.processTerminated(tab.view.process, exitCode: 3 << 8)

        let text = terminalCoverageText(tab.view)
        #expect(text.contains("Exit code: 3"))
        #expect(!text.contains("768"))
        withExtendedLifetime(tab.coordinator) {}
    }

    @Test
    func shellTabsNameTheSignalThatKilledTheShell() {
        let tab = makeShellTab()
        defer { TerminalCache.shared.removeCachedView(tab.id) }

        tab.view.processTerminated(tab.view.process, exitCode: 15)

        #expect(terminalCoverageText(tab.view).contains("Terminated by signal 15"))
        #expect(TerminalCache.shared.getTerminalView(tab.id) == nil)
        withExtendedLifetime(tab.coordinator) {}
    }
}
