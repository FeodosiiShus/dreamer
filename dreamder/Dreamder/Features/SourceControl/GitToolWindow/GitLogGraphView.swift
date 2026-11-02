import SwiftUI

enum GitLogGraphPalette {
    static let colors: [Color] = [
        Color(hex: 0x70AEFF),
        Color(hex: 0x73BD79),
        Color(hex: 0xD69A6B),
        Color(hex: 0xB188EB),
        Color(hex: 0xE88F89),
        Color(hex: 0x62B5C8),
        Color(hex: 0xE1C25E),
        Color(hex: 0xA1A3AB)
    ]

    static func color(forLane lane: Int) -> Color {
        colors[((lane % colors.count) + colors.count) % colors.count]
    }
}

struct GitLogGraphRowView: View {
    let row: GitLogGraphRow
    let laneCount: Int
    let laneWidth: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            for edge in row.edges {
                let startX = centerX(of: edge.fromLane)
                let endX = centerX(of: edge.toLane)
                var path = Path()
                if edge.fromLane == edge.toLane {
                    path.move(to: CGPoint(x: startX, y: edge.fromLane == row.lane ? middle : 0))
                    path.addLine(to: CGPoint(x: endX, y: size.height))
                } else {
                    path.move(to: CGPoint(x: startX, y: middle))
                    let controlY = middle + (size.height - middle) * 0.55
                    path.addCurve(
                        to: CGPoint(x: endX, y: size.height),
                        control1: CGPoint(x: startX, y: controlY),
                        control2: CGPoint(x: endX, y: controlY)
                    )
                }
                let color = GitLogGraphPalette.color(
                    forLane: edge.fromLane == edge.toLane ? edge.fromLane : edge.toLane
                )
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }

            let dot = CGRect(x: centerX(of: row.lane) - 3, y: middle - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: dot), with: .color(GitLogGraphPalette.color(forLane: row.lane)))
            context.stroke(Path(ellipseIn: dot), with: .color(Islands.island), lineWidth: 1)
        }
        .frame(width: max(CGFloat(laneCount), 1) * laneWidth, height: rowHeight)
    }

    private func centerX(of lane: Int) -> CGFloat {
        laneWidth / 2 + CGFloat(lane) * laneWidth
    }
}
