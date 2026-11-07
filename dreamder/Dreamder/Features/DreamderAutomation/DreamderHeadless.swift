import AppKit
import ObjectiveC

@MainActor
enum DreamderHeadless {
    static let argumentKey = "DreamderHeadless"
    static let environmentKey = "DREAMDER_HEADLESS"
    static let hiddenLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

    static let isEnabled: Bool = ProcessInfo.processInfo.environment[environmentKey] == "1"
        || UserDefaults.standard.bool(forKey: argumentKey)

    private static var observer: NSObjectProtocol?

    static func install() {
        guard isEnabled, observer == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        disableActivation()
        hideBeforeOrdering()
        suppressModals()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { hideWindows() }
        }
        hideWindows()
    }

    static func hide(_ window: NSWindow) {
        if window.level != hiddenLevel {
            window.level = hiddenLevel
        }
        window.isRestorable = false
        window.collectionBehavior.insert(.transient)
        window.collectionBehavior.insert(.ignoresCycle)
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        if window.parent == nil, !visibleFrame.isEmpty, !visibleFrame.contains(window.frame) {
            window.setFrameOrigin(NSPoint(x: visibleFrame.minX, y: visibleFrame.maxY - window.frame.height))
        }
    }

    private static func hideBeforeOrdering() {
        let selector = NSSelectorFromString("orderWindow:relativeTo:")
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
        let original = method_getImplementation(method)
        typealias OrderFunction = @convention(c) (NSWindow, Selector, NSWindow.OrderingMode, Int) -> Void
        let originalOrder = unsafeBitCast(original, to: OrderFunction.self)
        let block: @convention(block) (NSWindow, NSWindow.OrderingMode, Int) -> Void = { window, mode, relative in
            MainActor.assumeIsolated {
                if mode != .out {
                    hide(window)
                }
            }
            originalOrder(window, selector, mode, relative)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    static func hideWindows() {
        for window in NSApp.windows where window.isVisible && window.level != hiddenLevel {
            hide(window)
        }
    }

    private static func disableActivation() {
        let block: @convention(block) (AnyObject) -> Void = { _ in }
        let noArgument = imp_implementationWithBlock(block)
        let flagBlock: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        let flagArgument = imp_implementationWithBlock(flagBlock)
        if let method = class_getInstanceMethod(NSApplication.self, NSSelectorFromString("activate")) {
            method_setImplementation(method, noArgument)
        }
        if let method = class_getInstanceMethod(
            NSApplication.self,
            NSSelectorFromString("activateIgnoringOtherApps:")
        ) {
            method_setImplementation(method, flagArgument)
        }
    }

    private(set) static var suppressedModals: [String] = []

    private static func suppressModals() {
        let alertRunModal: @convention(block) (NSAlert) -> Int = { alert in
            MainActor.assumeIsolated { suppressedModals.append(alert.messageText) }
            return NSApplication.ModalResponse.abort.rawValue
        }
        if let method = class_getInstanceMethod(NSAlert.self, #selector(NSAlert.runModal)) {
            method_setImplementation(method, imp_implementationWithBlock(alertRunModal))
        }
        let alertSheet: @convention(block) (NSAlert, NSWindow?, ((NSApplication.ModalResponse) -> Void)?) -> Void = {
            alert, _, handler in
            MainActor.assumeIsolated { suppressedModals.append(alert.messageText) }
            handler?(.abort)
        }
        if let method = class_getInstanceMethod(
            NSAlert.self,
            #selector(NSAlert.beginSheetModal(for:completionHandler:))
        ) {
            method_setImplementation(method, imp_implementationWithBlock(alertSheet))
        }
        let panelRunModal: @convention(block) (NSSavePanel) -> Int = { panel in
            MainActor.assumeIsolated { suppressedModals.append(panel.message) }
            return NSApplication.ModalResponse.cancel.rawValue
        }
        if let method = class_getInstanceMethod(NSSavePanel.self, #selector(NSSavePanel.runModal)) {
            method_setImplementation(method, imp_implementationWithBlock(panelRunModal))
        }
    }
}
