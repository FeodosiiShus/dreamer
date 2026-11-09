import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlAddExistingRemoteViewCoverage {
    private func host(
        _ harness: ScmViewsAHarness,
        model: SourceControlAddExistingRemoteModel
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(harness.workspace) {
            SourceControlAddExistingRemoteView(model: model)
        }
    }

    @Test
    func suggestsOriginAndFocusesTheLocationWhenNoOriginExists() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir, withRemote: false)
            defer { harness.close() }
            let model = SourceControlAddExistingRemoteModel()
            let hosted = try host(harness, model: model)
            defer { hosted.close() }

            try await eventually { ScmViewsAControls.fieldValues(in: hosted).contains("origin") }
            #expect(model.name == "origin")
            #expect(model.location.isEmpty)
            #expect(model.manager === harness.manager)
        }
    }

    @Test
    func keepsTheNameEmptyWhenOriginAlreadyExists() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            let model = SourceControlAddExistingRemoteModel()
            let hosted = try host(harness, model: model)
            defer { hosted.close() }

            try await hosted.settle()
            #expect(model.manager === harness.manager)
            #expect(model.name.isEmpty)
            #expect(ScmViewsAControls.fieldValues(in: hosted).contains("origin") == false)
        }
    }

    @Test
    func addingTheRemoteRegistersItAndClearsTheForm() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir, withRemote: false)
            defer { harness.close() }
            let model = SourceControlAddExistingRemoteModel(location: harness.remotePath)
            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await eventually { ScmViewsAControls.fieldValues(in: hosted).contains("origin") }
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.submit()
            await model.submission?.value

            #expect(harness.manager.remotes.map(\.name) == ["origin"])
            #expect(model.name.isEmpty)
            #expect(model.location.isEmpty)
            #expect(dismissals.value == 1)
            try await eventually { ScmViewsAControls.fieldValues(in: hosted).contains("origin") == false }
            #expect(harness.manager.lastAlert == nil)
            #expect(harness.manager.operationRemote == nil)
            let remotes = try await harness.repo.run("remote")
            #expect(remotes.contains("origin"))
        }
    }

    @Test
    func addingTheRemoteDuringAPullSelectsItForTheOperation() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir, withRemote: false)
            defer { harness.close() }
            harness.manager.pullSheetIsPresented = true
            let model = SourceControlAddExistingRemoteModel(name: "origin", location: harness.remotePath)
            model.attach(manager: harness.manager, dismiss: {})

            await model.perform()

            #expect(harness.manager.operationRemote?.name == "origin")
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func addingTheRemoteDuringAPushSelectsItForTheOperation() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir, withRemote: false)
            defer { harness.close() }
            harness.manager.pushSheetIsPresented = true
            let model = SourceControlAddExistingRemoteModel(name: "origin", location: harness.remotePath)
            model.attach(manager: harness.manager, dismiss: {})

            await model.perform()

            #expect(harness.manager.operationRemote?.name == "origin")
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func addingADuplicateRemoteReportsTheFailure() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            let model = SourceControlAddExistingRemoteModel(name: "origin", location: harness.remotePath)
            let dismissals = ScmViewsBCounter()
            model.attach(manager: harness.manager, dismiss: { dismissals.increment() })

            await model.perform()

            #expect(harness.manager.lastAlert?.title == "Failed to add remote")
            #expect(harness.manager.lastAlert?.message.isEmpty == false)
            #expect(harness.manager.remotes.count == 1)
            #expect(model.name == "origin")
            #expect(dismissals.value == 0)
        }
    }

    @Test
    func cancelDismissesAndClearsTheEnteredValues() async throws {
        try await withTempDir { dir in
            let harness = try await ScmViewsAHarness.make(in: dir)
            defer { harness.close() }
            let model = SourceControlAddExistingRemoteModel(name: "scratch", location: "/tmp/scratch-remote")
            let hosted = try host(harness, model: model)
            defer { hosted.close() }
            try await eventually {
                let values = ScmViewsAControls.fieldValues(in: hosted)
                return values.contains("scratch") && values.contains("/tmp/scratch-remote")
            }
            let dismissals = ScmViewsBCounter()
            model.dismiss = { dismissals.increment() }

            model.cancel()

            #expect(dismissals.value == 1)
            #expect(model.name.isEmpty)
            #expect(model.location.isEmpty)
            try await eventually {
                let values = ScmViewsAControls.fieldValues(in: hosted)
                return values.contains("scratch") == false && values.contains("/tmp/scratch-remote") == false
            }
            #expect(harness.manager.remotes.count == 1)
        }
    }

    @Test
    func detachedModelIgnoresSubmitAndSuggestsNothing() async {
        let model = SourceControlAddExistingRemoteModel(name: "origin", location: "/tmp/x")
        let dismissals = ScmViewsBCounter()
        model.dismiss = { dismissals.increment() }

        await model.perform()

        #expect(model.suggestOriginWhenMissing() == false)
        #expect(model.name == "origin")
        #expect(model.location == "/tmp/x")
        #expect(dismissals.value == 0)
    }
}
