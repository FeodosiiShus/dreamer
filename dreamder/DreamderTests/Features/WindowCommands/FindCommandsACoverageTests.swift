import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct FindCommandsACoverageTests {
    @Test
    func itemsAreOfferedInTheFindMenuOrder() {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            FindCommands.FindButtons(responder: recorder, jumpTarget: recorder)
        }
        defer { menu.close() }

        #expect(menu.titles == [
            "Find...",
            "Find and Replace...",
            "Find Next",
            "Find Previous",
            "Use Selection for Find",
            "Jump to Selection"
        ])
        #expect(menu.enabledStates == [true, true, true, true, true, true])
    }

    @Test
    func buttonsSendTheirFindPanelActionsToTheResponder() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            FindCommands.FindButtons(responder: recorder, jumpTarget: recorder)
        }
        defer { menu.close() }

        for index in 0..<5 {
            try menu.click(index)
        }

        #expect(recorder.findTags == [
            Int(NSFindPanelAction.showFindPanel.rawValue),
            12,
            Int(NSFindPanelAction.next.rawValue),
            Int(NSFindPanelAction.previous.rawValue),
            Int(NSFindPanelAction.setFindString.rawValue)
        ])
        #expect(recorder.received.isEmpty)
    }

    @Test
    func jumpToSelectionSendsCenterSelectionToItsTarget() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            FindCommands.FindButtons(responder: recorder, jumpTarget: recorder)
        }
        defer { menu.close() }

        try menu.click(5)

        #expect(recorder.received == ["centerSelectionInVisibleArea(_:)"])
        #expect(recorder.findTags.isEmpty)
    }

    @Test
    func buttonsWithoutAResponderSendNothing() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            FindCommands.FindButtons(responder: nil, jumpTarget: recorder)
        }
        defer { menu.close() }

        for index in 0..<5 {
            try menu.click(index)
        }

        #expect(recorder.findTags.isEmpty)
    }

    @Test
    func commandBodyBuilds() {
        let commands = FindCommands()

        _ = commands.body
        _ = commands.hasResponder
    }
}
