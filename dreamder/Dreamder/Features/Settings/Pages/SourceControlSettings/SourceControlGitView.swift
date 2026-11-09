//
//  SourceControlGitView.swift
//  Dreamder
//
//  Created by Raymond Vleeshouwer on 02/04/23.
//

import SwiftUI
import os

@Observable
@MainActor
final class SourceControlGitModel {
    var authorName: String = "" {
        didSet {
            if hasAppeared {
                persist(id: "authorNameDebouncer", key: "user.name", value: authorName)
            }
        }
    }
    var authorEmail: String = "" {
        didSet {
            if hasAppeared {
                persist(id: "authorEmailDebouncer", key: "user.email", value: authorEmail)
            }
        }
    }
    var defaultBranch: String = "" {
        didSet {
            if hasAppeared {
                persist(id: "defaultBranchDebouncer", key: "init.defaultBranch", value: defaultBranch)
            }
        }
    }
    var preferRebaseWhenPulling: Bool = false {
        didSet {
            if hasAppeared {
                persist(id: "pullRebaseDebouncer", key: "pull.rebase", value: preferRebaseWhenPulling)
            }
        }
    }
    var hasAppeared: Bool = false
    var resolvedGitIgnorePath: String = "~/.gitignore_global"

    let ignorePatterns: IgnorePatternModel

    @ObservationIgnored private let gitConfig: GitConfigClient
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private let debounceInterval: TimeInterval
    @ObservationIgnored private let documentController: any AppDocumentControlling

    nonisolated private static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "SourceControlGitModel")

    init(
        gitConfig: GitConfigClient = GitConfigClient(shellClient: currentWorld.shellClient),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        debounceInterval: TimeInterval = 0.5,
        documentController: any AppDocumentControlling = NSDocumentController.shared,
        ignorePatterns: IgnorePatternModel? = nil
    ) {
        self.gitConfig = gitConfig
        self.homeDirectory = homeDirectory
        self.debounceInterval = debounceInterval
        self.documentController = documentController
        self.ignorePatterns = ignorePatterns ?? IgnorePatternModel(gitConfig: gitConfig, homeDirectory: homeDirectory)
    }

    func load() async {
        do {
            authorName = try await gitConfig.get(key: "user.name", global: true) ?? ""
            authorEmail = try await gitConfig.get(key: "user.email", global: true) ?? ""
            defaultBranch = try await gitConfig.get(key: "init.defaultBranch", global: true) ?? ""
            preferRebaseWhenPulling = try await gitConfig.get(key: "pull.rebase", global: true) ?? false
            try? await Task.sleep(for: .milliseconds(0))
            hasAppeared = true
        } catch {
            Self.logger.error("Failed to read git config: \(error.localizedDescription, privacy: .public)")
        }
    }

    func resolveGitIgnorePath() async {
        resolvedGitIgnorePath = await gitIgnorePath()
    }

    func gitIgnoreURL() async throws -> URL {
        if let excludesfile: String = try await gitConfig.get(
            key: "core.excludesfile",
            global: true
        ), !excludesfile.isEmpty {
            if excludesfile.starts(with: "~/") {
                let relativePath = String(excludesfile.dropFirst(2))
                return homeDirectory.appending(path: relativePath)
            } else if excludesfile.starts(with: "/") {
                return URL(fileURLWithPath: excludesfile)
            } else {
                return homeDirectory.appending(path: excludesfile)
            }
        } else {
            let defaultURL = homeDirectory.appending(
                path: ".gitignore_global"
            )
            await gitConfig.set(key: "core.excludesfile", value: "~/\(defaultURL.lastPathComponent)", global: true)
            return defaultURL
        }
    }

    func gitIgnorePath() async -> String {
        do {
            let url = try await gitIgnoreURL()
            return url.path.replacingOccurrences(of: homeDirectory.path, with: "~")
        } catch {
            return "~/.gitignore_global"
        }
    }

    func openGitConfigFile() {
        let fileURL = homeDirectory.appending(path: ".gitconfig")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        documentController.openDocument(
            withContentsOf: fileURL,
            display: true
        ) { _, _, error in
            if let error = error {
                Self.logger.error("Failed to open document: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func openGitIgnoreFile() {
        Task {
            do {
                let fileURL = try await gitIgnoreURL()

                // Ensure the file exists
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                }

                // Open the file in the editor
                try await open(fileURL)
            } catch {
                Self.logger.error("Failed to open document: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func open(_ fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            documentController.openDocument(withContentsOf: fileURL, display: true) { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func persist<Value: GitConfigRepresentable & Sendable>(id: String, key: String, value: Value) {
        let gitConfig = gitConfig
        Limiter.debounce(id: id, duration: debounceInterval) {
            Task {
                await gitConfig.set(key: key, value: value, global: true)
            }
        }
    }
}

struct SourceControlGitView: View {
    @AppSettings(\.sourceControl.git)
    var git

    @State private var model: SourceControlGitModel

    init(model: SourceControlGitModel = SourceControlGitModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            Section {
                gitAuthorName
                gitEmail
            } header: {
                Text("Git Configuration")
                Text("""
                Applied globally to all repositories on your Mac. \
                [Learn more...](https://git-scm.com/docs/git-config)
                """)
            }
            Section {
                defaultBranchName
                preferToRebaseWhenPulling
                showMergeCommitsInPerFileLog
            }
            Section {
                gitConfigEditor
            }
            Section {
                IgnoredFilesListView(model: model.ignorePatterns)
            } header: {
                Text("Ignored Files")
                Text("""
                Patterns for files and folders that Git should ignore and not track. \
                Applied globally to all repositories on your Mac. \
                [Learn more...](https://git-scm.com/docs/gitignore)
                """)
            }
            Section {
                gitIgnoreEditor
            }
        }
        .onAppear {
            // Intentionally using an onAppear with a Task instead of just a .task modifier.
            // When we did this it was executing too often.
            Task {
                await model.load()
            }
        }
    }
}

private extension SourceControlGitView {
    private var gitAuthorName: some View {
        TextField("Author Name", text: $model.authorName)
    }

    private var gitEmail: some View {
        TextField("Author Email", text: $model.authorEmail)
    }

    private var defaultBranchName: some View {
        TextField(text: $model.defaultBranch) {
            Text("Default branch name")
            Text("Cannot contain spaces, backslashes, or other symbols")
        }
    }

    private var preferToRebaseWhenPulling: some View {
        Toggle(
            "Prefer to rebase when pulling",
            isOn: $model.preferRebaseWhenPulling
        )
    }

    private var showMergeCommitsInPerFileLog: some View {
        Toggle(
            "Show merge commits in per-file log",
            isOn: $git.showMergeCommitsPerFileLog
        )
    }

    private var gitConfigEditor: some View {
        HStack {
            Text("Git configuration is stored in \"~/.gitconfig\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in Editor...", action: model.openGitConfigFile)
        }
        .frame(maxWidth: .infinity)
    }

    private var gitIgnoreEditor: some View {
        HStack {
            Text("Ignored file patterns are stored in \"\(model.resolvedGitIgnorePath)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in Editor...", action: model.openGitIgnoreFile)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Task {
                await model.resolveGitIgnorePath()
            }
        }
    }
}
