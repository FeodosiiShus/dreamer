import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class KeybindingsFakeMonitoring: NSEventMonitoring {
    private(set) var localHandlers: [(NSEvent) -> NSEvent?] = []
    private(set) var localMatching: [NSEvent.EventTypeMask] = []
    private(set) var removed: [Int] = []

    func addLocalMonitor(matching: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        localHandlers.append(handler)
        localMatching.append(matching)
        return localHandlers.count
    }

    func removeMonitor(_ monitor: Any) {
        if let token = monitor as? Int {
            removed.append(token)
        }
    }
}

@MainActor
private final class ModifierKeysRecorder {
    var keys: NSEvent.ModifierFlags = []
}

private struct ModifierKeysProbe: View {
    @Environment(\.modifierKeys) private var modifierKeys
    let recorder: ModifierKeysRecorder

    var body: some View {
        Color.clear
            .onChange(of: modifierKeys, initial: true, record)
    }

    func record(_ oldValue: NSEvent.ModifierFlags, _ newValue: NSEvent.ModifierFlags) {
        recorder.keys = newValue
    }
}

@MainActor
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
            keyCode: 63
        )
    )
}

@MainActor
@Suite(.uiGate)
struct ModifierKeysObserverCoverageTests {
    @Test
    func environmentValueDefaultsToNoModifiersAndStoresWhatIsSet() {
        var environment = EnvironmentValues()
        #expect(environment.modifierKeys == [])
        #expect(EventModifierEnvironmentKey.defaultValue == [])

        environment.modifierKeys = [.shift, .command]

        #expect(environment.modifierKeys == [.shift, .command])
    }

    @Test
    func startingRegistersOneFlagsChangedMonitorThatPublishesTheFlagsAndPassesTheEventOn() throws {
        let monitoring = KeybindingsFakeMonitoring()
        let model = ModifierKeysModel(monitoring: monitoring)
        #expect(model.flags == [])

        model.start()
        model.start()
        let event = try makeFlagsChangedEvent(.shift)
        let handler = try #require(monitoring.localHandlers.first)
        let returned = handler(event)

        #expect(monitoring.localHandlers.count == 1)
        #expect(monitoring.localMatching == [.flagsChanged])
        #expect(returned === event)
        #expect(model.flags.contains(.shift))
    }

    @Test
    func stoppingRemovesTheMonitorOnlyOnceAndStartingAgainRegistersANewOne() {
        let monitoring = KeybindingsFakeMonitoring()
        let model = ModifierKeysModel(monitoring: monitoring)
        model.stop()
        #expect(monitoring.removed.isEmpty)

        model.start()
        model.stop()
        model.stop()
        #expect(monitoring.removed == [1])

        model.start()
        #expect(monitoring.localHandlers.count == 2)
    }

    @Test
    func releasingTheModelRemovesTheMonitorAndTheHandlerIgnoresLaterEvents() throws {
        let monitoring = KeybindingsFakeMonitoring()
        var model: ModifierKeysModel? = ModifierKeysModel(monitoring: monitoring)
        model?.start()
        let handler = try #require(monitoring.localHandlers.first)

        model = nil

        #expect(monitoring.removed == [1])
        let event = try makeFlagsChangedEvent(.option)
        #expect(handler(event) === event)
    }

    @Test
    func liveMonitoringPublishesFlagChangesSentThroughTheApplicationUntilStopped() throws {
        let model = ModifierKeysModel()
        model.start()

        NSApp.sendEvent(try makeFlagsChangedEvent(.function))
        #expect(model.flags.contains(.function))

        model.stop()
        NSApp.sendEvent(try makeFlagsChangedEvent(.control))
        #expect(!model.flags.contains(.control))
    }

    @Test
    func windowObserverPublishesTheModifierKeysIntoTheEnvironment() async throws {
        let recorder = ModifierKeysRecorder()
        let hosted = HostedViewFixture.host {
            WindowObserver(window: WindowBox(value: nil)) {
                ModifierKeysProbe(recorder: recorder)
            }
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))

        NSApp.sendEvent(try makeFlagsChangedEvent(.shift))

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return recorder.keys.contains(.shift)
        }
    }
}
