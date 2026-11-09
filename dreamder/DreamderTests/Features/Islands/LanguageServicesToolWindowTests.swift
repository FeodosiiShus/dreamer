import AppKit
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
enum LanguageServicesFixture {
    static let megabyte: UInt64 = 1_048_576
    static let missingBinary = "/nonexistent/dreamder-language-services-test-server"

    static func makeClient(
        _ key: LSPService.ClientKey,
        pid: pid_t = getpid(),
        serverInfo: ServerInfo? = nil,
        execPath: String = missingBinary,
        logs: [String] = []
    ) -> LSPService.LanguageServerType {
        let client = LSPService.LanguageServerType(
            languageId: key.languageId,
            binary: LanguageServerBinary(execPath: execPath, args: [], env: nil),
            lspInstance: InitializingServer(
                server: BufferingServerConnection(),
                initializeParamsProvider: LSPService.LanguageServerType.getInitParams(
                    workspacePath: key.workspacePath
                )
            ),
            lspPid: pid,
            serverCapabilities: ServerCapabilities(),
            rootPath: URL(fileURLWithPath: key.workspacePath),
            logContainer: LanguageServerLogContainer(languageID: key.languageId.rawValue)
        )
        client.serverInfo = serverInfo
        for message in logs {
            client.logContainer.appendLog(LogMessageParams(type: .info, message: message))
        }
        return client
    }

    static func isFailed(_ state: LSPService.ServerState?) -> Bool {
        if case .failed = state { return true }
        return false
    }

    static func unreachableBinary() -> LanguageServerBinary {
        LanguageServerBinary(execPath: missingBinary, args: [], env: nil)
    }
}

@MainActor
@Suite(.uiGate)
struct LanguageServicesModelTests {
    @Test
    func rowsAreScopedToTheWorkspacePath() {
        let service = LSPService()
        let mine = LSPService.ClientKey(.swift, "/lsm/rows/a")
        let theirs = LSPService.ClientKey(.python, "/lsm/rows/b")
        service.languageClients[mine] = LanguageServicesFixture.makeClient(mine)
        service.serverStates[theirs] = .failed("boom")
        let model = LanguageServicesModel(lspService: service)

        #expect(model.rows(workspacePath: "/lsm/rows/a").map(\.key) == [mine])
        #expect(model.rows(workspacePath: "/lsm/rows/b").map(\.status) == [.failed])
        #expect(model.rows(workspacePath: nil).count == 2)
        #expect(model.rows(workspacePath: "/lsm/rows/none").isEmpty)
    }

    @Test
    func logMessagesAreNilWithoutAClientAndCappedAtTheLast200() throws {
        let service = LSPService()
        let key = LSPService.ClientKey(.swift, "/lsm/logs")
        let model = LanguageServicesModel(lspService: service)
        #expect(model.logMessages(for: key) == nil)

        let logs = (0..<205).map { "m\($0)" }
        service.languageClients[key] = LanguageServicesFixture.makeClient(key, logs: logs)
        let messages = try #require(model.logMessages(for: key))
        #expect(messages.count == 200)
        #expect(messages.first == "m5")
        #expect(messages.last == "m204")
    }

    @Test
    func togglesFlipTheExpandedIdsIndependently() {
        let model = LanguageServicesModel(lspService: LSPService())
        model.toggleMessageAction("a")()
        model.toggleLogsAction("b")()
        #expect(model.expandedMessages == ["a"])
        #expect(model.expandedLogs == ["b"])

        model.toggleMessageAction("a")()
        model.toggleLogsAction("b")()
        #expect(model.expandedMessages.isEmpty)
        #expect(model.expandedLogs.isEmpty)
    }

    @Test
    func refreshMemoryRecordsRoundedFootprintsOfRunningServersOnly() throws {
        let service = LSPService()
        let alive = LSPService.ClientKey(.swift, "/lsm/memory")
        let dead = LSPService.ClientKey(.python, "/lsm/memory")
        let stopped = LSPService.ClientKey(.go, "/lsm/memory")
        service.languageClients[alive] = LanguageServicesFixture.makeClient(alive)
        service.languageClients[dead] = LanguageServicesFixture.makeClient(dead, pid: -1)
        service.languageClients[stopped] = LanguageServicesFixture.makeClient(stopped, pid: getppid())
        service.serverStates[stopped] = .stopped
        let model = LanguageServicesModel(lspService: service)

        model.refreshMemory(workspacePath: "/lsm/memory")
        let bytes = try #require(model.memory[getpid()])
        #expect(bytes > 0)
        #expect(bytes % LanguageServicesFixture.megabyte == 0)
        #expect(model.memory.count == 1)

        model.refreshMemory(workspacePath: "/lsm/memory")
        #expect(model.memory.keys.sorted() == [getpid()])
    }

