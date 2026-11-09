import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

extension InlayHintCoordinator {
    func isCovered(_ window: RequestWindow) -> Bool {
        coverage?.contains(window.visible) ?? false
    }

    func requestWindow(in textView: TextView) -> RequestWindow? {
        guard let layoutManager = textView.layoutManager else { return nil }
        let lineCount = layoutManager.lineCount
        let visibleRect = textView.visibleRect
        var firstVisible = 0
        if let line = layoutManager.textLineForPosition(max(visibleRect.minY, 0)) {
            firstVisible = line.index
        }
        var lastVisible = lineCount - 1
        if let line = layoutManager.textLineForPosition(visibleRect.maxY) {
            lastVisible = line.index
        }
        lastVisible = max(lastVisible, firstVisible)
        let startLine = max(firstVisible - Self.visibleMarginLines, 0)
        let endLine = min(lastVisible + Self.visibleMarginLines + 1, lineCount)
        let length = textView.textStorage.length
        let upper = layoutManager.textLineForIndex(endLine)?.range.location ?? length + 1
        var lower = 0
        if let first = layoutManager.textLineForIndex(startLine) {
            lower = first.range.location
        }
        var visibleLower = lower
        if let position = layoutManager.textLineForIndex(firstVisible) {
            visibleLower = position.range.location
        }
        var visibleUpper = length
        if let position = layoutManager.textLineForIndex(lastVisible) {
            visibleUpper = position.range.upperBound
        }
        return RequestWindow(
            lines: startLine..<endLine,
            coverage: InlayHintCoverage(range: NSRange(location: lower, length: upper - lower)),
            visible: NSRange(location: visibleLower, length: visibleUpper - visibleLower)
        )
    }

    @MainActor
    func refresh(force: Bool) async {
        guard let controller, let textView = controller.textView, let fileURL else { return }
        let current = currentSettings
        guard current.enabled else {
            coverage = nil
            removeHints()
            return
        }
        guard let client = LSPService.shared.languageClient(forDocument: fileURL)
        else {
            if clientAttempts < Self.maxClientAttempts {
                clientAttempts += 1
                schedule(after: .seconds(2), force: force)
            }
            return
        }
        guard client.serverCapabilities.inlayHintProvider != nil else {
            removeHints()
            return
        }
        guard let window = requestWindow(in: textView), force || !isCovered(window) else { return }
        let range = LSPRange(
            start: Position(line: window.lines.lowerBound, character: 0),
            end: Position(line: window.lines.upperBound, character: 0)
        )
        requestsInFlight += 1
        defer { requestsInFlight -= 1 }
        guard let response = try? await client.requestInlayHint(for: fileURL.lspURI, range),
              !Task.isCancelled,
              self.controller === controller else {
            return
        }
        let fontSize = max(controller.font.pointSize - 1, 9)
        apply(response, in: window, settings: current, textView: textView, fontSize: fontSize)
        coverage = window.coverage
    }

    @MainActor
    private func apply(
        _ hints: [InlayHint],
        in window: RequestWindow,
        settings: InlayHintSettings,
        textView: TextView,
        fontSize: CGFloat
    ) {
        removeHints(in: window.coverage.range)
        guard let layoutManager = textView.layoutManager else { return }
        let text = textView.textStorage.mutableString
        for hint in hints where window.lines.contains(hint.position.line) {
            let label = InlayHintLayout.label(of: hint)
            guard !label.isEmpty,
                  let line = layoutManager.textLineForIndex(hint.position.line),
                  let offset = InlayHintLayout.offset(
                    of: hint.position,
                    lineStart: line.range.location,
                    lineLength: line.range.length
                  ) else {
                continue
            }
            let followsParenthesis = offset > 0 && text.character(at: offset - 1) == InlayHintLayout.closingParenthesis
            guard settings.shows(kind: hint.kind, followsClosingParenthesis: followsParenthesis) else { continue }
            layoutManager.attachments.add(
                InlayHintAttachment(text: label, fontSize: fontSize),
                for: NSRange(location: offset, length: 0)
            )
        }
        layoutManager.setNeedsLayout()
        NotificationCenter.default.post(name: Self.hintsDidChangeNotification, object: textView)
    }

    func removeHints(in range: NSRange? = nil) {
        guard let textView = controller?.textView else { return }
        let attachments = textView.layoutManager.attachments
        let target = range ?? NSRange(location: 0, length: textView.textStorage.length + 1)
        for item in attachments.getAttachmentsStartingIn(target) where item.attachment is InlayHintAttachment {
            attachments.remove(atOffset: item.range.location)
        }
    }
}
