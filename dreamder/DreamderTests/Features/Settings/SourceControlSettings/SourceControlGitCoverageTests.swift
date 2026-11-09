import AppKit
import Foundation
import SwiftUI
import Synchronization
import Testing
@testable import Dreamder

nonisolated final class CovExtGitConfigStore: Sendable {
    private struct State {
        var values: [String: String]
        var failing = false
        var sets: [[String]] = []
    }

    private let state: Mutex<State>

    init(_ values: [String: String] = [:]) {
        state = Mutex(State(values: values))
    }

    var values: [String: String] {
        state.withLock { $0.values }
    }

    var recordedSets: [[String]] {
        state.withLock { $0.sets }
    }

    func setFailing(_ failing: Bool) {
        state.withLock { $0.failing = failing }
    }

    func handle(_ invocation: ProcessInvocation) -> ProcessOutput {
        guard let configIndex = invocation.arguments.firstIndex(of: "config") else {
            return FakeProcessRunner.output("", stderr: "unexpected command", exitCode: 129)
        }
        let rest = Array(invocation.arguments[(configIndex + 1)...]).filter { $0 != "--global" }
        return state.withLock { state in
            if state.failing {
                return FakeProcessRunner.output("", stderr: "fatal: bad config", exitCode: 128)
            }
            if rest.count == 2, rest[0] == "--unset" {
                let existed = state.values.removeValue(forKey: rest[1]) != nil
                state.sets.append(rest)
                return FakeProcessRunner.output("", exitCode: existed ? 0 : 5)
            }
            if rest.count == 1 {
                guard let value = state.values[rest[0]] else {
                    return FakeProcessRunner.output("", exitCode: 1)
                }
                return FakeProcessRunner.output(value + "\n")
            }
            if rest.count == 2 {
                state.values[rest[0]] = rest[1]
                state.sets.append(rest)
                return FakeProcessRunner.output("")
            }
            return FakeProcessRunner.output("", stderr: "unsupported", exitCode: 129)
        }
    }
}

@MainActor
final class CovExtGitDocumentController: AppDocumentControlling {
    var documents: [NSDocument] = []
    var error: (any Error)?
    private(set) var opened: [URL] = []

    func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        opened.append(url)
        completionHandler(nil, false, error)
    }

    func openDocument(_ sender: Any?) {}

    func newDocument(_ sender: Any?) {}

    func closeAllDocuments(
        withDelegate delegate: Any?,
        didCloseAllSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {}
}

@MainActor
enum CovExtGitModelFixtures {
    static func gitConfig(_ store: CovExtGitConfigStore) -> GitConfigClient {
        let runner = FakeProcessRunner(handler: { store.handle($0) })
        let commandRunner = GitCommandRunner(
            runner: runner,
            gitExecutable: URL(fileURLWithPath: "/usr/bin/git"),
            baseEnvironment: { [:] }
        )
        return GitConfigClient(commandRunner: commandRunner)
    }

    static func model(
        home: URL,
        store: CovExtGitConfigStore,
        controller: CovExtGitDocumentController = CovExtGitDocumentController(),
        ignorePatterns: IgnorePatternModel? = nil
    ) -> SourceControlGitModel {
        SourceControlGitModel(
            gitConfig: gitConfig(store),
            homeDirectory: home,
            debounceInterval: 0.02,
            documentController: controller,
            ignorePatterns: ignorePatterns
        )
    }

    static func ignoreModel(home: URL, store: CovExtGitConfigStore) -> IgnorePatternModel {
        IgnorePatternModel(gitConfig: gitConfig(store), homeDirectory: home)
    }

