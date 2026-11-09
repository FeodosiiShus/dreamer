import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DiffCodeStyleCoverageTests {
    @Test
    func displayExpandsTabsOnly() {
        #expect(DiffCodeStyle.display("plain") == "plain")
        #expect(DiffCodeStyle.display("a\tb") == "a    b")
        #expect(DiffCodeStyle.display("\t\tx") == "        x")
    }

    @Test
    func columnsCountTabsAsTabWidthAndStopAfterTheCap() {
        #expect(DiffCodeStyle.columns(in: "") == 0)
        #expect(DiffCodeStyle.columns(in: "abc") == 3)
        #expect(DiffCodeStyle.columns(in: "\t\tab") == 10)
        let long = String(repeating: "x", count: 9000)
        #expect(DiffCodeStyle.columns(in: long) == 4001)
    }

    @Test
    func changeColorsAreDistinct() {
        #expect(DiffColors.inserted != DiffColors.deleted)
        #expect(DiffColors.deleted != DiffColors.modified)
        #expect(DiffColors.modified != DiffColors.inserted)
    }

    @Test
    func statusColorsFollowTheIslandsPalette() {
        #expect(GitStatus.added.fileStatusColor == Islands.fileAdded)
        #expect(GitStatus.deleted.fileStatusColor == Islands.fileDeleted)
        #expect(GitStatus.untracked.fileStatusColor == Islands.fileUnversioned)
        #expect(GitStatus.unmerged.fileStatusColor == Islands.fileConflict)
        #expect(GitStatus.modified.fileStatusColor == Islands.fileModified)
        #expect(GitStatus.renamed.fileStatusColor == Islands.fileModified)
    }

    @Test
    func emptyMetricsAreTheDocumentedDefaults() {
        let empty = DiffLayoutMetrics.empty
        #expect(empty.rowHeight == 20)
        #expect(empty.leftLineNumberWidth == 40)
        #expect(empty.rightLineNumberWidth == 40)
        #expect(empty.leftCodeWidth == 400)
        #expect(empty.rightCodeWidth == 400)
    }

    @Test
    func metricsForASmallDiffUseTheMinimumWidths() {
        let metrics = DiffLayoutMetrics.make(for: TextDiff(left: "a\n", right: "b\n"))

        #expect(metrics.rowHeight >= 18)
        #expect(metrics.leftLineNumberWidth == 34)
        #expect(metrics.rightLineNumberWidth == 34)
        #expect(metrics.leftCodeWidth == 260)
        #expect(metrics.rightCodeWidth == 260)
    }

    @Test
    func metricsGrowWithLineCountAndLineLengthUpToTheCap() {
        let manyLines = (0..<100_000).map { "line \($0)" }
        let wide = String(repeating: "w", count: 5000)
        let metrics = DiffLayoutMetrics.make(for: TextDiff(leftLines: manyLines, rightLines: manyLines + [wide]))

        #expect(metrics.leftLineNumberWidth > 34)
        #expect(metrics.rightLineNumberWidth > 34)
        #expect(metrics.rightCodeWidth == 4000)
        #expect(metrics.leftCodeWidth >= 260)
        #expect(metrics.leftCodeWidth < 4000)
    }

    @Test
    func metricsForEmptyDiffKeepMinimums() {
        let metrics = DiffLayoutMetrics.make(for: TextDiff(left: "", right: ""))

        #expect(metrics.leftLineNumberWidth == 34)
        #expect(metrics.leftCodeWidth == 260)
    }

    @Test
    func relativePathOutsideTheRootIsEmpty() {
        let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        #expect(DiffPath.relativePath(of: URL(fileURLWithPath: "/var/elsewhere/file.txt"), from: root).isEmpty)
        #expect(DiffPath.relativePath(of: root, from: root).isEmpty)
    }
}
