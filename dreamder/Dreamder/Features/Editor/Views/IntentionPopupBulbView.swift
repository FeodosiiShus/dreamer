import AppKit

final class IntentionPopupBulbView: NSView {
    static let size = CGSize(width: 16, height: 16)
    static let iconName = "codeInsight/quickfixBulb"
    static let hoverAlpha: CGFloat = 0.1

    var onActivate: (() -> Void)?

    private let icon = IntelliJIcon.nsImage(IntentionPopupBulbView.iconName)
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: frameRect.origin, size: Self.size))
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            NSColor.white.withAlphaComponent(Self.hoverAlpha).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        }
        icon?.draw(in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }
}
