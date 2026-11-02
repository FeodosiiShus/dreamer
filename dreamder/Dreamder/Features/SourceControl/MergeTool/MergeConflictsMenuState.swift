import AppKit
import Combine
import SwiftUI

@propertyWrapper
struct MergeConflictsMenuState: DynamicProperty {
    @StateObject private var store = Store()

    var wrappedValue: Bool { store.hasUnmergedFiles }

    final class Store: ObservableObject {
        @Published private(set) var hasUnmergedFiles = false

        private var cancellables: Set<AnyCancellable> = []

        init() {
            DispatchQueue.main.async { [weak self] in
                self?.subscribe()
            }
        }

        private func subscribe() {
            MainActor.assumeIsolated {
                let center = MergeConflictsCenter.shared
                center.$states
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.refresh()
                        }
                    }
                    .store(in: &cancellables)
                NSApp.publisher(for: \.keyWindow)
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.refresh()
                        }
                    }
                    .store(in: &cancellables)
                refresh()
            }
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
