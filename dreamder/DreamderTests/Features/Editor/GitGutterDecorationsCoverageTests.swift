import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class GitGutterCoverageChangeLog {
    var rollbacks: [GitLineChange] = []
    var diffs: [GitLineChange] = []
}

@MainActor
@Suite(.uiGate)
struct GitGutterDecorationsCoverageTests {
    private static let source = (1...14).map { "line\($0)" }.joined(separator: "\n") + "\n"

    private static let added = GitLineChange(kind: .added, oldLines: nil, newLines: 2...2, anchorLine: 2)
    private static let modifiedBlock = GitLineChange(kind: .modified, oldLines: 4...6, newLines: 4...6, anchorLine: 4)
    private static let modifiedSingle = GitLineChange(kind: .modified, oldLines: 8...8, newLines: 8...8, anchorLine: 8)
    private static let addedPair = GitLineChange(kind: .added, oldLines: nil, newLines: 10...11, anchorLine: 10)
    private static let deletedSingle = GitLineChange(kind: .deleted, oldLines: 20...20, newLines: nil, anchorLine: 12)
    private static let deletedAtTop = GitLineChange(kind: .deleted, oldLines: 30...31, newLines: nil, anchorLine: 0)

    private func gutterSession(
        in directory: URL
    ) async throws -> (session: DecorationsCoverageSession, marker: GitGutterMarkerView, gutter: GutterView) {
        let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
            [fixture.document.contentCoordinator]
        }
        let gutter = try #require(session.hosted.views(ofType: GutterView.self).first)
        let marker = GitGutterMarkerView(frame: .zero)
        marker.textView = session.textView
        gutter.addSubview(marker)
        marker.viewWillDraw()
        return (session, marker, gutter)
    }

    private func middle(of lineNumber: Int, in session: DecorationsCoverageSession) throws -> CGFloat {
        let line = try #require(session.textView.layoutManager.textLineForIndex(lineNumber - 1))
        return line.yPos + line.height / 2
    }

    private func bottom(of lineNumber: Int, in session: DecorationsCoverageSession) throws -> CGFloat {
        let line = try #require(session.textView.layoutManager.textLineForIndex(lineNumber - 1))
        return line.yPos + line.height
    }

    private func click(_ marker: GitGutterMarkerView, atY y: CGFloat) throws {
        let windowPoint = marker.convert(NSPoint(x: 6, y: y), to: nil)
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: windowPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: marker.window?.windowNumber ?? 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        marker.mouseDown(with: event)
    }

    private func hunkView(of marker: GitGutterMarkerView) throws -> GitHunkPopoverView {
        let popover = try #require(marker.popover)
        let controller = try #require(popover.contentViewController as? NSHostingController<GitHunkPopoverView>)
        return controller.rootView
    }

    private func expect(
        _ pixel: MarkerPixels.Pixel?,
        matches hex: UInt32,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let pixel else {
            Issue.record("missing pixel", sourceLocation: sourceLocation)
            return
        }
        let tolerance: CGFloat = 3.0 / 255
        #expect(pixel.alpha > 0.99, sourceLocation: sourceLocation)
        #expect(abs(pixel.red - CGFloat((hex >> 16) & 0xFF) / 255) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(pixel.green - CGFloat((hex >> 8) & 0xFF) / 255) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(pixel.blue - CGFloat(hex & 0xFF) / 255) < tolerance, sourceLocation: sourceLocation)
    }

    @Test
    func markerPinsItselfToTheRightEdgeOfItsSuperviewBeforeDrawing() async throws {
        try await withTempDir { directory in
            let (session, marker, gutter) = try await gutterSession(in: directory)
            defer { session.close() }
            let expected = NSRect(
                x: gutter.bounds.width - GitGutterMarkerView.stripWidth,
                y: 0,
                width: GitGutterMarkerView.stripWidth,
                height: gutter.bounds.height
            )
            #expect(marker.frame == expected)

            marker.frame = NSRect(x: 0, y: 0, width: 3, height: 3)
            marker.viewWillDraw()
            #expect(marker.frame == expected)
        }
    }

    @Test
    func markerRepinsItselfToItsSuperviewEveryTimeItWillDraw() {
        let superview = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 50))
        let marker = GitGutterMarkerView(frame: .zero)
        superview.addSubview(marker)

        marker.viewWillDraw()
        #expect(marker.frame == NSRect(x: 68, y: 0, width: GitGutterMarkerView.stripWidth, height: 50))

        marker.viewWillDraw()
        #expect(marker.frame == NSRect(x: 68, y: 0, width: GitGutterMarkerView.stripWidth, height: 50))

        superview.setFrameSize(NSSize(width: 8, height: 30))
        marker.viewWillDraw()
        #expect(marker.frame == NSRect(x: 0, y: 0, width: GitGutterMarkerView.stripWidth, height: 30))
    }

    @Test
    func markerPaintsChangeBarsAndDeletionTriangles() async throws {
        try await withTempDir { directory in
            let (session, marker, _) = try await gutterSession(in: directory)
            defer { session.close() }
            let deletionBelowLineNine = GitLineChange(kind: .deleted, oldLines: 3...3, newLines: nil, anchorLine: 9)
            marker.changes = [
                Self.added,
                Self.modifiedBlock,
                deletionBelowLineNine,
                Self.deletedAtTop
            ]

            let pixels = try #require(MarkerPixels(drawing: marker))
            let barX = 5
            let addedHex: UInt32 = 0x549159
            let modifiedHex: UInt32 = 0x375FAD
            let deletedHex: UInt32 = 0x868A91

            expect(pixels.pixel(x: barX, y: Int(try middle(of: 2, in: session))), matches: addedHex)
            expect(pixels.pixel(x: barX, y: Int(try middle(of: 4, in: session))), matches: modifiedHex)
            expect(pixels.pixel(x: barX, y: Int(try middle(of: 6, in: session))), matches: modifiedHex)
            expect(pixels.pixel(x: barX, y: Int(try bottom(of: 9, in: session)) - 2), matches: deletedHex)
            expect(pixels.pixel(x: barX, y: 3), matches: deletedHex)
            let untouched = pixels.pixel(x: barX, y: Int(try middle(of: 12, in: session)))
            #expect(untouched?.alpha == 0)
            let leftOfTheBar = pixels.pixel(x: 1, y: Int(try middle(of: 2, in: session)))
            #expect(leftOfTheBar?.alpha == 0)
        }
    }

    @Test
    func markerWithoutATextViewDrawsNothing() throws {
        let marker = GitGutterMarkerView(frame: NSRect(x: 0, y: 0, width: 12, height: 40))
        marker.changes = [Self.added]

        let pixels = try #require(MarkerPixels(drawing: marker))

        #expect(pixels.pixel(x: 5, y: 5)?.alpha == 0)
    }

    @Test
    func hitTestAcceptsOnlyPointsOnAChangeInsideTheStrip() async throws {
        try await withTempDir { directory in
            let (session, marker, gutter) = try await gutterSession(in: directory)
            defer { session.close() }
            marker.changes = [Self.added, Self.deletedAtTop]
            @MainActor func inGutter(x: CGFloat, y: CGFloat) -> NSPoint {
                marker.convert(NSPoint(x: x, y: y), to: gutter)
            }

            let changedY = try middle(of: 2, in: session)
            let plainY = try middle(of: 7, in: session)

            #expect(marker.hitTest(inGutter(x: 6, y: changedY)) === marker)
            #expect(marker.hitTest(inGutter(x: 6, y: 1)) === marker)
            #expect(marker.hitTest(inGutter(x: 6, y: plainY)) == nil)
            #expect(marker.hitTest(inGutter(x: -5, y: changedY)) == nil)
            #expect(gutter.subviews.contains(marker))
        }
    }

    @Test
    func hitTestWithoutASuperviewHitsNothing() {
        let marker = GitGutterMarkerView(frame: NSRect(x: 0, y: 0, width: 12, height: 40))
        marker.changes = [Self.added]

        #expect(marker.hitTest(NSPoint(x: 6, y: 5)) == nil)
    }

    @Test
    func clickingWithoutATextViewOrBelowTheLastLinePresentsNothing() async throws {
        try await withTempDir { directory in
            let (session, marker, _) = try await gutterSession(in: directory)
            defer { session.close() }
            marker.changes = [Self.added]

            try click(marker, atY: marker.bounds.height - 4)
            #expect(marker.popover == nil)

            marker.textView = nil
            try click(marker, atY: try middle(of: 2, in: session))
            #expect(marker.popover == nil)
        }
    }

    @Test
    func clickingAChangePresentsAPopoverDescribingItAndItsPreviousContent() async throws {
        try await withTempDir { directory in
            let (session, marker, _) = try await gutterSession(in: directory)
            defer {
                marker.popover?.close()
                session.close()
            }
            marker.changes = [
                Self.added,
                Self.modifiedBlock,
                Self.modifiedSingle,
                Self.addedPair,
                Self.deletedSingle,
                Self.deletedAtTop
            ]
            marker.previousContent = { "old \($0.anchorLine)" }

            try click(marker, atY: try middle(of: 1, in: session))
            #expect(marker.popover == nil)

            let cases: [(CGFloat, GitLineChange, String)] = [
                (try middle(of: 2, in: session), Self.added, "Added 1 line"),
                (try middle(of: 5, in: session), Self.modifiedBlock, "Modified 3 lines"),
                (try middle(of: 8, in: session), Self.modifiedSingle, "Modified 1 line"),
                (try middle(of: 10, in: session), Self.addedPair, "Added 2 lines"),
                (try bottom(of: 12, in: session) - 1, Self.deletedSingle, "Deleted 1 line"),
                (1, Self.deletedAtTop, "Deleted 2 lines")
            ]
            for (y, change, title) in cases {
                try click(marker, atY: y)
                let content = try hunkView(of: marker)
                #expect(content.title == title)
                #expect(content.previousText == "old \(change.anchorLine)")
            }
        }
    }

    @Test
    func popoverButtonsInvokeRollbackAndShowDiffAndCloseThePopover() async throws {
        try await withTempDir { directory in
            let (session, marker, _) = try await gutterSession(in: directory)
            defer { session.close() }
            let log = GitGutterCoverageChangeLog()
            marker.changes = [Self.modifiedBlock]
            marker.rollback = { log.rollbacks.append($0) }
            marker.showDiff = { log.diffs.append($0) }

            try click(marker, atY: try middle(of: 5, in: session))
            let first = try #require(marker.popover)
            try hunkView(of: marker).onRollback()
            #expect(log.rollbacks == [Self.modifiedBlock])
            #expect(log.diffs.isEmpty)
            #expect(!first.isShown)

            try click(marker, atY: try middle(of: 5, in: session))
            let second = try #require(marker.popover)
            try hunkView(of: marker).onShowDiff()
            #expect(log.diffs == [Self.modifiedBlock])
            #expect(!second.isShown)
        }
    }

    @Test
    func popoverWithoutPreviousContentCallbacksStillOpens() async throws {
        try await withTempDir { directory in
            let (session, marker, _) = try await gutterSession(in: directory)
            defer {
                marker.popover?.close()
                session.close()
            }
            marker.changes = [Self.added]

            try click(marker, atY: try middle(of: 2, in: session))
            let content = try hunkView(of: marker)
            content.onRollback()
            content.onShowDiff()

            #expect(content.previousText == nil)
            #expect(content.title == "Added 1 line")
        }
    }

    @Test
    func popoverViewRendersPreviousContentOrAPlaceholder() async throws {
        let withText = HostedViewFixture.host(size: NSSize(width: 400, height: 300)) {
            GitHunkPopoverView(
                title: "Modified 1 line",
                previousText: "let previous = 1\nlet other = 2",
                onRollback: {},
                onShowDiff: {}
            )
        }
        defer { withText.close() }
        let withoutText = HostedViewFixture.host(size: NSSize(width: 400, height: 300)) {
            GitHunkPopoverView(title: "Modified 1 line", previousText: nil, onRollback: {}, onShowDiff: {})
        }
        defer { withoutText.close() }
        let emptyText = HostedViewFixture.host(size: NSSize(width: 400, height: 300)) {
            GitHunkPopoverView(title: "Modified 1 line", previousText: "", onRollback: {}, onShowDiff: {})
        }
        defer { emptyText.close() }

        try await withText.settle(.milliseconds(100))
        try await withoutText.settle(.milliseconds(100))
        try await emptyText.settle(.milliseconds(100))

        #expect(withText.renders())
        #expect(withoutText.renders())
        #expect(emptyText.renders())
        #expect(HostedView.pixelsDiffer(withText.snapshot(), withoutText.snapshot()))
    }
}

@MainActor
struct MarkerPixels {
    struct Pixel {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(drawing marker: GitGutterMarkerView) {
        let width = Int(marker.bounds.width.rounded(.up))
        let height = Int(marker.bounds.height.rounded(.up))
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            marker.draw(marker.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> Pixel? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        return Pixel(
            red: CGFloat(bytes[offset]) / 255,
            green: CGFloat(bytes[offset + 1]) / 255,
            blue: CGFloat(bytes[offset + 2]) / 255,
            alpha: CGFloat(bytes[offset + 3]) / 255
        )
    }
}