    @Test
    func trackMemoryKeepsRefreshingUntilCancelled() async throws {
        let service = LSPService()
        let key = LSPService.ClientKey(.swift, "/lsm/track")
        service.languageClients[key] = LanguageServicesFixture.makeClient(key)
        let model = LanguageServicesModel(lspService: service)

        let task = Task {
            await model.trackMemory(workspacePath: "/lsm/track", every: .milliseconds(10))
        }
        try await eventually { model.memory[getpid()] != nil }
        service.languageClients.removeAll()
        try await eventually { model.memory.isEmpty }
        task.cancel()
        await task.value
    }

    @Test
    func stopShutsTheServerDownAndMarksItStopped() async {
        let service = LSPService()
        let key = LSPService.ClientKey(.swift, "/lsm/stop")
        service.languageClients[key] = LanguageServicesFixture.makeClient(key)
        service.serverStates[key] = .running
        let model = LanguageServicesModel(lspService: service)

        await model.stop(key)

        #expect(service.languageClients[key] == nil)
        #expect(service.serverStates[key] == .stopped)
    }

    @Test
    func stopOfAnUnknownServerIsSwallowed() async {
        let service = LSPService()
        let key = LSPService.ClientKey(.swift, "/lsm/stop-unknown")
        let model = LanguageServicesModel(lspService: service)

        await model.stop(key)

        #expect(service.serverStates[key] == nil)
    }

    @Test
    func stopActionRunsTheStopInATask() async throws {
        let service = LSPService()
        let key = LSPService.ClientKey(.swift, "/lsm/stop-action")
        service.languageClients[key] = LanguageServicesFixture.makeClient(key)
        service.serverStates[key] = .running
        let model = LanguageServicesModel(lspService: service)

        model.stopAction(key)()

        try await eventually { service.serverStates[key] == .stopped }
        #expect(service.languageClients[key] == nil)
    }

    @Test
    func stopAllActionStopsEveryServer() async throws {
        let service = LSPService()
        let first = LSPService.ClientKey(.swift, "/lsm/stop-all")
        let second = LSPService.ClientKey(.python, "/lsm/stop-all")
        service.languageClients[first] = LanguageServicesFixture.makeClient(first)
        service.languageClients[second] = LanguageServicesFixture.makeClient(second)
        let model = LanguageServicesModel(lspService: service)

        model.stopAllAction()()

        try await eventually { service.languageClients.isEmpty }
        #expect(service.serverStates[first] == .stopped)
        #expect(service.serverStates[second] == .stopped)
    }

