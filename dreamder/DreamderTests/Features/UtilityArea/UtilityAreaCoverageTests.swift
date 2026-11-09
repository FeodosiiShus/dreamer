import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class UtilityAreaStreamProbe {
    var received: String?
}

@MainActor
@Suite(.uiGate)
struct UtilityAreaViewModelCoverageTests {
    private func makeModel(terminalCount: Int) -> UtilityAreaViewModel {
        let model = UtilityAreaViewModel()
        for _ in 0..<terminalCount {
            model.addTerminal(rootURL: URL(filePath: "/tmp"))
        }
        return model
    }

    private func makeWorkspace() -> WorkspaceDocument {
        let workspace = WorkspaceDocument()
        workspace.fileURL = URL(filePath: "/dreamder-tests/utility-area-\(UUID().uuidString)")
        return workspace
    }

    private func forgetState(of workspace: WorkspaceDocument) {
        guard let url = workspace.fileURL else { return }
        UserDefaults.standard.removeObject(forKey: WorkspaceDocument.workspaceStateKey(for: url))
    }

    @Test
    func restoreFromStateFallsBackToDefaultsWithoutPersistedValues() {
        let workspace = makeWorkspace()
        defer { forgetState(of: workspace) }
        let model = UtilityAreaViewModel()
        model.isCollapsed = true
        model.isMaximized = true
        model.currentHeight = 10

        model.restoreFromState(workspace)

        #expect(model.isCollapsed == false)
        #expect(model.isMaximized == false)
        #expect(model.currentHeight == 300)
    }

    @Test
    func savedStateRoundTripsThroughTheWorkspace() {
        let workspace = makeWorkspace()
        defer { forgetState(of: workspace) }
        let saved = UtilityAreaViewModel()
        saved.isCollapsed = true
        saved.isMaximized = true
        saved.currentHeight = 123

        saved.saveRestorationState(workspace)
        let restored = UtilityAreaViewModel()
        restored.restoreFromState(workspace)

        #expect(restored.isCollapsed)
        #expect(restored.isMaximized)
        #expect(restored.currentHeight == 123)
    }

    @Test
    func togglePanelFlipsCollapsedClearsMaximizedAndRemembersTheAnimationFlag() {
        let model = UtilityAreaViewModel()
        model.isMaximized = true

        model.togglePanel(animation: false)

        #expect(model.isCollapsed)
        #expect(model.isMaximized == false)
        #expect(model.animateCollapse == false)

        model.togglePanel()

        #expect(model.isCollapsed == false)
        #expect(model.animateCollapse)
    }

    @Test
    func addTerminalSelectsTheNewTerminalAndUsesTheShellNameAsTitle() {
        let model = UtilityAreaViewModel()

        model.addTerminal(rootURL: nil)
        model.addTerminal(shell: .zsh, rootURL: URL(filePath: "/tmp"))

        #expect(model.terminals.count == 2)
        #expect(model.terminals[0].title == "terminal")
        #expect(model.terminals[1].title == Shell.zsh.rawValue)
        #expect(model.terminals[1].shell == .zsh)
        #expect(model.selectedTerminals == [model.terminals[1].id])
    }

    @Test
    func initializeTerminalsOnlyCreatesATerminalWhenNoneExist() {
        let model = UtilityAreaViewModel()

        model.initializeTerminals(workspaceURL: URL(filePath: "/tmp"))
        model.initializeTerminals(workspaceURL: URL(filePath: "/tmp"))

        #expect(model.terminals.count == 1)
    }

    @Test
    func removeTerminalsKeepsTheRemainingSelectionOrFallsBackToTheLastTerminal() {
        let model = makeModel(terminalCount: 4)
        let ids = model.terminals.map(\.id)
        model.selectedTerminals = [ids[0], ids[1]]

        model.removeTerminals([ids[0]])
        #expect(model.selectedTerminals == [ids[1]])
        #expect(model.terminals.count == 3)

        model.removeTerminals([ids[1]])
        #expect(model.selectedTerminals == [ids[3]])

        model.removeTerminals(Set(ids))
        #expect(model.terminals.isEmpty)
        #expect(model.selectedTerminals.isEmpty)
    }

