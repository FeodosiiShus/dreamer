import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct StructureCommandsTests {
    @Test
    func commandsBodyBuilds() {
        let commands = StructureCommands()

        _ = commands.body
    }

    @Test
    func fileStructureSendsItsResponderChainSelector() {
        let recorder = CommandsBSelectorRecorder()
        let menu = StructureMenuItems(windowController: nil, sendAction: { recorder.record($0) })

        menu.showFileStructure()

        #expect(recorder.selectors == [#selector(DreamderWindowController.showFileStructure(_:))])
    }

    @Test
    func theMenuItemRendersWithoutAWindowController() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 40)) {
            StructureMenuItems(windowController: nil)
        }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func theCommandIsBoundToCommandF12() {
        #expect(KeymapCommand.fileStructure.id == "navigate.fileStructure")
        #expect(KeymapCommand.fileStructure.title == "File Structure")
        #expect(KeymapCommand.fileStructure.group == .navigate)
    }
}
