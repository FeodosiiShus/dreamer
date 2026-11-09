import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite("DiagnosticTooltipPresenter", .uiGate)
struct DiagnosticTooltipPresenterTests {
    static let source = "let alpha = 1\nlet beta = 2\n"

    @MainActor
    final class PopoverLog {
        private(set) var models: [DiagnosticTooltipModel] = []

        var factory: DiagnosticTooltipPresenter.PopoverFactory {
            { [self] model, _, _ in
                models.append(model)
                return NSPopover()
            }
        }
    }

    func model(_ message: String) -> DiagnosticTooltipModel {
        DiagnosticTooltipModel(
            entries: [DiagnosticTooltipModel.Entry(severity: .error, message: message, origin: nil)],
            showsMoreActions: false
        )
    }

    func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in textView: TextView) throws -> NSEvent {
        let window = try #require(textView.window)
        return try #require(
            NSEvent.mouseEvent(
                with: type,
                location: textView.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: type == .mouseMoved ? 0 : 1,
                pressure: 0
            )
        )
    }

    func point(ofOffset offset: Int, in textView: TextView) throws -> NSPoint {
        let rect = try #require(textView.layoutManager.rectForOffset(offset))
        return NSPoint(x: rect.midX + 1, y: rect.midY)
    }

    func awaitLayout(of textView: TextView) async throws {
        try await eventually {
            [4, 18].allSatisfy { offset in
                guard let rect = textView.layoutManager.rectForOffset(offset) else { return false }
                let probe = NSPoint(x: rect.midX + 1, y: rect.midY)
                return textView.bounds.contains(probe) && textView.layoutManager.textOffsetAtPoint(probe) != nil
            }
        }
    }

    @Test
    func hoveringADiagnosticPresentsThePopoverAndLeavingDismissesIt() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let clock = TestClock()
            let log = PopoverLog()
            var requested: [[Int]] = []
            let presenter = DiagnosticTooltipPresenter(
                delay: .milliseconds(400),
                clock: clock,
                popoverFactory: log.factory
            ) { line, column in
                requested.append([line, column])
                return line == 0 ? model("first") : nil
            }
            presenter.install(textView: session.textView)
            presenter.install(textView: session.textView)
            defer { presenter.remove() }

            presenter.hover(line: 0, column: 4, anchor: .zero)
            #expect(presenter.pendingModel == model("first"))
            try await clock.waitForSleepers()
            clock.advance(by: .milliseconds(400))
            try await eventually(timeout: .seconds(30)) { presenter.popover != nil }
            #expect(requested == [[0, 4]])
            #expect(log.models == [model("first")])
            let shown = presenter.popover

            presenter.hover(line: 0, column: 4, anchor: .zero)
            #expect(presenter.popover === shown)
            #expect(log.models.count == 1)

            presenter.hover(line: 1, column: 4, anchor: .zero)
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel == nil)
        }
    }

    @Test
    func hoveringOutsideTheTextViewDismissesThePendingTooltip() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let presenter = DiagnosticTooltipPresenter(delay: .seconds(60)) { _, _ in model("first") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }

            presenter.hover(line: 0, column: 4, anchor: .zero)
            #expect(presenter.pendingModel == model("first"))
            presenter.hover(at: NSPoint(x: -50, y: -50))

            #expect(presenter.pendingModel == nil)
            #expect(presenter.popover == nil)
        }
    }

    @Test
    func theDefaultPopoverHostsTheTooltipViewForTheHoveredModel() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let presenter = DiagnosticTooltipPresenter(delay: .milliseconds(1)) { _, _ in model("real") }
            defer { presenter.remove() }
            try await awaitLayout(of: session.textView)

            presenter.install(textView: session.textView)
            presenter.hover(at: try point(ofOffset: 4, in: session.textView))
            try await eventually(timeout: .seconds(30)) { presenter.popover != nil }

            let hosting = presenter.popover?.contentViewController as? NSHostingController<DiagnosticTooltipView>
            #expect(hosting?.rootView.model == model("real"))
        }
    }

    @Test
    func pointerResolvesToTheCharacterUnderItOnBothHalvesAndAtLineStart() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            var requested: [[Int]] = []
            let presenter = DiagnosticTooltipPresenter(delay: .seconds(60)) { line, column in
                requested.append([line, column])
                return nil
            }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            try await awaitLayout(of: session.textView)
            let textView = session.textView
            let character = try #require(textView.layoutManager.rectForOffset(4))
            let lineStart = try #require(textView.layoutManager.rectForOffset(14))

            presenter.hover(at: NSPoint(x: character.minX + 1, y: character.midY))
            presenter.hover(at: NSPoint(x: character.midX + 1, y: character.midY))
            presenter.hover(at: NSPoint(x: lineStart.minX + 1, y: lineStart.midY))

            #expect(requested == [[0, 4], [0, 4], [1, 0]])
        }
    }
}
