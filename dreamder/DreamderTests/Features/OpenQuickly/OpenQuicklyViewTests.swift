import AppKit
import CodeEditTextView
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class OpenQuicklyRecorder {
    var opened: [CEWorkspaceFile] = []
    var closes = 0
}

@MainActor
@Suite(.uiGate)
struct OpenQuicklyViewTests {
    private struct Harness {
        let workspace: WorkspaceDocument
        let model: OpenQuicklyViewModel
        let recorder: OpenQuicklyRecorder
        let hosted: HostedView
    }

    private func makeHarness(in root: URL, withFileManager: Bool = true) throws -> Harness {
        try Data("alpha".utf8).write(to: root.appending(path: "alpha.txt"))
        try Data("beta".utf8).write(to: root.appending(path: "beta.txt"))
        let workspace = try HostedViewFixture.makeWorkspace(in: root)
        if !withFileManager {
            workspace.workspaceFileManager = nil
        }
        let model = try #require(workspace.openQuicklyViewModel)
        let recorder = OpenQuicklyRecorder()
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 900, height: 600)) {
            OpenQuicklyView(
                state: model,
                onClose: { recorder.closes += 1 },
                openFile: { recorder.opened.append($0) }
            )
        }
        return Harness(workspace: workspace, model: model, recorder: recorder, hosted: hosted)
    }

    private func fieldEditor(in hosted: HostedView) throws -> NSTextView {
        let field = try #require(hosted.views(of: NSTextField.self).first { $0.isEditable })
        hosted.window.makeFirstResponder(field)
        if field.currentEditor() == nil {
            field.selectText(nil)
        }
        return try #require(field.currentEditor() as? NSTextView)
    }

    private func awaitSelectedFirstRow(_ harness: Harness) async throws {
        try await eventually(timeout: .seconds(30)) {
            harness.hosted.layout()
            return harness.hosted.views(of: NSTableView.self).first?.selectedRow == 0
        }
    }

    @Test
    func emptyQueryShowsNoResults() async throws {
        try await withTempDir { root in
            let harness = try makeHarness(in: root)
            defer { harness.hosted.close() }
            try await harness.hosted.settle(.milliseconds(400))

            #expect(harness.model.searchResults.isEmpty)
            #expect(harness.hosted.views(of: NSTableView.self).isEmpty)
            #expect(harness.recorder.closes == 0)
        }
    }

    @Test
    func typingSearchesDebouncedAndListsTheMatchingFileWithItsPreview() async throws {
        try await withTempDir { root in
            let harness = try makeHarness(in: root)
            defer { harness.hosted.close() }
            try await harness.hosted.settle()

            harness.model.query = "alp"
            try await Task.sleep(for: .milliseconds(50))
            harness.model.query = "alpha"

            try await eventually(timeout: .seconds(30)) {
                harness.model.searchResults.map(\.fileURL.lastPathComponent) == ["alpha.txt"]
            }
            try await awaitSelectedFirstRow(harness)
            try await eventually(timeout: .seconds(30)) {
                harness.hosted.layout()
                return !harness.hosted.views(of: CodeEditTextView.TextView.self).isEmpty
            }
            #expect(harness.recorder.opened.isEmpty)
        }
    }

    @Test
    func submittingOpensTheSelectedFileClearsTheQueryAndCloses() async throws {
        try await withTempDir { root in
            let harness = try makeHarness(in: root)
            defer { harness.hosted.close() }
            try await harness.hosted.settle()

            harness.model.query = "alpha"
            try await eventually(timeout: .seconds(30)) {
                harness.model.searchResults.map(\.fileURL.lastPathComponent) == ["alpha.txt"]
            }
            try await awaitSelectedFirstRow(harness)
            try fieldEditor(in: harness.hosted).doCommand(by: #selector(NSResponder.insertNewline(_:)))

            #expect(harness.recorder.opened.map(\.name) == ["alpha.txt"])
            #expect(harness.recorder.closes == 1)
            #expect(harness.model.query.isEmpty)

            harness.hosted.hosting.rootView = AnyView(Color.clear)
            try await harness.hosted.settle(.milliseconds(50))
        }
    }

    @Test
    func submittingWithoutAWorkspaceFileManagerOpensNothing() async throws {
        try await withTempDir { root in
            let harness = try makeHarness(in: root, withFileManager: false)
            defer { harness.hosted.close() }
            try await harness.hosted.settle()

            harness.model.query = "alpha"
            try await eventually(timeout: .seconds(30)) {
                harness.model.searchResults.map(\.fileURL.lastPathComponent) == ["alpha.txt"]
            }
            try await awaitSelectedFirstRow(harness)
            try fieldEditor(in: harness.hosted).doCommand(by: #selector(NSResponder.insertNewline(_:)))

            #expect(harness.recorder.opened.isEmpty)
            #expect(harness.recorder.closes == 0)
            #expect(harness.model.query == "alpha")
        }
    }
}
