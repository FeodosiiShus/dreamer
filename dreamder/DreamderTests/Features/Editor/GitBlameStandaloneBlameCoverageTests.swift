import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitBlameParserBlameCoverageTests {
    private let firstHash = "d3a3502fee4ab7d2bbd73cf7d7ed4a8bc02eb28c"
    private let secondHash = "9fceb02a1a1c2a1f5a8f1d3a0e3b4c5d6e7f8091"

    private func porcelain(lineEnding: String, headerEnding: String) -> String {
        let rows = [
            "\(firstHash) 1 1 1\(headerEnding)",
            "author Ann\(headerEnding)",
            "author-time 1700000000\(headerEnding)",
            "summary First\(headerEnding)",
            "filename a.txt\(headerEnding)",
            "\tfirst line\(lineEnding)",
            "\(secondHash) 2 2 1\(headerEnding)",
            "author Bob\(headerEnding)",
            "author-time 1700001000\(headerEnding)",
            "summary Second\(headerEnding)",
            "filename a.txt\(headerEnding)",
            "\tsecond line\(lineEnding)"
        ]
        return rows.joined(separator: "\n")
    }

    private func expectedLines() -> [GitBlameLine] {
        [
            GitBlameLine(
                line: 1,
                commitHash: firstHash,
                author: "Ann",
                authorDate: Date(timeIntervalSince1970: 1_700_000_000),
                summary: "First"
            ),
            GitBlameLine(
                line: 2,
                commitHash: secondHash,
                author: "Bob",
                authorDate: Date(timeIntervalSince1970: 1_700_001_000),
                summary: "Second"
            )
        ]
    }

    @Test
    func contentLinesOfCRLFFilesDoNotSwallowTheNextHeader() {
        let output = porcelain(lineEnding: "\r", headerEnding: "") + "\n"

        #expect(GitBlameParser.parse(output) == expectedLines())
    }

    @Test
    func everyRowEndingInCarriageReturnIsTrimmed() {
        let output = porcelain(lineEnding: "\r", headerEnding: "\r") + "\n"

        #expect(GitBlameParser.parse(output) == expectedLines())
    }

    @Test
    func aTrailingCarriageReturnWithoutLineFeedIsTrimmed() {
        let output = porcelain(lineEnding: "\r", headerEnding: "")

        #expect(GitBlameParser.parse(output) == expectedLines())
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct GitBlameOverlayViewBlameCoverageTests {
    private func render(_ view: NSView) -> NSBitmapImageRep? {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation
    }

    @Test
    func overlayViewsCannotBeDecoded() {
        let inline = GitBlameInlineView(coder: NSKeyedArchiver(requiringSecureCoding: false))
        let annotation = GitBlameAnnotationView(coder: NSKeyedArchiver(requiringSecureCoding: false))
        #expect(inline == nil)
        #expect(annotation == nil)
    }

    @Test
    func inlineViewPaintsItsTextNextToTheAnchor() throws {
        let view = GitBlameInlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.setText("Author, just now • Subject")
        let withoutAnchor = try #require(render(view))

        view.anchorProvider = { CGRect(x: 40, y: 100, width: 8, height: 20) }
        let withAnchor = try #require(render(view))

        #expect(HostedView.pixelsDiffer(withoutAnchor, withAnchor))
    }

    @Test
    func annotationColumnIsTopLeftOrientedFollowsItsSuperviewAndOnlyHitsItsColumn() {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        let annotation = GitBlameAnnotationView(textView: TextView(string: "alpha\nbeta\n"))
        host.addSubview(annotation)

        annotation.matchSuperviewBounds()
        #expect(annotation.isFlipped)
        #expect(annotation.frame == host.bounds)
        #expect(annotation.hitTest(NSPoint(x: 490, y: 10)) == nil)

        annotation.isHidden = true
        #expect(annotation.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test
    func inlineViewPaintsNothingWithoutText() throws {
        let view = GitBlameInlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.anchorProvider = { CGRect(x: 40, y: 100, width: 8, height: 20) }
        let empty = try #require(render(view))

        view.setText("Author, just now • Subject")
        let painted = try #require(render(view))

        #expect(HostedView.pixelsDiffer(empty, painted))
    }
}
