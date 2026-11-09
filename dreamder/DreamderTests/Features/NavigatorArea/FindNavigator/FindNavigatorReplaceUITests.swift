import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class BarButtonTaps {
    var count = 0
}

@MainActor
@Suite(.uiGate)
struct FindNavigatorReplaceUITests {
    private static let skippedStrikethrough = NSUnderlineStyle.single.rawValue

    private func makeMatch(
        _ line: String,
        keyword: String,
        replacement: String? = nil,
        path: String = "/project/src/Preview.swift"
    ) throws -> SearchResultMatchModel {
        let range = try #require(line.range(of: keyword))
        let start = line.utf16.distance(from: line.startIndex, to: range.lowerBound)
        let length = keyword.utf16.count
        let usage = replacement.map {
            FindUsage(
                range: NSRange(location: start, length: length),
                replacement: $0,
                start: FindTextPosition(line: 1, column: start + 1),
                end: FindTextPosition(line: 1, column: start + length + 1)
            )
        }
        return SearchResultMatchModel(
            rangeWithinFile: line.startIndex..<line.endIndex,
            file: CEWorkspaceFile(url: URL(fileURLWithPath: path)),
            lineContent: line,
            keywordRange: range,
            usage: usage
        )
    }

    private func components(_ color: NSColor?) -> [CGFloat] {
        guard let converted = color?.usingColorSpace(.sRGB) else { return [] }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent]
    }

    private func foreground(_ string: NSAttributedString, at index: Int) -> [CGFloat] {
        components(string.attributes(at: index, effectiveRange: nil)[.foregroundColor] as? NSColor)
    }

    private func background(_ string: NSAttributedString, at index: Int) -> [CGFloat] {
        components(string.attributes(at: index, effectiveRange: nil)[.backgroundColor] as? NSColor)
    }

    private func tinted(_ color: Color) -> [CGFloat] {
        components(NSColor(color).withAlphaComponent(0.3))
    }

    private func plain(_ color: Color) -> [CGFloat] {
        components(NSColor(color))
    }

    @Test
    func previewRowShowsTheOldLineTintedRedAndTheNewLineTintedGreen() throws {
        let match = try makeMatch("let needle = 1", keyword: "needle", replacement: "pin")
        #expect(match.replacementDisplay == "pin")
        #expect(match.replacementPreviewLine == "let pin = 1")

        let result = FindNavigatorListMatchCell.attributedString(for: match)

        #expect(result.string == "let needle = 1\nlet pin = 1")
        #expect(foreground(result, at: 0) == plain(Islands.secondaryForeground))
        #expect(background(result, at: 0).isEmpty)
        #expect(background(result, at: 4) == tinted(Islands.errorForeground))
        #expect(foreground(result, at: 4) == plain(Islands.foreground))
        #expect(background(result, at: 9) == tinted(Islands.errorForeground))
        #expect(background(result, at: 10).isEmpty)

        #expect(foreground(result, at: 15) == plain(Islands.secondaryForeground))
        #expect(background(result, at: 15).isEmpty)
        #expect(background(result, at: 19) == tinted(Islands.successForeground))
        #expect(background(result, at: 21) == tinted(Islands.successForeground))
        #expect(foreground(result, at: 19) == plain(Islands.foreground))
        #expect(background(result, at: 22).isEmpty)
        #expect(result.attributes(at: 0, effectiveRange: nil)[.strikethroughStyle] == nil)
    }

    @Test
    func findModeRowsKeepASingleLineWithTheSearchTint() throws {
        let match = try makeMatch("let needle = 1", keyword: "needle")
        #expect(match.replacementDisplay == nil)
        #expect(match.replacementPreviewLine == nil)

        let result = FindNavigatorListMatchCell.attributedString(for: match)

        #expect(result.string == "let needle = 1")
        #expect(background(result, at: 4) == tinted(Islands.searchMatch))
    }

    @Test
    func multilineReplacementsAreShownWithTheLineBreakGlyph() throws {
        let match = try makeMatch("let needle = 1", keyword: "needle", replacement: "a\nb")

        #expect(match.replacementDisplay == "a⏎b")
        #expect(match.replacementPreviewLine == "let a⏎b = 1")
        #expect(FindNavigatorListMatchCell.attributedString(for: match).string == "let needle = 1\nlet a⏎b = 1")
    }

    @Test
    func previewTintFollowsUTF16OffsetsAfterWideCharacters() throws {
        let match = try makeMatch("😀 needle", keyword: "needle", replacement: "pin")

        let result = FindNavigatorListMatchCell.attributedString(for: match)

        #expect(result.string == "😀 needle\n😀 pin")
        #expect(background(result, at: 3) == tinted(Islands.errorForeground))
        #expect(background(result, at: 12).isEmpty)
        #expect(background(result, at: 13) == tinted(Islands.successForeground))
        #expect(background(result, at: 15) == tinted(Islands.successForeground))
    }

    @Test
    func skippedRowsAreStruckThroughAndDimmed() throws {
        let match = try makeMatch("let needle = 1", keyword: "needle", replacement: "pin")
        match.isSkipped = true

        let result = FindNavigatorListMatchCell.attributedString(for: match)

        for index in [0, 5, 16, 20] {
            let attributes = result.attributes(at: index, effectiveRange: nil)
            #expect(attributes[.strikethroughStyle] as? Int == Self.skippedStrikethrough, "\(index)")
            #expect(foreground(result, at: index) == plain(Islands.disabledForeground), "\(index)")
        }

        match.isSkipped = false
        let restored = FindNavigatorListMatchCell.attributedString(for: match)
        #expect(restored.attributes(at: 0, effectiveRange: nil)[.strikethroughStyle] == nil)
    }

    @Test
    func previewRowsAllowTwiceAsManyLinesAndRenderBothInTheCell() throws {
        let detail = Settings.shared.preferences.general.findNavigatorDetail.rawValue
        let single = try makeMatch("let needle = 1", keyword: "needle")
        let preview = try makeMatch("let needle = 1", keyword: "needle", replacement: "pin")

        #expect(FindNavigatorListMatchCell.maximumLines(for: single) == detail)
        #expect(FindNavigatorListMatchCell.maximumLines(for: preview) == detail * 2)

        let cell = FindNavigatorListMatchCell(frame: NSRect(x: 0, y: 0, width: 300, height: 40), matchItem: preview)
        let label = try #require(cell.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.maximumNumberOfLines == detail * 2)
        #expect(label.attributedStringValue.string == "let needle = 1\nlet pin = 1")
    }

    @Test
    func fileCellShowsNameRelativeDirectoryAndMatchCount() throws {
        let matches = try (0..<3).map { _ in try makeMatch("let needle = 1", keyword: "needle") }
        let result = SearchResultModel(
            file: CEWorkspaceFile(url: URL(fileURLWithPath: "/project/src/nested/a.swift")),
            score: 0,
            lineMatches: matches
        )
        let root = URL(fileURLWithPath: "/project", isDirectory: true)

        let cell = FindNavigatorListFileCell(
            frame: NSRect(x: 0, y: 0, width: 300, height: 24),
            result: result,
            projectRoot: root
        )

        #expect(cell.displayedName == "a.swift")
        #expect(cell.displayedDirectory == "src/nested")
        #expect(cell.displayedCount == "3")
        #expect(cell.subviews.count == 4)
        #expect(cell.subviews.contains { $0 is NSImageView })
    }

    @Test
    func fileCellWithoutAProjectRootShowsTheFullDirectory() throws {
        let result = SearchResultModel(
            file: CEWorkspaceFile(url: URL(fileURLWithPath: "/project/src/a.swift")),
            score: 0
        )

        let cell = FindNavigatorListFileCell(
            frame: NSRect(x: 0, y: 0, width: 300, height: 24),
            result: result,
            projectRoot: nil
        )

        #expect(cell.displayedDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "project/src")
        #expect(cell.displayedCount == "0")
    }

    @Test
    func relativeDirectoryIsEmptyAtTheRootAndAbsoluteOutsideIt() {
        let root = URL(fileURLWithPath: "/project", isDirectory: true)
        let atRoot = URL(fileURLWithPath: "/project/a.swift")
        let inside = URL(fileURLWithPath: "/project/src/a.swift")
        let outside = URL(fileURLWithPath: "/other/a.swift")

        #expect(FindNavigatorListFileCell.relativeDirectory(of: atRoot, in: root) == "")
        #expect(FindNavigatorListFileCell.relativeDirectory(of: inside, in: root) == "src")
        let absolute = FindNavigatorListFileCell.relativeDirectory(of: outside, in: root)
        #expect(absolute.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "other")
        #expect(absolute.hasPrefix("/"))
        let withoutRoot = FindNavigatorListFileCell.relativeDirectory(of: inside, in: nil)
        #expect(withoutRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "project/src")
    }

    @Test
    func fileCellCannotBeDecoded() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        #expect(FindNavigatorListFileCell(coder: decoder) == nil)
    }

    @Test
    func replaceModeListRendersPreviewRowsAndTallerRowHeights() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let column = try #require(harness.outline.tableColumns.first)
            column.width = 400
            let match = try harness.fileA.lineMatches.required(at: 0)
            #expect(match.replacementPreviewLine != nil)

            let view = harness.controller.outlineView(harness.outline, viewFor: column, item: match)
            let cell = try #require(view as? FindNavigatorListMatchCell)
            let label = try #require(cell.subviews.compactMap { $0 as? NSTextField }.first)
            #expect(label.attributedStringValue.string.contains("\n"))
            #expect(label.attributedStringValue.string.hasSuffix("let pin = 1"))

            let previewHeight = harness.controller.outlineView(harness.outline, heightOfRowByItem: match)
            match.usage = nil
            let singleHeight = harness.controller.outlineView(harness.outline, heightOfRowByItem: match)
            #expect(previewHeight >= singleHeight)
        }
    }

    @Test
    func hostedReplaceResultsShowTheReplacementUnderEachMatch() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            defer { workspace.close() }

            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 600, height: 500)) {
                FindNavigatorResultList()
            }
            defer { hosted.close() }
            try await eventually { !hosted.views(of: FindNavigatorListMatchCell.self).isEmpty }

            let labels = hosted.views(of: FindNavigatorListMatchCell.self)
                .compactMap { $0.subviews.compactMap { $0 as? NSTextField }.first }
            #expect(!labels.isEmpty)
            #expect(labels.allSatisfy { $0.attributedStringValue.string.contains("pin") })
        }
    }

    @Test
    func replaceBarEnablesButtonsFromTheSelectionAndTheReplacementError() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let result = try #require(state.searchResult.first)

            let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 60)) {
                FindNavigatorReplaceBar(state: state)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            let unselected = hosted.snapshot()

            state.resultSelection = .file(result)
            try await hosted.settle(.milliseconds(100))
            let selected = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(unselected, selected))

            state.replacementError = "No group 5"
            try await hosted.settle(.milliseconds(100))
            let blocked = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(selected, blocked))

            state.replacementError = nil
            state.resultSelection = nil
            try await hosted.settle(.milliseconds(100))
            #expect(!HostedView.pixelsDiffer(unselected, hosted.snapshot()))
        }
    }

    @Test
    func replaceBarSkipTogglesAndReplaceActsOnTheSelection() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let fileB = try #require(state.searchResult.first { $0.file.name == "b.txt" })
            let match = try #require(fileB.lineMatches.first)
            let bar = FindNavigatorReplaceBar(state: state)
            let revision = state.skipRevision

            state.resultSelection = .match(match)
            bar.skipSelected()
            #expect(match.isSkipped)
            #expect(state.skipRevision == revision + 1)
            bar.skipSelected()
            #expect(!match.isSkipped)

            bar.replaceSelected()

            try await eventually { state.searchResult.count == 1 }
            let replaced = try String(contentsOf: dir.appending(path: "b.txt"), encoding: .utf8)
            #expect(replaced == "pin here\n")
        }
    }

    @Test
    func barButtonRendersEnabledAndDisabledAndForwardsItsAction() async throws {
        let taps = BarButtonTaps()
        let enabled = HostedViewFixture.host(size: NSSize(width: 120, height: 40)) {
            FindNavigatorBarButton(title: "Replace", isEnabled: true, action: { taps.count += 1 })
        }
        defer { enabled.close() }
        let disabled = HostedViewFixture.host(size: NSSize(width: 120, height: 40)) {
            FindNavigatorBarButton(title: "Replace", isEnabled: false, action: { taps.count += 1 })
        }
        defer { disabled.close() }
        try await enabled.settle(.milliseconds(100))
        try await disabled.settle(.milliseconds(100))

        #expect(enabled.renders())
        #expect(disabled.renders())
        #expect(HostedView.pixelsDiffer(enabled.snapshot(), disabled.snapshot()))

        FindNavigatorBarButton(title: "Skip", isEnabled: true, action: { taps.count += 1 }).action()
        #expect(taps.count == 1)
    }

    @Test
    func viewShowsTheReplaceNoticeAndTheReplaceBarWithResults() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorView() }
            defer { hosted.close() }
            try await eventually { hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5 }
            try await hosted.settle()
            let clean = hosted.snapshot()

            state.resultSelection = .file(try #require(state.searchResult.first))
            try await hosted.settle()
            let selected = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(clean, selected))

            state.replaceNotice = "1 successfully updated, 1 errors occurred. Please check logs."
            try await hosted.settle()
            let noticed = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(selected, noticed))
            #expect(hosted.views(of: NSOutlineView.self).count == 1)

            state.replaceNotice = nil
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(noticed, hosted.snapshot()))
        }
    }

    @Test
    func viewKeepsTheListWhileSearchingWithPartialResults() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorView() }
            defer { hosted.close() }
            try await eventually { hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5 }

            state.findNavigatorStatus = .searching
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5)

            state.findNavigatorStatus = .found
            try await hosted.settle()
            #expect(hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5)
        }
    }

    @Test
    func formShowsTheReplacementErrorUnderTheReplaceField() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            state.selectedMode = FindNavigatorTestWorkspace.replaceMode

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            let clean = hosted.snapshot()

            state.replacementError = "No group 5"
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(clean, hosted.snapshot()))
        }
    }
}
