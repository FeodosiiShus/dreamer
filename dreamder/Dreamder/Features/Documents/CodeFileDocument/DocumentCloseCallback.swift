import AppKit

enum DocumentCloseCallback {
    private typealias Callback = @convention(c) (Any, Selector, Any, Bool, UnsafeMutableRawPointer?) -> Void

    static func invoke(
        on receiver: NSObject,
        selector: Selector,
        document: NSDocument,
        shouldClose: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let implementation = receiver.method(for: selector)
        let callback = unsafeBitCast(implementation, to: Callback.self)
        callback(receiver, selector, document, shouldClose, contextInfo)
    }
}
