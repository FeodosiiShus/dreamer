import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitCloneViewCoverage {
    private let recorder = GitCloneCoverageRecorder()
    private let size = NSSize(width: 480, height: 240)

    private func makeView(model: GitCloneViewModel) -> GitCloneView {
        let recorder = recorder
        return GitCloneView(
            viewModel: model,
            openBranchView: { recorder.branchViews.append($0) },
            openDocument: { recorder.documents.append($0) }
        )
    }

    @Test
    func defaultViewModelIsCreatedWhenNoneIsInjected() {
        let view = GitCloneView(openBranchView: { _ in }, openDocument: { _ in })

        #expect(Mirror(reflecting: view).children.contains { $0.label == "_viewModel" })
    }

    @Test
    func idleStateRendersWithAnEmptyField() async throws {
        let model = GitCloneViewModel(services: recorder.services())
        let hosted = HostedViewFixture.host(size: size) { makeView(model: model) }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.renders())
        #expect(model.repoUrlStr.isEmpty)
        #expect(model.isCloning == false)
    }

    @Test
    func clipboardUrlIsPickedUpWhenTheViewAppears() async throws {
        recorder.clipboard = "https://github.com/user/repo.git"
        let model = GitCloneViewModel(services: recorder.services())
        let hosted = HostedViewFixture.host(size: size) { makeView(model: model) }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(10)) { model.repoUrlStr == "https://github.com/user/repo.git" }
        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func typingChangesTheRenderedState() async throws {
        let model = GitCloneViewModel(services: recorder.services())
        let hosted = HostedViewFixture.host(size: size) { makeView(model: model) }
        defer { hosted.close() }
        try await hosted.settle()
        let empty = hosted.snapshot()

        model.repoUrlStr = "nonsense"
        try await hosted.settle()
        let invalid = hosted.snapshot()
        #expect(model.isValidUrl(url: model.repoUrlStr) == false)

        model.repoUrlStr = "https://github.com/user/repo.git"
        try await hosted.settle()
        let valid = hosted.snapshot()
        #expect(model.isValidUrl(url: model.repoUrlStr))

        #expect(HostedView.pixelsDiffer(empty, invalid))
        #expect(HostedView.pixelsDiffer(invalid, valid))
    }

    @Test
    func cloningStatePresentsTheProgressSheet() async throws {
        let model = GitCloneViewModel(services: recorder.services())
        let hosted = HostedViewFixture.host(size: size) { makeView(model: model) }
        defer { hosted.close() }
        try await hosted.settle()

        model.cloningProgress = .init(progress: 40, state: .receiving)
        model.isCloning = true

        try await eventually(timeout: .seconds(10)) { hosted.window.attachedSheet != nil }
        try await hosted.settle()

        model.isCloning = false
        try await eventually(timeout: .seconds(10)) { hosted.window.attachedSheet == nil }
    }

    @Test
    func progressSheetRendersEveryCloneState() async throws {
        let model = GitCloneViewModel(services: recorder.services())
        let states: [GitClient.GitCloneProgressState] = [.initialState, .counting, .compressing, .receiving, .resolving]
        var snapshots: [NSBitmapImageRep?] = []

        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 140)) {
            GitCloneProgressSheet(viewModel: model)
        }
        defer { hosted.close() }

        for (index, state) in states.enumerated() {
            model.cloningProgress = .init(progress: Double(index * 25), state: state)
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            snapshots.append(hosted.snapshot())
        }

        #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[4]))
    }

    @Test
    func progressSheetInstallsItsCancelToolbarItemInAManagedWindow() async throws {
        let model = GitCloneViewModel(services: recorder.services())
        model.isCloning = true
        let controller = NSHostingController(rootView: GitCloneProgressSheet(viewModel: model))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()

        #expect(window.contentView != nil)
        #expect(model.isCloning)
    }

    @Test
    func cloneButtonActionDismissesAndOpensTheDocumentForASingleBranchRepository() async throws {
        try await withTempDir { directory in
            let origin = try await GitCloneCoverageOrigin.makeBare(in: directory, branches: [])
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let model = GitCloneViewModel(services: recorder.services())
            model.repoUrlStr = origin.path(percentEncoded: false)
            let view = makeView(model: model)

            view.cloneRepository()
            try await eventually(timeout: .seconds(60)) { !recorder.documents.isEmpty }

            #expect(recorder.documents.map { $0.path(percentEncoded: false) } == [destination.path(percentEncoded: false)])
            #expect(recorder.branchViews.isEmpty)
            #expect(recorder.alerts.isEmpty)
        }
    }

    @Test
    func cloneButtonActionOpensTheBranchViewWhenSeveralRemoteBranchesExist() async throws {
        try await withTempDir { directory in
            let origin = try await GitCloneCoverageOrigin.makeBare(in: directory, branches: ["feature"])
            let destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            recorder.destination = destination
            let model = GitCloneViewModel(services: recorder.services())
            model.repoUrlStr = origin.path(percentEncoded: false)
            let view = makeView(model: model)

            view.cloneRepository()
            try await eventually(timeout: .seconds(60)) { !recorder.branchViews.isEmpty }

            #expect(recorder.branchViews.map { $0.path(percentEncoded: false) } == [destination.path(percentEncoded: false)])
            #expect(recorder.documents.isEmpty)
        }
    }

    @Test
    func cloneButtonActionDoesNothingAfterAFailedClone() async throws {
        try await withTempDir { directory in
            recorder.destination = directory.appending(path: "clone", directoryHint: .isDirectory)
            let model = GitCloneViewModel(services: recorder.services())
            model.repoUrlStr = directory.appending(path: "missing.git").path(percentEncoded: false)
            let view = makeView(model: model)

            view.cloneRepository()
            try await eventually(timeout: .seconds(60)) { !recorder.alerts.isEmpty }

            #expect(recorder.alerts.map(\.message) == ["Failed to clone"])
            #expect(recorder.documents.isEmpty)
            #expect(recorder.branchViews.isEmpty)
        }
    }
}
