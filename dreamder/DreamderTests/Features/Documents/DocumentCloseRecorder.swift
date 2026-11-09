import AppKit
import Foundation

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
