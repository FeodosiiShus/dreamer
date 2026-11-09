import AppKit
import CodeEditTextView
import Foundation
import Testing
import WebKit
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownEditorWithPreviewCoverageTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let window: NSWindow
        let store: MarkdownPreviewLayoutStore
        let file: URL

        func close() {
            window.close()
            workspace.close()
        }

        func webViews() -> [WKWebView] {
            views(of: WKWebView.self)
        }

        func editors() -> [TextView] {
            views(of: TextView.self)
        }

        func previewText() async -> String? {
            guard let webView = webViews().first else { return nil }
            let value = try? await webView.evaluateJavaScript("document.body.innerText")
            return value as? String
        }

        func waitForPreview(containing text: String) async throws {
            try await eventually(timeout: .seconds(30)) { await previewText()?.contains(text) == true }
        }

        private func views<T: NSView>(of type: T.Type) -> [T] {
            guard let contentView = window.contentView else { return [] }
            return Self.descendants(of: contentView).compactMap { $0 as? T }
        }

        private static func descendants(of view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }
    }

    private func makeHarness(in directory: URL, markdown: String) throws -> Harness {
        let file = directory.appending(path: "README.md")
        try markdown.write(to: file, atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        let store = MarkdownPreviewLayoutStore.store(
            for: workspace,
            settings: Dreamder.Settings(baseURL: directory)
        )
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let window = try #require(workspace.windowControllers.first?.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 900), display: true)
        let manager = try #require(workspace.editorManager)
        let item = try #require(workspace.workspaceFileManager?.getFile(
            file.path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: item)
        return Harness(workspace: workspace, window: window, store: store, file: file)
    }

    @Test
    func theLayoutSwitchShowsTheEditorThePreviewOrBoth() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory, markdown: "# Dreamder Notes\n\nSome text.\n")
            defer { harness.close() }
            try await harness.waitForPreview(containing: "Dreamder Notes")
            try await eventually(timeout: .seconds(30)) { !harness.editors().isEmpty }

            harness.store.select(.previewOnly, for: harness.file)
            try await eventually(timeout: .seconds(30)) { harness.editors().isEmpty }
            try await harness.waitForPreview(containing: "Dreamder Notes")

            harness.store.select(.editorOnly, for: harness.file)
            try await eventually(timeout: .seconds(30)) { harness.webViews().isEmpty }
            try await eventually(timeout: .seconds(30)) { !harness.editors().isEmpty }

            harness.store.select(.editorAndPreview, for: harness.file)
            try await eventually(timeout: .seconds(30)) { await harness.previewText()?.contains("Some text.") == true }
            try await eventually(timeout: .seconds(30)) { !harness.editors().isEmpty }
        }
    }

    @Test
    func theOrientationFlipKeepsBothPanesVisible() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory, markdown: "# Flip\n")
            defer { harness.close() }
            try await eventually(timeout: .seconds(30)) { await harness.previewText()?.contains("Flip") == true }

            harness.store.select(.editorAndPreview, for: harness.file)
            #expect(harness.store.isVerticalSplit(for: harness.file) == false)
            try await Task.sleep(for: .milliseconds(200))
            #expect(harness.webViews().isEmpty == false)
            #expect(harness.editors().isEmpty == false)

            harness.store.select(.editorAndPreview, for: harness.file)
            #expect(harness.store.isVerticalSplit(for: harness.file))
            try await Task.sleep(for: .milliseconds(200))
            #expect(harness.webViews().isEmpty == false)
            #expect(harness.editors().isEmpty == false)
        }
    }

    @Test
    func anEmptyDocumentOpensEditorOnlyUntilALayoutIsChosen() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory, markdown: "")
            defer { harness.close() }
            try await eventually(timeout: .seconds(30)) { !harness.editors().isEmpty }
            #expect(harness.store.layout(for: harness.file) == .editorOnly)
            try await Task.sleep(for: .milliseconds(300))
            #expect(harness.webViews().isEmpty)

            harness.store.select(.editorAndPreview, for: harness.file)

            try await eventually(timeout: .seconds(30)) { !harness.webViews().isEmpty }
            #expect(harness.store.layout(for: harness.file) == .editorAndPreview)
        }
    }
}
