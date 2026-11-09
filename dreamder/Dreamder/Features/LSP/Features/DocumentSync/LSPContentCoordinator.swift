//
//  LSPContentCoordinator.swift
//  Dreamder
//
//  Created by Khan Winter on 9/12/24.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// This content coordinator forwards content notifications from the editor's text storage to a language service.
///
/// This is a text view coordinator so that it can be installed on an open editor. It is kept as a property on
/// ``CodeFileDocument`` since the language server does all it's document management using instances of that type.
///
/// Language servers expect edits to be sent in chunks (and it helps reduce processing overhead). Edits are collected
/// and sent as one batch after ``batchInterval``. Anything that issues a request to the server first awaits
/// ``flushPendingChanges()`` so the server never answers against stale text.
class LSPContentCoordinator<DocumentType: LanguageServerDocument>: TextViewCoordinator, TextViewDelegate {
    private var editedRange: LSPRange?
    private var pendingElements: [LSPContentSequenceElement] = []
    private var batchTask: Task<Void, Never>?
    private var inFlightSend: Task<Void, Never>?
    private let batchInterval: Duration
    private weak var observedTextView: TextView?
    private var changeObservers: [any NSObjectProtocol] = []
    private var changeDepth = 0
    private var lengthBeforeChange = 0
    private var recordedDelta = 0

    weak var languageServer: LanguageServer<DocumentType>?
    var documentURI: String?

    init(
        documentURI: String? = nil,
        languageServer: LanguageServer<DocumentType>? = nil,
        batchInterval: Duration = .milliseconds(250)
    ) {
        self.documentURI = documentURI
        self.languageServer = languageServer
        self.batchInterval = batchInterval
    }

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
    }

    func prepareCoordinator(controller: TextViewController) {
        batchTask?.cancel()
        batchTask = nil
        stopObservingChanges()
        guard let textView = controller.textView else { return }
        observedTextView = textView
        changeObservers = [
            Self.observer(for: TextView.textWillChangeNotification, object: textView, coordinator: self) {
                $0.textWillChange()
            },
            Self.observer(for: TextView.textDidChangeNotification, object: textView, coordinator: self) {
                $0.textDidChange()
            }
        ]
    }

    var hasPendingChanges: Bool {
        !pendingElements.isEmpty
    }

    /// We grab the lsp range before the content (and layout) is changed so we get correct line/col info for the
    /// language server range.
    func textView(_ textView: TextView, willReplaceContentsIn range: NSRange, with string: String) {
        self.editedRange = textView.lspRangeFrom(nsRange: range)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        guard let lspRange = editedRange, let documentURI else {
            return
        }
        self.editedRange = nil
        recordedDelta += string.utf16.count - range.length
        recordEdit(uri: documentURI, range: lspRange, string: string)
    }

    func recordEdit(uri: String, range: LSPRange, string: String) {
        record(LSPContentSequenceElement(uri: uri, range: range, string: string))
    }

    func flushPendingChanges() async {
        batchTask?.cancel()
        batchTask = nil
        let batch = pendingElements
        pendingElements.removeAll()
        guard let uri = batch.first?.uri else {
            await inFlightSend?.value
            return
        }
        let previous = inFlightSend
        let server = languageServer
        let replacesWholeDocument = batch.contains { $0.range == nil }
        let send = Task {
            await previous?.value
            if replacesWholeDocument {
                await Self.reload(uri: uri, on: server)
            } else {
                let changes = batch.compactMap { element in
                    element.range.map {
                        LanguageServer<DocumentType>.DocumentChange(replacingContentsIn: $0, with: element.string)
                    }
                }
                try? await server?.documentChanged(uri: uri, changes: changes)
            }
        }
        inFlightSend = send
        await send.value
    }

    func discardPendingChanges() {
        pendingElements.removeAll()
        batchTask?.cancel()
        batchTask = nil
    }

    func destroy() {
        batchTask?.cancel()
        batchTask = nil
        pendingElements.removeAll()
        stopObservingChanges()
    }

    isolated deinit {
        destroy()
    }

    private static func reload(uri: String, on server: LanguageServer<DocumentType>?) async {
        guard let server, let document = server.openFiles.document(for: uri) else { return }
        try? await server.reloadDocument(document)
    }

    private static func observer(
        for name: Notification.Name,
        object: TextView,
        coordinator: LSPContentCoordinator,
        handler: @escaping @MainActor (LSPContentCoordinator) -> Void
    ) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak coordinator] _ in
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated {
                if let coordinator {
                    handler(coordinator)
                }
            }
        }
    }

    private func stopObservingChanges() {
        for observer in changeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        changeObservers.removeAll()
        changeDepth = 0
    }

    private func textWillChange() {
        changeDepth += 1
        guard changeDepth == 1, let observedTextView else { return }
        lengthBeforeChange = observedTextView.textStorage.length
        recordedDelta = 0
    }

    private func textDidChange() {
        changeDepth = max(changeDepth - 1, 0)
        guard changeDepth == 0, let observedTextView, let documentURI else { return }
        let actualDelta = observedTextView.textStorage.length - lengthBeforeChange
        guard actualDelta != recordedDelta else { return }
        record(LSPContentSequenceElement(uri: documentURI, range: nil, string: ""))
    }

    private func record(_ element: LSPContentSequenceElement) {
        languageServer?.lspCache.invalidate(uri: element.uri)
        pendingElements.append(element)
        scheduleBatch()
    }

    private func scheduleBatch() {
        guard batchTask == nil else { return }
        let interval = batchInterval
        batchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard let self else { return }
            self.batchTask = nil
            await self.flushPendingChanges()
        }
    }
}

nonisolated private struct LSPContentSequenceElement: Sendable {
    let uri: String
    let range: LSPRange?
    let string: String
}
