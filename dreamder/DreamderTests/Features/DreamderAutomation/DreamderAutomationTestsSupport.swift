import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension DreamderAutomationTests {
    static let sampleSource = "let one = 1\nlet two = 2\nlet three = 3\n"

    @MainActor
    struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let manager: EditorManager
        let root: URL

        func bringToFront() {
            controller.window?.makeKeyAndOrderFront(nil)
        }

        func path(_ relative: String) -> String {
            root.appending(path: relative).path(percentEncoded: false)
        }

        func openTab(_ relative: String) throws {
            let file = try #require(workspace.workspaceFileManager?.getFile(path(relative), createIfNotFound: true))
            manager.openTab(item: file)
        }

        func close() {
            controller.window?.close()
            workspace.close()
        }
    }

    func makeHarness(in directory: URL, files: [String] = ["One.swift"]) throws -> Harness {
        for file in files {
            let url = directory.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.sampleSource.write(to: url, atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        DreamderDocumentController.shared.addDocument(workspace)
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        let manager = try #require(workspace.editorManager)
        return Harness(workspace: workspace, controller: controller, manager: manager, root: directory)
    }

    func output(_ name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

    @MainActor
    final class ActionProbe: NSObject, NSApplicationDelegate {
        private(set) var calls = 0

        @objc
        func dreamderAutomationProbe(_ sender: Any?) {
            calls += 1
        }
    }

    func makeInstalledCenter() -> NotificationCenter {
        let center = NotificationCenter()
        DreamderAutomation.install(center: center, enabled: true, queue: nil)
        return center
    }

    func attachTextView(
        to harness: Harness,
        text: String = "hello\nworld\n",
        inside container: NSView? = nil,
        makeFirstResponder: Bool = true
    ) throws -> TextView {
        let window = try #require(harness.controller.window)
        let textView = TextView(string: text)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        if let container {
            container.addSubview(textView)
            window.contentView?.addSubview(container)
        } else {
            window.contentView?.addSubview(textView)
        }
        if makeFirstResponder {
            window.makeFirstResponder(textView)
        }
        harness.bringToFront()
        return textView
    }

    func outputLines(_ name: String, in directory: URL) throws -> [String] {
        try output(name, in: directory).split(separator: "\n").map(String.init)
    }

    func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @MainActor
    final class ProbeWindow: NSWindow {
        var reportedFrame: NSRect?
        var reportsNoChildren = false
        var hidesContentView = false

        override var frame: NSRect {
            reportedFrame ?? super.frame
        }

        override var childWindows: [NSWindow]? {
            reportsNoChildren ? nil : super.childWindows
        }

        override var contentView: NSView? {
            get { hidesContentView ? nil : super.contentView }
            set { super.contentView = newValue }
        }
    }

    var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
    }

    func removeTemporaryFile(_ name: String) {
        try? FileManager.default.removeItem(at: temporaryDirectory.appending(path: name))
    }

    func makeProbeWindow(width: CGFloat = 400, style: NSWindow.StyleMask = [.titled]) -> ProbeWindow {
        let window = ProbeWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 300),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    func snapshotIndex(of window: NSWindow, in manifest: [String]) throws -> Int {
        let line = try #require(manifest.dropFirst().firstIndex { $0.hasPrefix("\(window.windowNumber) ") })
        return line - 1
    }

    func pictureExists(_ name: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
    }

    func attachChild(_ child: ProbeWindow, to parent: ProbeWindow) {
        parent.orderFront(nil)
        child.orderFront(nil)
        parent.addChildWindow(child, ordered: .above)
    }
}
