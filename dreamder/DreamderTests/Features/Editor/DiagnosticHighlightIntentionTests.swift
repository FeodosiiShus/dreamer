import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private struct DiagnosticIntentionSession {
    let harness: CodeActionsHarness
    let hosted: HostedSourceEditor
    let coordinator: DiagnosticHighlightCoordinator
    let controller: TextViewController
    let textView: TextView
    let store: DiagnosticsStore
    let url: URL

    static let source = "let alpha = 1\nlet beta = 2\nlet gamma = 3\n"

    static func open(
        in directory: URL,
        response: CodeActionsHarness.Response?,
        hasService: Bool = true
    ) async throws -> DiagnosticIntentionSession {
        let harness = try await CodeActionsHarness.make(in: directory, text: source)
        if let response {
            try harness.script(response)
        }
        let service = harness.service
        let coordinator = DiagnosticHighlightCoordinator(
            codeFile: harness.document,
            intentionDelay: .milliseconds(5),
            tooltipDelay: .milliseconds(5),
            lspService: { hasService ? service : nil }
        )
        let url = try #require(harness.document.fileURL)
        let fixture = HostedSourceEditorFixture(
            document: harness.document,
            editorInstance: EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        )
        let hosted = fixture.host(
            coordinators: [
                harness.document.contentCoordinator,
                harness.document.textViewBinder,
                harness.document.languageServerObjects.textCoordinator,
                coordinator
            ],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        try await eventually {
            !hosted.views(ofType: IntentionPopupBulbView.self).isEmpty
                && !hosted.views(ofType: ErrorStripeView.self).isEmpty
        }
        try #require(hosted.controller?.textView).selectionManager.setSelectedRange(NSRange(location: 0, length: 0))
        return DiagnosticIntentionSession(
            harness: harness,
            hosted: hosted,
            coordinator: coordinator,
            controller: try #require(hosted.controller),
            textView: try #require(hosted.controller?.textView),
            store: harness.workspace.workspace.diagnosticsStore,
            url: url
        )
    }

    var bulbView: IntentionPopupBulbView? { hosted.views(ofType: IntentionPopupBulbView.self).first }
    var stripeView: ErrorStripeView? { hosted.views(ofType: ErrorStripeView.self).first }

    func diagnostic(
        line: Int,
        from: Int = 4,
        to: Int = 9,
        severity: WorkspaceDiagnostic.Severity = .error
    ) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: url,
            startLine: line,
            startColumn: from,
            endLine: line,
            endColumn: to,
            severity: severity,
            message: "problem on \(line)",
            source: "swift",
            code: "E\(line)"
        )
    }

    func close() {
        hosted.close()
        harness.workspace.close()
    }

    func lineStart(_ index: Int) throws -> Int {
        try #require(textView.layoutManager.textLineForIndex(index)).range.location
    }
}

@MainActor
@Suite("DiagnosticHighlightIntentions", .uiGate)
struct DiagnosticHighlightIntentionTests {
    private let quickFix = CodeActionsHarness.Response([
        .optionB(CodeAction(title: "Fix it", kind: "quickfix", edit: WorkspaceEdit(changes: [:], documentChanges: nil)))
    ])
    private let refactorOnly = CodeActionsHarness.Response([
        .optionB(CodeAction(title: "Extract", kind: "refactor.extract", edit: WorkspaceEdit(changes: [:], documentChanges: nil)))
    ])

