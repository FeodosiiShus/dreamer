import AppKit

extension DreamderAutomation {
    static func snapshot(
        to path: String?,
        windowImage: @MainActor (NSWindow) -> CGImage? = DreamderAutomation.windowServerImage(of:),
        makeContext: (Int, Int) -> CGContext? = DreamderAutomation.compositeContext(width:height:)
    ) {
        let directory = URL(fileURLWithPath: path ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let windows = NSApp.orderedWindows.filter { $0.isVisible && $0.frame.width > 300 && $0.parent == nil }
        let captured = windows.flatMap { [$0] + descendants(of: $0) }
        let alphas = captured.map(\.alphaValue)
        captured.forEach { $0.alphaValue = 1 }
        captured.forEach { $0.displayIfNeeded() }
        CATransaction.flush()
        defer {
            for (window, alpha) in zip(captured, alphas) {
                window.alphaValue = alpha
            }
        }
        for (index, window) in windows.enumerated() {
            write(
                capture(window, windowImage: windowImage, makeContext: makeContext),
                to: directory.appendingPathComponent("window-\(index).png")
            )
            for (childIndex, child) in descendants(of: window).enumerated() {
                write(
                    render(child, windowImage: windowImage),
                    to: directory.appendingPathComponent("window-\(index)-popup-\(childIndex).png")
                )
            }
        }
        let method = captureMethod(windowServerAvailable: windowListCreateImage != nil)
        let manifest = [method] + windows.map {
            "\($0.windowNumber) \(type(of: $0)) \(NSStringFromRect($0.frame)) \($0.title)"
        }
        try? manifest.joined(separator: "\n").write(
            to: directory.appendingPathComponent("windows.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func write(_ image: CGImage?, to url: URL) {
        guard let image else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    nonisolated static func compositeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func capture(
        _ window: NSWindow,
        windowImage: @MainActor (NSWindow) -> CGImage?,
        makeContext: (Int, Int) -> CGContext?
    ) -> CGImage? {
        guard let base = render(window, windowImage: windowImage), window.frame.width > 0 else { return nil }
        let layers = [window] + descendants(of: window).filter { $0.frame.intersects(window.frame) }
        let union = layers.map(\.frame).reduce(window.frame) { $0.union($1) }
        let scale = CGFloat(base.width) / window.frame.width
        guard let context = makeContext(
            Int((union.width * scale).rounded()),
            Int((union.height * scale).rounded())
        ) else { return base }
        for layer in layers {
            let image = layer === window ? base : render(layer, windowImage: windowImage)
            guard let image else { continue }
            context.draw(
                image,
                in: CGRect(
                    x: (layer.frame.minX - union.minX) * scale,
                    y: (layer.frame.minY - union.minY) * scale,
                    width: layer.frame.width * scale,
                    height: layer.frame.height * scale
                )
            )
        }
        return context.makeImage()
    }

    typealias WindowListCreateImage = @convention(c) (
        CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private static let windowListCreateImage = resolveWindowListCreateImage(symbol: "CGWindowListCreateImage")

    static func resolveWindowListCreateImage(symbol: String) -> WindowListCreateImage? {
        guard let handle = dlopen(nil, RTLD_NOW), let address = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(address, to: WindowListCreateImage.self)
    }

    static func captureMethod(windowServerAvailable: Bool) -> String {
        windowServerAvailable ? "capture=window-server" : "capture=in-process"
    }

    static func windowServerImage(of window: NSWindow) -> CGImage? {
        windowListCreateImage?(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution, .boundsIgnoreFraming]
        )?.takeRetainedValue()
    }

    private static func render(_ window: NSWindow, windowImage: @MainActor (NSWindow) -> CGImage?) -> CGImage? {
        if let image = windowImage(window) {
            return image
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func descendants(of window: NSWindow) -> [NSWindow] {
        (window.childWindows ?? [])
            .filter(\.isVisible)
            .flatMap { [$0] + descendants(of: $0) }
    }
}
