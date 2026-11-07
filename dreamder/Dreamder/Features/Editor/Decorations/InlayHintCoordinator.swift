import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

final class InlayHintAttachment: TextAttachment {
    static let horizontalPadding: CGFloat = 6
    static let margin: CGFloat = 2
    static let cornerRadius: CGFloat = 3.5
    static let background = NSColor(srgbRed: 0x38 / 255, green: 0x3C / 255, blue: 0x45 / 255, alpha: 0.55)
    static let foreground = NSColor(srgbRed: 0x8C / 255, green: 0x8F / 255, blue: 0x96 / 255, alpha: 1)

    let text: String
    var isSelected = false
    private let line: CTLine
    private let textWidth: CGFloat
    private let ascent: CGFloat
    private let descent: CGFloat

    init(text: String, fontSize: CGFloat) {
        self.text = text
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: Self.foreground]
        )
        line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        self.ascent = ascent
        self.descent = descent
    }

    var width: CGFloat {
        ceil(textWidth) + Self.horizontalPadding * 2 + Self.margin * 2
    }

    func draw(in context: CGContext, rect: NSRect) {
        let pill = NSRect(
            x: rect.minX + Self.margin,
            y: rect.minY - 1,
            width: rect.width - Self.margin * 2,
            height: rect.height + 2
        )
        context.saveGState()
        context.addPath(
            CGPath(roundedRect: pill, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        )
        context.setFillColor(Self.background.cgColor)
        context.fillPath()
        context.textPosition = CGPoint(
            x: pill.minX + Self.horizontalPadding,
            y: pill.midY + (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    func attachmentAction() -> TextAttachmentAction {
        .none
    }
}

nonisolated enum InlayHintLayout {
    static func label(of hint: InlayHint) -> String {
        let text: String
        switch hint.label {
        case .optionA(let value):
            text = value
        case .optionB(let parts):
            text = parts.map(\.value).joined()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func offset(of position: Position, lineStart: Int, lineLength: Int) -> Int? {
        guard position.character >= 0, position.character <= lineLength else { return nil }
        return lineStart + position.character
    }
}

final class InlayHintCoordinator: TextViewCoordinator {
    private static let maxClientAttempts = 15
    static let hintsDidChangeNotification = Notification.Name("dev.dreamder.InlayHintCoordinator.hintsDidChange")

    private let fileURL: URL?
    private weak var controller: TextViewController?
    private var refreshTask: Task<Void, Never>?
    private var clientAttempts = 0

    init(codeFile: CodeFileDocument) {
        fileURL = codeFile.fileURL
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        schedule(after: .milliseconds(300))
    }

    func textViewDidChangeText(controller: TextViewController) {
        schedule(after: .milliseconds(600))
    }

    func destroy() {
        refreshTask?.cancel()
        refreshTask = nil
        removeHints()
        controller = nil
    }

    private func schedule(after delay: Duration) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    @MainActor
    private func refresh() async {
        guard let controller, let textView = controller.textView, let fileURL else { return }
        guard let client = ServiceContainer.resolve(.singleton, LSPService.self)?.languageClient(forDocument: fileURL)
        else {
            if clientAttempts < Self.maxClientAttempts {
                clientAttempts += 1
                schedule(after: .seconds(2))
            }
            return
        }
        guard client.serverCapabilities.inlayHintProvider != nil else {
            removeHints()
            return
        }
        guard let layoutManager = textView.layoutManager else { return }
        let range = LSPRange(
            start: Position(line: 0, character: 0),
            end: Position(line: max(layoutManager.lineCount, 1), character: 0)
        )
        guard let response = try? await client.requestInlayHint(for: fileURL.lspURI, range),
              !Task.isCancelled,
              self.controller === controller else {
            return
        }
        apply(response, textView: textView, fontSize: max(controller.font.pointSize - 1, 9))
    }

    @MainActor
    private func apply(_ hints: [InlayHint], textView: TextView, fontSize: CGFloat) {
        removeHints()
        guard let layoutManager = textView.layoutManager else { return }
        for hint in hints {
            let text = InlayHintLayout.label(of: hint)
            guard !text.isEmpty,
                  let line = layoutManager.textLineForIndex(hint.position.line),
                  let offset = InlayHintLayout.offset(
                    of: hint.position,
                    lineStart: line.range.location,
                    lineLength: line.range.length
                  ) else {
                continue
            }
            layoutManager.attachments.add(
                InlayHintAttachment(text: text, fontSize: fontSize),
                for: NSRange(location: offset, length: 0)
            )
        }
        layoutManager.setNeedsLayout()
        NotificationCenter.default.post(name: Self.hintsDidChangeNotification, object: textView)
    }

    private func removeHints() {
        guard let textView = controller?.textView else { return }
        let attachments = textView.layoutManager.attachments
        let everything = NSRange(location: 0, length: textView.textStorage.length + 1)
        for item in attachments.getAttachmentsStartingIn(everything) where item.attachment is InlayHintAttachment {
            attachments.remove(atOffset: item.range.location)
        }
    }
}
