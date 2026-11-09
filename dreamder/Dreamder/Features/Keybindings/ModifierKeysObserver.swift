//
//  ModifierKeysObserver.swift
//  Dreamder
//
//  Created by Wouter Hennen on 04/03/2023.
//

import SwiftUI

struct EventModifierEnvironmentKey: EnvironmentKey {
    static var defaultValue: NSEvent.ModifierFlags = []
}

extension EnvironmentValues {
    var modifierKeys: EventModifierEnvironmentKey.Value {
        get { self[EventModifierEnvironmentKey.self] }
        set { self[EventModifierEnvironmentKey.self] = newValue }
    }
}

protocol NSEventMonitoring {
    func addLocalMonitor(matching: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    func removeMonitor(_ monitor: Any)
}

struct LiveNSEventMonitoring: NSEventMonitoring {
    func addLocalMonitor(matching: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: matching, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

@Observable
@MainActor
final class ModifierKeysModel {
    private(set) var flags: NSEvent.ModifierFlags = []

    @ObservationIgnored private let monitoring: any NSEventMonitoring
    @ObservationIgnored private var monitor: Any?

    init(monitoring: any NSEventMonitoring = LiveNSEventMonitoring()) {
        self.monitoring = monitoring
    }

    func start() {
        guard monitor == nil else { return }
        monitor = monitoring.addLocalMonitor(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated {
                self?.flags = flags
            }
            return event
        }
    }

    func stop() {
        guard let monitor else { return }
        self.monitor = nil
        monitoring.removeMonitor(monitor)
    }

    isolated deinit {
        stop()
    }
}
