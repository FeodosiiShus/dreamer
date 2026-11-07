import AppKit
import Combine
import SwiftUI

@propertyWrapper
struct MergeConflictsMenuState: DynamicProperty {
    @State private var store = Store()

    var wrappedValue: Bool { store.hasUnmergedFiles }

    func update() {
        store.start()
    }

    @Observable
    final class Store {
        private(set) var hasUnmergedFiles = false

        @ObservationIgnored private var statesObservation: Task<Void, Never>?
        @ObservationIgnored private var keyWindowCancellable: AnyCancellable?

        func start() {
            guard statesObservation == nil else { return }
            statesObservation = Task { [weak self] in
                for await _ in Observations({ _ = MergeConflictsCenter.shared.states }) {
                    guard let self else { return }
                    refresh()
                }
            }
            keyWindowCancellable = NSApp.publisher(for: \.keyWindow)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.refresh()
                    }
                }
        }

        isolated deinit {
            statesObservation?.cancel()
        }

        @MainActor
        func refresh() {
            guard let manager = MergeToolPresenter.activeWorkspace()?.sourceControlManager else {
                set(false)
                return
            }
            MergeConflictsCenter.shared.monitor(manager)
            set(MergeConflictsCenter.shared.hasConflicts(rootURL: manager.workspaceURL))
        }

        private func set(_ value: Bool) {
            if hasUnmergedFiles != value {
                hasUnmergedFiles = value
            }
        }
    }
}
