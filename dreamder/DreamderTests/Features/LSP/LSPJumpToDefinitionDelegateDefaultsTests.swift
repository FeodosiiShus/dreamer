import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPJumpToDefinitionDelegateDefaults", .serialized, .uiGate)
struct LSPJumpToDefinitionDelegateDefaultsTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func selfLink(for url: URL) -> (destination: LSPNavigationDestination, link: JumpToDefinitionLink) {
        let destination = LSPNavigationDestination(
            uri: url.lspURI,
            fileURL: url,
            range: LSPRange(start: Position(line: 1, character: 2), end: Position(line: 1, character: 4))
        )
        let link = JumpToDefinitionLink(
            url: url,
            targetRange: CursorPosition(line: destination.line, column: destination.column),
            typeName: "symbol",
            sourcePreview: "",
            documentation: nil
        )
        return (destination, link)
    }

    @Test
    func theDefaultLookupCapturesTheWindowControllerAndASelfLinkShowsUsagesInsteadOfJumping() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "Target.swift")
            try "alpha\nbeta\n".write(to: url, atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let window = makeWindow()
            let controller = DreamderWindowController(window: window, workspace: nil)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            let content = try #require(window.contentView)
            content.addSubview(view)
            let delegate = LSPJumpToDefinitionDelegate<SyncTestDocument>()
            let pair = selfLink(for: url)

            delegate.attach(to: view)
            delegate.rememberSelfLink(pair.destination)
            delegate.openLink(link: pair.link)

            #expect(delegate.capturedController === controller)
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)
            window.close()
        }
    }

    @Test
    func withoutAWindowTheDefaultLookupCapturesNothingAndASelfLinkJumps() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "Target.swift")
            try "alpha\nbeta\n".write(to: url, atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let delegate = LSPJumpToDefinitionDelegate<SyncTestDocument>()
            let pair = selfLink(for: url)

            delegate.attach(to: NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50)))
            delegate.rememberSelfLink(pair.destination)
            delegate.openLink(link: pair.link)

            #expect(delegate.capturedController == nil)
            #expect(workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent == "Target.swift")
        }
    }
}
