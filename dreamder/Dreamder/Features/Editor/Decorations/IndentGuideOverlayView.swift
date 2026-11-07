import AppKit
import CodeEditTextView

final class IndentGuideOverlayView: NSView {
    private static let guideColor = NSColor(srgbRed: 0x32 / 255, green: 0x34 / 255, blue: 0x38 / 255, alpha: 1)
    private static let activeGuideColor = NSColor(srgbRed: 0x4E / 255, green: 0x51 / 255, blue: 0x57 / 255, alpha: 1)
    private static let inheritScanLimit = 200
    private static let blockScanLimit = 400

    weak var textView: TextView?
    var tabWidth: Int = 4

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        autoresizingMask = [.width, .height]
        if frame != superview.bounds {
            frame = superview.bounds
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let storage = textView.textStorage,
              storage.length > 0,
              tabWidth > 0,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let text = storage.string as NSString
        let charWidth = (" " as NSString).size(withAttributes: [.font: textView.font]).width
        guard charWidth > 0 else { return }
        let inset = layoutManager.edgeInsets.left
        let caret = caretBlock(layoutManager: layoutManager, text: text)

        let minY = max(0, dirtyRect.minY)
        let maxY = max(minY, dirtyRect.maxY)
        for line in layoutManager.linesStartingAt(minY, until: maxY) {
            let level = indentationLevel(lineIndex: line.index, layoutManager: layoutManager, text: text)
            guard level > 0 else { continue }
            let isActiveLine = caret.map { $0.lines.contains(line.index + 1) } ?? false
            for depth in 1...level {
                let x = (inset + CGFloat(depth * tabWidth) * charWidth).rounded() - 0.5
                let isActive = isActiveLine && caret?.level == depth
                context.setStrokeColor((isActive ? Self.activeGuideColor : Self.guideColor).cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: x, y: line.yPos))
                context.addLine(to: CGPoint(x: x, y: line.yPos + line.height))
                context.strokePath()
            }
        }
    }

    private func caretBlock(
        layoutManager: TextLayoutManager,
        text: NSString
    ) -> (level: Int, lines: ClosedRange<Int>)? {
        guard let selection = textView?.selectionManager.textSelections.first,
              let caretLine = layoutManager.textLineForOffset(selection.range.location) else {
            return nil
        }
        let caretIndex = caretLine.index
        let level = indentationLevel(lineIndex: caretIndex, layoutManager: layoutManager, text: text)
        guard level > 0 else { return nil }

        var lower = caretIndex
        var upper = caretIndex
        var scanned = 0
        while lower > 0, scanned < Self.blockScanLimit {
            let previous = indentationLevel(lineIndex: lower - 1, layoutManager: layoutManager, text: text)
            if previous < level { break }
            lower -= 1
            scanned += 1
        }
        scanned = 0
        while upper + 1 < layoutManager.lineCount, scanned < Self.blockScanLimit {
            let next = indentationLevel(lineIndex: upper + 1, layoutManager: layoutManager, text: text)
            if next < level { break }
            upper += 1
            scanned += 1
        }
        return (level, (lower + 1)...(upper + 1))
    }

    private func indentationLevel(lineIndex: Int, layoutManager: TextLayoutManager, text: NSString) -> Int {
        var index = lineIndex
        var scanned = 0
        while index >= 0, scanned <= Self.inheritScanLimit {
            guard let line = layoutManager.textLineForIndex(index) else { return 0 }
            let content = Self.lineContent(in: line.range, text: text)
            if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                return IndentGuides.indentationColumns(of: content, tabWidth: tabWidth) / tabWidth
            }
            guard index > 0 else { return 0 }
            index -= 1
            scanned += 1
        }
        return 0
    }

    nonisolated static func lineContent(in range: NSRange, text: NSString) -> String {
        guard range.location >= 0,
              range.length > 0,
              range.location <= text.length,
              range.length <= text.length - range.location else {
            return ""
        }
        let end = range.location + range.length
        var length = range.length
        let last = text.character(at: end - 1)
        if last == 0x0A || last == 0x0D {
            length -= 1
            if length > 0, last == 0x0A, text.character(at: end - 2) == 0x0D {
                length -= 1
            }
        }
        guard length > 0 else { return "" }
        return text.substring(with: NSRange(location: range.location, length: length))
    }
}
