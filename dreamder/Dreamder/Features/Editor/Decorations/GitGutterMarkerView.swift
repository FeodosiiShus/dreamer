import AppKit
import CodeEditTextView
import SwiftUI

final class GitGutterMarkerView: NSView {
    static let stripWidth: CGFloat = 12

    private static let barWidth: CGFloat = 3
    private static let barRightInset: CGFloat = 5
    private static let triangleWidth: CGFloat = 7
    private static let triangleHeight: CGFloat = 5
    private static let hitTolerance: CGFloat = 4

    private static let addedColor = NSColor(srgbRed: 0x54 / 255, green: 0x91 / 255, blue: 0x59 / 255, alpha: 1)
    private static let modifiedColor = NSColor(srgbRed: 0x37 / 255, green: 0x5F / 255, blue: 0xAD / 255, alpha: 1)
    private static let deletedColor = NSColor(srgbRed: 0x86 / 255, green: 0x8A / 255, blue: 0x91 / 255, alpha: 1)

    weak var textView: TextView?

    var changes: [GitLineChange] = [] {
        didSet {
            rebuildIndexes()
            needsDisplay = true
        }
    }

    var previousContent: ((GitLineChange) -> String?)?
    var rollback: ((GitLineChange) -> Void)?
    var showDiff: ((GitLineChange) -> Void)?

    private var lineMarkers: [Int: GitLineChange] = [:]
    private var boundaryMarkers: [Int: GitLineChange] = [:]
    private var popover: NSPopover?

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override func viewWillDraw() {
        syncFrameWithSuperview()
        super.viewWillDraw()
    }

    private func syncFrameWithSuperview() {
        guard let superview else { return }
        let expected = NSRect(
            x: max(0, superview.bounds.width - Self.stripWidth),
            y: 0,
            width: Self.stripWidth,
            height: superview.bounds.height
        )
        guard frame != expected else { return }
        frame = expected
        needsDisplay = true
    }

    private var barX: CGFloat {
        bounds.width - Self.barRightInset - Self.barWidth
    }

    private func rebuildIndexes() {
        lineMarkers.removeAll()
        boundaryMarkers.removeAll()
        for change in changes {
            if let newLines = change.newLines {
                for line in newLines {
                    lineMarkers[line] = change
                }
            } else {
                boundaryMarkers[change.anchorLine] = change
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let layoutManager = textView?.layoutManager else {
            return
        }
        if let change = boundaryMarkers[0] {
            drawDeletionTriangle(context: context, change: change, boundaryY: 0)
        }
        let minY = max(0, dirtyRect.minY)
        let maxY = max(minY, dirtyRect.maxY)
        for line in layoutManager.linesStartingAt(minY, until: maxY) {
            let lineNumber = line.index + 1
            if let change = lineMarkers[lineNumber] {
                context.setFillColor(color(for: change.kind).cgColor)
                let rect = CGRect(
                    x: barX,
                    y: line.yPos + 1,
                    width: Self.barWidth,
                    height: max(1, line.height - 2)
                ).pixelAligned
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                context.fillPath()
            }
            if let change = boundaryMarkers[lineNumber] {
                drawDeletionTriangle(context: context, change: change, boundaryY: line.yPos + line.height)
            }
        }
    }

    private func color(for kind: GitLineChange.Kind) -> NSColor {
        switch kind {
        case .added:
            return Self.addedColor
        case .modified:
            return Self.modifiedColor
        case .deleted:
            return Self.deletedColor
        }
    }

    private func drawDeletionTriangle(context: CGContext, change: GitLineChange, boundaryY: CGFloat) {
        context.setFillColor(Self.deletedColor.cgColor)
        let centerX = barX + Self.barWidth / 2
        let tipY = max(boundaryY, Self.triangleHeight)
        let topY = tipY - Self.triangleHeight
        let halfWidth = Self.triangleWidth / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: centerX - halfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX + halfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX, y: tipY))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint), change(at: localPoint) != nil else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = change(at: point) else { return }
        presentPopover(for: hit.change, relativeTo: hit.rect)
    }

    private func change(at point: NSPoint) -> (change: GitLineChange, rect: NSRect)? {
        guard let layoutManager = textView?.layoutManager else { return nil }
        var best: (change: GitLineChange, rect: NSRect, distance: CGFloat)?
        let rectHeight: CGFloat = 2

        func consider(_ change: GitLineChange?, boundaryY: CGFloat) {
            guard let change else { return }
            let distance = abs(point.y - boundaryY)
            guard distance <= Self.hitTolerance else { return }
            guard best == nil || distance < (best?.distance ?? .greatestFiniteMagnitude) else { return }
            best = (
                change,
                NSRect(x: 0, y: boundaryY - rectHeight / 2, width: bounds.width, height: rectHeight),
                distance
            )
        }

        consider(boundaryMarkers[0], boundaryY: 0)
        guard let line = layoutManager.textLineForPosition(point.y) else { return best.map { ($0.change, $0.rect) } }
        consider(boundaryMarkers[line.index + 1], boundaryY: line.yPos + line.height)
        consider(boundaryMarkers[line.index], boundaryY: line.yPos)
        if let change = lineMarkers[line.index + 1] {
            return (change, NSRect(x: 0, y: line.yPos, width: bounds.width, height: line.height))
        }
        return best.map { ($0.change, $0.rect) }
    }

    private func presentPopover(for change: GitLineChange, relativeTo rect: NSRect) {
        popover?.close()
        let content = GitHunkPopoverView(
            title: Self.title(for: change),
            previousText: previousContent?(change),
            onRollback: { [weak self] in
                self?.popover?.close()
                self?.rollback?(change)
            },
            onShowDiff: { [weak self] in
                self?.popover?.close()
                self?.showDiff?(change)
            }
        )
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxX)
        self.popover = popover
    }

    private static func title(for change: GitLineChange) -> String {
        switch change.kind {
        case .added:
            let count = change.newLines?.count ?? 0
            return count == 1 ? "Added 1 line" : "Added \(count) lines"
        case .modified:
            let count = change.newLines?.count ?? 0
            return count == 1 ? "Modified 1 line" : "Modified \(count) lines"
        case .deleted:
            let count = change.oldLines?.count ?? 0
            return count == 1 ? "Deleted 1 line" : "Deleted \(count) lines"
        }
    }
}
