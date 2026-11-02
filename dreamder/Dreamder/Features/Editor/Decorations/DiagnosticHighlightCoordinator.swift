import AppKit
import Combine
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI

final class DiagnosticHighlightCoordinator: TextViewCoordinator {
    private static let errorGroup = "dreamder.diagnostics.error"
    private static let warningGroup = "dreamder.diagnostics.warning"

    private let fileURL: URL?
    private weak var controller: TextViewController?
    private weak var store: DiagnosticsStore?
    private var cancellables: Set<AnyCancellable> = []
    private var applyWorkItem: DispatchWorkItem?

    init(codeFile: CodeFileDocument) {
        fileURL = codeFile.fileURL
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        guard store == nil, let fileURL, let workspace = fileURL.findWorkspace() else { return }
        store = workspace.diagnosticsStore
        workspace.diagnosticsStore.$diagnosticsByFile
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleApply()
            }
            .store(in: &cancellables)
        scheduleApply()
    }

    func textViewDidChangeText(controller: TextViewController) {
        scheduleApply()
    }

    func destroy() {
        applyWorkItem?.cancel()
        applyWorkItem = nil
        cancellables.removeAll()
        removeEmphases()
        store = nil
        controller = nil
    }

    private func scheduleApply() {
        guard applyWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.applyWorkItem = nil
            self?.applyEmphases()
        }
        applyWorkItem = item
        DispatchQueue.main.async(execute: item)
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
        return NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    }
}
