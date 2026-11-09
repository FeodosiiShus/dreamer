import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@Suite("DiagnosticTooltipModel")
struct DiagnosticTooltipModelTests {
    private let file = URL(fileURLWithPath: "/tmp/a.swift")

    private func diagnostic(
        _ message: String,
        from: (Int, Int),
        to: (Int, Int),
        severity: WorkspaceDiagnostic.Severity = .error,
        source: String? = nil,
        code: String? = nil
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: file,
            startLine: from.0,
            startColumn: from.1,
            endLine: to.0,
            endColumn: to.1,
            severity: severity,
            message: message,
            source: source,
            code: code
        )
    }

    struct PositionCase: Sendable, CustomTestStringConvertible {
        let line: Int
        let column: Int
        let hit: Bool

        var testDescription: String { "\(line):\(column) -> \(hit)" }
    }

    @Test(arguments: [
        PositionCase(line: 1, column: 3, hit: false),
        PositionCase(line: 1, column: 4, hit: true),
        PositionCase(line: 1, column: 8, hit: true),
        PositionCase(line: 1, column: 9, hit: false),
        PositionCase(line: 0, column: 4, hit: false),
        PositionCase(line: 2, column: 0, hit: false)
    ])
    func singleLineDiagnosticsContainTheirHalfOpenColumnRange(_ position: PositionCase) {
        let model = DiagnosticTooltipModel.make(
            diagnostics: [diagnostic("m", from: (1, 4), to: (1, 9))],
            line: position.line,
            column: position.column,
            showsMoreActions: false
        )

        #expect((model != nil) == position.hit)
    }

    @Test(arguments: [
        PositionCase(line: 1, column: 5, hit: false),
        PositionCase(line: 1, column: 6, hit: true),
        PositionCase(line: 2, column: 100, hit: true),
        PositionCase(line: 3, column: 1, hit: true),
        PositionCase(line: 3, column: 2, hit: false)
    ])
    func multiLineDiagnosticsSpanFromStartToEnd(_ position: PositionCase) {
        let model = DiagnosticTooltipModel.make(
            diagnostics: [diagnostic("m", from: (1, 6), to: (3, 2))],
            line: position.line,
            column: position.column,
            showsMoreActions: false
        )

        #expect((model != nil) == position.hit)
    }

    @Test
    func emptyRangesOnlyContainTheirStartPosition() {
        let empty = diagnostic("m", from: (2, 5), to: (2, 5))

        #expect(DiagnosticTooltipModel.make(diagnostics: [empty], line: 2, column: 5, showsMoreActions: false) != nil)
        #expect(DiagnosticTooltipModel.make(diagnostics: [empty], line: 2, column: 6, showsMoreActions: false) == nil)
    }

    @Test
    func entriesAreSortedBySeverityAndDeduplicated() throws {
        let diagnostics = [
            diagnostic("warned", from: (0, 0), to: (0, 9), severity: .warning, source: "lint"),
            diagnostic("broken", from: (0, 2), to: (0, 5), severity: .error, source: "swift", code: "E1"),
            diagnostic("broken", from: (0, 2), to: (0, 5), severity: .error, source: "swift", code: "E1"),
            diagnostic("info", from: (0, 3), to: (0, 4), severity: .information, code: "I9"),
            diagnostic("far away", from: (4, 0), to: (4, 3))
        ]

        let model = try #require(
            DiagnosticTooltipModel.make(diagnostics: diagnostics, line: 0, column: 3, showsMoreActions: true)
        )

        #expect(model.entries.map(\.message) == ["broken", "warned", "info"])
        #expect(model.entries.map(\.origin) == ["swift (E1)", "lint", "I9"])
        #expect(model.entries.map(\.severity) == [.error, .warning, .information])
        #expect(model.showsMoreActions)
    }

    @Test
    func noDiagnosticAtThePositionYieldsNoModel() {
        #expect(DiagnosticTooltipModel.make(diagnostics: [], line: 0, column: 0, showsMoreActions: false) == nil)
    }

    @Test
    func originCombinesSourceAndCode() {
        #expect(DiagnosticTooltipModel.origin(source: "ts", code: "2322") == "ts (2322)")
        #expect(DiagnosticTooltipModel.origin(source: "ts", code: nil) == "ts")
        #expect(DiagnosticTooltipModel.origin(source: nil, code: "2322") == "2322")
        #expect(DiagnosticTooltipModel.origin(source: nil, code: nil) == nil)
    }
}

@MainActor
@Suite("DiagnosticTooltipView", .uiGate)
struct DiagnosticTooltipViewTests {
    private func entry(
        _ severity: WorkspaceDiagnostic.Severity,
        _ message: String = "message",
        origin: String? = nil
    ) -> DiagnosticTooltipModel.Entry {
        DiagnosticTooltipModel.Entry(severity: severity, message: message, origin: origin)
    }

