import SwiftUI

enum GitLogGraphPalette {
    static func color(forColorId colorId: Int) -> Color {
        guard colorId != GitLogGraphColorGetter.defaultColorId else {
            return Color(hex: 0xA1A3AB)
        }
        return Color(hue: GitLogGraphColors.hue(forColorId: colorId), saturation: 0.5, brightness: 0.88)
    }
}

struct GitLogGraphRowView: View {
    let row: GitLogGraphRow
    let laneCount: Int
    let laneWidth: CGFloat
    let rowHeight: CGFloat

    private var lineWidth: CGFloat { 1.5 }
    private var circleRadius: CGFloat { 3.5 }
    private var arrowLength: CGFloat { 0.3 }
    private var arrowCosSquared: CGFloat { 0.7 }

    var body: some View {
        Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            let middle = size.height / 2

            for element in row.elements {
                if case .edge(let edge) = element {
                    draw(edge, in: &context, size: size, middle: middle)
                }
            }
            for element in row.elements {
                if case .node(let node) = element {
                    draw(node, in: &context, middle: middle)
                }
            }
        }
        .frame(width: max(CGFloat(laneCount), 1) * laneWidth, height: rowHeight)
    }

    private func centerX(of lane: Int) -> CGFloat {
        laneWidth / 2 + CGFloat(lane) * laneWidth
    }

    private func draw(_ edge: GitLogEdgePrintElement, in context: inout GraphicsContext, size: CGSize, middle: CGFloat) {
        let isDown = edge.direction == .down
        let startX = centerX(of: edge.positionInCurrentRow)
        let endX = centerX(of: edge.positionInOtherRow)
        let endY: CGFloat
        let arrowPoint: CGPoint
        if edge.positionInCurrentRow == edge.positionInOtherRow {
            let gap = edge.isTerminal ? circleRadius / 2 + 1 : 0
            endY = isDown ? size.height - gap : gap
            arrowPoint = CGPoint(x: startX, y: endY)
        } else {
            endY = isDown ? size.height + middle : middle - size.height
            arrowPoint = CGPoint(x: (startX + endX) / 2, y: (middle + endY) / 2)
        }

        var path = Path()
        path.move(to: CGPoint(x: startX, y: middle))
        path.addLine(to: CGPoint(x: endX, y: endY))

        let color = GitLogGraphPalette.color(forColorId: edge.colorId)
        let style = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: edge.lineStyle == .dashed && !edge.hasArrow ? [3, 3] : []
        )
        context.stroke(path, with: .color(color), style: style)

        if edge.hasArrow {
            drawArrow(
                from: CGPoint(x: startX, y: middle),
                at: arrowPoint,
                color: color,
                in: &context
            )
        }
    }

    private func drawArrow(from origin: CGPoint, at tip: CGPoint, color: Color, in context: inout GraphicsContext) {
        let dx = origin.x - tip.x
        let dy = origin.y - tip.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return }
        let length = arrowLength * rowHeight
        let scaleX = length * dx / distance
        let scaleY = length * dy / distance
        let cosine = arrowCosSquared.squareRoot()
        let sine = (1 - arrowCosSquared).squareRoot()

        var path = Path()
        for sign in [CGFloat(1), CGFloat(-1)] {
            let rotatedX = scaleX * cosine - scaleY * sine * sign
            let rotatedY = scaleX * sine * sign + scaleY * cosine
            path.move(to: tip)
            path.addLine(to: CGPoint(x: rotatedX + tip.x, y: rotatedY + tip.y))
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func draw(_ node: GitLogNodePrintElement, in context: inout GraphicsContext, middle: CGFloat) {
        let color = GitLogGraphPalette.color(forColorId: node.colorId)
        let center = CGPoint(x: centerX(of: node.position), y: middle)
        let dot = CGRect(
            x: center.x - circleRadius,
            y: center.y - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2
        )
        if row.isHead {
            context.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(color))
            context.fill(Path(ellipseIn: dot.insetBy(dx: 0.5, dy: 0.5)), with: .color(Islands.island))
            context.fill(Path(ellipseIn: dot.insetBy(dx: 1.5, dy: 1.5)), with: .color(color))
        } else {
            context.fill(Path(ellipseIn: dot), with: .color(color))
            context.stroke(Path(ellipseIn: dot), with: .color(Islands.island), lineWidth: 1)
        }
    }
}
