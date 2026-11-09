import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct RenamePanelHostTests {
    private func model(_ name: String = "hello") -> RenamePopupViewModel {
        RenamePopupViewModel(target: RenameTarget(name: name, range: nil))
    }

    private func makeOrphanPresenter() -> RenamePanelPresenter {
        RenamePanelPresenter(controller: DreamderWindowController(window: nil, workspace: nil))
    }

    @Test
    func thePanelHostsTheFixedSizeRenameViewAsAChildWindow() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()

            try await results.present(model(), in: harness)

            let panel = try #require(harness.renamePanels.first)
            let hosting = try #require(panel.contentView as? NSHostingView<RenamePopupView>)
            #expect(hosting.sizingOptions == [])
            #expect(panel.frame.size == NSSize(width: 380, height: 104))
            #expect(hosting.rootView.model.name == "hello")
            #expect(results.values.isEmpty)
        }
    }

    @Test
    func confirmingReportsTheTrimmedNameOnceAndClosesThePanel() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let model = model()

            try await results.present(model, in: harness)
            model.name = " greetings "
            model.confirm()

            try await eventually { results.values.count == 1 }
            #expect(results.values == ["greetings"])
            #expect(harness.renamePanels.isEmpty)
        }
    }

    @Test
    func cancellingAndClosingThePanelReportNil() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let first = model()

            try await results.present(first, in: harness)
            first.cancel()
            try await eventually { results.values.count == 1 }
            #expect(results.values == [nil])
            #expect(harness.renamePanels.isEmpty)

            try await results.present(model(), in: harness)
            harness.renamePanels.first?.close()

            try await eventually { results.values.count == 2 }
            #expect(results.values == [nil, nil])
        }
    }

    @Test
    func theKeyEventsOfThePanelConfirmAndCancel() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let confirming = model()

            try await results.present(confirming, in: harness)
            confirming.name = "greetings"
            let returnHandler = try #require(harness.renamePanels.first?.onKeyEvent)
            let handledReturn = returnHandler(try renameKeyEvent(36))
            #expect(handledReturn)
            try await eventually { results.values.count == 1 }
            #expect(results.values == ["greetings"])

            try await results.present(model(), in: harness)
            let escapeHandler = try #require(harness.renamePanels.first?.onKeyEvent)
            let handledEscape = escapeHandler(try renameKeyEvent(53))
            #expect(handledEscape)
            try await eventually { results.values.count == 2 }
            #expect(results.values == ["greetings", nil])
        }
    }

    @Test
    func anInvalidNameKeepsThePanelOpen() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()
            let model = model()

            try await results.present(model, in: harness)
            model.name = "two words"
            model.confirm()

            #expect(results.values.isEmpty)
            #expect(harness.renamePanels.count == 1)
        }
    }

    @Test
    func presentingAgainReplacesTheOpenPanelAndCancelsItsRequest() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let results = RenameNameResults()

            try await results.present(model("one"), in: harness)
            try await results.present(model("two"), in: harness)

            try await eventually { results.values.count == 1 }
            #expect(results.values == [nil])
            #expect(harness.renamePanels.count == 1)
            #expect(harness.renameModel?.name == "two")
        }
    }

    @Test
    func withoutAWindowTheRequestIsCancelledImmediately() async {
        let controller = DreamderWindowController(window: nil, workspace: nil)

        let name = await RenamePanelHost.shared.present(model(), anchor: nil, in: controller)

        #expect(name == nil)
    }

    @Test
    func requestNameSuspendsUntilTheUserConfirms() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let target = RenameTarget(name: "hello", range: nil)

            let request = Task { await RenamePanelHost.shared.requestName(for: target, in: harness.controller) }
            try await eventually { harness.renameModel != nil }
            let model = try #require(harness.renameModel)
            model.name = "greetings"
            model.confirm()

            #expect(await request.value == "greetings")
        }
    }

    @Test
    func thePresenterShowsMessagesAndRequestsNamesThroughTheHosts() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let presenter = RenamePanelPresenter(controller: harness.controller)

            presenter.showMessage("Nothing to rename")
            #expect(harness.messagePanels.count == 1)

            let request = Task { await presenter.requestName(for: RenameTarget(name: "hello", range: nil)) }
            try await eventually { harness.renameModel != nil }
            harness.renameModel?.cancel()

            #expect(await request.value == nil)
        }
    }

    @Test
    func aPresenterWhoseWindowControllerIsGoneDoesNothing() async {
        let presenter = makeOrphanPresenter()

        presenter.showMessage("ignored")
        let name = await presenter.requestName(for: RenameTarget(name: "hello", range: nil))

        #expect(name == nil)
    }

    @Test
    func theKeyHandlerOfAPanelOutlivingItsModelLeavesKeysAlone() async throws {
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let target = RenameTarget(name: "hello", range: nil)
            let request = Task { await RenamePanelHost.shared.requestName(for: target, in: harness.controller) }
            try await eventually { harness.renameModel != nil }
            let panel = try #require(harness.renamePanels.first)
            weak let weakModel: RenamePopupViewModel? = harness.renameModel

            harness.renameModel?.cancel()
            #expect(await request.value == nil)
            panel.contentView = nil
            try await eventually { weakModel == nil }

            #expect(panel.onKeyEvent?(try renameKeyEvent(53)) == false)
        }
    }
}
