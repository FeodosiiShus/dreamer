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

    static let closingParenthesis = unichar(UInt8(ascii: ")"))
}

nonisolated struct InlayHintCoverage: Equatable {
    enum EditRelation: Equatable {
        case before
        case overlapping
        case after
    }

    var range: NSRange

    func contains(_ other: NSRange) -> Bool {
        range.location <= other.location && other.upperBound <= range.upperBound
    }

    func relation(toEdit edit: NSRange) -> EditRelation {
        if edit.upperBound < range.location {
            return .before
        }
        if edit.location > range.upperBound {
            return .after
        }
        return .overlapping
    }

    func shifted(by delta: Int) -> InlayHintCoverage {
        InlayHintCoverage(range: NSRange(location: max(range.location + delta, 0), length: range.length))
    }
}

final class InlayHintCoordinator: TextViewCoordinator, TextViewDelegate {
    static let visibleMarginLines = 40
    static let scrollDebounce: Duration = .milliseconds(150)
    static let editDebounce: Duration = .milliseconds(600)
    static let appearDebounce: Duration = .milliseconds(300)
    static let maxClientAttempts = 15
    static let hintsDidChangeNotification = Notification.Name("dev.dreamder.InlayHintCoordinator.hintsDidChange")

    struct RequestWindow {
        let lines: Range<Int>
        let coverage: InlayHintCoverage
        let visible: NSRange
    }

    let fileURL: URL?
    private let settings: Settings
    private let languageServerConfiguration: @MainActor (InlayHintSettings) -> LSPAny
    weak var controller: TextViewController?
    private var refreshTask: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?
    private var scrollObserver: NSObjectProtocol?
    private var refreshObserver: NSObjectProtocol?
    var clientAttempts = 0
    var coverage: InlayHintCoverage?
    var requestsInFlight = 0
    private var observedSettings: InlayHintSettings

    init(
        codeFile: CodeFileDocument,
        settings: Settings = .shared,
        languageServerConfiguration: @escaping @MainActor (InlayHintSettings) -> LSPAny =
            InlayHintServerPreferences.configurationSettings(for:)
    ) {
        fileURL = codeFile.fileURL
        self.settings = settings
        self.languageServerConfiguration = languageServerConfiguration
        observedSettings = settings.preferences.textEditing.inlayHints
    }

    isolated deinit {
        settingsObservation?.cancel()
        refreshTask?.cancel()
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
        }
    }

    var currentSettings: InlayHintSettings {
        settings.preferences.textEditing.inlayHints
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        settingsObservation?.cancel()
        let settings = self.settings
        settingsObservation = Task { @MainActor [weak self] in
            let values = Observations { settings.preferences.textEditing.inlayHints }
            for await value in values {
                guard let self else { return }
                settingsDidChange(to: value)
            }
        }
    }

    func controllerDidAppear(controller: TextViewController) {
        observeScrolling(of: controller)
        observeRefreshRequests()
        schedule(after: Self.appearDebounce, force: true)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        guard currentSettings.enabled else { return }
        if requestsInFlight == 0, let coverage {
            switch coverage.relation(toEdit: range) {
            case .before:
                self.coverage = coverage.shifted(by: (string as NSString).length - range.length)
                return
            case .after:
                return
            case .overlapping:
                break
            }
        }
        schedule(after: Self.editDebounce, force: true)
    }

    func destroy() {
        refreshTask?.cancel()
        refreshTask = nil
        settingsObservation?.cancel()
        settingsObservation = nil
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        scrollObserver = nil
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
        }
        refreshObserver = nil
        removeHints()
        controller = nil
    }

    private func observeScrolling(of controller: TextViewController) {
        guard scrollObserver == nil, let clipView = controller.scrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scrollPositionDidChange()
            }
        }
    }

    private func observeRefreshRequests() {
        guard refreshObserver == nil else { return }
        let kindKey = LSPService.refreshKindUserInfoKey
        let pathKey = LSPService.refreshWorkspacePathUserInfoKey
        refreshObserver = NotificationCenter.default.addObserver(
            forName: LSPService.refreshRequestedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let kind = notification.userInfo?[kindKey] as? String
            let workspacePath = notification.userInfo?[pathKey] as? String
            MainActor.assumeIsolated {
                self?.serverRequestedRefresh(kind: kind, workspacePath: workspacePath)
            }
        }
    }

    private func serverRequestedRefresh(kind: String?, workspacePath: String?) {
        let service = LSPService.shared
        guard kind == LSPRefreshKind.inlayHint.rawValue,
              let workspacePath,
              currentSettings.enabled,
              let fileURL,
              let client = service.languageClient(forDocument: fileURL),
              service.languageClients.contains(where: { $0.key.workspacePath == workspacePath && $0.value === client })
        else {
            return
        }
        coverage = nil
        removeHints()
        schedule(after: .zero, force: true)
    }

    private func scrollPositionDidChange() {
        guard currentSettings.enabled,
              let textView = controller?.textView,
              let window = requestWindow(in: textView),
              !isCovered(window) else {
            return
        }
        schedule(after: Self.scrollDebounce, force: false)
    }

    private func settingsDidChange(to value: InlayHintSettings) {
        guard value != observedSettings else { return }
        observedSettings = value
        coverage = nil
        pushLanguageServerConfiguration(for: value)
        if value.enabled {
            schedule(after: Self.appearDebounce, force: true)
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            removeHints()
        }
    }

    private func pushLanguageServerConfiguration(for value: InlayHintSettings) {
        guard let fileURL,
              let client = LSPService.shared.languageClient(forDocument: fileURL)
        else { return }
        let params = DidChangeConfigurationParams(settings: languageServerConfiguration(value))
        Task { @MainActor in
            try? await client.lspInstance.didChangeConfiguration(params)
        }
    }

    func schedule(after delay: Duration, force: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh(force: force)
        }
    }
}
