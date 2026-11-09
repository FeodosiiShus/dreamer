//
//  GitCloneViewModel.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/17/23.
//

import Foundation
import AppKit

struct GitCloneServices {
    var processRunner: any ProcessRunning = ProcessRunner()
    var clipboardText: @MainActor () -> String? = { NSPasteboard.general.string(forType: .string) }
    var filePanels: any FilePanelPresenting = SystemFilePanels()
    var presentAlert: @MainActor (NSAlert) -> Void = { _ = $0.runModal() }
    var makeGitClient: @MainActor (URL) -> GitClient = { GitClient(directoryURL: $0, shellClient: .live()) }
}

@Observable
class GitCloneViewModel {
    var repoUrlStr = ""
    var isCloning: Bool = false
    var cloningProgress: GitClient.CloneProgress = .init(progress: 0, state: .initialState)

    @ObservationIgnored var gitClient: GitClient?
    @ObservationIgnored var cloningTask: Task<Void, Never>?
    @ObservationIgnored private let services: GitCloneServices

    init(services: GitCloneServices = GitCloneServices()) {
        self.services = services
    }

    /// Check if url is valid
    /// - Parameter url: Url to check
    /// - Returns: True if url is valid
    func isValidUrl(url: String) -> Bool {
        // Doing the same kind of check that Xcode does when cloning
        let url = url.lowercased()
        if url.starts(with: "http://") && url.count > 7 {
            return true
        } else if url.starts(with: "https://") && url.count > 8 {
            return true
        } else if url.starts(with: "git@") && url.count > 4 {
            return true
        }
        return false
    }
    /// Check if Git is installed
    /// - Returns: True if Git is found by running "which git" command
    func isGitInstalled() async -> Bool {
        let invocation = ProcessInvocation(executable: URL(fileURLWithPath: "/usr/bin/which"), arguments: ["git"])
        return (try? await services.processRunner.run(invocation))?.succeeded == true
    }

    /// Check if clipboard contains git url
    func checkClipboard() {
        if let url = services.clipboardText(), isValidUrl(url: url) {
            self.repoUrlStr = url
        }
    }

    /// Clone repository
    func cloneRepository(completionHandler: @escaping (URL) -> Void) {
        cloningTask = Task {
            await prepareCloning(completionHandler: completionHandler)
        }
    }

    func cancelCloning() {
        cloningTask?.cancel()
        cloningTask = nil
        isCloning = false
    }

    private func prepareCloning(completionHandler: @escaping (URL) -> Void) async {
        if await !isGitInstalled() {
            showAlert(
                alertMsg: "Git installation not found.",
                infoText: "Ensure Git is installed on your system and try again."
            )
            return
        }
        if repoUrlStr == "" {
            showAlert(
                alertMsg: "Url cannot be empty",
                infoText: "You must specify a repository to clone"
            )
            return
        }

        // Parsing repo name
        guard let remoteUrl = URL(string: repoUrlStr) else {
            return
        }

        var repoName = remoteUrl.lastPathComponent

        // Strip .git from name if it has it.
        // Cloning repository without .git also works
        if repoName.hasSuffix(".git") {
            repoName.removeLast(4)
        }

        guard let localPath = getPath(saveName: repoName) else {
            return
        }

        if FileManager.default.fileExists(atPath: localPath.relativePath) {
            showAlert(alertMsg: "Error", infoText: "Directory already exists")
            return
        }

        do {
            try FileManager.default.createDirectory(
                atPath: localPath.relativePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            showAlert(alertMsg: "Failed to create folder", infoText: "\(error)")
            return
        }

        let gitClient = services.makeGitClient(localPath)
        self.gitClient = gitClient

        await processCloning(
            gitClient: gitClient,
            remoteUrl: remoteUrl,
            localPath: localPath,
            completionHandler: completionHandler
        )
    }

    /// Process cloning
    /// - Parameters:
    ///   - remoteUrl: Path to remote repository
    ///   - localPath: Path to local folder
    ///   - completionHandler: Completion handler if cloning is successful
    private func processCloning(
        gitClient: GitClient,
        remoteUrl: URL,
        localPath: URL,
        completionHandler: @escaping (URL) -> Void
    ) async {
        isCloning = true

        do {
            for try await progress in gitClient.cloneRepository(remoteUrl: remoteUrl, localPath: localPath) {
                cloningProgress = progress
            }

            if Task.isCancelled {
                deleteTemporaryFolder(localPath: localPath)
                return
            }

            completionHandler(localPath)
        } catch {
            if let error = error as? GitClient.GitClientError {
                showAlert(alertMsg: "Failed to clone", infoText: error.description)
            } else {
                showAlert(alertMsg: "Failed to clone", infoText: error.localizedDescription)
            }
            deleteTemporaryFolder(localPath: localPath)
        }

        isCloning = false
    }

    private func deleteTemporaryFolder(localPath: URL) {
        do {
            try FileManager.default.removeItem(atPath: localPath.relativePath)
        } catch {
            showAlert(alertMsg: "Failed to delete folder", infoText: "\(error)")
        }
    }

    private func getPath(saveName: String) -> URL? {
        let request = SavePanelRequest(
            title: "Clone a Repository",
            prompt: "Clone",
            nameFieldLabel: "Clone as",
            nameFieldStringValue: saveName,
            showsTagField: false
        )
        return services.filePanels.chooseSaveLocation(request)
    }

    private func showAlert(alertMsg: String, infoText: String) {
        let alert = NSAlert()
        alert.messageText = alertMsg
        alert.informativeText = infoText
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        services.presentAlert(alert)
    }
}