    @Test
    func updateTerminalHonoursCustomTitlesAndIgnoresUnknownIDs() {
        let model = makeModel(terminalCount: 1)
        let terminal = model.terminals[0]

        model.updateTerminal(UUID(), title: "ignored")
        #expect(terminal.title == "terminal")

        model.updateTerminal(terminal.id, title: "first")
        #expect(terminal.title == "first")
        #expect(terminal.terminalTitle == "first")

        terminal.customTitle = true
        model.updateTerminal(terminal.id, title: "second")
        #expect(terminal.title == "first")
        #expect(terminal.terminalTitle == "second")

        model.updateTerminal(terminal.id, title: nil)
        #expect(terminal.customTitle == false)
    }

    @Test
    func replaceTerminalIgnoresUnknownIDs() {
        let model = makeModel(terminalCount: 1)
        let original = model.terminals[0].id

        model.replaceTerminal(UUID())

        #expect(model.terminals.map(\.id) == [original])
    }

    @Test
    func replaceTerminalSwapsTheTerminalAndKeepsItsDirectoryAndShell() {
        let model = UtilityAreaViewModel()
        model.addTerminal(shell: .zsh, rootURL: URL(filePath: "/tmp/replace"))
        let original = model.terminals[0]

        model.replaceTerminal(original.id)

        #expect(model.terminals.count == 1)
        #expect(model.terminals[0].id != original.id)
        #expect(model.terminals[0].url == original.url)
        #expect(model.terminals[0].shell == .zsh)
        #expect(model.selectedTerminals == [model.terminals[0].id])
    }

    @Test
    func replaceTerminalKillsTheCachedShellProcess() async throws {
        let model = UtilityAreaViewModel()
        model.addTerminal(shell: .zsh, rootURL: URL(filePath: "/tmp"))
        let id = model.terminals[0].id
        let view = CELocalShellTerminalView(frame: .zero)
        view.process.startProcess(
            executable: "/bin/sleep",
            args: ["60"],
            environment: [],
            execName: nil,
            currentDirectory: nil
        )
        try #require(view.process.shellPid > 0)
        TerminalCache.shared.cacheTerminalView(for: id, view: view)

        model.replaceTerminal(id)

        try await eventually { !view.process.running }
        #expect(TerminalCache.shared.getTerminalView(id) == nil)
    }

    private func startShellWithBackgroundChild(in view: CELocalShellTerminalView) async throws -> pid_t {
        view.process.startProcess(
            executable: "/bin/zsh",
            args: ["-f", "-i", "-c", "sleep 600 & echo child-pid-$!-end; wait"],
            environment: nil,
            execName: "zsh",
            currentDirectory: nil
        )
        try await eventually { TasksCoverageProcessProbe.announcedPID(in: terminalCoverageText(view)) != nil }
        return try #require(TasksCoverageProcessProbe.announcedPID(in: terminalCoverageText(view)))
    }

    @Test
    func removingATerminalKillsTheShellAndEverythingItStarted() async throws {
        let model = UtilityAreaViewModel()
        model.addTerminal(shell: .zsh, rootURL: URL(filePath: "/tmp"))
        let id = model.terminals[0].id
        let view = CELocalShellTerminalView(frame: .zero)
        view.terminationEscalationDelay = .milliseconds(20)
        let child = try await startShellWithBackgroundChild(in: view)
        defer { kill(child, SIGKILL) }
        TerminalCache.shared.cacheTerminalView(for: id, view: view)

        model.removeTerminals([id])

        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !view.process.running }
        #expect(TerminalCache.shared.getTerminalView(id) == nil)
    }

    @Test
    func replacingATerminalKillsTheShellAndEverythingItStarted() async throws {
        let model = UtilityAreaViewModel()
        model.addTerminal(shell: .zsh, rootURL: URL(filePath: "/tmp"))
        let id = model.terminals[0].id
        let view = CELocalShellTerminalView(frame: .zero)
        let child = try await startShellWithBackgroundChild(in: view)
        defer { kill(child, SIGKILL) }
        TerminalCache.shared.cacheTerminalView(for: id, view: view)

        model.replaceTerminal(id)

        try await eventually { TasksCoverageProcessProbe.isGone(child) }
        try await eventually { !view.process.running }
    }

    @Test
    func replaceTerminalNeverSignalsAShellThatNeverStarted() {
        let model = UtilityAreaViewModel()
        model.addTerminal(shell: .zsh, rootURL: URL(filePath: "/tmp"))
        let original = model.terminals[0]
        let view = CELocalShellTerminalView(frame: .zero)
        #expect(view.process.shellPid <= 0)
        TerminalCache.shared.cacheTerminalView(for: original.id, view: view)

        model.replaceTerminal(original.id)

        #expect(model.terminals.count == 1)
        #expect(model.terminals[0].id != original.id)
        #expect(TerminalCache.shared.getTerminalView(original.id) == nil)
    }

    @Test
    func reorderTerminalsMovesTheSourceRows() {
        let model = makeModel(terminalCount: 3)
        let ids = model.terminals.map(\.id)

        model.reorderTerminals(from: IndexSet(integer: 0), to: 3)

        #expect(model.terminals.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    @Test
    func terminalsCompareByIdentity() {
        let id = UUID()
        let first = UtilityAreaTerminal(id: id, url: URL(filePath: "/a"), title: "a", shell: nil)
        let second = UtilityAreaTerminal(id: id, url: URL(filePath: "/b"), title: "b", shell: .zsh)
        let other = UtilityAreaTerminal(id: UUID(), url: URL(filePath: "/a"), title: "a", shell: nil)

        #expect(first == second)
        #expect(first != other)
        #expect(first.terminalTitle == "a")
        #expect(first.customTitle == false)
    }
}

