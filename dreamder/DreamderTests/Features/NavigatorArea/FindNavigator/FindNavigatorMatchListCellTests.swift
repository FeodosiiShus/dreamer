import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorMatchListCellTests {
    private func makeMatch(_ line: String, keyword: String) throws -> SearchResultMatchModel {
        let range = try #require(line.range(of: keyword))
        return SearchResultMatchModel(
            rangeWithinFile: line.startIndex..<line.endIndex,
            file: CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/FindNavigatorMatchListCell.swift")),
            lineContent: line,
            keywordRange: range
        )
    }

    private func components(_ color: NSColor?) -> [CGFloat] {
        guard let converted = color?.usingColorSpace(.sRGB) else { return [] }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent]
    }

    @Test
    func attributedStringHighlightsOnlyTheKeyword() throws {
        let match = try makeMatch("let needle = 1", keyword: "needle")
        let result = FindNavigatorListMatchCell.attributedString(for: match)
        #expect(result.string == "let needle = 1")

        let plain = result.attributes(at: 0, effectiveRange: nil)
        let keyword = result.attributes(at: 5, effectiveRange: nil)
        #expect(plain[.backgroundColor] == nil)
        #expect(components(plain[.foregroundColor] as? NSColor) == components(NSColor(Islands.secondaryForeground)))
        #expect(components(keyword[.foregroundColor] as? NSColor) == components(NSColor(Islands.foreground)))
        #expect(
            components(keyword[.backgroundColor] as? NSColor)
                == components(NSColor(Islands.searchMatch).withAlphaComponent(0.3))
        )
        #expect((keyword[.font] as? NSFont) == Islands.codeNSFont)
    }

    @Test
    func cellShowsTheMatchLineInsideItsFrame() throws {
        let match = try makeMatch("let needle = 1", keyword: "needle")
        let cell = FindNavigatorListMatchCell(frame: NSRect(x: 4, y: 6, width: 300, height: 40), matchItem: match)

        #expect(cell.frame == NSRect(x: 4, y: 6, width: 300, height: 40))
        let label = try #require(cell.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.stringValue == "let needle = 1")
        #expect(!label.isEditable)
        #expect(!label.isSelectable)
        #expect(!label.drawsBackground)
        #expect(label.maximumNumberOfLines == Settings.shared.preferences.general.findNavigatorDetail.rawValue)
        #expect(label.attributedStringValue.string == "let needle = 1")
        #expect(cell.constraints.count == 4)
    }

    @Test
    func cellCannotBeDecoded() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        #expect(FindNavigatorListMatchCell(coder: decoder) == nil)
    }
}
