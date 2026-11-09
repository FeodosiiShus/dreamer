import CoreGraphics

nonisolated struct ErrorStripeMark: Equatable, Sendable {
    let line: Int
    let severity: WorkspaceDiagnostic.Severity
}

nonisolated struct ErrorStripeLayout: Sendable {
    nonisolated struct Segment: Equatable, Sendable {
        let y: CGFloat
        let height: CGFloat
        let severity: WorkspaceDiagnostic.Severity
        let lines: [Int]

        var firstLine: Int { lines.first ?? 0 }
        var lastLine: Int { lines.last ?? 0 }
        var maxY: CGFloat { y + height }
    }

    static let defaultMinimumHeight: CGFloat = 2
    static let defaultHitSlop: CGFloat = 3

    static func segments(
        marks: [ErrorStripeMark],
        lineCount: Int,
        trackHeight: CGFloat,
        minimumHeight: CGFloat = defaultMinimumHeight
    ) -> [Segment] {
        guard lineCount > 0, trackHeight > 0 else { return [] }
        let height = min(trackHeight, max(minimumHeight, trackHeight / CGFloat(lineCount)))
        let placed = marks
            .filter { $0.severity != .hint }
            .map { mark -> Segment in
                let line = min(max(mark.line, 0), lineCount - 1)
                let y = min(CGFloat(line) * trackHeight / CGFloat(lineCount), trackHeight - height)
                return Segment(y: y, height: height, severity: mark.severity, lines: [line])
            }
            .sorted { ($0.y, $0.firstLine) < ($1.y, $1.firstLine) }
        var merged: [Segment] = []
        for segment in placed {
            guard let last = merged.last, segment.y <= last.maxY else {
                merged.append(segment)
                continue
            }
            merged[merged.count - 1] = Segment(
                y: last.y,
                height: max(last.maxY, segment.maxY) - last.y,
                severity: min(last.severity, segment.severity),
                lines: Array(Set(last.lines).union(segment.lines)).sorted()
            )
        }
        return merged
    }

    static func line(
        atY y: CGFloat,
        trackHeight: CGFloat,
        lineCount: Int,
        segments: [Segment],
        slop: CGFloat = defaultHitSlop
    ) -> Int? {
        guard lineCount > 0, trackHeight > 0 else { return nil }
        let candidates = segments
            .map { (segment: $0, distance: max($0.y - y, y - $0.maxY, 0)) }
            .filter { $0.distance <= slop }
        guard let hit = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
        let clickLine = y / trackHeight * CGFloat(lineCount)
        return hit.segment.lines.min { abs(CGFloat($0) + 0.5 - clickLine) < abs(CGFloat($1) + 0.5 - clickLine) }
    }
}
