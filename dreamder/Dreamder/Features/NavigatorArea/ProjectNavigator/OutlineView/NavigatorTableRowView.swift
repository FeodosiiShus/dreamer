import SwiftUI
import AppKit

final class NavigatorTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        let rect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: Islands.rowRadius, yRadius: Islands.rowRadius)
        (isEmphasized ? NSColor(Islands.selection) : NSColor(Islands.selectionInactive)).setFill()
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {}
}
