import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct TerminalToolWindowTests {
    private func makeActions(_ workspace: WorkspaceDocument) throws -> TerminalToolWindowActions {
        TerminalToolWindowActions(
            workspace: workspace,
            utilityAreaViewModel: try #require(workspace.utilityAreaModel)
        )
    }

    @Test
    func tabTitleCombinesFolderAndShellName() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let actions = try makeActions(workspace)
            let folder = URL(fileURLWithPath: "/tmp/terminal-project", isDirectory: true)

            let explicit = UtilityAreaTerminal(id: UUID(), url: folder, title: "t", shell: .bash)
            #expect(actions.tabTitle(explicit) == "terminal-project — bash")

            let detected = UtilityAreaTerminal(id: UUID(), url: folder, title: "t", shell: nil)
            let detectedName = URL(fileURLWithPath: Shell.autoDetectDefaultShell()).lastPathComponent
            #expect(actions.tabTitle(detected) == "terminal-project — \(detectedName)")

            let root = UtilityAreaTerminal(id: UUID(), url: URL(fileURLWithPath: "/"), title: "t", shell: .zsh)
            #expect(actions.tabTitle(root) == "/ — zsh")
        }
    }

    @Test
    func ensureAddsOneTerminalForTheWorkspaceAndAddAppendsAnother() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let actions = try makeActions(workspace)
            let model = actions.utilityAreaViewModel
            model.terminals.removeAll()

            actions.ensure()
            #expect(model.terminals.count == 1)
            #expect(model.terminals.first?.url == workspace.fileURL)

            actions.ensure()
            #expect(model.terminals.count == 1)

            actions.add()
            #expect(model.terminals.count == 2)
            #expect(model.selectedTerminals == [model.terminals[1].id])
        }
    }

    @Test
    func selectCloseAndTitleChangeActOnTheGivenTerminal() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let actions = try makeActions(workspace)
            let model = actions.utilityAreaViewModel
            model.terminals.removeAll()
            actions.add()
            actions.add()
            let first = model.terminals[0]
            let second = model.terminals[1]

            actions.select(first)()
            #expect(model.selectedTerminals == [first.id])

            actions.titleChange(second)("Build output")
            try await eventually { second.terminalTitle == "Build output" }
            #expect(second.title == "Build output")

            actions.close(second)()
            #expect(model.terminals.map(\.id) == [first.id])
            actions.close(first)()
            #expect(model.terminals.isEmpty)
        }
    }

    @Test
    func rendersTabsSwitchesTerminalsAndShowsPlaceholderWithoutTerminals() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let actions = try makeActions(workspace)
            let model = actions.utilityAreaViewModel
            model.terminals.removeAll()
            workspace.toolWindowManager.show(.terminal)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { TerminalToolWindow() }
            defer { hosted.close() }
            try await eventually { model.terminals.count == 1 }
            try await hosted.settle(.milliseconds(200))
            #expect(hosted.renders())
            let oneTerminal = hosted.snapshot()

            actions.add()
            try await hosted.settle(.milliseconds(200))
            let twoTerminals = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(oneTerminal, twoTerminals))

            let first = model.terminals[0]
            actions.select(first)()
            try await hosted.settle(.milliseconds(200))
            #expect(hosted.renders())

            model.selectedTerminals = [UUID()]
            try await hosted.settle(.milliseconds(200))
            #expect(hosted.renders())

            model.removeTerminals(Set(model.terminals.map(\.id)))
            model.terminals.removeAll()
            model.selectedTerminals = []
            try await hosted.settle(.milliseconds(200))
            #expect(HostedView.pixelsDiffer(twoTerminals, hosted.snapshot()))
        }
    }

    @Test
    func menuItemsListEveryTerminalAndAlwaysOfferANewOne() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let actions = try makeActions(workspace)
            let model = actions.utilityAreaViewModel
            model.terminals.removeAll()

            let empty = HostedViewFixture.host { VStack { TerminalToolWindowMenuItems(actions: actions) } }
            defer { empty.close() }
            try await empty.settle(.milliseconds(100))
            let emptySnapshot = empty.snapshot()

            actions.add()
            actions.add()
            let populated = HostedViewFixture.host { VStack { TerminalToolWindowMenuItems(actions: actions) } }
            defer { populated.close() }
            try await populated.settle(.milliseconds(100))
            #expect(HostedView.pixelsDiffer(emptySnapshot, populated.snapshot()))
        }
    }
}
