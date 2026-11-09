import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class HostedView {
    let window: NSWindow
    let hosting: NSHostingView<AnyView>

    init(window: NSWindow, hosting: NSHostingView<AnyView>) {
        self.window = window
        self.hosting = hosting
    }

    var rootView: NSView {
        hosting
    }

    func layout() {
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
    }

    func settle(_ duration: Duration = .milliseconds(300)) async throws {
        layout()
        try await Task.sleep(for: duration)
        layout()
    }

    func views<T: NSView>(of type: T.Type) -> [T] {
        Self.descendants(of: hosting).compactMap { $0 as? T }
    }

    func snapshot() -> NSBitmapImageRep? {
        layout()
        hosting.display()
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        return representation
    }

    func renders() -> Bool {
        guard let representation = snapshot() else { return false }
        return Self.hasVisiblePixels(representation)
    }

    static func pixelsDiffer(_ lhs: NSBitmapImageRep?, _ rhs: NSBitmapImageRep?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs != nil || lhs != nil && rhs == nil }
        guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return true }
        guard let left = lhs.tiffRepresentation, let right = rhs.tiffRepresentation else { return true }
        return left != right
    }

    private static func hasVisiblePixels(_ representation: NSBitmapImageRep) -> Bool {
        let step = max(1, min(representation.pixelsWide, representation.pixelsHigh) / 64)
        var y = 0
        while y < representation.pixelsHigh {
            var x = 0
            while x < representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.05 {
                    return true
                }
                x += step
            }
            y += step
        }
        return false
    }

    func close() {
        window.close()
    }

    private static func descendants(of view: NSView) -> [NSView] {
        var result: [NSView] = [view]
        for subview in view.subviews {
            result.append(contentsOf: descendants(of: subview))
        }
        return result
    }
}

@MainActor
enum HostedViewFixture {
    static func host<Content: View>(
        size: NSSize = NSSize(width: 900, height: 600),
        @ViewBuilder _ content: () -> Content
    ) -> HostedView {
        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        return HostedView(window: window, hosting: hosting)
    }

    static func hostInWorkspace<Content: View>(
        _ workspace: WorkspaceDocument,
        size: NSSize = NSSize(width: 900, height: 600),
        @ViewBuilder _ content: () -> Content
    ) throws -> HostedView {
        let editorManager = try #require(workspace.editorManager)
        let statusBarViewModel = try #require(workspace.statusBarViewModel)
        let utilityAreaModel = try #require(workspace.utilityAreaModel)
        let taskManager = try #require(workspace.taskManager)
        let view = content()
        return host(size: size) {
            SettingsInjector {
                view
                    .environment(workspace)
                    .environment(editorManager)
                    .environment(statusBarViewModel)
                    .environment(utilityAreaModel)
                    .environment(taskManager)
                    .environment(workspace.undoRegistration)
                    .environment(workspace.toolWindowManager)
                    .environment(workspace.sourceControlManager)
            }
        }
    }

    static func makeWorkspace(in directory: URL) throws -> WorkspaceDocument {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        return workspace
    }
}
