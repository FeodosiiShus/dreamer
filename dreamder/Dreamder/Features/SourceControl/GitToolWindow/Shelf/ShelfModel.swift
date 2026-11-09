import Foundation
import Observation

struct ShelfDialogs {
    var promptName: (_ title: String, _ message: String, _ initialValue: String) -> String?
    var confirm: (_ title: String, _ message: String, _ confirmTitle: String) -> Bool
    var error: (_ title: String, _ message: String) -> Void
    var notify: (BranchesPopupNotificationRequest) -> Void

    static let live = ShelfDialogs(
        promptName: { title, message, initialValue in
            BranchesPopupPrompt.name(title: title, message: message, placeholder: "Name", initialValue: initialValue)
        },
        confirm: { title, message, confirmTitle in
            BranchesPopupPrompt.confirm(title: title, message: message, confirmTitle: confirmTitle)
        },
        error: { title, message in
            BranchesPopupPrompt.error(title: title, message: message)
        },
        notify: { request in
            BranchesPopupNotifications.post(request)
        }
    )
}

@Observable
@MainActor
final class ShelfModel {
    static let defaultName = "Changes"

    private(set) var shelves: [GitShelf] = []
    private(set) var isLoaded = false
    var selectedHash: String?

    @ObservationIgnored private let dialogs: ShelfDialogs
    @ObservationIgnored private weak var manager: SourceControlManager?
    @ObservationIgnored private var showConflicts: () -> Void = {}
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    init(dialogs: ShelfDialogs = .live) {
        self.dialogs = dialogs
    }

    var selectedShelf: GitShelf? {
        shelves.first { $0.hash == selectedHash }
    }

    func attach(manager: SourceControlManager, showConflicts: @escaping () -> Void) {
        self.manager = manager
        self.showConflicts = showConflicts
    }

    func select(_ shelf: GitShelf) {
        selectedHash = shelf.hash
    }

    func enqueue(_ operation: @escaping @MainActor (ShelfModel) async -> Void) {
        let previous = lastOperation
        lastOperation = Task {
            await previous?.value
            await operation(self)
        }
    }

    func settle() async {
        await lastOperation?.value
    }

    func reload() async {
        guard let manager else { return }
        shelves = (try? await manager.shelfList()) ?? []
        if selectedShelf == nil {
            selectedHash = shelves.first?.hash
        }
        isLoaded = true
    }

    func shelveAllChanges() async {
        guard let manager else { return }
        guard let name = dialogs.promptName("Shelve Changes", "Name of the shelf", Self.defaultName) else { return }
        await shelve(files: manager.changedFiles, name: name)
    }

    @discardableResult
    func shelve(files: [GitChangedFile], name: String) async -> GitShelf? {
        guard let manager else { return nil }
        do {
            let shelf = try await manager.shelveChanges(files: files, name: name)
            await reload()
            selectedHash = shelf.hash
            return shelf
        } catch {
            dialogs.error("Shelving failed", Self.message(for: error))
            return nil
        }
    }

    func unshelveSelected(keep: Bool) async {
        guard let shelf = selectedShelf else { return }
        await unshelve(shelf, keep: keep)
    }

    func renameSelected() async {
        guard let shelf = selectedShelf else { return }
        await rename(shelf)
    }

    func deleteSelected() async {
        guard let shelf = selectedShelf else { return }
        await delete(shelf)
    }

    func unshelve(_ shelf: GitShelf, keep: Bool) async {
        guard let manager else { return }
        do {
            let outcome = try await manager.unshelve(shelf, keep: keep)
            await reload()
            if outcome == .conflicts {
                presentConflicts(for: shelf)
            }
        } catch {
            await reload()
            dialogs.error("Unshelve failed", Self.message(for: error))
        }
    }

    func rename(_ shelf: GitShelf) async {
        guard let manager else { return }
        guard let name = dialogs.promptName("Rename Shelf", "New name of the shelf", shelf.name) else { return }
        do {
            try await manager.renameShelf(shelf, to: name)
            await reload()
        } catch {
            await reload()
            dialogs.error("Rename failed", Self.message(for: error))
        }
    }

    func delete(_ shelf: GitShelf) async {
        guard let manager else { return }
        let message = "Delete the shelf \"\(shelf.name)\"? The shelved changes will be lost."
        guard dialogs.confirm("Delete Shelf", message, "Delete") else { return }
        do {
            try await manager.deleteShelf(shelf)
            await reload()
        } catch {
            await reload()
            dialogs.error("Delete failed", Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        (error as? GitShelfError)?.message ?? (error as? GitClient.GitClientError)?.description ?? error.localizedDescription
    }

    private func presentConflicts(for shelf: GitShelf) {
        let present = showConflicts
        present()
        dialogs.notify(
            BranchesPopupNotificationRequest(
                title: "Shelf '\(shelf.name)' unshelved with conflicts",
                description: "Resolve the conflicts to finish unshelving. The shelf was kept.",
                actionTitle: "Resolve Conflicts…",
                action: present
            )
        )
    }
}
