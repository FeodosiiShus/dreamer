import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlFetchViewCoverage {
    private func host(
        _ harness: ScmViewsAHarness,
        model: SourceControlFetchModel = SourceControlFetchModel()
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(harness.workspace) {
            SourceControlFetchView(model: model)
        }
    }

    @Test
    func fetchingDownloadsRemoteBranchesAndRefreshesTheSyncCounts() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            try await harness.publishFromAnotherClone(branches: ["main", "fetched"])
            let before = try await harness.repo.run("branch", "-r")
            #expect(before.contains("origin/fetched") == false)
            let hosted = try host(harness)
            defer { hosted.close() }

            try await eventually { try await harness.repo.run("branch", "-r").contains("origin/fetched") }
            try await eventually { harness.manager.numberOfUnsyncedCommits.behind == 1 }
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func aFailingFetchReportsAnAlert() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            let missing = dir.appending(path: "missing.git").path(percentEncoded: false)
            try await harness.repo.run("remote", "set-url", "origin", missing)
            let hosted = try host(harness)
            defer { hosted.close() }

            try await eventually { harness.manager.lastAlert?.title == "Failed to fetch changes" }
            #expect(harness.manager.lastAlert?.message.isEmpty == false)
        }
    }

    @Test
    func fetchDismissesTheSheetWhenItFinishesAndCancelDismissesItEarly() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            try harness.repo.write("b.txt", "b\n")
            try await harness.repo.commit("local only")
            let model = SourceControlFetchModel()
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })

            model.cancel()
            #expect(dismissals.value == 1)

            await model.perform()
            #expect(dismissals.value == 2)
            #expect(harness.manager.lastAlert == nil)
            try await eventually { harness.manager.numberOfUnsyncedCommits.ahead == 1 }

            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(model.manager === harness.manager)
        }
    }

    @Test
    func detachedModelIgnoresFetchAndCancel() async {
        let model = SourceControlFetchModel()

        await model.perform()
        model.cancel()

        #expect(model.manager == nil)
    }
}
