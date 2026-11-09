import AppKit
import ObjectiveC

@MainActor
enum DreamderHeadless {
    static let argumentKey = "DreamderHeadless"
    static let environmentKey = "DREAMDER_HEADLESS"
    static let hiddenLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.minimumWindow)))

    static let isEnabled = resolveIsEnabled(environment: ProcessInfo.processInfo.environment, defaults: .standard)

    static func resolveIsEnabled(environment: [String: String], defaults: UserDefaults) -> Bool {
        if environment[environmentKey] == "1" {
            return true
        }
        return defaults.bool(forKey: argumentKey)
    }

    private static var observer: NSObjectProtocol?
    private static var stallSampler: MainThreadStallSampler?

    static func install() {
        guard isEnabled, observer == nil else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
        disableActivation()
        hideBeforeOrdering()
        keepOffscreenFrames()
        suppressModals()
        reportUncaughtExceptions()
        stallSampler = MainThreadStallSampler.installFromEnvironment()
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
        if window.alphaValue != 0 {
            window.alphaValue = 0
        }
        window.isRestorable = false
        window.collectionBehavior.insert(.transient)
        window.collectionBehavior.insert(.ignoresCycle)
        window.collectionBehavior.insert(.stationary)
        if window.parent == nil, intersectsAnyScreen(window.frame) {
            window.setFrameOrigin(offscreenOrigin)
        }
    }

    private static func reportUncaughtExceptions() {
        NSSetUncaughtExceptionHandler { exception in
            let report = "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n") + "\n"
            FileHandle.standardError.write(Data(report.utf8))
        }
    }

    static let orderSelector = NSSelectorFromString("orderWindow:relativeTo:")

    static func hideBeforeOrdering(method: Method? = class_getInstanceMethod(NSWindow.self, orderSelector)) {
        guard let method else { return }
        let original = method_getImplementation(method)
        typealias OrderFunction = @convention(c) (NSWindow, Selector, NSWindow.OrderingMode, Int) -> Void
        let originalOrder = unsafeBitCast(original, to: OrderFunction.self)
        let block: @convention(block) (NSWindow, NSWindow.OrderingMode, Int) -> Void = { window, mode, relative in
            MainActor.assumeIsolated {
                if mode != .out {
                    hide(window)
                }
            }
            originalOrder(window, orderSelector, mode, relative)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    static func hideWindows() {
        for window in NSApp.windows where window.isVisible && !isHidden(window) {
            hide(window)
        }
    }

    static func isHidden(_ window: NSWindow) -> Bool {
        window.level == hiddenLevel && window.alphaValue == 0
            && (window.parent != nil || !intersectsAnyScreen(window.frame))
    }

    static func intersectsAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    static var offscreenOrigin: NSPoint {
        origin(beyond: NSScreen.screens.map(\.frame))
    }

    static func origin(beyond screens: [NSRect]) -> NSPoint {
        let maxX = screens.map(\.maxX).max() ?? 0
        let maxY = screens.map(\.maxY).max() ?? 0
        return NSPoint(x: maxX + offscreenGap, y: maxY + offscreenGap)
    }

    private static let offscreenGap: CGFloat = 20_000

    static let constrainSelector = #selector(NSWindow.constrainFrameRect(_:to:))

    static func keepOffscreenFrames(method: Method? = class_getInstanceMethod(NSWindow.self, constrainSelector)) {
        let selector = constrainSelector
        guard let method else { return }
        let original = method_getImplementation(method)
        typealias ConstrainFunction = @convention(c) (NSWindow, Selector, NSRect, NSScreen?) -> NSRect
        let originalConstrain = unsafeBitCast(original, to: ConstrainFunction.self)
        let block: @convention(block) (NSWindow, NSRect, NSScreen?) -> NSRect = { window, frame, screen in
            if intersectsAnyScreen(frame) {
                return originalConstrain(window, selector, frame, screen)
            }
            return frame
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
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
    private(set) static var suppressedExternalOpens: [String] = []
    private(set) static var suppressedTerminations = 0
    private(set) static var interceptedSelectors: Set<String> = []
    private(set) static var missingSelectors: Set<String> = []

    static func recordSuppressedModal(_ name: String) {
        suppressedModals.append(name)
    }

    private static func replace(_ selector: Selector, of type: AnyClass, with block: Any) {
        swizzle(
            class_getInstanceMethod(type, selector),
            named: "\(type).\(NSStringFromSelector(selector))",
            with: block,
            intercepted: &interceptedSelectors,
            missing: &missingSelectors
        )
    }

    static func swizzle(
        _ method: Method?,
        named name: String,
        with block: Any,
        intercepted: inout Set<String>,
        missing: inout Set<String>
    ) {
        guard let method else {
            missing.insert(name)
            return
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        intercepted.insert(name)
    }

    private static func suppressModals() {
        let alertRunModal: @convention(block) (NSAlert) -> Int = { alert in
            MainActor.assumeIsolated { suppressedModals.append(alert.messageText) }
            return NSApplication.ModalResponse.abort.rawValue
        }
        replace(#selector(NSAlert.runModal), of: NSAlert.self, with: alertRunModal)
        let alertSheet: @convention(block) (NSAlert, NSWindow?, ((NSApplication.ModalResponse) -> Void)?) -> Void = {
            alert, _, handler in
            MainActor.assumeIsolated { suppressedModals.append(alert.messageText) }
            handler?(.abort)
        }
        replace(#selector(NSAlert.beginSheetModal(for:completionHandler:)), of: NSAlert.self, with: alertSheet)
        let applicationModal: @convention(block) (NSApplication, NSWindow) -> Int = { _, window in
            MainActor.assumeIsolated { suppressedModals.append(window.title) }
            return NSApplication.ModalResponse.abort.rawValue
        }
        replace(#selector(NSApplication.runModal(for:)), of: NSApplication.self, with: applicationModal)
        let terminate: @convention(block) (NSApplication, Any?) -> Void = { _, _ in
            MainActor.assumeIsolated { suppressedTerminations += 1 }
        }
        replace(#selector(NSApplication.terminate(_:)), of: NSApplication.self, with: terminate)
        suppressPopupMenus()
        suppressExternalOpens()
    }

    private static func suppressPopupMenus() {
        let popUp: @convention(block) (NSMenu, NSMenuItem?, NSPoint, NSView?) -> Bool = { menu, _, _, _ in
            MainActor.assumeIsolated { suppressedModals.append(menu.title) }
            return false
        }
        replace(#selector(NSMenu.popUp(positioning:at:in:)), of: NSMenu.self, with: popUp)
        let contextMenu: @convention(block) (AnyObject, NSMenu, NSEvent, NSView) -> Void = { _, menu, _, _ in
            MainActor.assumeIsolated { suppressedModals.append(menu.title) }
        }
        swizzle(
            class_getClassMethod(NSMenu.self, #selector(NSMenu.popUpContextMenu(_:with:for:))),
            named: "NSMenu.+popUpContextMenu:withEvent:forView:",
            with: contextMenu,
            intercepted: &interceptedSelectors,
            missing: &missingSelectors
        )
    }

    private static func suppressExternalOpens() {
        let openURL: @convention(block) (NSWorkspace, URL) -> Bool = { _, url in
            MainActor.assumeIsolated { suppressedExternalOpens.append(url.absoluteString) }
            return false
        }
        replace(#selector(NSWorkspace.open(_:) as (NSWorkspace) -> (URL) -> Bool), of: NSWorkspace.self, with: openURL)
        let reveal: @convention(block) (NSWorkspace, [URL]) -> Void = { _, urls in
            MainActor.assumeIsolated { suppressedExternalOpens.append(contentsOf: urls.map(\.absoluteString)) }
        }
        replace(#selector(NSWorkspace.activateFileViewerSelecting(_:)), of: NSWorkspace.self, with: reveal)
        let selectFile: @convention(block) (NSWorkspace, String?, String) -> Bool = { _, path, _ in
            MainActor.assumeIsolated { suppressedExternalOpens.append(path ?? "") }
            return false
        }
        replace(
            #selector(NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)),
            of: NSWorkspace.self,
            with: selectFile
        )
        let openConfigured: @convention(block) (
            NSWorkspace, URL, NSWorkspace.OpenConfiguration, ((NSRunningApplication?, (any Error)?) -> Void)?
        ) -> Void = { _, url, _, handler in
            MainActor.assumeIsolated { suppressedExternalOpens.append(url.absoluteString) }
            handler?(nil, CocoaError(.featureUnsupported))
        }
        replace(
            #selector(NSWorkspace.open(_:configuration:completionHandler:)),
            of: NSWorkspace.self,
            with: openConfigured
        )
        let openWithApplication: @convention(block) (
            NSWorkspace, [URL], URL, NSWorkspace.OpenConfiguration, ((NSRunningApplication?, (any Error)?) -> Void)?
        ) -> Void = { _, urls, _, _, handler in
            MainActor.assumeIsolated { suppressedExternalOpens.append(contentsOf: urls.map(\.absoluteString)) }
            handler?(nil, CocoaError(.featureUnsupported))
        }
        replace(
            #selector(NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)),
            of: NSWorkspace.self,
            with: openWithApplication
        )
        let openApplication: @convention(block) (
            NSWorkspace, URL, NSWorkspace.OpenConfiguration, ((NSRunningApplication?, (any Error)?) -> Void)?
        ) -> Void = { _, url, _, handler in
            MainActor.assumeIsolated { suppressedExternalOpens.append(url.absoluteString) }
            handler?(nil, CocoaError(.featureUnsupported))
        }
        replace(
            #selector(NSWorkspace.openApplication(at:configuration:completionHandler:)),
            of: NSWorkspace.self,
            with: openApplication
        )
    }
}
