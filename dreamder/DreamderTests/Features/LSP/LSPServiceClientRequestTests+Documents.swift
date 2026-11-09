import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@MainActor
extension LSPServiceClientRequestTests {
    @Test
    func externalDocumentsAreHandedToTheSystemOpener() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, _, key, _ in
            fixture.opensExternalURLs = true
            let web = try #require(URL(string: "https://example.com/docs"))

            #expect(service.showDocument(ShowDocumentParams(uri: web.absoluteString), for: key))
            #expect(service.showDocument(ShowDocumentParams(uri: "file:///tmp/report.pdf", external: true), for: key))
            fixture.opensExternalURLs = false
            #expect(!service.showDocument(ShowDocumentParams(uri: web.absoluteString), for: key))

            #expect(fixture.externallyOpenedURLs == [web, URL(fileURLWithPath: "/tmp/report.pdf"), web])
        }
    }

    @Test
    func fileDocumentsOpenInTheEditorAtTheRequestedSelection() async throws {
        try await running(["a.ts": "line one\nline two\nline three\n"]) { service, workspace, key, _ in
            let uri = workspace.uri("a.ts")

            #expect(service.showDocument(ShowDocumentParams(uri: uri), for: key))
            #expect(openedFileName(workspace) == "a.ts")
            #expect(caret(workspace)?.start.line == 1)
            #expect(caret(workspace)?.start.column == 1)
            #expect(caret(workspace)?.end == nil)

            let range = LSPRange(startPair: (1, 2), endPair: (1, 5))
            #expect(service.showDocument(ShowDocumentParams(uri: uri, selection: range), for: key))
            #expect(caret(workspace)?.start.line == 2)
            #expect(caret(workspace)?.start.column == 3)
            #expect(caret(workspace)?.end?.line == 2)
            #expect(caret(workspace)?.end?.column == 6)

            let collapsed = LSPRange(startPair: (2, 1), endPair: (2, 1))
            #expect(service.showDocument(ShowDocumentParams(uri: uri, selection: collapsed), for: key))
            #expect(caret(workspace)?.start.line == 3)
            #expect(caret(workspace)?.start.column == 2)
            #expect(caret(workspace)?.end == nil)
            #expect(fixture.externallyOpenedURLs.isEmpty)
        }
    }

    @Test
    func documentsThatCannotBeShownAreReportedAsFailures() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            #expect(!service.showDocument(ShowDocumentParams(uri: workspace.uri("missing.ts")), for: key))
            #expect(!service.showDocument(ShowDocumentParams(uri: "untitled:Untitled-1"), for: key))

            #expect(openedFileName(workspace) == nil)

            workspace.workspace.editorManager = nil
            #expect(!service.showDocument(ShowDocumentParams(uri: workspace.uri("a.ts")), for: key))
        }
    }

    @Test
    func filesOutsideTheWorkspaceOpenInTheWorkspaceOfTheRequestingServer() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            try withTempDir { elsewhere in
                let outside = elsewhere.appending(path: "outside.ts")
                try "let o = 1\n".write(to: outside, atomically: true, encoding: .utf8)

                #expect(service.showDocument(ShowDocumentParams(uri: outside.lspURI), for: key))

                #expect(openedFileName(workspace) == "outside.ts")
            }
        }
    }

    @Test
    func liveDependenciesNeverShowModalsOrOpenExternalURLsInHeadlessMode() throws {
        try #require(DreamderHeadless.isEnabled)
        let live = LSPService.Dependencies.live
        let web = try #require(URL(string: "https://example.com"))

        #expect(live.runAlert(NSAlert()) == .abort)
        #expect(live.openExternalURL(web) == false)
    }

    @Test
    func nonHeadlessPresentationReachesTheSystemAndIsSuppressedByTheHostSwizzles() throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSAlert.runModal"))
        try #require(DreamderHeadless.interceptedSelectors.contains("NSWorkspace.openURL:"))
        let token = UUID().uuidString
        let alert = NSAlert()
        alert.messageText = "lsp dependency alert \(token)"
        let url = try #require(URL(string: "https://example.com/lsp-dependency/\(token)"))

        #expect(LSPService.Dependencies.presentAlert(alert, headless: true) == .abort)
        #expect(!DreamderHeadless.suppressedModals.contains(alert.messageText))
        #expect(LSPService.Dependencies.presentAlert(alert, headless: false) == .abort)
        #expect(DreamderHeadless.suppressedModals.contains(alert.messageText))

        #expect(!LSPService.Dependencies.openURL(url, headless: true))
        #expect(!DreamderHeadless.suppressedExternalOpens.contains(url.absoluteString))
        #expect(!LSPService.Dependencies.openURL(url, headless: false))
        #expect(DreamderHeadless.suppressedExternalOpens.contains(url.absoluteString))
    }
}
