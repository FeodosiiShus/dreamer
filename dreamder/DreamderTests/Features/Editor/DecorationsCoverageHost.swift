import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
struct DecorationsCoverageSession {
    let workspace: WorkspaceDocument?
    let fixture: HostedSourceEditorFixture
    let hosted: HostedSourceEditor
    let controller: TextViewController
    let textView: TextView
    let fileURL: URL

    func close() {
        hosted.close()
        workspace?.close()
    }

    func lineStart(_ index: Int) throws -> Int {
        let line = try #require(textView.layoutManager.textLineForIndex(index))
        return line.range.location
    }
}

@MainActor
enum DecorationsCoverageHost {
    static func open(
        in directory: URL,
        contents: String,
        withWorkspace: Bool = false,
        coordinators: (HostedSourceEditorFixture) -> [TextViewCoordinator]
    ) async throws -> DecorationsCoverageSession {
        let workspace = try withWorkspace ? HostedSourceEditorFixture.registerWorkspace(at: directory) : nil
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "Notes.txt",
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let hosted = fixture.host(coordinators: coordinators(fixture), size: NSSize(width: 900, height: 600))
        try await eventually(timeout: .seconds(60)) {
            guard let textView = hosted.controller?.textView,
                  textView.window === hosted.window,
                  let gutter = hosted.views(ofType: GutterView.self).first else {
                return false
            }
            return gutter.bounds.height > 0 && textView.layoutManager.textLineForIndex(0) != nil
        }
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        let fileURL = try #require(fixture.document.fileURL)
        return DecorationsCoverageSession(
            workspace: workspace,
            fixture: fixture,
            hosted: hosted,
            controller: controller,
            textView: textView,
            fileURL: fileURL
        )
    }
}

@MainActor
enum DecorationsCoveragePixels {
    static func render(_ view: NSView, in rect: NSRect? = nil) throws -> NSBitmapImageRep {
        let area = rect ?? view.bounds
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: area))
        view.cacheDisplay(in: area, to: representation)
        return representation
    }

    static func color(in representation: NSBitmapImageRep, at point: NSPoint, area: NSRect) -> NSColor? {
        let scale = CGFloat(representation.pixelsWide) / area.width
        let x = Int(((point.x - area.minX) * scale).rounded(.down))
        let y = Int(((point.y - area.minY) * scale).rounded(.down))
        guard x >= 0, y >= 0, x < representation.pixelsWide, y < representation.pixelsHigh else { return nil }
        return representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }
}
