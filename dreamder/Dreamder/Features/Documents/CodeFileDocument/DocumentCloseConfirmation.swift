import AppKit

final class DocumentCloseConfirmation: NSObject {
    private var pending: [NSDocument]
    private var completion: ((Bool) -> Void)?
    private var retainedUntilAnswered: DocumentCloseConfirmation?

    private init(documents: [NSDocument], completion: @escaping (Bool) -> Void) {
        pending = documents.filter(\.isDocumentEdited)
        self.completion = completion
        super.init()
    }

    static func ask(_ documents: [NSDocument], completion: @escaping (Bool) -> Void) {
        let confirmation = DocumentCloseConfirmation(documents: documents, completion: completion)
        confirmation.retainedUntilAnswered = confirmation
        confirmation.askNext()
    }

    private func askNext() {
        guard !pending.isEmpty else {
            finish(shouldClose: true)
            return
        }
        pending.removeFirst().canClose(
            withDelegate: self,
            shouldClose: #selector(answered(_:shouldClose:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc
    private func answered(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if shouldClose {
            askNext()
        } else {
            finish(shouldClose: false)
        }
    }

    private func finish(shouldClose: Bool) {
        let completion = completion
        self.completion = nil
        pending = []
        completion?(shouldClose)
        retainedUntilAnswered = nil
    }
}
