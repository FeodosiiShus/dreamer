import AppKit
import CodeEditTextView

final class GitBlameInlineView: NSView {
    private static let font = NSFont.systemFont(ofSize: Islands.smallFontSize)
    private static let textColor = NSColor(srgbRed: 0x8D / 255, green: 0x91 / 255, blue: 0x99 / 255, alpha: 1)

    private var content: NSAttributedString?

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setText(_ text: String) {
        let content = NSAttributedString(
            string: text,
            attributes: [
                .font: Self.font,
                .foregroundColor: Self.textColor
            ]
        )
        self.content = content
        let size = content.size()
        setFrameSize(NSSize(width: ceil(size.width) + 2, height: ceil(size.height)))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        content?.draw(at: .zero)
    }
}

nonisolated enum GitBlameAnnotationPalette {
    private static let recent = (red: 0x2F, green: 0x51, blue: 0x94)
    private static let old = (red: 0x22, green: 0x25, blue: 0x2E)

    static func tint(ageFraction: Double, alternate: Bool) -> NSColor {
        let fraction = min(max(ageFraction, 0), 1)
        var red = interpolate(recent.red, old.red, fraction)
        var green = interpolate(recent.green, old.green, fraction)
        var blue = interpolate(recent.blue, old.blue, fraction)
        let shift: Double = alternate ? 0.16 : 0
        red += (255 - red) * shift
        green += (255 - green) * shift
        blue += (255 - blue) * shift
        return NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func interpolate(_ start: Int, _ end: Int, _ fraction: Double) -> Double {
        Double(start) + (Double(end) - Double(start)) * fraction
    }
}

final class GitBlameAnnotationView: NSView, NSViewToolTipOwner {
    static let columnWidth: CGFloat = 210

    private static let font = NSFont.systemFont(ofSize: Islands.smallFontSize)
    private static let textColor = NSColor(srgbRed: 0x8D / 255, green: 0x91 / 255, blue: 0x99 / 255, alpha: 1)
    private static let columnColor = NSColor(srgbRed: 0x1E / 255, green: 0x1F / 255, blue: 0x22 / 255, alpha: 1)
    private static let separatorColor = NSColor(srgbRed: 0x32 / 255, green: 0x34 / 255, blue: 0x38 / 255, alpha: 1)

    private weak var textView: TextView?
    private var lines: [Int: GitBlameLine] = [:]
    private var tints: [String: NSColor] = [:]

    var onSelectCommit: (() -> Void)?

    init(textView: TextView) {
        self.textView = textView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func update(lines: [Int: GitBlameLine]) {
        self.lines = lines
        tints = Self.tints(for: lines)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        removeAllToolTips()
        guard newSize.width > 0, newSize.height > 0 else { return }
        addToolTip(bounds, owner: self, userData: nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        let local = convert(point, from: superview)
        return columnRect().contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onSelectCommit?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden, let textView else { return }
        let column = columnRect()
        guard column.width > 0, column.height > 0 else { return }

        Self.columnColor.setFill()
        NSBezierPath(rect: column).fill()

        guard let layoutManager = textView.layoutManager else { return }
        let visible = textView.visibleRect
        guard let start = layoutManager.textLineForPosition(max(visible.minY, 0)) else { return }

        var index = start.index
        let lineCount = layoutManager.lineCount
        while index < lineCount {
            guard let position = layoutManager.textLineForIndex(index) else { break }
            if position.yPos > visible.maxY { break }
            if let blame = lines[index + 1] {
                let tint = tints[blame.commitHash]
                    ?? GitBlameAnnotationPalette.tint(ageFraction: 1, alternate: false)
                let row = textView.convert(
                    CGRect(x: 0, y: position.yPos, width: 1, height: max(position.height, 1)),
                    to: self
                )
                tint.setFill()
                NSBezierPath(
                    rect: NSRect(x: column.minX, y: row.minY, width: column.width, height: row.height)
                ).fill()
                draw(rowText(for: blame), in: NSRect(
                    x: column.minX + 8,
                    y: row.minY,
                    width: column.width - 16,
                    height: row.height
                ))
            }
            index += 1
        }

        Self.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: column.maxX - 1, y: 0, width: 1, height: bounds.height)).fill()
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        guard let blame = line(atViewPoint: point) else { return "" }
        let date = GitBlameRelativeDate.absoluteString(for: blame.authorDate)
        let author = blame.isUncommitted ? "You" : blame.author
        guard !blame.summary.isEmpty else {
            return "\(author), \(date) — \(blame.shortHash)"
        }
        return "\(blame.summary) — \(author), \(date) — \(blame.shortHash)"
    }

    private func columnRect() -> NSRect {
        let leading = max(textView?.textInsets.left ?? 0, 0)
        return NSRect(
            x: leading,
            y: 0,
            width: min(Self.columnWidth, max(bounds.width - leading, 0)),
            height: bounds.height
        )
    }

    private func line(atViewPoint point: NSPoint) -> GitBlameLine? {
        guard let textView else { return nil }
        let converted = convert(point, to: textView)
        guard let position = textView.layoutManager.textLineForPosition(converted.y) else { return nil }
        return lines[position.index + 1]
    }

    private func rowText(for blame: GitBlameLine) -> String {
        guard !blame.isUncommitted else { return "You  uncommitted" }
        return "\(blame.author)  \(GitBlameRelativeDate.string(for: blame.authorDate))"
    }

    private func draw(_ text: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: Self.font,
                .foregroundColor: Self.textColor,
                .paragraphStyle: paragraph
            ]
        )
        let height = ceil(attributed.size().height)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - height / 2,
            width: rect.width,
            height: height
        )
        attributed.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    private static func tints(for lines: [Int: GitBlameLine]) -> [String: NSColor] {
        var dates: [String: Date] = [:]
        var order: [String] = []
        for key in lines.keys.sorted() {
            guard let line = lines[key], !line.isUncommitted else { continue }
            if dates[line.commitHash] == nil {
                dates[line.commitHash] = line.authorDate
                order.append(line.commitHash)
            }
        }

        var tints: [String: NSColor] = [
            GitBlameLine.uncommittedHash: GitBlameAnnotationPalette.tint(ageFraction: 0, alternate: true)
        ]
        guard let newest = dates.values.max(), let oldest = dates.values.min() else { return tints }
        let span = newest.timeIntervalSince(oldest)

        for (index, hash) in order.enumerated() {
            let date = dates[hash] ?? oldest
            let age = span > 0 ? newest.timeIntervalSince(date) / span : 0
            tints[hash] = GitBlameAnnotationPalette.tint(ageFraction: age, alternate: index % 2 == 1)
        }
        return tints
    }
}
