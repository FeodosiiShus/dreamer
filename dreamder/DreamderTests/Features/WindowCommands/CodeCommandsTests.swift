import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class CodeCommandsSelectorRecorder {
    private(set) var selectors: [Selector] = []

    func record(_ selector: Selector) {
        selectors.append(selector)
    }
}

@MainActor
@Suite("CodeCommands", .uiGate)
struct CodeCommandsTests {
    @Test
    func menuItemsSendTheirActionsThroughTheResponderChain() {
        let recorder = CodeCommandsSelectorRecorder()
        let menu = CodeMenu(windowController: nil, sendAction: { recorder.record($0) })

        menu.showContextActions()
        menu.reformatCode()
        menu.optimizeImports()

        #expect(recorder.selectors == [
            #selector(DreamderWindowController.showContextActions(_:)),
            #selector(DreamderWindowController.reformatCode(_:)),
            #selector(DreamderWindowController.optimizeImports(_:))
        ])
    }

    @Test
    func commandBodyBuilds() {
        _ = CodeCommands().body
    }

    @Test
    func menuItemsAreDisabledWithoutAnActiveDocument() {
        let menu = CodeMenu(windowController: nil)

        #expect(!menu.hasCodeDocument)
        #expect(!menu.hasLanguageServer)
    }

    @Test
    func menuStateWithAnOpenTabNeedsAServerForServerBackedItems() throws {
        try withTempDir { dir in
            try "x\n".write(to: dir.appending(path: "a.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let file = try #require(workspace.workspaceFileManager?.getFile(
                dir.appending(path: "a.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            workspace.editorManager?.openTab(item: file)
            let controller = makeCommandsBWindowController(workspace: workspace)
            defer { controller.window?.close() }
            let menu = CodeMenu(windowController: controller)

            #expect(menu.hasLanguageServer == false)
            #expect(menu.hasCodeDocument == (file.fileDocument != nil))
        }
    }

    @Test
    func defaultShortcutsMatchIntelliJ() {
        #expect(KeymapCommand.showContextActions.title == "Show Context Actions")
        #expect(KeymapCommand.showContextActions.defaultShortcuts == [.stroke(KeyNames.enter, .option)])
        #expect(KeymapCommand.reformatCode.title == "Reformat Code")
        #expect(KeymapCommand.reformatCode.defaultShortcuts == [.stroke("l", [.option, .command])])
        #expect(KeymapCommand.optimizeImports.title == "Optimize Imports")
        #expect(KeymapCommand.optimizeImports.defaultShortcuts == [.stroke("o", [.control, .option])])
    }

    @Test
    func menuRendersWithAndWithoutAWindowController() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 300)) {
            VStack { CodeMenu(windowController: nil) }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))

        #expect(hosted.renders())
    }
}
