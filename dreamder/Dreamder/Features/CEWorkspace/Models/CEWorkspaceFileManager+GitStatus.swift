import Foundation

extension CEWorkspaceFileManager {
    func applyGitStatuses(_ plan: GitStatusPlan) {
        gitStatusPlan = plan
        var carriers: Set<String> = []
        var changed: Set<CEWorkspaceFile> = []

        for (path, status) in plan.statuses {
            guard let file = flattenedFileItems[path] else { continue }
            mark(file, with: status, carriers: &carriers, changed: &changed)
        }
        for directory in plan.untrackedDirectories where flattenedFileItems[directory] != nil {
            markDescendants(ofDirectory: directory, with: .untracked, carriers: &carriers, changed: &changed)
        }
        for id in statusCarriers.subtracting(carriers) {
            guard let file = flattenedFileItems[id] else { continue }
            let inherited = plan.status(forPath: id)
            if inherited != nil {
                carriers.insert(id)
            }
            if file.gitStatus != inherited {
                file.gitStatus = inherited
                changed.insert(file)
            }
        }

        statusCarriers = carriers
        if !changed.isEmpty {
            notifyObservers(updatedItems: changed)
        }
    }

    private func mark(
        _ file: CEWorkspaceFile,
        with status: GitStatus,
        carriers: inout Set<String>,
        changed: inout Set<CEWorkspaceFile>
    ) {
        carriers.insert(file.id)
        if file.gitStatus != status {
            file.gitStatus = status
            changed.insert(file)
        }
    }

    private func markDescendants(
        ofDirectory directory: String,
        with status: GitStatus,
        carriers: inout Set<String>,
        changed: inout Set<CEWorkspaceFile>
    ) {
        var pending = childrenMap[directory] ?? []
        while let id = pending.popLast() {
            guard let file = flattenedFileItems[id] else { continue }
            mark(file, with: status, carriers: &carriers, changed: &changed)
            pending.append(contentsOf: childrenMap[id] ?? [])
        }
    }
}