    @Test
    func restartStopsTheOldServerAndRecordsAFailedStart() async throws {
        let fixture = LSPServiceFixture()
        fixture.createFailure = LSPServiceFixtureFailure.creation
        let service = fixture.makeService()
        let key = LSPService.ClientKey(.swift, "/lsm/restart")
        service.languageClients[key] = LanguageServicesFixture.makeClient(key)
        service.serverStates[key] = .running
        let model = LanguageServicesModel(lspService: service)

        await model.restart([key])

        #expect(service.languageClients[key] == nil)
        let state = try #require(service.serverStates[key])
        guard case .failed(let message) = state else {
            Issue.record("expected a failed state, got \(state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test
    func restartActionRestartsASingleServer() async throws {
        let fixture = LSPServiceFixture()
        fixture.createFailure = LSPServiceFixtureFailure.creation
        let service = fixture.makeService()
        let key = LSPService.ClientKey(.swift, "/lsm/restart-action")
        let model = LanguageServicesModel(lspService: service)

        model.restartAction(key)()

        try await eventually { LanguageServicesFixture.isFailed(service.serverStates[key]) }
    }

    @Test
    func restartAllActionRestartsEveryServerOfTheWorkspaceOnly() async throws {
        let fixture = LSPServiceFixture()
        fixture.createFailure = LSPServiceFixtureFailure.creation
        let service = fixture.makeService()
        let first = LSPService.ClientKey(.swift, "/lsm/restart-all")
        let second = LSPService.ClientKey(.python, "/lsm/restart-all")
        let foreign = LSPService.ClientKey(.go, "/lsm/restart-all-foreign")
        service.serverStates[first] = .stopped
        service.serverStates[second] = .stopped
        service.serverStates[foreign] = .stopped
        let model = LanguageServicesModel(lspService: service)

        model.restartAllAction(workspacePath: "/lsm/restart-all")()

        try await eventually {
            LanguageServicesFixture.isFailed(service.serverStates[first])
                && LanguageServicesFixture.isFailed(service.serverStates[second])
        }
        #expect(service.serverStates[foreign] == .stopped)
    }

    @Test
    func hideActionHidesTheLanguageServicesToolWindow() {
        let manager = ToolWindowManager()
        manager.show(.languageServices)
        #expect(manager.isVisible(.languageServices))

        LanguageServicesModel(lspService: LSPService()).hideAction(manager)()

        #expect(!manager.isVisible(.languageServices))
    }
}

@MainActor
@Suite(.uiGate)
struct LanguageServicesToolWindowViewTests {
    @Test
    func rendersTheEmptyStateThenEveryServerStateAndItsExpansions() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let path = try #require(workspace.fileURL).absolutePath
            let service = LSPService()
            let model = LanguageServicesModel(lspService: service)
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                LanguageServicesToolWindow(model: model, memoryInterval: .milliseconds(20))
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            let empty = hosted.snapshot()

            let failed = LSPService.ClientKey(.python, path)
            let starting = LSPService.ClientKey(.go, path)
            let stopped = LSPService.ClientKey(.rust, path)
            service.serverStates[failed] = .failed("python server crashed")
            service.serverStates[starting] = .starting
            service.serverStates[stopped] = .stopped
            try await hosted.settle(.milliseconds(100))
            let withoutRunning = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(empty, withoutRunning))

            let running = LSPService.ClientKey(.swift, path)
            service.languageClients[running] = LanguageServicesFixture.makeClient(
                running,
                serverInfo: ServerInfo(name: "SwiftServer", version: "1.2.3"),
                logs: ["first log", "second log"]
            )
            service.serverStates[running] = .running
            try await eventually { model.memory[getpid()] != nil }
            try await hosted.settle(.milliseconds(100))
            let collapsed = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(withoutRunning, collapsed))

            let rows = model.rows(workspacePath: path)
            #expect(rows.count == 4)
            for row in rows {
                model.toggleMessageAction(row.id)()
                model.toggleLogsAction(row.id)()
            }
            try await hosted.settle(.milliseconds(100))
            let expanded = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(collapsed, expanded))

            for row in rows {
                model.toggleMessageAction(row.id)()
                model.toggleLogsAction(row.id)()
            }
            service.languageClients.removeAll()
            service.serverStates.removeAll()
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
        }
    }

    @Test
    func rendersTheDefaultModelFromTheRegisteredService() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                LanguageServicesToolWindow()
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
        }
    }

    @Test
    func buttonRendersEnabledAndDisabled() async throws {
        let enabled = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            LanguageServicesButton(icon: "run/restart", title: "Restart") {}
                .background(Color.black)
        }
        defer { enabled.close() }
        let disabled = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            LanguageServicesButton(icon: "run/restart", title: "Restart") {}
                .disabled(true)
                .background(Color.black)
        }
        defer { disabled.close() }
        try await enabled.settle(.milliseconds(50))
        try await disabled.settle(.milliseconds(50))

        #expect(enabled.renders())
        #expect(disabled.renders())
        #expect(HostedView.pixelsDiffer(enabled.snapshot(), disabled.snapshot()))
    }

    @Test
    func titleFallsBackToProjectWithoutAWorkspaceFolder() {
        #expect(LanguageServicesToolWindow.projectTitle(of: nil) == "Project")
        #expect(LanguageServicesToolWindow.projectTitle(of: URL(fileURLWithPath: "/tmp/Folder")) == "Folder")
    }

    @Test
    func buttonHoverStateIsSettable() {
        let button = LanguageServicesButton(icon: "run/restart", title: "Restart") {}

        button.setHovering(true)
        button.setHovering(false)
    }

    @Test
    func memoryFootprintIsMissingForUnknownProcesses() {
        #expect(LanguageServerRowModel.memoryFootprint(pid: pid_t.max) == nil)
        #expect(LanguageServerRowModel.memoryFootprint(pid: 0) == nil)
        #expect(LanguageServerRowModel.memoryFootprint(pid: getpid()) != nil)
    }
}
