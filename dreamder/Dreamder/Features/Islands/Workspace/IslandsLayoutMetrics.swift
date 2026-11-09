import CoreGraphics

nonisolated struct IslandsLayoutMetrics: Equatable, Sendable {
    let gap: CGFloat
    let radius: CGFloat

    static let compact = IslandsLayoutMetrics(gap: 4, radius: 8)
    static let regular = IslandsLayoutMetrics(gap: 6, radius: 10)

    static func make(isCompact: Bool) -> IslandsLayoutMetrics {
        isCompact ? .compact : .regular
    }

    nonisolated struct Input: Equatable, Sendable {
        var hasLeft: Bool
        var leftWidth: CGFloat
        var hasBottom: Bool
        var bottomHeight: CGFloat
        var bottomMaximized: Bool
    }

    nonisolated struct Frames: Equatable, Sendable {
        var left: CGRect = .zero
        var leftDivider: CGRect = .zero
        var editor: CGRect = .zero
        var bottomDivider: CGRect = .zero
        var bottom: CGRect = .zero

        var islands: [CGRect] {
            [left, editor, bottom].filter { !$0.isEmpty }
        }

        var dividers: [CGRect] {
            [leftDivider, bottomDivider].filter { !$0.isEmpty }
        }

        func frame(for slot: IslandSlot) -> CGRect {
            switch slot {
            case .left: left
            case .leftDivider: leftDivider
            case .editor: editor
            case .bottomDivider: bottomDivider
            case .bottom: bottom
            }
        }
    }

    func innerSize(of area: CGSize) -> CGSize {
        CGSize(width: max(0, area.width - 2 * gap), height: max(0, area.height - 2 * gap))
    }

    func frames(in area: CGSize, input: Input) -> Frames {
        let inner = CGRect(origin: CGPoint(x: gap, y: gap), size: innerSize(of: area))
        if input.bottomMaximized, input.hasBottom {
            return Frames(bottom: inner)
        }

        let bottomHeight = input.hasBottom
            ? ToolWindowLayout.clampBottomHeight(input.bottomHeight, availableHeight: inner.height)
            : 0
        let upperHeight = max(0, inner.height - (input.hasBottom ? bottomHeight + gap : 0))
        let leftWidth = input.hasLeft
            ? ToolWindowLayout.clampLeftWidth(input.leftWidth, availableWidth: inner.width)
            : 0
        let editorX = inner.minX + (input.hasLeft ? leftWidth + gap : 0)

        var frames = Frames()
        frames.editor = CGRect(x: editorX, y: inner.minY, width: max(0, inner.maxX - editorX), height: upperHeight)
        if input.hasLeft {
            frames.left = CGRect(x: inner.minX, y: inner.minY, width: leftWidth, height: upperHeight)
            frames.leftDivider = CGRect(x: inner.minX + leftWidth, y: inner.minY, width: gap, height: upperHeight)
        }
        if input.hasBottom {
            frames.bottomDivider = CGRect(x: inner.minX, y: inner.minY + upperHeight, width: inner.width, height: gap)
            frames.bottom = CGRect(
                x: inner.minX,
                y: inner.maxY - bottomHeight,
                width: inner.width,
                height: bottomHeight
            )
        }
        return frames
    }
}
