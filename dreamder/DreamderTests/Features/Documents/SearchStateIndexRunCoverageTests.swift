import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SearchStateIndexRunCoverageTests {
    private func indexedFileNames(_ state: WorkspaceDocument.SearchState) -> Set<String> {
        Set(state.indexer?.search("needle").map(\.url.lastPathComponent) ?? [])
    }

    @Test
    func rebuildingTwiceInARowLeavesOneFinishedIndexOfTheProject() async throws {
        try await withTempDir { dir in
            try "alpha needle\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            try "beta needle\n".write(to: dir.appending(path: "b.txt"), atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            state.addProjectToIndex()
            state.addProjectToIndex()

            try await eventually(timeout: .seconds(60)) {
                state.indexStatus == .done
                    && state.indexingNotificationID == nil
                    && indexedFileNames(state) == ["a.txt", "b.txt"]
            }
        }
    }

    @Test
    func aWorkspaceWithoutFilesFinishesIndexingWithAnEmptyIndex() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            state.addProjectToIndex()

            try await eventually(timeout: .seconds(60)) {
                state.indexStatus == .done && state.indexer?.documents().isEmpty == true
            }
        }
    }

    @MainActor
    private final class NotificationLog {
        var entries: [(action: String, id: String, title: String?, workspace: URL?)] = []

        func record(_ event: TaskNotificationEvent) {
            entries.append((
                action: event.action?.rawValue ?? "",
                id: event.id ?? "",
                title: event.title,
                workspace: event.workspace
            ))
        }
    }

    @Test
    func finishedIndexingRemovesItsNotificationInsteadOfLeavingItBehind() async throws {
        try await withTempDir { dir in
            try "alpha needle\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let url = try #require(workspace.taskNotificationHandler.workspaceURL)
            let center = NotificationCenter()
            state.notificationCenter = center
            let handler = TaskNotificationHandler(workspaceURL: url, center: center)
            let log = NotificationLog()
            let observer = center.addObserver(forName: .taskNotification, object: nil, queue: .main) { notification in
                let event = TaskNotificationEvent(userInfo: notification.userInfo)
                MainActor.assumeIsolated { log.record(event) }
            }
            defer { center.removeObserver(observer) }

            state.addProjectToIndex()

            @MainActor func ownDelete() -> Bool {
                guard let created = log.entries.first(where: { $0.action == "create" }) else { return false }
                return log.entries.contains { $0.action == "delete" && $0.id == created.id }
            }
            try await eventually(timeout: .seconds(60)) {
                state.indexStatus == .done && ownDelete()
            }
            let created = try #require(log.entries.first { $0.action == "create" })
            let deleted = try #require(log.entries.last { $0.action == "delete" && $0.id == created.id })
            #expect(created.workspace == url)
            #expect(deleted.workspace == url)
            #expect(log.entries.allSatisfy { $0.action != "deleteWithDelay" && $0.title != "Finished indexing" })
            try await eventually { handler.notifications.isEmpty }
        }
    }
}