    static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct SourceControlGitModelCoverageTests {
    private let author = [
        "user.name": "Ada",
        "user.email": "ada@example.com",
        "init.defaultBranch": "trunk",
        "pull.rebase": "true"
    ]

    @Test
    func loadReadsTheGlobalAuthorBranchAndRebaseSettings() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(author)
            let model = CovExtGitModelFixtures.model(home: home, store: store)

            await model.load()

            #expect(model.authorName == "Ada")
            #expect(model.authorEmail == "ada@example.com")
            #expect(model.defaultBranch == "trunk")
            #expect(model.preferRebaseWhenPulling)
            #expect(model.hasAppeared)
            try await Task.sleep(for: .milliseconds(120))
            #expect(store.recordedSets.isEmpty)
        }
    }

    @Test
    func loadWithoutStoredKeysUsesEmptyDefaults() async throws {
        try await withTempDir { home in
            let model = CovExtGitModelFixtures.model(home: home, store: CovExtGitConfigStore())

            await model.load()

            #expect(model.authorName.isEmpty)
            #expect(model.authorEmail.isEmpty)
            #expect(model.defaultBranch.isEmpty)
            #expect(model.preferRebaseWhenPulling == false)
            #expect(model.hasAppeared)
        }
    }

    @Test
    func loadFailureLeavesTheModelUnarmed() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(author)
            store.setFailing(true)
            let model = CovExtGitModelFixtures.model(home: home, store: store)

            await model.load()

            #expect(model.hasAppeared == false)
            #expect(model.authorName.isEmpty)
        }
    }

    @Test
    func editsBeforeLoadAreNotPersisted() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore()
            let model = CovExtGitModelFixtures.model(home: home, store: store)

            model.authorName = "Early"
            model.authorEmail = "early@example.com"
            model.defaultBranch = "early"
            model.preferRebaseWhenPulling = true
            try await Task.sleep(for: .milliseconds(120))

            #expect(store.recordedSets.isEmpty)
        }
    }

    @Test
    func editsAfterLoadAreWrittenToTheGlobalConfig() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore()
            let model = CovExtGitModelFixtures.model(home: home, store: store)
            await model.load()

            model.authorName = "Grace"
            model.authorEmail = "grace@example.com"
            model.defaultBranch = "main"
            model.preferRebaseWhenPulling = true

            try await eventually(timeout: .seconds(10)) {
                let values = store.values
                return values["user.name"] == "Grace"
                    && values["user.email"] == "grace@example.com"
                    && values["init.defaultBranch"] == "main"
                    && values["pull.rebase"] == "true"
            }
        }
    }

    @Test
    func clearingValuesUnsetsTheConfigKeys() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(author)
            let model = CovExtGitModelFixtures.model(home: home, store: store)
            await model.load()

            model.preferRebaseWhenPulling = false
            try await eventually(timeout: .seconds(10)) { store.values["pull.rebase"] == nil }
            model.authorName = ""
            try await eventually(timeout: .seconds(10)) { store.values["user.name"] == nil }
        }
    }

    @Test(arguments: ExcludesFileStyle.allCases)
    func ignoreFileResolvesAgainstTheHomeDirectory(style: ExcludesFileStyle) async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(["core.excludesfile": style.configValue(home: home)])
            let model = CovExtGitModelFixtures.model(home: home, store: store)

            let url = try await model.gitIgnoreURL()
            let path = await model.gitIgnorePath()

            #expect(url.path == style.fileURL(home: home).path)
            #expect(path == "~/\(style.fileURL(home: home).lastPathComponent)")
        }
    }

    @Test(arguments: [nil, ""] as [String?])
    func unsetOrEmptyExcludesFileFallsBackToTheGlobalIgnoreFile(configured: String?) async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(configured.map { ["core.excludesfile": $0] } ?? [:])
            let model = CovExtGitModelFixtures.model(home: home, store: store)

            let url = try await model.gitIgnoreURL()

            #expect(url.path == home.appending(path: ".gitignore_global").path)
            #expect(store.values["core.excludesfile"] == "~/.gitignore_global")
        }
    }

    @Test
    func resolvingThePathUpdatesTheDisplayedPathAndFallsBackOnFailure() async throws {
        try await withTempDir { home in
            let store = CovExtGitConfigStore(["core.excludesfile": "~/nested.ignore"])
            let model = CovExtGitModelFixtures.model(home: home, store: store)
            #expect(model.resolvedGitIgnorePath == "~/.gitignore_global")

            await model.resolveGitIgnorePath()
            #expect(model.resolvedGitIgnorePath == "~/nested.ignore")

            store.setFailing(true)
            await model.resolveGitIgnorePath()
            #expect(model.resolvedGitIgnorePath == "~/.gitignore_global")
        }
    }

    @Test
    func openingTheGitConfigCreatesTheFileAndOpensItInTheEditor() async throws {
        try withTempDir { home in
            let controller = CovExtGitDocumentController()
            let model = CovExtGitModelFixtures.model(home: home, store: CovExtGitConfigStore(), controller: controller)
            let configFile = home.appending(path: ".gitconfig")

            model.openGitConfigFile()

            #expect(FileManager.default.fileExists(atPath: configFile.path))
            #expect(controller.opened == [configFile])
        }
    }

    @Test
    func openingAnExistingGitConfigKeepsItsContentAndSurvivesOpenFailures() async throws {
        try withTempDir { home in
            let controller = CovExtGitDocumentController()
            controller.error = CovExtGitFailure()
            let model = CovExtGitModelFixtures.model(home: home, store: CovExtGitConfigStore(), controller: controller)
            let configFile = home.appending(path: ".gitconfig")
            try CovExtGitModelFixtures.write("[user]\n\tname = Ada\n", to: configFile)

            model.openGitConfigFile()

            #expect(controller.opened == [configFile])
            #expect(try String(contentsOf: configFile, encoding: .utf8) == "[user]\n\tname = Ada\n")
        }
    }

    @Test
    func openingTheIgnoreFileCreatesItAndOpensItInTheEditor() async throws {
        try await withTempDir { home in
            let controller = CovExtGitDocumentController()
            let store = CovExtGitConfigStore(["core.excludesfile": "~/nested.ignore"])
            let model = CovExtGitModelFixtures.model(home: home, store: store, controller: controller)
            let ignoreFile = home.appending(path: "nested.ignore")

            model.openGitIgnoreFile()

            try await eventually { controller.opened.count == 1 }
            #expect(controller.opened == [ignoreFile])
            #expect(FileManager.default.fileExists(atPath: ignoreFile.path))
        }
    }

    @Test
    func openingAnExistingIgnoreFileReportsEditorFailuresWithoutCrashing() async throws {
        try await withTempDir { home in
            let controller = CovExtGitDocumentController()
            controller.error = CovExtGitFailure()
            let store = CovExtGitConfigStore(["core.excludesfile": "~/nested.ignore"])
            let model = CovExtGitModelFixtures.model(home: home, store: store, controller: controller)
            let ignoreFile = home.appending(path: "nested.ignore")
            try CovExtGitModelFixtures.write("*.log\n", to: ignoreFile)

            model.openGitIgnoreFile()

            try await eventually { controller.opened.count == 1 }
            try await Task.sleep(for: .milliseconds(50))
            #expect(try String(contentsOf: ignoreFile, encoding: .utf8) == "*.log\n")
        }
    }

    @Test
    func openingTheIgnoreFileWithFailingConfigOpensNothing() async throws {
        try await withTempDir { home in
            let controller = CovExtGitDocumentController()
            let store = CovExtGitConfigStore()
            store.setFailing(true)
            let model = CovExtGitModelFixtures.model(home: home, store: store, controller: controller)

            model.openGitIgnoreFile()
            try await Task.sleep(for: .milliseconds(150))

            #expect(controller.opened.isEmpty)
        }
    }

    @Test
    func ignorePatternsShareTheConfiguredGitConfigAndHome() async throws {
        try await withTempDir { home in
            try CovExtGitModelFixtures.write("*.log\n", to: home.appending(path: ".gitignore_global"))
            let store = CovExtGitConfigStore(["core.excludesfile": "~/.gitignore_global"])
            let model = CovExtGitModelFixtures.model(home: home, store: store)

            await model.ignorePatterns.loadPatterns()

            #expect(model.ignorePatterns.patterns.map(\.value) == ["*.log"])
        }
    }

    @Test
    func suppliedIgnorePatternModelIsUsedAsIs() async throws {
        try withTempDir { home in
            let store = CovExtGitConfigStore()
            let ignore = CovExtGitModelFixtures.ignoreModel(home: home, store: store)

            let model = CovExtGitModelFixtures.model(home: home, store: store, ignorePatterns: ignore)

            #expect(model.ignorePatterns === ignore)
        }
    }

    @Test
    func defaultModelBuildsWithoutTouchingGit() {
        let model = SourceControlGitModel()

        #expect(model.authorName.isEmpty)
        #expect(model.hasAppeared == false)
    }
}
