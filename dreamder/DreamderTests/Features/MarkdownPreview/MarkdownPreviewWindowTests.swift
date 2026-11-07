import AppKit
import Testing
import WebKit
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct MarkdownPreviewWindowTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let window: NSWindow

        func close() {
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL, markdown: String) throws -> Harness {
        try markdown.write(to: directory.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let window = try #require(workspace.windowControllers.first?.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 900), display: true)
        let manager = try #require(workspace.editorManager)
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: "README.md").path(percentEncoded: false),
            createIfNotFound: true
        ))
        manager.openTab(item: file)
        return Harness(workspace: workspace, window: window)
    }

    private func webView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = webView(in: subview) { return found }
        }
        return nil
    }

    private func previewText(in harness: Harness) async -> String? {
        guard let contentView = harness.window.contentView, let webView = webView(in: contentView) else { return nil }
        return try? await webView.evaluateJavaScript("document.body.innerText") as? String
    }

    @Test
    func openingAMarkdownFileRendersItsPreview() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory, markdown: "# Dreamder Notes\n\nSome **bold** text.\n")
            defer { harness.close() }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(20))
            var text: String?
            while clock.now < deadline {
                text = await previewText(in: harness)
                if text?.contains("Dreamder Notes") == true { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            #expect(text?.contains("Dreamder Notes") == true, "preview text: \(String(describing: text))")
            #expect(text?.contains("Some bold text.") == true)
        }
    }
}
