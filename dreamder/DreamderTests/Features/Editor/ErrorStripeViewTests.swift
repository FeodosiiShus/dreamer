import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ErrorStripeViewTests {
    private static let trackHeight: CGFloat = 200
    private static let lineCount = 100

    private struct Fixture {
        let window: NSWindow
        let container: NSView
        let stripe: ErrorStripeView
    }

    private func makeFixture() -> Fixture {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: Self.trackHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: Self.trackHeight))
        window.contentView = container
        let stripe = ErrorStripeView(frame: NSRect(
            x: 100 - ErrorStripeView.stripWidth,
            y: 0,
            width: ErrorStripeView.stripWidth,
            height: Self.trackHeight
        ))
        container.addSubview(stripe)
        stripe.lineCount = Self.lineCount
        stripe.marks = [
            ErrorStripeMark(line: 10, severity: .error),
            ErrorStripeMark(line: 50, severity: .warning),
            ErrorStripeMark(line: 90, severity: .information),
            ErrorStripeMark(line: 70, severity: .hint),
        ]
        return Fixture(window: window, container: container, stripe: stripe)
    }

    private func click(_ stripe: ErrorStripeView, atY y: CGFloat) throws {
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: stripe.convert(NSPoint(x: 5, y: y), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: stripe.window?.windowNumber ?? 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        stripe.mouseDown(with: event)
    }

    private func pixel(_ stripe: ErrorStripeView, atY y: CGFloat) throws -> NSColor {
        let width = Int(stripe.bounds.width.rounded(.up))
        let height = Int(stripe.bounds.height.rounded(.up))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
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
            stripe.draw(stripe.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        #expect(drawn)
        let offset = (Int(y) * width + 5) * 4
        let alpha = CGFloat(bytes[offset + 3]) / 255
        let divisor = max(alpha, 0.0001) * 255
        return NSColor(
            srgbRed: CGFloat(bytes[offset]) / divisor,
            green: CGFloat(bytes[offset + 1]) / divisor,
            blue: CGFloat(bytes[offset + 2]) / divisor,
            alpha: alpha
        )
    }

    private func expect(_ color: NSColor, matches expected: Color, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let expectedColor = try #require(NSColor(expected).usingColorSpace(.sRGB))
        #expect(color.alphaComponent > 0.9, sourceLocation: sourceLocation)
        #expect(abs(color.redComponent - expectedColor.redComponent) < 0.02, sourceLocation: sourceLocation)
        #expect(abs(color.greenComponent - expectedColor.greenComponent) < 0.02, sourceLocation: sourceLocation)
        #expect(abs(color.blueComponent - expectedColor.blueComponent) < 0.02, sourceLocation: sourceLocation)
    }

    @Test
    func viewIsFrameManagedAndFlipped() {
        let fixture = makeFixture()
        #expect(fixture.stripe.translatesAutoresizingMaskIntoConstraints == false)
        #expect(fixture.stripe.isFlipped)
        #expect(fixture.stripe.isOpaque == false)
        #expect(fixture.stripe.constraints.isEmpty)
        #expect(ErrorStripeView.stripWidth == 10)
    }

    @Test
    func coderInitializerFails() {
        #expect(ErrorStripeView(coder: NSKeyedArchiver(requiringSecureCoding: false)) == nil)
    }

    @Test
    func segmentsMatchTheLayoutOfTheCurrentBounds() {
        let stripe = makeFixture().stripe
        let expected = ErrorStripeLayout.segments(
            marks: stripe.marks,
            lineCount: Self.lineCount,
            trackHeight: Self.trackHeight
        )
        #expect(stripe.segments == expected)
        #expect(stripe.segments.map(\.severity) == [.error, .warning, .information])
        #expect(stripe.segments.map(\.y) == [20, 100, 180])
    }

    @Test
    func segmentsFollowTheFrameHeight() {
        let stripe = makeFixture().stripe
        stripe.frame.size.height = 100
        #expect(stripe.segments.map(\.y) == [10, 50, 90])
    }

    @Test
    func hitTestAcceptsOnlyPointsInsideTheStrip() {
        let fixture = makeFixture()
        #expect(fixture.stripe.hitTest(NSPoint(x: 95, y: 10)) === fixture.stripe)
        #expect(fixture.stripe.hitTest(NSPoint(x: 50, y: 10)) == nil)
        #expect(ErrorStripeView(frame: NSRect(x: 0, y: 0, width: 10, height: 10)).hitTest(.zero) == nil)
    }

    @Test
    func clickOnSegmentSelectsItsLine() throws {
        let fixture = makeFixture()
        var selected: [Int] = []
        fixture.stripe.onSelect = { selected.append($0) }
        try click(fixture.stripe, atY: 21)
        try click(fixture.stripe, atY: 101)
        try click(fixture.stripe, atY: 183)
        #expect(selected == [10, 50, 90])
    }

    @Test
    func clickOnEmptyTrackSelectsNothing() throws {
        let fixture = makeFixture()
        var selected: [Int] = []
        fixture.stripe.onSelect = { selected.append($0) }
        try click(fixture.stripe, atY: 60)
        try click(fixture.stripe, atY: 140)
        #expect(selected.isEmpty)
    }

    @Test
    func clickWithoutHandlerIsHarmless() throws {
        let fixture = makeFixture()
        try click(fixture.stripe, atY: 21)
        #expect(fixture.stripe.onSelect == nil)
    }

    @Test
    func drawsSeveritiesOverSubtleTrack() throws {
        let fixture = makeFixture()
        let stripe = fixture.stripe
        try expect(try pixel(stripe, atY: 21), matches: Islands.errorForeground)
        try expect(try pixel(stripe, atY: 101), matches: Islands.warningForeground)
        try expect(try pixel(stripe, atY: 181), matches: Islands.link)
        try expect(try pixel(stripe, atY: 60), matches: Islands.islandRaised)
        try expect(try pixel(stripe, atY: 141), matches: Islands.islandRaised)
    }

    @Test
    func emptyStripeDrawsOnlyTheTrack() throws {
        let fixture = makeFixture()
        let stripe = fixture.stripe
        stripe.marks = []
        try expect(try pixel(stripe, atY: 21), matches: Islands.islandRaised)
        stripe.marks = [ErrorStripeMark(line: 10, severity: .error)]
        stripe.lineCount = 0
        try expect(try pixel(stripe, atY: 21), matches: Islands.islandRaised)
    }
}
