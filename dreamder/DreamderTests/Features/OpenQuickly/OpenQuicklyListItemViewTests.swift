import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct OpenQuicklyListItemViewTests {
    private let base = URL(filePath: "/fake/project", directoryHint: .isDirectory)

    private func item(_ relativePath: String, matches: [NSRange] = []) -> OpenQuicklyListItemView {
        OpenQuicklyListItemView(
            baseDirectory: base,
            searchResult: OpenQuicklyViewModel.SearchResult(
                fileURL: base.appending(path: relativePath),
                matchedCharacters: matches
            )
        )
    }

    private func isBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    @Test
    func relativePathComponentsAreTheDirectoriesBetweenTheBaseAndTheFile() {
        #expect(Array(item("Sources/App/main.swift").relativePathComponents) == ["Sources", "App"])
        #expect(item("main.swift").relativePathComponents.isEmpty)
    }

    @Test
    func rendersTheFileNameWithHighlightedMatches() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 60)) {
            item("Sources/App/main.swift", matches: [NSRange(location: 0, length: 2)])
        }
        defer { hosted.close() }
        try await hosted.settle()

        let label = try #require(hosted.views(of: NSTextField.self).first { $0.stringValue == "main.swift" })
        let matched = label.attributedStringValue.attributes(at: 0, effectiveRange: nil)
        let unmatched = label.attributedStringValue.attributes(at: 5, effectiveRange: nil)
        #expect(isBold(matched))
        #expect(isBold(unmatched) == false)
        #expect(hosted.renders())
    }

    @Test
    func fileDirectlyInTheBaseRendersWithoutAPathLine() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 60)) {
            item("main.swift")
        }
        defer { hosted.close() }
        try await hosted.settle()

        let labels = hosted.views(of: NSTextField.self).map(\.stringValue)
        #expect(labels == ["main.swift"])
    }
}
