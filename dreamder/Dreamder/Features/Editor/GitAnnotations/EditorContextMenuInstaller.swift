import AppKit
import CodeEditTextView

enum EditorContextMenuInstaller {
    private final class HandlerBox {
        let handler: (NSEvent) -> NSMenu?

        init(_ handler: @escaping (NSEvent) -> NSMenu?) {
            self.handler = handler
        }
    }

    private static let handlers = NSMapTable<TextView, HandlerBox>.weakToStrongObjects()
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        let selector = #selector(NSView.menu(for:))
        guard let method = class_getInstanceMethod(TextView.self, selector) else { return }

        typealias MenuImplementation = @convention(c) (AnyObject, Selector, NSEvent) -> NSMenu?
        let original = unsafeBitCast(method_getImplementation(method), to: MenuImplementation.self)

        let block: @convention(block) (AnyObject, NSEvent) -> NSMenu? = { view, event in
            if let textView = view as? TextView,
               Self.isContextMenuEvent(event),
               let handler = Self.handler(for: textView) {
                return handler(event)
            }
            return original(view, selector, event)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    static func setHandler(_ handler: @escaping (NSEvent) -> NSMenu?, for textView: TextView) {
        handlers.setObject(HandlerBox(handler), forKey: textView)
    }

    static func removeHandler(for textView: TextView) {
        handlers.removeObject(forKey: textView)
    }

    static func handler(for textView: TextView) -> ((NSEvent) -> NSMenu?)? {
        handlers.object(forKey: textView)?.handler
    }

    private static func isContextMenuEvent(_ event: NSEvent) -> Bool {
        if event.type == .rightMouseDown {
            return true
        }
        return event.type == .leftMouseDown && event.modifierFlags.contains(.control)
    }
}
