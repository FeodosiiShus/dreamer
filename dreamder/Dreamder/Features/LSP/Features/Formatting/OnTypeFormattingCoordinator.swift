import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

final class OnTypeFormattingCoordinator: TextViewCoordinator {
    private weak var codeFile: CodeFileDocument?
    private weak var textView: TextView?
    private let lspService: () -> LSPService?
    private var requestTask: Task<Void, Never>?
    private var editObserver: (any NSObjectProtocol)?

    init(
        codeFile: CodeFileDocument,
        lspService: @escaping () -> LSPService? = { .shared }
    ) {
        self.codeFile = codeFile
        self.lspService = lspService
    }

    isolated deinit {
        stopObserving()
    }

    func prepareCoordinator(controller: TextViewController) {
        requestTask?.cancel()
        requestTask = nil
        stopObserving()
        guard let textView = controller.textView else { return }
        self.textView = textView
        editObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard Thread.isMainThread, let storage = notification.object as AnyObject? else { return }
            let storageID = ObjectIdentifier(storage)
            MainActor.assumeIsolated {
                self?.storageDidChange(storageID)
            }
        }
    }

    func destroy() {
        requestTask?.cancel()
        requestTask = nil
        stopObserving()
    }

    private func stopObserving() {
        if let editObserver {
            NotificationCenter.default.removeObserver(editObserver)
        }
        editObserver = nil
    }

    private func storageDidChange(_ storageID: ObjectIdentifier) {
        guard let textView, let storage = textView.textStorage, ObjectIdentifier(storage) == storageID,
              storage.editedMask.contains(.editedCharacters) else { return }
        storageDidEdit(in: textView, edited: storage.editedRange)
    }

    func storageDidEdit(in textView: TextView, edited: NSRange) {
        let undoManager = textView.undoManager
        guard let storage = textView.textStorage,
              edited.length == 1,
              NSMaxRange(edited) <= storage.length,
              undoManager?.isUndoing != true,
              undoManager?.isRedoing != true,
              let codeFile,
              let fileURL = codeFile.fileURL,
              let client = lspService()?.languageClient(forDocument: fileURL),
              let options = client.onTypeFormattingOptions,
              let character = OnTypeFormattingTrigger.character(
                inserted: storage.mutableString.substring(with: edited),
                options: options
              ) else {
            return
        }
        let caretOffset = NSMaxRange(edited)
        guard OnTypeFormattingTrigger.isTyped(
            caretOffset: caretOffset,
            selections: textView.selectionManager.textSelections.map(\.range)
        ) else {
            return
        }
        let snapshot = storage.string
        let position = FormattingTextPositions.position(atOffset: caretOffset, in: Array(snapshot.utf16))
        let formattingOptions = codeFile.formattingOptions
        requestTask?.cancel()
        requestTask = Task { @MainActor in
            await Self.format(
                client: client,
                uri: fileURL.lspURI,
                position: position,
                character: character,
                options: formattingOptions,
                textView: textView,
                snapshot: snapshot
            )
        }
    }

    private static func format(
        client: LSPService.LanguageServerType,
        uri: String,
        position: Position,
        character: String,
        options: FormattingOptions,
        textView: TextView,
        snapshot: String
    ) async {
        guard let edits = try? await client.requestOnTypeFormatting(
            for: uri,
            position,
            character: character,
            withFormat: options
        ),
            !edits.isEmpty,
            !Task.isCancelled,
            textView.textStorage.string == snapshot else {
            return
        }
        _ = try? await WorkspaceEditApplier(client: client).editOpenDocument(uri: uri, edits: edits)
    }
}
