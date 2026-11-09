import AppKit
import Observation
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI

final class DiagnosticHighlightCoordinator: TextViewCoordinator {
    typealias LSPServiceProvider = @MainActor () -> LSPService?

    private static let errorGroup = "dreamder.diagnostics.error"
    private static let warningGroup = "dreamder.diagnostics.warning"

    private let fileURL: URL?
    private weak var codeFile: CodeFileDocument?
    private let lspService: LSPServiceProvider
    private let intentionDelay: Duration
    private let tooltipDelay: Duration
    private weak var controller: TextViewController?
    private weak var store: DiagnosticsStore?
    private var storeObservation: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var intentionTask: Task<Void, Never>?
    private var intentionLine: Int?
    let stripe = ErrorStripeInstaller()
    let bulb = IntentionBulbPresenter()
    lazy var tooltip = DiagnosticTooltipPresenter(delay: tooltipDelay) { [weak self] line, column in
        self?.tooltipModel(line: line, column: column)
    }

    init(
        codeFile: CodeFileDocument,
        intentionDelay: Duration = .milliseconds(150),
        tooltipDelay: Duration = .milliseconds(400),
        lspService: @escaping LSPServiceProvider = { .shared }
    ) {
        fileURL = codeFile.fileURL
        self.codeFile = codeFile
        self.intentionDelay = intentionDelay
        self.tooltipDelay = tooltipDelay
        self.lspService = lspService
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        installDecorations(in: controller)
        guard store == nil, let fileURL, let workspace = fileURL.findWorkspace() else { return }
        let diagnosticsStore = workspace.diagnosticsStore
        store = diagnosticsStore
        storeObservation = Task { [weak self, weak diagnosticsStore] in
            let changes = Observations { [weak diagnosticsStore] in diagnosticsStore?.diagnosticsByFile }
            for await _ in changes {
                guard let self else { return }
                scheduleApply()
            }
        }
        scheduleApply()
    }

    func textViewDidChangeText(controller: TextViewController) {
        scheduleApply()
        bulb.reposition()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        scheduleIntentionRefresh()
    }

    func intentionAvailable(line: Int) -> Bool {
        intentionLine == line
    }

    func destroy() {
        applyTask?.cancel()
        applyTask = nil
        storeObservation?.cancel()
        storeObservation = nil
        intentionTask?.cancel()
        intentionTask = nil
        intentionLine = nil
        removeEmphases()
        stripe.remove()
        bulb.remove()
        tooltip.remove()
        store = nil
        controller = nil
    }

    private func installDecorations(in controller: TextViewController) {
        stripe.onSelect = { [weak self] line in self?.selectDiagnostic(onLine: line) }
        stripe.install(in: controller)
        bulb.onActivate = {
            NSApp.sendAction(#selector(DreamderWindowController.showContextActions(_:)), to: nil, from: nil)
        }
        bulb.install(controller: controller)
        if let textView = controller.textView {
            tooltip.install(textView: textView)
        }
    }

    private func scheduleApply() {
        guard applyTask == nil else { return }
        applyTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            applyTask = nil
            applyEmphases()
            scheduleIntentionRefresh()
        }
    }

    private func removeEmphases() {
        guard let emphasisManager = controller?.textView?.emphasisManager else { return }
        emphasisManager.removeEmphases(for: Self.errorGroup)
        emphasisManager.removeEmphases(for: Self.warningGroup)
    }

    private func applyEmphases() {
        guard let controller,
              let textView = controller.textView,
              let emphasisManager = textView.emphasisManager,
              let layoutManager = textView.layoutManager,
              let fileURL,
              let store else {
            return
        }
        let diagnostics = store.diagnostics(for: fileURL)
        var errors: [Emphasis] = []
        var warnings: [Emphasis] = []
        let textLength = textView.textStorage.length

        for diagnostic in diagnostics {
            guard diagnostic.severity == .error || diagnostic.severity == .warning,
                  let range = Self.range(for: diagnostic, layoutManager: layoutManager, textLength: textLength) else {
                continue
            }
            let emphasis = Emphasis(range: range, style: .underline(color: Self.color(for: diagnostic.severity)))
            if diagnostic.severity == .error {
                errors.append(emphasis)
            } else {
                warnings.append(emphasis)
            }
        }

        emphasisManager.replaceEmphases(errors, for: Self.errorGroup)
        emphasisManager.replaceEmphases(warnings, for: Self.warningGroup)
        stripe.update(
            marks: diagnostics.map { ErrorStripeMark(line: $0.startLine, severity: $0.severity) },
            lineCount: layoutManager.lineCount
        )
    }

    private func selectDiagnostic(onLine line: Int) {
        guard let textView = controller?.textView,
              let fileURL,
              let diagnostic = store?.diagnostics(for: fileURL).first(where: { $0.startLine == line }),
              let range = Self.range(
                  for: diagnostic,
                  layoutManager: textView.layoutManager,
                  textLength: textView.textStorage.length
              ) else {
            return
        }
        textView.selectionManager.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollSelectionToVisible()
    }

    private func scheduleIntentionRefresh() {
        intentionTask?.cancel()
        let delay = intentionDelay
        intentionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshIntention()
        }
    }

    private func refreshIntention() async {
        guard let codeFile,
              let fileURL,
              let store,
              let line = caretLine() else {
            clearIntention()
            return
        }
        let diagnostics = store.diagnostics(for: fileURL)
        guard let request = CodeActionRequest.makeForLine(
            line,
            codeFile: codeFile,
            diagnostics: diagnostics,
            lspService: lspService()
        ) else {
            clearIntention()
            return
        }
        let groups = await request.fetch(triggerKind: .automatic)
        guard !Task.isCancelled else { return }
        if groups.hasQuickFixes {
            intentionLine = line
            bulb.show(line: line)
        } else {
            clearIntention()
        }
    }

    private func clearIntention() {
        intentionLine = nil
        bulb.hide()
    }

    private func caretLine() -> Int? {
        guard let textView = controller?.textView,
              let location = textView.selectionManager.textSelections.first?.range.location else {
            return nil
        }
        return textView.layoutManager.textLineForOffset(location)?.index
    }

    private func tooltipModel(line: Int, column: Int) -> DiagnosticTooltipModel? {
        guard let fileURL, let store else { return nil }
        return DiagnosticTooltipModel.make(
            diagnostics: store.diagnostics(for: fileURL),
            line: line,
            column: column,
            showsMoreActions: intentionAvailable(line: line)
        )
    }

    private static func range(
        for diagnostic: WorkspaceDiagnostic,
        layoutManager: TextLayoutManager,
        textLength: Int
    ) -> NSRange? {
        guard textLength > 0,
              let startLine = layoutManager.textLineForIndex(diagnostic.startLine),
              let endLine = layoutManager.textLineForIndex(diagnostic.endLine) else {
            return nil
        }
        let start = min(startLine.range.location + max(0, diagnostic.startColumn), textLength)
        var end = min(endLine.range.location + max(0, diagnostic.endColumn), textLength)
        if end <= start {
            end = min(start + 1, textLength)
        }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func color(for severity: WorkspaceDiagnostic.Severity) -> NSColor {
        let color = severity == .error ? Islands.errorForeground : Islands.warningForeground
        return NSColor(color)
    }
}
