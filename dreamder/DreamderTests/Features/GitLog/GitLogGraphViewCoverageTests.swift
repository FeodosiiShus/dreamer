import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogGraphViewCoverage {
    private func node(position: Int, colorId: Int = 1) -> GitLogPrintElement {
        .node(GitLogNodePrintElement(rowIndex: 0, position: position, nodeIndex: 0, colorId: colorId))
    }

    private func edge(
        from: Int,
        to: Int,
        direction: GitLogEdgeDirection = .down,
        lineStyle: GitLogEdgeLineStyle = .solid,
        hasArrow: Bool = false,
        isTerminal: Bool = false,
        colorId: Int = 1
    ) -> GitLogPrintElement {
        .edge(
            GitLogEdgePrintElement(
                rowIndex: 0,
                positionInCurrentRow: from,
                positionInOtherRow: to,
                direction: direction,
                lineStyle: lineStyle,
                hasArrow: hasArrow,
                isTerminal: isTerminal,
                colorId: colorId,
                edge: GitLogLinearEdge.normal(0, 1)
            )
        )
    }

    private func row(_ elements: [GitLogPrintElement], isHead: Bool = false) -> GitLogGraphRow {
        GitLogGraphRow(hash: "hash", lane: 0, edges: [], elements: elements, nodeColorId: 1, isHead: isHead)
    }

    private func pixels(of row: GitLogGraphRow, laneCount: Int = 3, rowHeight: CGFloat = 24) throws -> Data {
        let renderer = ImageRenderer(
            content: GitLogGraphRowView(row: row, laneCount: laneCount, laneWidth: 12, rowHeight: rowHeight)
        )
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return try #require(NSBitmapImageRep(cgImage: image).tiffRepresentation)
    }

    private func components(_ color: Color) -> [Float] {
        let resolved = color.resolve(in: EnvironmentValues())
        return [resolved.red, resolved.green, resolved.blue]
    }

    @Test
    func defaultColorIdUsesTheNeutralGreyAndOtherIdsAreHashedHues() {
        let neutral = components(GitLogGraphPalette.color(forColorId: GitLogGraphColorGetter.defaultColorId))
        let first = components(GitLogGraphPalette.color(forColorId: 1))
        let second = components(GitLogGraphPalette.color(forColorId: 2))

        #expect(neutral == components(Color(hex: 0xA1A3AB)))
        #expect(first != neutral)
        #expect(second != neutral)
        #expect(first != second)
        #expect(first == components(GitLogGraphPalette.color(forColorId: 1)))
    }

    @Test
    func rowWithoutElementsRendersBlankWhileANodeDrawsADot() throws {
        let blank = try pixels(of: row([]))
        let blankAgain = try pixels(of: row([]))
        let withNode = try pixels(of: row([node(position: 1)]))

        #expect(blank != withNode)
        #expect(blank == blankAgain)
    }

    @Test
    func laneCountBelowOneStillGetsOneLaneOfWidth() throws {
        let laneWidth: CGFloat = 12
        let rowHeight: CGFloat = 24
        for laneCount in [-1, 0, 1] {
            let hosting = NSHostingView(
                rootView: GitLogGraphRowView(
                    row: row([node(position: 0)]),
                    laneCount: laneCount,
                    laneWidth: laneWidth,
                    rowHeight: rowHeight
                )
            )
            #expect(hosting.fittingSize == NSSize(width: laneWidth, height: rowHeight))
        }
    }

    @Test
    func headNodeIsDrawnWithARingUnlikeAPlainNode() throws {
        let plain = try pixels(of: row([node(position: 1)], isHead: false))
        let head = try pixels(of: row([node(position: 1)], isHead: true))

        #expect(plain != head)
    }

    @Test
    func straightEdgesDifferByDirectionAndTerminalGap() throws {
        let down = try pixels(of: row([edge(from: 1, to: 1, direction: .down)]))
        let up = try pixels(of: row([edge(from: 1, to: 1, direction: .up)]))
        let terminalDown = try pixels(of: row([edge(from: 1, to: 1, direction: .down, isTerminal: true)]))
        let terminalUp = try pixels(of: row([edge(from: 1, to: 1, direction: .up, isTerminal: true)]))

        #expect(down != up)
        #expect(down != terminalDown)
        #expect(up != terminalUp)
    }

    @Test
    func diagonalEdgesDifferByDirection() throws {
        let down = try pixels(of: row([edge(from: 0, to: 2, direction: .down)]))
        let up = try pixels(of: row([edge(from: 0, to: 2, direction: .up)]))
        let straight = try pixels(of: row([edge(from: 0, to: 0, direction: .down)]))

        #expect(down != up)
        #expect(down != straight)
    }

    @Test
    func dashedEdgesDrawGapsUnlessTheyCarryAnArrow() throws {
        let solid = try pixels(of: row([edge(from: 1, to: 1, direction: .down, lineStyle: .solid)]))
        let dashed = try pixels(of: row([edge(from: 1, to: 1, direction: .down, lineStyle: .dashed)]))
        let solidArrow = try pixels(
            of: row([edge(from: 1, to: 1, direction: .down, lineStyle: .solid, hasArrow: true)])
        )
        let dashedArrow = try pixels(
            of: row([edge(from: 1, to: 1, direction: .down, lineStyle: .dashed, hasArrow: true)])
        )

        #expect(solid != dashed)
        #expect(solid != solidArrow)
        #expect(solidArrow == dashedArrow)
    }

    @Test
    func arrowsAreDrawnOnStraightAndDiagonalEdgesInBothDirections() throws {
        for direction in [GitLogEdgeDirection.down, .up] {
            let straight = try pixels(of: row([edge(from: 1, to: 1, direction: direction)]))
            let straightArrow = try pixels(of: row([edge(from: 1, to: 1, direction: direction, hasArrow: true)]))
            let diagonal = try pixels(of: row([edge(from: 0, to: 2, direction: direction)]))
            let diagonalArrow = try pixels(of: row([edge(from: 0, to: 2, direction: direction, hasArrow: true)]))

            #expect(straight != straightArrow)
            #expect(diagonal != diagonalArrow)
        }
    }

    @Test
    func edgeColorFollowsItsColorId() throws {
        let neutral = try pixels(of: row([edge(from: 1, to: 1, colorId: GitLogGraphColorGetter.defaultColorId)]))
        let colored = try pixels(of: row([edge(from: 1, to: 1, colorId: 4)]))

        #expect(neutral != colored)
    }

    @Test
    func edgesAreDrawnBeneathNodes() throws {
        let both = try rgba(of: row([node(position: 1), edge(from: 1, to: 1)]))
        let reversed = try rgba(of: row([edge(from: 1, to: 1), node(position: 1)]))

        #expect(both.count == reversed.count)
        #expect(zip(both, reversed).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
    }

    private func rgba(of row: GitLogGraphRow) throws -> [UInt8] {
        let renderer = ImageRenderer(
            content: GitLogGraphRowView(row: row, laneCount: 3, laneWidth: 12, rowHeight: 24)
        )
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bytesPerRow = image.width * 4
        let context = try #require(
            CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        return Array(UnsafeRawBufferPointer(start: data, count: bytesPerRow * image.height))
    }

    @Test
    func arrowWithoutDistanceFromItsOriginIsSkipped() throws {
        let height: CGFloat = 5.5
        let plain = try pixels(
            of: row([edge(from: 1, to: 1, direction: .down, isTerminal: true)]),
            rowHeight: height
        )
        let arrow = try pixels(
            of: row([edge(from: 1, to: 1, direction: .down, hasArrow: true, isTerminal: true)]),
            rowHeight: height
        )

        #expect(plain == arrow)
    }

    @Test
    func rowsFromTheRealLayoutRenderForMergeAndLinearHistory() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func commit(_ hash: String, _ parents: [String], refs: [GitLogRef] = []) -> GitLogCommit {
            GitLogCommit(
                hash: hash,
                parents: parents,
                authorName: "Author",
                authorEmail: "author@example.com",
                date: date,
                refs: refs,
                subject: hash
            )
        }
        let commits = [
            commit("m", ["a", "b"], refs: [GitLogRef(name: "main", kind: .head)]),
            commit("a", ["c"]),
            commit("b", ["c"], refs: [GitLogRef(name: "feature", kind: .branch)]),
            commit("c", [])
        ]
        let snapshot = GitLogGraphLayout.snapshot(commits: commits, visibleHashes: nil, firstParentOnly: false)
        let laneCount = GitLogGraphLayout.displayedLaneCount(snapshot)

        let rendered = try snapshot.rows.map { try pixels(of: $0, laneCount: laneCount) }

        #expect(snapshot.rows.count == 4)
        #expect(snapshot.rows.first?.isHead == true)
        #expect(Set(rendered).count > 1)
    }

    @Test
    func rowViewRendersInsideAHostedWindow() async throws {
        let graphRow = row([node(position: 0), edge(from: 0, to: 1, direction: .down, hasArrow: true)], isHead: true)
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 60)) {
            GitLogGraphRowView(row: graphRow, laneCount: 3, laneWidth: 12, rowHeight: 24)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))

        #expect(hosted.renders())
    }
}
