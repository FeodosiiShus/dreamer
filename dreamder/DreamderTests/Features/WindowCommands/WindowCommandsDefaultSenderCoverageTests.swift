import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WindowCommandsDefaultSenderCoverageTests {
    @Test
    func menusDispatchUnhandledSelectorsThroughTheResponderChainWithoutEffect() {
        let unhandled = Selector(("dreamderWindowCommandsDefaultSenderProbe:"))

        CodeMenu(windowController: nil).sendAction(unhandled)
        StructureMenuItems(windowController: nil).sendAction(unhandled)
        NavigateMenu(windowController: nil).sendAction(unhandled)
        RefactorMenu(windowController: nil).sendAction(unhandled)
        NavigationExtrasMenuItems(windowController: nil).sendAction(unhandled)

        #expect(NSApp.target(forAction: unhandled) == nil)
    }
}
