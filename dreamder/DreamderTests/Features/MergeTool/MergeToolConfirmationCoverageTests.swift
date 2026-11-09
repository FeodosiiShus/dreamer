import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MergeToolConfirmationCoverageTests {
    private func ask(window: NSWindow?, title: String) async -> Bool {
        await MergeToolConfirmation.ask(
            window: window,
            title: title,
            message: "Message",
            confirmTitle: "Confirm",
            cancelTitle: "Cancel"
        )
    }

    @Test
    func askWithoutAWindowShowsTheModalAlert() async throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSAlert.runModal"))
        let title = "Merge confirmation modal \(UUID().uuidString)"

        let confirmed = await ask(window: nil, title: title)

        #expect(confirmed == false)
        #expect(DreamderHeadless.suppressedModals.contains(title))
    }

    @Test
    func askForAHiddenWindowShowsTheModalAlert() async throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSAlert.runModal"))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        try #require(window.isVisible == false)
        let title = "Merge confirmation hidden \(UUID().uuidString)"

        let confirmed = await ask(window: window, title: title)

        #expect(confirmed == false)
        #expect(DreamderHeadless.suppressedModals.contains(title))
    }

    @Test
    func askForAVisibleWindowShowsASheet() async throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSAlert.beginSheetModalForWindow:completionHandler:"))
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
            Color.clear
        }
        defer { hosted.close() }
        try #require(hosted.window.isVisible)
        let title = "Merge confirmation sheet \(UUID().uuidString)"

        let confirmed = await ask(window: hosted.window, title: title)

        #expect(confirmed == false)
        #expect(DreamderHeadless.suppressedModals.contains(title))
    }

    @Test
    func overrideAnswersWithoutShowingAnything() async {
        let title = "Merge confirmation override \(UUID().uuidString)"

        let accepted = await MergeToolConfirmation.$override.withValue(true) {
            await ask(window: nil, title: title)
        }
        let declined = await MergeToolConfirmation.$override.withValue(false) {
            await ask(window: nil, title: title)
        }

        #expect(accepted)
        #expect(declined == false)
        #expect(DreamderHeadless.suppressedModals.contains(title) == false)
    }

    @Test
    func automationAnswerIsConsumedByTheNextQuestionOnly() async throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSAlert.runModal"))
        let title = "Merge confirmation automation \(UUID().uuidString)"
        MergeToolConfirmation.automationAnswer = true

        let automated = await ask(window: nil, title: title)
        #expect(automated)
        #expect(MergeToolConfirmation.automationAnswer == nil)
        #expect(DreamderHeadless.suppressedModals.contains(title) == false)

        let manual = await ask(window: nil, title: title)
        #expect(manual == false)
        #expect(DreamderHeadless.suppressedModals.contains(title))
    }
}