    private func render(_ model: DiagnosticTooltipModel) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 460, height: 200)) {
            DiagnosticTooltipView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        return hosted.snapshot()
    }

    @Test
    func tooltipRendersAndVariantsDiffer() async throws {
        let plain = try await render(DiagnosticTooltipModel(entries: [entry(.error)], showsMoreActions: false))
        let withOrigin = try await render(
            DiagnosticTooltipModel(entries: [entry(.error, origin: "swift (E1)")], showsMoreActions: false)
        )
        let withActions = try await render(DiagnosticTooltipModel(entries: [entry(.error)], showsMoreActions: true))
        let warning = try await render(DiagnosticTooltipModel(entries: [entry(.warning)], showsMoreActions: false))
        let information = try await render(
            DiagnosticTooltipModel(entries: [entry(.information)], showsMoreActions: false)
        )
        let stacked = try await render(
            DiagnosticTooltipModel(entries: [entry(.error), entry(.warning, "second")], showsMoreActions: false)
        )

        #expect(plain != nil)
        #expect(HostedView.pixelsDiffer(plain, withOrigin))
        #expect(HostedView.pixelsDiffer(plain, withActions))
        #expect(HostedView.pixelsDiffer(plain, warning))
        #expect(HostedView.pixelsDiffer(warning, information))
        #expect(HostedView.pixelsDiffer(plain, stacked))
    }

    @Test
    func severityColorsFollowIslands() {
        #expect(DiagnosticTooltipView.color(for: .error) == Islands.errorForeground)
        #expect(DiagnosticTooltipView.color(for: .warning) == Islands.warningForeground)
        #expect(DiagnosticTooltipView.color(for: .information) == Islands.link)
        #expect(DiagnosticTooltipView.color(for: .hint) == Islands.link)
        #expect(DiagnosticTooltipView.moreActionsHint.contains("More actions"))
    }
}

@MainActor
@Suite("DiagnosticTooltipPresenter", .uiGate)
struct DiagnosticTooltipPresenterTests {
    private static let source = "let alpha = 1\nlet beta = 2\n"


    @MainActor
    private final class PopoverLog {
        private(set) var models: [DiagnosticTooltipModel] = []

        var factory: DiagnosticTooltipPresenter.PopoverFactory {
            { [self] model, _, _ in
                models.append(model)
                return NSPopover()
            }
        }
    }
    private func model(_ message: String) -> DiagnosticTooltipModel {
        DiagnosticTooltipModel(
            entries: [DiagnosticTooltipModel.Entry(severity: .error, message: message, origin: nil)],
            showsMoreActions: false
        )
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in textView: TextView) throws -> NSEvent {
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

    private func point(ofOffset offset: Int, in textView: TextView) throws -> NSPoint {
        let rect = try #require(textView.layoutManager.rectForOffset(offset))
        return NSPoint(x: rect.midX + 1, y: rect.midY)
    }

    private func awaitLayout(of textView: TextView) async throws {
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

    @Test
    func monitorForwardsMouseMovesAndDismissesOnInput() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let clock = TestClock()
            let log = PopoverLog()
            let presenter = DiagnosticTooltipPresenter(
                delay: .milliseconds(5),
                clock: clock,
                popoverFactory: log.factory
            ) { _, _ in model("any") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            try await awaitLayout(of: session.textView)
            let target = try point(ofOffset: 4, in: session.textView)

            NSApp.sendEvent(try mouseEvent(.mouseMoved, at: target, in: session.textView))
            #expect(presenter.pendingModel == model("any"))
            try await clock.waitForSleepers()
            clock.advance(by: .milliseconds(5))
            try await eventually(timeout: .seconds(30)) { presenter.popover != nil }
            #expect(log.models == [model("any")])

            NSApp.sendEvent(try mouseEvent(.leftMouseDown, at: target, in: session.textView))
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel == nil)

            NSApp.sendEvent(try mouseEvent(.mouseMoved, at: target, in: session.textView))
            #expect(presenter.pendingModel == model("any"))
            presenter.remove()
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel == nil)

            NSApp.sendEvent(try mouseEvent(.mouseMoved, at: target, in: session.textView))
            #expect(presenter.pendingModel == nil)
        }
    }

    @Test
    func eventsFromOtherWindowsAreIgnored() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let presenter = DiagnosticTooltipPresenter(delay: .milliseconds(5)) { _, _ in model("any") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            other.isReleasedWhenClosed = false
            defer { other.close() }
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: NSPoint(x: 10, y: 10),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: other.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 0,
                    pressure: 0
                )
            )

            presenter.handle(event)

            #expect(presenter.pendingModel == nil)
        }
    }

    @Test
    func presentingAfterTheTextViewLeftItsWindowIsSkipped() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            let clock = TestClock()
            let log = PopoverLog()
            let presenter = DiagnosticTooltipPresenter(
                delay: .milliseconds(30),
                clock: clock,
                popoverFactory: log.factory
            ) { _, _ in model("any") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            try await awaitLayout(of: session.textView)

            presenter.hover(at: try point(ofOffset: 4, in: session.textView))
            try await clock.waitForSleepers()
            session.textView.removeFromSuperview()
            session.close()
            clock.advance(by: .milliseconds(30))
            await Task.yield()
            await Task.yield()

            #expect(log.models.isEmpty)
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel != nil)
        }
    }
}
