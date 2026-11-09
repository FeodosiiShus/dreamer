import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPDefinitionWindowLookup", .serialized, .uiGate)
struct LSPDefinitionWindowLookupTests {
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

    @Test
    func aViewInsideAWindowResolvesTheDreamderWindowControllerOfThatWindow() throws {
        let window = makeWindow()
        let controller = DreamderWindowController(window: window, workspace: nil)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let content = try #require(window.contentView)
        content.addSubview(view)

        let resolved = LSPDefinitionWindowLookup.windowController(of: view)

        #expect(resolved === controller)
        window.close()
    }

    @Test
    func aViewWithoutAWindowHasNoWindowController() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))

        #expect(LSPDefinitionWindowLookup.windowController(of: view) == nil)
    }

    @Test
    func aWindowOwnedByAnotherKindOfWindowControllerHasNoDreamderWindowController() throws {
        let window = makeWindow()
        let controller = NSWindowController(window: window)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let content = try #require(window.contentView)
        content.addSubview(view)

        let resolved = LSPDefinitionWindowLookup.windowController(of: view)

        #expect(resolved == nil)
        #expect(window.windowController === controller)
        window.close()
    }

    @Test
    func showingUsagesForAWindowWithoutAWorkspaceDoesNothing() {
        let controller = DreamderWindowController(window: makeWindow(), workspace: nil)

        LSPDefinitionWindowLookup.showUsages(in: controller)

        #expect(controller.workspace == nil)
        #expect(ShowUsagesController.present(in: controller) == nil)
        controller.window?.close()
    }
}
