import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPService work done progress", .uiGate)
struct LSPServiceWorkDoneProgressTests {
    typealias Created = LSPServiceFixture.CreatedServer
    typealias Posted = LSPServiceFixture.PostedTask

    let fixture = LSPServiceFixture()

    private func running(
        _ body: (LSPService, LSPServiceWorkspace, LSPService.ClientKey, Created) async throws -> Void
    ) async throws {
        try await withTempDir { directory in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: directory, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            _ = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let created = try #require(fixture.created.first)
            try await body(service, workspace, workspace.key(.typescript), created)
        }
    }

    private func progressEvent(_ token: ProgressToken, _ value: LSPAny) -> ServerEvent {
        .notification(.protocolProgress(ProgressParams(token: token, value: value)))
    }

    private func beginTwoProgresses(_ created: Created, key: LSPService.ClientKey) async throws -> Set<String> {
        let first = ProgressToken.optionA(1)
        let second = ProgressToken.optionB("two")
        created.connection.emit(progressEvent(first, ["kind": "begin", "title": "One"]))
        created.connection.emit(progressEvent(second, ["kind": "begin", "title": "Two"]))
        try await eventually(timeout: .seconds(30)) { fixture.postedTasks.count == 2 }
        return [
            LSPService.workDoneProgressTaskID(for: first, key: key),
            LSPService.workDoneProgressTaskID(for: second, key: key)
        ]
    }

    private func deletedTaskIDs() -> Set<String> {
        Set(fixture.postedTasks.filter { $0.action == .delete }.map(\.model.id))
    }

    @Test func beginReportAndEndBecomeCreateUpdateAndDeleteForTheWorkspace() async throws {
        try await running { _, workspace, key, created in
            let token = ProgressToken.optionB("indexing")
            let id = LSPService.workDoneProgressTaskID(for: token, key: key)
            let url = try #require(workspace.workspace.fileURL)
            let begin: LSPAny = ["kind": "begin", "title": "Indexing", "message": "starting", "percentage": 10]
            let report: LSPAny = ["kind": "report", "message": "3/10", "percentage": 30]

            created.connection.emit(progressEvent(token, begin))
            created.connection.emit(progressEvent(token, report))
            created.connection.emit(progressEvent(token, ["kind": "end"]))
            try await eventually(timeout: .seconds(30)) { fixture.postedTasks.count == 3 }

            #expect(fixture.postedTasks == [
                Posted(
                    workspaceURL: url,
                    action: .create,
                    model: TaskNotificationModel(
                        id: id, title: "Indexing", message: "starting", percentage: 0.1, isLoading: true
                    )
                ),
                Posted(
                    workspaceURL: url,
                    action: .update,
                    model: TaskNotificationModel(
                        id: id, title: "Indexing", message: "3/10", percentage: 0.3, isLoading: true
                    )
                ),
                Posted(
                    workspaceURL: url,
                    action: .delete,
                    model: TaskNotificationModel(id: id, title: "", message: nil, percentage: nil, isLoading: true)
                )
            ])
        }
    }

    @Test func ignoredProgressEventsPostNothingAndTokensOfDifferentTypesStayDistinct() async throws {
        try await running { _, _, key, created in
            created.connection.emit(progressEvent(.optionA(9), ["kind": "report", "message": "orphan"]))
            created.connection.emit(progressEvent(.optionA(9), ["kind": "end"]))
            created.connection.emit(progressEvent(.optionA(1), ["kind": "begin", "title": "Number"]))
            created.connection.emit(progressEvent(.optionB("1"), ["kind": "begin", "title": "Text"]))
            try await eventually(timeout: .seconds(30)) { fixture.postedTasks.count == 2 }

            let ids = fixture.postedTasks.map(\.model.id)
            #expect(ids == [
                LSPService.workDoneProgressTaskID(for: .optionA(1), key: key),
                LSPService.workDoneProgressTaskID(for: .optionB("1"), key: key)
            ])
            #expect(Set(ids).count == 2)
            #expect(fixture.postedTasks.map(\.model.title) == ["Number", "Text"])
        }
    }

    @Test func progressOfAWorkspaceThatIsNotOpenPostsNothing() async throws {
        try await running { service, _, _, created in
            let token = ProgressToken.optionA(5)
            created.server.workDoneProgress.apply(ProgressParams(token: token, value: ["kind": "begin", "title": "Lost"]))
            let closed = LSPService.ClientKey(.typescript, "/no/such/workspace")

            service.publishWorkDoneProgress(.began, for: token, client: created.server, key: closed)
            service.discardWorkDoneProgress(of: created.server, key: closed)

            #expect(fixture.postedTasks.isEmpty)
            #expect(created.server.workDoneProgress.isShutDown)
        }
    }

    @Test func stoppingAServerDeletesItsRunningProgress() async throws {
        try await running { service, workspace, key, created in
            let ids = try await beginTwoProgresses(created, key: key)

            try await service.stopServer(forLanguage: .typescript, workspacePath: workspace.path)

            #expect(deletedTaskIDs() == ids)
            #expect(created.server.workDoneProgress.isShutDown)
        }
    }

    @Test func stoppingAllServersDeletesTheirRunningProgress() async throws {
        try await running { service, _, key, created in
            let ids = try await beginTwoProgresses(created, key: key)

            await service.stopAllServers()

            #expect(deletedTaskIDs() == ids)
            #expect(created.server.workDoneProgress.isShutDown)
        }
    }

    @Test func closingTheWorkspaceDeletesItsRunningProgress() async throws {
        try await running { service, workspace, key, created in
            let ids = try await beginTwoProgresses(created, key: key)

            service.closeWorkspace(workspace.path)

            #expect(deletedTaskIDs() == ids)
            try await eventually(timeout: .seconds(30)) { service.languageClients[key] == nil }
        }
    }

    @Test func aCrashedServerDeletesItsRunningProgress() async throws {
        try await running { service, _, key, created in
            let ids = try await beginTwoProgresses(created, key: key)

            created.terminate()
            try await eventually(timeout: .seconds(30)) { deletedTaskIDs() == ids }
            await service.waitForAutomaticRestarts()

            #expect(created.server.workDoneProgress.isShutDown)
        }
    }

    @Test func liveTaskPostingReachesTheHandlerOfTheWorkspaceOnly() async throws {
        let workspaceURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "progress-\(UUID().uuidString)", directoryHint: .isDirectory)
        let otherURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "progress-\(UUID().uuidString)", directoryHint: .isDirectory)
        let handler = TaskNotificationHandler(workspaceURL: workspaceURL)
        let other = TaskNotificationHandler(workspaceURL: otherURL)
        let live = LSPService.Dependencies.live
        let created = TaskNotificationModel(
            id: "lsp.progress.live", title: "Indexing", message: "1/2", percentage: 0.5, isLoading: true
        )
        var updated = created
        updated.message = "2/2"
        updated.percentage = 1

        live.postTask(workspaceURL, .create, created)
        try await eventually(timeout: .seconds(30)) { handler.notifications == [created] }
        live.postTask(workspaceURL, .update, updated)
        try await eventually(timeout: .seconds(30)) { handler.notifications == [updated] }
        live.postTask(workspaceURL, .delete, created)
        try await eventually(timeout: .seconds(30)) { handler.notifications.isEmpty }

        #expect(other.notifications.isEmpty)
    }
}
