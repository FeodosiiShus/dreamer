import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Observable
private final class QuickSearchResultLabelCoverageDriver {
    var labelName = "Alpha Beta"
    var ranges: [NSRange] = []
    var attributed: NSAttributedString?
}

private struct QuickSearchResultLabelCoverageHost: View {
    let driver: QuickSearchResultLabelCoverageDriver

    var body: some View {
        QuickSearchResultLabel(
            labelName: driver.labelName,
            charactersToHighlight: driver.ranges,
            nsLabelName: driver.attributed
        )
    }
}

@MainActor
@Suite(.uiGate)
struct QuickSearchResultLabelCoverageTests {
    private func isBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    private func host(_ driver: QuickSearchResultLabelCoverageDriver) throws -> (HostedView, NSTextField) {
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 60)) {
            QuickSearchResultLabelCoverageHost(driver: driver)
        }
        hosted.layout()
        let label = try #require(hosted.views(of: NSTextField.self).first)
        return (hosted, label)
    }

    @Test
    func plainLabelShowsNameWithoutHighlight() throws {
        let (hosted, label) = try host(QuickSearchResultLabelCoverageDriver())
        defer { hosted.close() }

        #expect(label.stringValue == "Alpha Beta")
        #expect(label.isEditable == false)
        #expect(label.isSelectable == false)
        #expect(label.maximumNumberOfLines == 1)
        #expect(label.drawsBackground == false)
        let attributes = label.attributedStringValue.attributes(at: 0, effectiveRange: nil)
        #expect(isBold(attributes) == false)
    }

    @Test
    func charactersToHighlightAreBoldAndTinted() throws {
        let driver = QuickSearchResultLabelCoverageDriver()
        driver.ranges = [NSRange(location: 0, length: 2), NSRange(location: 6, length: 1)]
        let (hosted, label) = try host(driver)
        defer { hosted.close() }

        let value = label.attributedStringValue
        #expect(value.string == "Alpha Beta")
        for location in [0, 1, 6] {
            let attributes = value.attributes(at: location, effectiveRange: nil)
            #expect(isBold(attributes))
            #expect((attributes[.foregroundColor] as? NSColor) == NSColor.controlTextColor)
        }
        #expect(isBold(value.attributes(at: 3, effectiveRange: nil)) == false)
    }

    @Test
    func attributedNameWinsOverHighlight() throws {
        let driver = QuickSearchResultLabelCoverageDriver()
        driver.ranges = [NSRange(location: 0, length: 2)]
        driver.attributed = NSAttributedString(
            string: "Custom",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        let (hosted, label) = try host(driver)
        defer { hosted.close() }

        let value = label.attributedStringValue
        #expect(value.string == "Custom")
        #expect((value.attributes(at: 0, effectiveRange: nil)[.foregroundColor] as? NSColor) == NSColor.systemRed)
    }

    @Test
    func updatesFollowModelChanges() async throws {
        let driver = QuickSearchResultLabelCoverageDriver()
        let (hosted, label) = try host(driver)
        defer { hosted.close() }

        driver.labelName = "Gamma"
        driver.ranges = [NSRange(location: 0, length: 1)]
        try await eventually { label.attributedStringValue.string == "Gamma" }
        #expect(isBold(label.attributedStringValue.attributes(at: 0, effectiveRange: nil)))
        #expect(isBold(label.attributedStringValue.attributes(at: 2, effectiveRange: nil)) == false)

        driver.attributed = NSAttributedString(string: "Delta")
        try await eventually { label.attributedStringValue.string == "Delta" }

        driver.attributed = nil
        driver.ranges = []
        driver.labelName = "Epsilon"
        try await eventually { label.attributedStringValue.string == "Epsilon" }
        #expect(isBold(label.attributedStringValue.attributes(at: 0, effectiveRange: nil)) == false)
    }
}
