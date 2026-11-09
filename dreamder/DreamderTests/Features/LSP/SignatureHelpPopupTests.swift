import AppKit
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class SignatureHelpSwallowFlag {
    var value = true
}

@MainActor
@Suite(.uiGate)
struct SignatureHelpPopupTests {
    private typealias Fixtures = SignatureHelpFixtures

    private let anchor = NSRect(x: 100, y: 200, width: 2, height: 16)

    private func presentation(_ help: SignatureHelp = Fixtures.twoOverloads()) throws -> SignatureHelpPresentation {
        try #require(SignatureHelpPresentation(help: help))
    }

    private func makePopup(visibleFrame: NSRect? = nil) -> SignatureHelpPopup {
        SignatureHelpPopup(visibleFrameProvider: { _ in visibleFrame })
    }

    private func panels(in window: NSWindow) -> [SignatureHelpPanel] {
        (window.childWindows ?? []).compactMap { $0 as? SignatureHelpPanel }
    }

    private func keyEvent(_ keyCode: UInt16, in window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @Test
    func showingPlacesANonKeyChildPanelAboveTheAnchor() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = makePopup()
        let shown = try presentation()

        popup.show(shown, anchor: anchor, in: parent.window)

        let panel = try #require(panels(in: parent.window).first)
        let size = SignatureHelpMetrics.size(for: shown.rows)
        #expect(popup.isShown)
        #expect(popup.presentation == shown)
        #expect(panel.frame == NSRect(x: anchor.minX, y: anchor.maxY + SignatureHelpPlacement.gap, width: size.width, height: size.height))
        #expect(popup.panelFrame == panel.frame)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.isFloatingPanel)
        let hosting = try #require(panel.contentView as? NSHostingView<SignatureHelpView>)
        #expect(hosting.sizingOptions == [])
        popup.close()
    }

    @Test
    func showingAgainReusesThePanelAndReplacesTheContent() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = makePopup()
        popup.show(try presentation(Fixtures.oneOverload()), anchor: anchor, in: parent.window)
        let first = try #require(panels(in: parent.window).first)

        let overloads = try presentation()
        let moved = NSRect(x: 300, y: 400, width: 2, height: 16)
        popup.show(overloads, anchor: moved, in: parent.window)

        #expect(panels(in: parent.window).count == 1)
        #expect(panels(in: parent.window).first === first)
        #expect(first.frame.origin == NSPoint(x: 300, y: 420))
        #expect(first.frame.size == SignatureHelpMetrics.size(for: overloads.rows))
        #expect(popup.presentation == overloads)
        popup.close()
    }

    @Test
    func showingInAnotherWindowMovesThePanelThere() throws {
        let first = HostedViewFixture.host { Color.clear }
        let second = HostedViewFixture.host { Color.clear }
        defer {
            first.close()
            second.close()
        }
        let popup = makePopup()
        popup.show(try presentation(), anchor: anchor, in: first.window)

        popup.show(try presentation(), anchor: anchor, in: second.window)

        #expect(panels(in: first.window).isEmpty)
        #expect(panels(in: second.window).count == 1)
        popup.close()
    }

    @Test
    func visibleFrameDecidesBetweenAboveAndBelow() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let shown = try presentation()
        let size = SignatureHelpMetrics.size(for: shown.rows)
        let tight = NSRect(x: 0, y: 0, width: 2_000, height: anchor.maxY + size.height)
        let popup = makePopup(visibleFrame: tight)

        popup.show(shown, anchor: anchor, in: parent.window)

        let frame = try #require(popup.panelFrame)
        #expect(frame.maxY <= anchor.minY)
        popup.close()
    }

    @Test
    func hidingRemovesThePanelAndKeepsItReusable() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = makePopup()
        popup.hide()
        #expect(!popup.isShown)
        #expect(popup.panelFrame == nil)

        popup.show(try presentation(), anchor: anchor, in: parent.window)
        popup.hide()

        #expect(!popup.isShown)
        #expect(popup.presentation == nil)
        #expect(panels(in: parent.window).isEmpty)
        popup.show(try presentation(), anchor: anchor, in: parent.window)
        #expect(panels(in: parent.window).count == 1)
        popup.close()
        #expect(panels(in: parent.window).isEmpty)
        #expect(popup.panelFrame == nil)
    }

    @Test
    func cyclingMovesTheActiveSignatureOnlyWhileShown() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = makePopup()
        popup.cycle(by: 1)
        #expect(popup.presentation == nil)

        popup.show(try presentation(), anchor: anchor, in: parent.window)
        popup.cycle(by: 1)
        #expect(popup.presentation?.activeIndex == 1)
        popup.cycle(by: 1)
        #expect(popup.presentation?.activeIndex == 0)
        popup.cycle(by: -1)
        #expect(popup.presentation?.activeIndex == 1)
        popup.hide()
        popup.cycle(by: 1)
        #expect(popup.presentation == nil)
        popup.close()
    }

    @Test
    func keyHandlerSeesKeysOnlyWhileTheMonitorIsInstalled() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = makePopup()
        var seen: [UInt16] = []
        let swallow = SignatureHelpSwallowFlag()
        popup.keyHandler = { event in
            seen.append(event.keyCode)
            return swallow.value
        }

        popup.show(try presentation(), anchor: anchor, in: parent.window)
        popup.show(try presentation(), anchor: anchor, in: parent.window)
        NSApp.sendEvent(try keyEvent(40, in: parent.window))
        swallow.value = false
        NSApp.sendEvent(try keyEvent(41, in: parent.window))
        popup.hide()
        NSApp.sendEvent(try keyEvent(42, in: parent.window))

        #expect(seen == [40, 41])
        popup.close()
    }

    @Test
    func monitorWithoutAKeyHandlerLeavesKeysAlone() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = makePopup()
        popup.show(try presentation(), anchor: anchor, in: parent.window)

        NSApp.sendEvent(try keyEvent(43, in: parent.window))

        #expect(popup.isShown)
        popup.close()
    }

    @Test
    func deallocatingThePopupClosesThePanelAndTheMonitor() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        var popup: SignatureHelpPopup? = makePopup()
        weak let weakPopup = popup
        var seen = 0
        popup?.keyHandler = { _ in
            seen += 1
            return true
        }
        popup?.show(try presentation(), anchor: anchor, in: parent.window)

        popup = nil
        NSApp.sendEvent(try keyEvent(44, in: parent.window))

        #expect(weakPopup == nil)
        #expect(seen == 0)
        #expect(panels(in: parent.window).isEmpty)
    }

    @Test
    func screenVisibleFrameFollowsTheScreenContainingTheAnchor() throws {
        #expect(SignatureHelpPopup.screenVisibleFrame(containing: NSRect(x: -9_000_000, y: -9_000_000, width: 1, height: 1)) == nil)
        guard let screen = NSScreen.screens.first else { return }
        let inside = NSRect(x: screen.frame.midX, y: screen.frame.midY, width: 2, height: 16)

        #expect(SignatureHelpPopup.screenVisibleFrame(containing: inside) != nil)
    }

    @Test
    func aPopupWithoutAVisibleFrameProviderPlacesItselfOnTheScreenOfTheAnchor() throws {
        let parent = HostedViewFixture.host { Color.clear }
        defer { parent.close() }
        let popup = SignatureHelpPopup()
        popup.show(try presentation(), anchor: anchor, in: parent.window)

        #expect(popup.isShown)
        #expect(panels(in: parent.window).count == 1)
        popup.close()
    }
}