    @Test
    func bulbFollowsQuickFixAvailabilityOnTheCaretLine() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: quickFix)
            defer { session.close() }
            let bulb = try #require(session.bulbView)
            #expect(bulb.isHidden)
            #expect(!session.coordinator.intentionAvailable(line: 0))

            session.store.replace([session.diagnostic(line: 0)], for: session.url)
            session.coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            try await eventually { session.coordinator.intentionAvailable(line: 0) }

            #expect(!bulb.isHidden)
            #expect(bulb.frame.origin.x == IntentionBulbPresenter.leadingInset)
            let line = try #require(session.textView.layoutManager.textLineForIndex(0))
            #expect(bulb.frame.midY >= line.yPos && bulb.frame.midY <= line.yPos + line.height)
            #expect(!session.coordinator.intentionAvailable(line: 1))
            let params = try #require(session.harness.connection.codeActionParams.last)
            #expect(params.context.triggerKind == .automatic)
            #expect(params.range == LSPRange(startPair: (0, 4), endPair: (0, 9)))
            #expect(params.context.diagnostics.map(\.message) == ["problem on 0"])

            session.coordinator.bulb.reposition()
            session.coordinator.textViewDidChangeText(controller: session.controller)
            #expect(!bulb.isHidden)

            session.store.replace([], for: session.url)
            try await eventually { !session.coordinator.intentionAvailable(line: 0) && bulb.isHidden }
        }
    }

    @Test
    func bulbMovesWithTheCaretLine() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: quickFix)
            defer { session.close() }
            session.store.replace([session.diagnostic(line: 0), session.diagnostic(line: 2)], for: session.url)
            try await eventually { session.coordinator.intentionAvailable(line: 0) }

            session.textView.selectionManager.setSelectedRange(NSRange(location: try session.lineStart(2) + 1, length: 0))
            session.coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])

            try await eventually { session.coordinator.intentionAvailable(line: 2) }
            #expect(!session.coordinator.intentionAvailable(line: 0))

            session.textView.selectionManager.setSelectedRange(NSRange(location: try session.lineStart(1) + 1, length: 0))
            session.coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            try await eventually { !session.coordinator.intentionAvailable(line: 2) }
            #expect(session.bulbView?.isHidden == true)
        }
    }

    @Test
    func refactoringOnlyResponsesNeverShowTheBulb() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: refactorOnly)
            defer { session.close() }

            session.store.replace([session.diagnostic(line: 0)], for: session.url)
            session.coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            try await eventually { !session.harness.connection.codeActionParams.isEmpty }
            try await Task.sleep(for: .milliseconds(80))

            #expect(!session.coordinator.intentionAvailable(line: 0))
            #expect(session.bulbView?.isHidden == true)
        }
    }

    @Test
    func bulbInstallsOnceAndHidesForLinesThatDoNotExist() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: nil)
            defer { session.close() }
            let bulb = try #require(session.bulbView)

            session.coordinator.bulb.install(controller: session.controller)
            #expect(session.hosted.views(ofType: IntentionPopupBulbView.self).count == 1)

            session.coordinator.bulb.show(line: 0)
            #expect(!bulb.isHidden)
            #expect(session.coordinator.bulb.line == 0)

            session.coordinator.bulb.show(line: 500)
            #expect(bulb.isHidden)

            session.coordinator.bulb.hide()
            #expect(session.coordinator.bulb.line == nil)
            #expect(bulb.isHidden)
        }
    }

    @Test
    func withoutAServerTheBulbStaysHidden() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: quickFix, hasService: false)
            defer { session.close() }

            session.store.replace([session.diagnostic(line: 0)], for: session.url)
            session.coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            try await Task.sleep(for: .milliseconds(100))

            #expect(!session.coordinator.intentionAvailable(line: 0))
            #expect(session.harness.connection.codeActionParams.isEmpty)
            session.bulbView?.onActivate?()
        }
    }

    @Test
    func stripeFollowsDiagnosticsAndClickingSelectsTheDiagnostic() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: nil)
            defer { session.close() }
            let stripe = try #require(session.stripeView)
            #expect(stripe.superview === session.controller.scrollView)
            #expect(stripe.frame.width == ErrorStripeView.stripWidth)
            try await eventually { stripe.frame.maxX == session.controller.scrollView.bounds.width }

            session.store.replace(
                [session.diagnostic(line: 1, from: 2, to: 6), session.diagnostic(line: 2, severity: .warning)],
                for: session.url
            )
            try await eventually { stripe.marks.count == 2 }

            #expect(stripe.marks == [
                ErrorStripeMark(line: 1, severity: .error),
                ErrorStripeMark(line: 2, severity: .warning)
            ])
            #expect(stripe.lineCount == session.textView.layoutManager.lineCount)

            stripe.onSelect?(1)
            #expect(session.textView.selectionManager.textSelections.first?.range == NSRange(
                location: try session.lineStart(1) + 2,
                length: 0
            ))

            stripe.onSelect?(0)
            #expect(session.textView.selectionManager.textSelections.first?.range.location == (try session.lineStart(1) + 2))

            session.controller.scrollView.setFrameSize(NSSize(width: 700, height: 500))
            session.coordinator.stripe.syncFrame()
            #expect(stripe.frame.maxX == session.controller.scrollView.bounds.width)
            #expect(stripe.frame.height == session.controller.scrollView.bounds.height)
        }
    }

    @Test
    func hoveringADiagnosticShowsATooltipThatMentionsMoreActionsWhenAFixExists() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: quickFix)
            defer { session.close() }
            session.store.replace([session.diagnostic(line: 0)], for: session.url)
            try await eventually { session.coordinator.intentionAvailable(line: 0) }
            let rect = try #require(session.textView.layoutManager.rectForOffset(6))

            session.coordinator.tooltip.hover(at: NSPoint(x: rect.midX + 1, y: rect.midY))
            try await eventually { session.coordinator.tooltip.isShowing }

            let model = try #require(session.coordinator.tooltip.pendingModel)
            #expect(model.entries.map(\.message) == ["problem on 0"])
            #expect(model.entries.first?.origin == "swift (E0)")
            #expect(model.showsMoreActions)

            let elsewhere = try #require(session.textView.layoutManager.rectForOffset(try session.lineStart(1) + 1))
            session.coordinator.tooltip.hover(at: NSPoint(x: elsewhere.midX + 1, y: elsewhere.midY))
            #expect(!session.coordinator.tooltip.isShowing)
        }
    }

    @Test
    func destroyingTheCoordinatorRemovesEveryDecoration() async throws {
        try await withTempDir { directory in
            let session = try await DiagnosticIntentionSession.open(in: directory, response: quickFix)
            defer { session.close() }
            session.store.replace([session.diagnostic(line: 0)], for: session.url)
            try await eventually { session.coordinator.intentionAvailable(line: 0) }

            session.coordinator.destroy()

            #expect(session.hosted.views(ofType: IntentionPopupBulbView.self).isEmpty)
            #expect(session.hosted.views(ofType: ErrorStripeView.self).isEmpty)
            #expect(!session.coordinator.intentionAvailable(line: 0))
            session.coordinator.textViewDidChangeSelection(controller: session.controller, newPositions: [])
            try await Task.sleep(for: .milliseconds(50))
            #expect(!session.coordinator.intentionAvailable(line: 0))
        }
    }
}
