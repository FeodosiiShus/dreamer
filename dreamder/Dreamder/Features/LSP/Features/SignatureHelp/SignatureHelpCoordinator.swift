import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

final class SignatureHelpCoordinator: TextViewCoordinator, TextViewDelegate {
    typealias Client = LanguageServer<CodeFileDocument>
    typealias ClientProvider = @MainActor () -> Client?
    typealias CompletionVisibility = @MainActor () -> Bool

    private struct RequestStamp: Equatable {
        let caret: Int
        let textVersion: Int
    }

    private weak var controller: TextViewController?
    private weak var codeFile: CodeFileDocument?
    private let clientProvider: ClientProvider
    private let isCompletionWindowVisible: CompletionVisibility
    private let refreshDelay: Duration
    private let popup: SignatureHelpPopup
    private var openParen: Int?
    private var textVersion = 0
    private var lastRequest: RequestStamp?
    private var requestSerial = 0
    private var requestTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        clientProvider: ClientProvider? = nil,
        refreshDelay: Duration = .milliseconds(200),
        visibleFrameProvider: @escaping SignatureHelpPopup.VisibleFrameProvider = SignatureHelpPopup.screenVisibleFrame,
        isCompletionWindowVisible: @escaping CompletionVisibility = SignatureHelpCoordinator.isSuggestionWindowVisible
    ) {
        self.isCompletionWindowVisible = isCompletionWindowVisible
        self.codeFile = codeFile
        self.refreshDelay = refreshDelay
        self.popup = SignatureHelpPopup(visibleFrameProvider: visibleFrameProvider)
        self.clientProvider = clientProvider ?? { [weak codeFile] in
            SignatureHelpCoordinator.serviceClient(for: codeFile)
        }
        popup.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        EditorFeatureHubs.hub(for: editorInstance).signatureHelp = self
    }

    isolated deinit {
        requestTask?.cancel()
        refreshTask?.cancel()
        popup.close()
    }

    var isShowingParameterInfo: Bool {
        popup.isShown
    }

    var shownPresentation: SignatureHelpPresentation? {
        popup.presentation
    }

    var shownPanelFrame: NSRect? {
        popup.isShown ? popup.panelFrame : nil
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidDisappear(controller: TextViewController) {
        closePopup()
    }

    func destroy() {
        closePopup()
        popup.close()
        controller = nil
    }

    func showParameterInfo() async {
        guard let textView = controller?.textView,
              let caret = textView.selectionManager.textSelections.first?.range.location else { return }
        let context = SignatureHelpContext.invoked(activeSignatureHelp: popup.presentation?.activeSignatureHelp)
        stamp(caret: caret)
        await request(context, caret: caret)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        textVersion += 1
        if let paren = openParen {
            openParen = SignatureHelpCallRegion.shifted(
                openParen: paren,
                forEditIn: range,
                replacementLength: string.utf16.count
            )
            if openParen == nil {
                closePopup()
            }
        }
        let activeHelp = popup.presentation?.activeSignatureHelp
        guard activeHelp != nil || string.count == 1,
              let capability = clientProvider()?.signatureHelpCapability else { return }
        let typedCaret = range.location + string.utf16.count
        let caret = string.count == 1
            ? typedCaret
            : textView.selectionManager.textSelections.first?.range.location ?? typedCaret
        if activeHelp != nil, let paren = openParen {
            let units = Array(textView.string.utf16)
            guard SignatureHelpCallRegion.contains(caret: caret, openParen: paren, in: units) else {
                closePopup()
                return
            }
        }
        if let context = SignatureHelpTriggerPolicy.context(
            typed: string,
            capability: capability,
            activeSignatureHelp: activeHelp
        ) {
            startRequest(context, caret: caret)
        } else if activeHelp != nil {
            scheduleRefresh()
        }
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        guard popup.isShown,
              let caret = newPositions.first?.range.location,
              lastRequest != RequestStamp(caret: caret, textVersion: textVersion) else { return }
        if let paren = openParen, let textView = controller.textView {
            let units = Array(textView.string.utf16)
            guard SignatureHelpCallRegion.contains(caret: caret, openParen: paren, in: units) else {
                closePopup()
                return
            }
        }
        scheduleRefresh()
    }

    private func stamp(caret: Int) {
        lastRequest = RequestStamp(caret: caret, textVersion: textVersion)
    }

    private func startRequest(_ context: SignatureHelpContext, caret: Int) {
        stamp(caret: caret)
        refreshTask?.cancel()
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.request(context, caret: caret)
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let delay = refreshDelay
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let textView = self.controller?.textView,
                  let caret = textView.selectionManager.textSelections.first?.range.location else { return }
            self.startRequest(
                .contentChange(activeSignatureHelp: self.popup.presentation?.activeSignatureHelp),
                caret: caret
            )
        }
    }

    private func request(_ context: SignatureHelpContext, caret: Int) async {
        guard let textView = controller?.textView,
              let client = clientProvider(),
              client.signatureHelpCapability != nil,
              let uri = codeFile?.languageServerURI else { return }
        requestSerial += 1
        let serial = requestSerial
        let units = Array(textView.string.utf16)
        let position = SignatureHelpCallRegion.position(ofOffset: caret, in: units)
        let response: SignatureHelp?
        do {
            response = try await client.requestSignatureHelp(for: uri, position: position, context: context)
        } catch {
            response = nil
        }
        guard serial == requestSerial else { return }
        let currentCaret = textView.selectionManager.textSelections.first?.range.location ?? caret
        guard let help = response,
              let presentation = SignatureHelpPresentation(help: help),
              let window = textView.window,
              let anchor = EditorCaretGeometry.screenRect(ofOffset: currentCaret, in: textView) else {
            closePopup()
            return
        }
        openParen = SignatureHelpCallRegion.enclosingOpenParen(
            before: currentCaret,
            in: Array(textView.string.utf16)
        )
        popup.show(presentation, anchor: anchor, in: window)
    }

    private func closePopup() {
        requestSerial += 1
        refreshTask?.cancel()
        requestTask?.cancel()
        openParen = nil
        lastRequest = nil
        popup.hide()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              !isCompletionWindowVisible(),
              let textView = controller?.textView,
              let window = textView.window,
              event.window === window,
              window.firstResponder === textView,
              let action = SignatureHelpKeyAction.resolve(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                signatureCount: popup.presentation?.rows.count ?? 0
              ) else { return false }
        switch action {
        case .dismiss:
            closePopup()
        case .previousSignature:
            popup.cycle(by: -1)
        case .nextSignature:
            popup.cycle(by: 1)
        }
        return true
    }

    static func isSuggestionWindowVisible() -> Bool {
        NSApp.windows.contains { $0.isVisible && $0.windowController is SuggestionController }
    }

    private static func serviceClient(for codeFile: CodeFileDocument?) -> Client? {
        guard let url = codeFile?.fileURL else { return nil }
        return LSPService.shared.languageClient(forDocument: url)
    }
}
