//
//  SourceControlModel.swift
//  Dreamder
//
//  Created by Nanashi Li on 2022/05/20.
//

import Foundation
import AppKit
import OSLog

/// This class is used to perform git functions such as fetch, pull, add/remove of changes, commit, push, etc.
/// It also stores remotes, branches, current changes, stashes, and commits
@Observable
@MainActor
final class SourceControlManager {
    let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "SourceControlManager")

    let gitClient: GitClient
    let changedFilesRefresh = CoalescedRefresh()

    /// The base URL of the workspace
    let workspaceURL: URL

    let repositoryURL: URL

    var lastAlert: SourceControlAlert?

    let editorManager: EditorManager
    @ObservationIgnored weak var fileManager: CEWorkspaceFileManager?

    /// A list of changed files
    var changedFiles: [GitChangedFile] = []

    var changedFilesFailure: String?

    /// Current branch
    var currentBranch: GitBranch?

    var currentHeadCommit: String?

    /// All branches, local and remote
    var branches: [GitBranch] = []

    /// All remotes
    var remotes: [GitRemote] = []

    /// All stashed entries
    var stashEntries: [GitStashEntry] = []

    /// Number of unsynced commits with remote in current branch
    var numberOfUnsyncedCommits: (ahead: Int, behind: Int) = (ahead: 0, behind: 0)

    /// Is project a git repository
    var isGitRepository: Bool = false

    /// Is the push sheet presented
    var pushSheetIsPresented: Bool = false {
        didSet {
            self.operationBranch = nil
            self.operationRebase = false
            self.operationForce = false
            self.operationIncludeTags = false
        }
    }

    /// Is the pull sheet presented
    var pullSheetIsPresented: Bool = false {
        didSet {
            self.operationBranch = nil
            self.operationRebase = false
            self.operationForce = false
            self.operationIncludeTags = false
        }
    }

    /// Is the fetch sheet presented
    var fetchSheetIsPresented: Bool = false

    /// Is the stash sheet presented
    var stashSheetIsPresented: Bool = false

    /// Is the remote sheet presented
    var addExistingRemoteSheetIsPresented: Bool = false

    /// Branch selected for source control operations
    var operationBranch: GitBranch?

    /// Remote selected for source control operations
    var operationRemote: GitRemote?

    /// Rebase boolean set for source control operations
    var operationRebase: Bool = false

    /// Force boolean set for source control operations
    var operationForce: Bool = false

    /// Include tags boolean set for source control operations
    var operationIncludeTags: Bool = false

    /// Branch to switch to
    var switchToBranch: GitBranch?

    /// Is discard all alert presented
    var discardAllAlertIsPresented: Bool = false

    /// Is no changes to stage alert presented
    var noChangesToStageAlertIsPresented: Bool = false

    /// Is no changes to unstage alert presented
    var noChangesToUnstageAlertIsPresented: Bool = false

    /// Is no changes to stash alert presented
    var noChangesToStashAlertIsPresented: Bool = false

    /// Is no changes to discard alert presented
    var noChangesToDiscardAlertIsPresented: Bool = false

    var orderedLocalBranches: [GitBranch] {
        var orderedBranches: [GitBranch] = [currentBranch].compactMap { $0 }
        let otherBranches = branches.filter { $0.isLocal && $0 != currentBranch }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        orderedBranches.append(contentsOf: otherBranches)
        return orderedBranches
    }

    init(
        workspaceURL: URL,
        editorManager: EditorManager,
        gitClient: GitClient? = nil
    ) {
        self.workspaceURL = workspaceURL
        self.editorManager = editorManager
        let location = Self.repositoryLocation(of: workspaceURL)
        let components = location?.prefix?.split(separator: "/") ?? []
        let repositoryURL = components.reduce(workspaceURL) { url, _ in url.deletingLastPathComponent() }
        self.repositoryURL = repositoryURL
        self.gitClient = gitClient ?? GitClient(
            directoryURL: repositoryURL,
            shellClient: currentWorld.shellClient,
            scopePath: location?.prefix
        )
        isGitRepository = location != nil
    }

    struct RepositoryLocation: Equatable {
        let prefix: String?
    }

    static func repositoryLocation(of workspaceURL: URL) -> RepositoryLocation? {
        var directory = workspaceURL.standardizedFileURL
        var components: [String] = []
        while directory.pathComponents.count > 1 {
            guard directory.lastPathComponent != ".git" else { return nil }
            let gitEntry = directory.appending(path: ".git", directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: gitEntry.path(percentEncoded: false)) {
                let prefix = components.reversed().joined(separator: "/")
                return RepositoryLocation(prefix: prefix.isEmpty ? nil : prefix)
            }
            components.append(directory.lastPathComponent)
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    /// Show alert for error
    func showAlertForError(title: String, error: Error) async {
        if let error = error as? GitClient.GitClientError {
            await showAlert(title: title, message: error.description)
            return
        }

        if let error = error as? LocalizedError {
            var description = error.errorDescription ?? ""
            if let failureReason = error.failureReason {
                if description.isEmpty {
                    description += failureReason
                } else {
                    description += "\n\n" + failureReason
                }
            }

            if let recoverySuggestion = error.recoverySuggestion {
                if description.isEmpty {
                    description += recoverySuggestion
                } else {
                    description += "\n\n" + recoverySuggestion
                }
            }

            await showAlert(title: title, message: description)
        } else {
            await showAlert(title: title, message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) async {
        await MainActor.run {
            lastAlert = SourceControlAlert(title: title, message: message)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

struct SourceControlAlert: Equatable {
    let title: String
    let message: String
}
