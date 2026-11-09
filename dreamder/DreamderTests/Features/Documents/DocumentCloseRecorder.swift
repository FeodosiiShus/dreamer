import AppKit
import Foundation
@testable import Dreamder

@MainActor
final class DocumentCloseRecorder: NSObject {
    struct Call {
        let document: NSDocument
        let shouldClose: Bool
        let contextInfo: UnsafeMutableRawPointer?
    }

    private(set) var calls: [Call] = []

    static let selector = #selector(DocumentCloseRecorder.recordDocument(_:shouldClose:contextInfo:))

    @objc(recordDocument:shouldClose:contextInfo:)
    func recordDocument(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        calls.append(Call(document: document, shouldClose: shouldClose, contextInfo: contextInfo))
    }
}

@MainActor
final class ContextToken {
    let pointer = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    init(initial: Bool = true) {
        pointer.initialize(to: initial)
    }

    var raw: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(pointer)
    }

    isolated deinit {
        pointer.deallocate()
    }
}

@MainActor
final class CloseConfirmationDouble {
    enum Decision {
        case save
        case discard
        case cancel
    }

    private struct Unanswered {
        let document: CodeFileDocument
        let answer: (Bool) -> Void
    }

    private(set) var askedNames: [String] = []
    private var unanswered: [Unanswered] = []
    private let immediateDecision: Decision?

    init(answering immediateDecision: Decision? = nil) {
        self.immediateDecision = immediateDecision
    }

    var pendingCount: Int {
        unanswered.count
    }

    func install(on documents: [CodeFileDocument]) {
        for document in documents {
            document.closeConfirmation = { [self] asked, answer in
                askedNames.append(asked.fileURL?.lastPathComponent ?? "")
                if let immediateDecision {
                    Self.apply(immediateDecision, to: asked, answer: answer)
                } else {
                    unanswered.append(Unanswered(document: asked, answer: answer))
                }
            }
        }
    }

    func answerNext(_ decision: Decision) {
        guard !unanswered.isEmpty else { return }
        let next = unanswered.removeFirst()
        Self.apply(decision, to: next.document, answer: next.answer)
    }

    private static func apply(_ decision: Decision, to document: CodeFileDocument, answer: (Bool) -> Void) {
        switch decision {
        case .save:
            document.updateChangeCount(.changeCleared)
            answer(true)
        case .discard:
            answer(true)
        case .cancel:
            answer(false)
        }
    }
}
