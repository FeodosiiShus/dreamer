import Combine
import Foundation

final class CommitToolWindowViewModel: ObservableObject {
    @Published var message = ""
    @Published var amend = false
    @Published var excludedIDs: Set<String> = []
    @Published var includedUnversionedIDs: Set<String> = []
    @Published private(set) var isCommitting = false

    static func isUnversioned(_ file: GitChangedFile) -> Bool {
        file.status == .untracked && file.stagedStatus == GitStatus.none
    }

    func isIncluded(_ file: GitChangedFile) -> Bool {
        if Self.isUnversioned(file) {
            return includedUnversionedIDs.contains(file.id)
        }
        return !excludedIDs.contains(file.id)
    }

    func setIncluded(_ included: Bool, for file: GitChangedFile) {
        if Self.isUnversioned(file) {
            if included {
                includedUnversionedIDs.insert(file.id)
            } else {
                includedUnversionedIDs.remove(file.id)
            }
        } else if included {
            excludedIDs.remove(file.id)
        } else {
            excludedIDs.insert(file.id)
        }
    }

    func versionedFiles(in files: [GitChangedFile]) -> [GitChangedFile] {
        files.filter { !Self.isUnversioned($0) }
    }

    func unversionedFiles(in files: [GitChangedFile]) -> [GitChangedFile] {
        files.filter { Self.isUnversioned($0) }
    }

    func canCommit(in files: [GitChangedFile]) -> Bool {
        guard !isCommitting, files.contains(where: { isIncluded($0) }) else { return false }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func commit(using manager: SourceControlManager, andPush: Bool) async {
        let files = manager.changedFiles
        let included = files.filter { isIncluded($0) }
        let stagedToReset = files.filter { !isIncluded($0) && $0.isStaged }
        guard !included.isEmpty, canCommit(in: files) else { return }

        isCommitting = true
        let wasAmend = amend
        do {
            try await manager.add(included.map(\.fileURL))
            if !stagedToReset.isEmpty {
                try await manager.reset(stagedToReset.map(\.fileURL))
            }
            try await manager.gitClient.commitToolWindow(message: message, amend: wasAmend)
        } catch {
            isCommitting = false
            await manager.showAlertForError(
                title: wasAmend ? "Failed to amend commit" : "Failed to commit",
                error: error
            )
            return
        }

        message = ""
        amend = false
        excludedIDs = []
        includedUnversionedIDs = []
        isCommitting = false
        await manager.refreshAllChangedFiles()
        await manager.refreshNumberOfUnsyncedCommits()
        if andPush {
            manager.pushSheetIsPresented = true
        }
    }

    @MainActor
    func rollback(_ files: [GitChangedFile], using manager: SourceControlManager) async {
        for file in files {
            do {
                let path = file.fileURL.path(percentEncoded: false)
                if Self.isUnversioned(file) || file.status == .added || file.stagedStatus == .added {
                    if !Self.isUnversioned(file) {
                        _ = try await manager.gitClient.run("reset -- \(GitClient.logGraphQuote(path))")
                    }
                    _ = try await manager.gitClient.run("clean -f -- \(GitClient.logGraphQuote(path))")
                } else {
                    _ = try await manager.gitClient.run(
                        "restore --source=HEAD --staged --worktree -- \(GitClient.logGraphQuote(path))"
                    )
                }
            } catch {
                await manager.showAlertForError(title: "Failed to rollback", error: error)
                break
            }
        }
        await manager.refreshAllChangedFiles()
    }
}
