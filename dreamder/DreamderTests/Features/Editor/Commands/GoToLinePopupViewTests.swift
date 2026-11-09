import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GoToLinePopupViewTests {
    private func makeModel(input: String) -> GoToLinePopupModel {
        let model = GoToLinePopupModel(lineCount: 30, currentLine: 4, currentColumn: 2, onSubmit: { _ in })
        model.input = input
        return model
    }

    @Test(arguments: ["", "12:3", "abc"])
    func rendersEveryStateVariant(input: String) async throws {
        let model = makeModel(input: input)
        let hosted = HostedViewFixture.host(size: NSSize(width: 320, height: 140)) {
            GoToLinePopupView(model: model)
        }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(hosted.renders())
    }

    @Test func validAndInvalidStatesLookDifferent() async throws {
        let valid = HostedViewFixture.host(size: NSSize(width: 320, height: 140)) {
            GoToLinePopupView(model: makeModel(input: "5"))
        }
        defer { valid.close() }
        let invalid = HostedViewFixture.host(size: NSSize(width: 320, height: 140)) {
            GoToLinePopupView(model: makeModel(input: "x"))
        }
        defer { invalid.close() }
        try await valid.settle()
        try await invalid.settle()
        #expect(HostedView.pixelsDiffer(valid.snapshot(), invalid.snapshot()))
    }

    @Test func presenterShowsAndDismissesThePopover() async throws {
        let host = HostedViewFixture.host(size: NSSize(width: 300, height: 200)) { Color.clear }
        defer { host.close() }
        try await host.settle()
        let presenter = GoToLinePopupPresenter()
        let anchor = NSRect(x: 10, y: 10, width: 20, height: 20)
        #expect(!presenter.isPresented)

        presenter.present(model: makeModel(input: "3"), relativeTo: anchor, of: host.rootView)
        #expect(presenter.isPresented)

        presenter.present(model: makeModel(input: "4"), relativeTo: anchor, of: host.rootView)
        #expect(presenter.isPresented)

        presenter.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))
        #expect(presenter.isPresented)

        presenter.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: presenter.popover))
        #expect(presenter.popover == nil)

        presenter.present(model: makeModel(input: "5"), relativeTo: anchor, of: host.rootView)
        presenter.dismiss()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!presenter.isPresented)
    }
}
