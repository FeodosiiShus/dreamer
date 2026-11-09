import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WindowObserverTests {
    @MainActor
    private final class EnvironmentRecorder {
        private(set) var fullscreenStates: [Bool] = []
        private(set) var modifierStates: [NSEvent.ModifierFlags] = []
        private(set) var windows: [NSWindow?] = []

        var lastFullscreen: Bool? { fullscreenStates.last }
        var lastModifiers: NSEvent.ModifierFlags? { modifierStates.last }
        var lastWindow: NSWindow? { windows.last ?? nil }

        func record(isFullscreen: Bool, modifiers: NSEvent.ModifierFlags, window: NSWindow?) {
            fullscreenStates.append(isFullscreen)
            modifierStates.append(modifiers)
            windows.append(window)
        }
    }

    private struct EnvironmentProbe: View {
        @Environment(\.isFullscreen) private var isFullscreen
        @Environment(\.modifierKeys) private var modifierKeys
        @Environment(\.window) private var window
        let recorder: EnvironmentRecorder

        var body: some View {
            let _ = recorder.record(isFullscreen: isFullscreen, modifiers: modifierKeys, window: window.value)
            Color.clear
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func host(observing window: NSWindow, recorder: EnvironmentRecorder) -> HostedView {
        HostedViewFixture.host {
            WindowObserver(window: WindowBox(value: window)) {
                EnvironmentProbe(recorder: recorder)
            }
        }
    }

    private func makeFlagsChangedEvent(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56
            )
        )
    }

    private func postUntil(
        _ name: Notification.Name,
        from window: NSWindow,
        reaches condition: () -> Bool
    ) async throws {
        try await eventually(timeout: .seconds(30)) {
            if !condition() {
                NotificationCenter.default.post(name: name, object: window)
            }
            return condition()
        }
    }

    @Test
    func contentReceivesTheObservedWindowAndStartsOutsideFullscreen() async throws {
        let observed = makeWindow()
        defer { observed.close() }
        let recorder = EnvironmentRecorder()
        let hosted = host(observing: observed, recorder: recorder)
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) { recorder.lastFullscreen != nil }

        #expect(recorder.lastFullscreen == false)
        #expect(recorder.lastWindow === observed)
    }

    @Test
    func theObservedWindowEnteringAndLeavingFullscreenUpdatesTheContentEnvironment() async throws {
        let observed = makeWindow()
        defer { observed.close() }
        let recorder = EnvironmentRecorder()
        let hosted = host(observing: observed, recorder: recorder)
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) { recorder.lastFullscreen != nil }

        try await postUntil(NSWindow.didEnterFullScreenNotification, from: observed) {
            recorder.lastFullscreen == true
        }

        try await postUntil(NSWindow.willExitFullScreenNotification, from: observed) {
            recorder.lastFullscreen == false
        }
    }

    @Test
    func fullscreenTransitionsOfOtherWindowsAreIgnored() async throws {
        let observed = makeWindow()
        let other = makeWindow()
        defer {
            observed.close()
            other.close()
        }
        let recorder = EnvironmentRecorder()
        let hosted = host(observing: observed, recorder: recorder)
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) { recorder.lastFullscreen != nil }

        try await postUntil(NSWindow.didEnterFullScreenNotification, from: observed) {
            recorder.lastFullscreen == true
        }

        NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: other)
        try await hosted.settle()

        #expect(recorder.lastFullscreen == true)
    }

    @Test
    func modifierKeyChangesReachTheContentEnvironment() async throws {
        let observed = makeWindow()
        defer { observed.close() }
        let recorder = EnvironmentRecorder()
        let hosted = host(observing: observed, recorder: recorder)
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) { recorder.lastFullscreen != nil }
        let shift = try makeFlagsChangedEvent(.shift)
        let released = try makeFlagsChangedEvent([])

        try await eventually(timeout: .seconds(30)) {
            if recorder.lastModifiers != .shift {
                NSApp.sendEvent(shift)
            }
            return recorder.lastModifiers == .shift
        }

        try await eventually(timeout: .seconds(30)) {
            if recorder.lastModifiers != [] {
                NSApp.sendEvent(released)
            }
            return recorder.lastModifiers == []
        }
    }
}
