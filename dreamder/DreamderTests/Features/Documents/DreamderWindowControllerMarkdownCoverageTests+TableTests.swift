import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class TableSizeRecorder {
    private(set) var sizes: [[Int]] = []

    func record(contentRows: Int, columns: Int) {
        sizes.append([contentRows, columns])
    }
}

extension DreamderWindowControllerMarkdownCoverageTests {
    @Test
    func insertTableAsksForASizeAndInsertsTheTableAtTheCaret() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "Intro\n\n")
            defer { harness.close() }
            harness.select([NSRange(location: 7, length: 0)])

            harness.controller.markdownInsertTable(nil)

            let presenter = MarkdownTablePopoverPresenter.shared
            let popover = try #require(presenter.popover)
            let picker = try #require(popover.contentViewController as? NSHostingController<MarkdownTableGridPicker>)
            picker.rootView.tap(at: Self.gridCellCenter)

            #expect(harness.text == "Intro\n\n|   |   |\n|---|---|\n|   |   |\n")
            #expect(presenter.popover == nil)
            try await eventually(timeout: .seconds(30)) { !popover.isShown }
        }
    }

    @Test
    func insertTableAnchorsThePopoverToTheFocusedTextView() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "Intro\n\n")
            defer { harness.close() }
            let textView = try harness.focusedTextView()
            textView.selectionManager.setSelectedRange(NSRange(location: 7, length: 0))

            harness.controller.markdownInsertTable(nil)

            let presenter = MarkdownTablePopoverPresenter.shared
            let popover = try #require(presenter.popover)
            let picker = try #require(popover.contentViewController as? NSHostingController<MarkdownTableGridPicker>)
            picker.rootView.tap(at: Self.gridCellCenter)

            #expect(textView.string == "Intro\n\n|   |   |\n|---|---|\n|   |   |\n")
            #expect(presenter.popover == nil)
        }
    }

    @Test
    func insertTableAnchorsToTheVisibleRectWhenTheCaretHasNoLayoutRect() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "Intro\n\n")
            defer { harness.close() }
            let textView = try harness.focusedTextView()
            textView.selectionManager.setSelectedRanges([])
            harness.select([NSRange(location: -1, length: 0)])

            harness.controller.markdownInsertTable(nil)

            let popover = try #require(MarkdownTablePopoverPresenter.shared.popover)
            defer { popover.close() }
            #expect(popover.positioningRect == textView.visibleRect)
        }
    }

    @Test
    func insertTableIsIgnoredOutsideMarkdownDocuments() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, fileName: "Code.swift", content: "let a = 1\n")
            defer { harness.close() }
            let before = MarkdownTablePopoverPresenter.shared.popover

            harness.controller.markdownInsertTable(nil)

            #expect(MarkdownTablePopoverPresenter.shared.popover === before)
            #expect(harness.text == "let a = 1\n")
        }
    }

    @Test
    func aNewPopoverReplacesTheOneThatIsStillShown() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "Intro\n")
            defer { harness.close() }
            let target = try #require(harness.controller.markdownEditorTarget())
            let presenter = MarkdownTablePopoverPresenter()
            let recorder = TableSizeRecorder()

            presenter.present(for: target, in: harness.window) { rows, columns in
                recorder.record(contentRows: rows, columns: columns)
            }
            let first = try #require(presenter.popover)
            presenter.present(for: target, in: harness.window) { rows, columns in
                recorder.record(contentRows: rows, columns: columns)
            }
            let second = try #require(presenter.popover)
            let picker = try #require(second.contentViewController as? NSHostingController<MarkdownTableGridPicker>)
            picker.rootView.tap(at: Self.gridCellCenter)

            #expect(first !== second)
            try await eventually(timeout: .seconds(30)) { !first.isShown }
            #expect(recorder.sizes == [[1, 2]])
            #expect(presenter.popover == nil)
        }
    }

    @Test
    func withoutAnAnchorNoPopoverIsKept() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, content: "Intro\n")
            defer { harness.close() }
            let target = try #require(harness.controller.markdownEditorTarget())
            let presenter = MarkdownTablePopoverPresenter()

            presenter.present(for: target, in: nil) { _, _ in }

            #expect(presenter.popover == nil)
        }
    }
}
