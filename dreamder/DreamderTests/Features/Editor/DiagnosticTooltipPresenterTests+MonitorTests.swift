import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
extension DiagnosticTooltipPresenterTests {
    @Test
    func monitorForwardsMouseMovesAndDismissesOnInput() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let clock = TestClock()
            let log = PopoverLog()
            let presenter = DiagnosticTooltipPresenter(
                delay: .milliseconds(5),
                clock: clock,
                popoverFactory: log.factory
            ) { _, _ in model("any") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            try await awaitLayout(of: session.textView)
            let target = try point(ofOffset: 4, in: session.textView)

            NSApp.sendEvent(try mouseEvent(.mouseMoved, at: target, in: session.textView))
            #expect(presenter.pendingModel == model("any"))
            try await clock.waitForSleepers()
            clock.advance(by: .milliseconds(5))
            try await eventually(timeout: .seconds(30)) { presenter.popover != nil }
            #expect(log.models == [model("any")])

            NSApp.sendEvent(try mouseEvent(.leftMouseDown, at: target, in: session.textView))
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel == nil)

            try await awaitLayout(of: session.textView)
            let movedTarget = try point(ofOffset: 4, in: session.textView)
            try await eventually {
                NSApp.sendEvent(try mouseEvent(.mouseMoved, at: movedTarget, in: session.textView))
                return presenter.pendingModel == model("any")
            }
            presenter.remove()
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel == nil)

            NSApp.sendEvent(try mouseEvent(.mouseMoved, at: target, in: session.textView))
            #expect(presenter.pendingModel == nil)
        }
    }

    @Test
    func eventsFromOtherWindowsAreIgnored() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            defer { session.close() }
            let presenter = DiagnosticTooltipPresenter(delay: .milliseconds(5)) { _, _ in model("any") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            let other = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            other.isReleasedWhenClosed = false
            defer { other.close() }
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: NSPoint(x: 10, y: 10),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: other.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 0,
                    pressure: 0
                )
            )

            presenter.handle(event)

            #expect(presenter.pendingModel == nil)
        }
    }

    @Test
    func presentingAfterTheTextViewLeftItsWindowIsSkipped() async throws {
        try await withTempDir { directory in
            let session = try await DecorationsCoverageHost.open(in: directory, contents: Self.source) { fixture in
                [fixture.document.contentCoordinator]
            }
            let clock = TestClock()
            let log = PopoverLog()
            let presenter = DiagnosticTooltipPresenter(
                delay: .milliseconds(30),
                clock: clock,
                popoverFactory: log.factory
            ) { _, _ in model("any") }
            presenter.install(textView: session.textView)
            defer { presenter.remove() }
            try await awaitLayout(of: session.textView)

            presenter.hover(at: try point(ofOffset: 4, in: session.textView))
            try await clock.waitForSleepers()
            session.textView.removeFromSuperview()
            session.close()
            clock.advance(by: .milliseconds(30))
            await Task.yield()
            await Task.yield()

            #expect(log.models.isEmpty)
            #expect(presenter.popover == nil)
            #expect(presenter.pendingModel != nil)
        }
    }
}
