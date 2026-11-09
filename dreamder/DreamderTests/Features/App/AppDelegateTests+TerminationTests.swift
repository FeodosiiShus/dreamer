import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension AppDelegateTests {
    @Test
    func applicationPolicyHooksKeepTheAppAliveAndSkipUntitledDocuments() {
        let delegate = AppDelegate()

        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
        #expect(delegate.applicationShouldOpenUntitledFile(NSApplication.shared) == false)
        #expect(delegate.applicationSupportsSecureRestorableState(NSApplication.shared))
    }

    @Test
    func theDefaultLanguageServiceIsTheSharedInstance() {
        #expect(AppDelegate().languageService() === LSPService.shared)
    }

    @Test
    func terminationRecordsOnlyOpenWorkspacesForRecovery() async throws {
        try await withTempDir { directory in
            let first = directory.appending(path: "First", directoryHint: .isDirectory)
            let second = directory.appending(path: "Second", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let harness = try TerminationHarness()
            defer { harness.tearDown() }
            let firstWorkspace = try makeWorkspace(at: first)
            let secondWorkspace = try makeWorkspace(at: second)
            defer {
                firstWorkspace.close()
                secondWorkspace.close()
            }
            let codeFile = try makeCodeFile(in: directory)
            harness.controller.stubbedDocuments = [firstWorkspace, codeFile, WorkspaceDocument(), secondWorkspace]

            let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

            #expect(reply == .terminateLater)
            #expect(harness.defaults.stringArray(forKey: AppDelegate.recoverWorkspacesKey) == [first.path, second.path])
            try await eventually { harness.recorder.replies == [true] }
        }
    }

    @Test
    func terminationWithNoDocumentsRecordsAnEmptyRecoveryList() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        harness.defaults.set(["/stale/project"], forKey: AppDelegate.recoverWorkspacesKey)

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(harness.defaults.stringArray(forKey: AppDelegate.recoverWorkspacesKey) == [])
        try await eventually { harness.recorder.replies == [true] }
    }

    @Test
    func cleanTerminationStopsTasksThenRepliesOnceAfterLanguageServersStopped() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let workspace = WorkspaceDocument()
        let manager = RecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        let activeTask = CETask(target: "build")
        manager.activeTasks[activeTask.id] = CEActiveTask(task: activeTask)
        workspace.taskManager = manager
        harness.controller.stubbedDocuments = [workspace]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateLater)
        #expect(harness.controller.closeAllCalls == 0)
        #expect(manager.stopAllCalls == 1)
        try await eventually { harness.recorder.replies == [true] && harness.recorder.notifications.count >= 3 }
        #expect(harness.recorder.replies == [true])
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:create",
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:delete"
        ])
    }

    @Test
    func cleanTerminationWithIdleTasksDoesNotAnnounceTaskTermination() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let workspace = WorkspaceDocument()
        let manager = RecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        workspace.taskManager = manager
        harness.controller.stubbedDocuments = [workspace]

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually { harness.recorder.replies == [true] && harness.recorder.notifications.count >= 2 }
        #expect(manager.stopAllCalls == 1)
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:delete"
        ])
    }

    @Test
    func terminationWithUnsavedDocumentsClosesThemFirstAndThenRepliesOnce() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        harness.controller.stubbedDocuments = [EditedDocument()]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateLater)
        #expect(harness.controller.closeAllCalls == 1)
        try await eventually { harness.recorder.replies == [true] }
    }

    @Test
    func cancellingTheSavePromptRepliesFalseAndKeepsTheApplicationRunning() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let workspace = WorkspaceDocument()
        let manager = RecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        workspace.taskManager = manager
        harness.controller.closeAllCompletes = false
        harness.controller.stubbedDocuments = [workspace, EditedDocument()]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateLater)
        #expect(harness.controller.closeAllCalls == 1)
        #expect(manager.stopAllCalls == 0)
        #expect(harness.recorder.replies == [false])
        #expect(harness.recorder.notifications.isEmpty)
    }

    @Test
    func terminationAnnouncesAndStopsRunningLanguageServers() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let service = harness.service
        let key = LSPService.ClientKey(.swift, "/app-delegate-tests/\(UUID().uuidString)")
        service.languageClients[key] = LanguageServicesFixture.makeClient(key, pid: Int32.max)

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually { harness.recorder.replies == [true] && harness.recorder.notifications.count >= 3 }
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:create",
            "appdelegate.terminate_language_servers:delete"
        ])
        #expect(service.languageClients.isEmpty)
    }

    private final class StuckShutdownConnection: ServerConnection, Sendable {
        let eventSequence: EventSequence

        init() {
            let (sequence, _) = EventSequence.makeStream()
            eventSequence = sequence
        }

        func sendNotification(_ notif: ClientNotification) async throws {}

        func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
            if request.method == .shutdown {
                try await Task.sleep(for: .seconds(3600))
                throw CancellationError()
            }
            let data = try JSONEncoder().encode(InitializationResponse(capabilities: .init(), serverInfo: nil))
            return try JSONDecoder().decode(Response.self, from: data)
        }
    }

    @Test
    func languageServersThatNeverAnswerShutdownAreKilledWhenTheTimeoutExpires() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        harness.delegate.languageServerShutdownTimeout = .milliseconds(100)
        let service = harness.service
        let key = LSPService.ClientKey(.swift, "/app-delegate-tests/stuck/\(UUID().uuidString)")
        let instance = InitializingServer(
            server: StuckShutdownConnection(),
            initializeParamsProvider: LSPService.LanguageServerType.getInitParams(workspacePath: key.workspacePath)
        )
        _ = try await instance.initializeIfNeeded()
        service.languageClients[key] = LSPService.LanguageServerType(
            languageId: key.languageId,
            binary: LanguageServerBinary(execPath: LanguageServicesFixture.missingBinary, args: [], env: nil),
            lspInstance: instance,
            lspPid: Int32.max,
            serverCapabilities: ServerCapabilities(),
            rootPath: URL(fileURLWithPath: key.workspacePath),
            logContainer: LanguageServerLogContainer(languageID: key.languageId.rawValue)
        )

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually(timeout: .seconds(30)) {
            harness.recorder.replies == [true] && harness.recorder.notifications.count >= 3
        }
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:create",
            "appdelegate.terminate_language_servers:delete"
        ])
    }
}