@MainActor
@Suite(.uiGate)
struct UtilityAreaLogModelCoverageTests {
    @Test
    func everyLogLevelHasAnIconColorAndBackground() {
        #expect(UtilityAreaLogLevel.error.iconName == "exclamationmark.3")
        #expect(UtilityAreaLogLevel.warning.iconName == "exclamationmark.2")
        #expect(UtilityAreaLogLevel.info.iconName == "info")
        #expect(UtilityAreaLogLevel.debug.iconName == "stethoscope")

        #expect(UtilityAreaLogLevel.error.color == Color(red: 202.0 / 255.0, green: 27.0 / 255.0, blue: 0))
        #expect(UtilityAreaLogLevel.warning.color == Color(red: 1, green: 186.0 / 255.0, blue: 0))
        #expect(UtilityAreaLogLevel.info.color == .cyan)
        #expect(UtilityAreaLogLevel.debug.color != UtilityAreaLogLevel.info.color)

        #expect(UtilityAreaLogLevel.error.backgroundColor == UtilityAreaLogLevel.error.color.opacity(0.1))
        #expect(UtilityAreaLogLevel.warning.backgroundColor == UtilityAreaLogLevel.warning.color.opacity(0.2))
        #expect(UtilityAreaLogLevel.info.backgroundColor == .clear)
        #expect(UtilityAreaLogLevel.debug.backgroundColor == .clear)
    }

    @Test
    func languageServerMessagesMapTheLogTypeToALevel() {
        func level(_ type: MessageType) -> UtilityAreaLogLevel {
            LanguageServerLogContainer.LanguageServerMessage(log: LogMessageParams(type: type, message: "m")).level
        }

        #expect(level(.error) == .error)
        #expect(level(.warning) == .warning)
        #expect(level(.info) == .info)
        #expect(level(.log) == .debug)
        #expect(
            LanguageServerLogContainer.LanguageServerMessage(log: LogMessageParams(type: .info, message: "text"))
                .message == "text"
        )
    }

    @Test
    func appendedLogsAreCachedInOrder() {
        let container = LanguageServerLogContainer(languageID: "swift")

        #expect(container.id == "swift")
        #expect(container.cachedMessages().isEmpty)

        container.appendLog(LogMessageParams(type: .error, message: "first"))
        container.appendLog(LogMessageParams(type: .log, message: "second"))

        #expect(container.cachedMessages().map(\.message) == ["first", "second"])
        #expect(container.logs.count == 2)
    }

    @Test
    func streamDeliversLogsToAWaitingConsumer() async throws {
        let container = LanguageServerLogContainer(languageID: "streaming")
        let probe = UtilityAreaStreamProbe()
        let consumer = Task { @MainActor in
            for await message in container.streamMessages() {
                probe.received = message.message
                break
            }
        }
        defer { consumer.cancel() }

        try await eventually {
            container.appendLog(LogMessageParams(type: .info, message: "hello"))
            return probe.received != nil
        }

        #expect(probe.received == "hello")
    }
}
