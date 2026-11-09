import AppKit
import SwiftUI

final class ErrorStripeView: NSView {
    static let stripWidth: CGFloat = 10

    private static let markInset: CGFloat = 2
    private static let trackColor = NSColor(Islands.islandRaised)
    private static let errorColor = NSColor(Islands.errorForeground)
    private static let warningColor = NSColor(Islands.warningForeground)
    private static let informationColor = NSColor(Islands.link)

    var marks: [ErrorStripeMark] = [] {
        didSet { needsDisplay = true }
    }

    var lineCount: Int = 0 {
        didSet { needsDisplay = true }
    }

    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var segments: [ErrorStripeLayout.Segment] {
        ErrorStripeLayout.segments(marks: marks, lineCount: lineCount, trackHeight: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.trackColor.setFill()
        bounds.fill()
        for segment in segments {
            Self.color(for: segment.severity).setFill()
            NSRect(
                x: Self.markInset,
                y: segment.y,
                width: max(bounds.width - Self.markInset * 2, 0),
                height: segment.height
            ).fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let line = ErrorStripeLayout.line(
            atY: point.y,
            trackHeight: bounds.height,
            lineCount: lineCount,
            segments: segments
        ) else { return }
        onSelect?(line)
    }

    private static func color(for severity: WorkspaceDiagnostic.Severity) -> NSColor {
        switch severity {
        case .error: errorColor
        case .warning: warningColor
        case .information, .hint: informationColor
        }
    }
}
