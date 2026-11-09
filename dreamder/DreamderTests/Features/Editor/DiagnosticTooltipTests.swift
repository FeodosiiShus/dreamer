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
