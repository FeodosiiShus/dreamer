import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated final class FakeGitConfig: Sendable {
    private struct State {
        var excludesFile: String?
        var failing = false
        var sets: [[String]] = []
    }

    private let state: Mutex<State>

    init(excludesFile: String?) {
        state = Mutex(State(excludesFile: excludesFile))
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
        let rest = Array(invocation.arguments[(configIndex + 1)...])
        let keyAndValue = rest.filter { $0 != "--global" }
        return state.withLock { state in
            if state.failing {
                return FakeProcessRunner.output("", stderr: "fatal: bad config", exitCode: 128)
            }
            if keyAndValue.count == 1 {
                guard let value = state.excludesFile else {
                    return FakeProcessRunner.output("", exitCode: 1)
                }
                return FakeProcessRunner.output(value + "\n")
            }
            state.sets.append(rest)
            state.excludesFile = keyAndValue.last
            return FakeProcessRunner.output("")
        }
    }
}

nonisolated enum ExcludesFileStyle: String, Sendable, CaseIterable {
    case tilde
    case relative
    case absolute

    func configValue(home: URL) -> String {
        switch self {
        case .tilde: "~/nested.ignore"
        case .relative: "relative.ignore"
        case .absolute: home.appending(path: "absolute.ignore").path
        }
    }

    func fileURL(home: URL) -> URL {
        switch self {
        case .tilde: home.appending(path: "nested.ignore")
        case .relative: home.appending(path: "relative.ignore")
        case .absolute: home.appending(path: "absolute.ignore")
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct IgnorePatternModelTests {
    private func makeModel(home: URL, config: FakeGitConfig) -> IgnorePatternModel {
        let runner = FakeProcessRunner(handler: { config.handle($0) })
        let commandRunner = GitCommandRunner(
            runner: runner,
            gitExecutable: URL(fileURLWithPath: "/usr/bin/git"),
            baseEnvironment: { [:] }
        )
        return IgnorePatternModel(
            gitConfig: GitConfigClient(commandRunner: commandRunner),
            homeDirectory: home
        )
    }

    private func globalFile(in home: URL) -> URL {
        home.appending(path: ".gitignore_global")
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func waitForContent(_ url: URL, _ expected: String) async {
        await waitForExpectation(timeout: .seconds(15), {
            (try? String(contentsOf: url, encoding: .utf8)) == expected
        }, onTimeout: {})
        let actual = try? String(contentsOf: url, encoding: .utf8)
        #expect(actual == expected)
    }

    private func waitForLines(_ url: URL, _ expected: [String]) async {
        func lines() -> [String]? {
            (try? String(contentsOf: url, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        }
        await waitForExpectation(timeout: .seconds(15), { lines() == expected }, onTimeout: {})
        let actual = lines()
        #expect(actual == expected)
    }

    @Test
    func loadSkipsCommentsBlankLinesAndTrimsWhitespace() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("# comment\n\n  *.log  \nbuild/\n   \n#x\n!keep.log\r\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))

            await model.loadPatterns()

            #expect(model.patterns.map(\.value) == ["*.log", "build/", "!keep.log"])
            #expect(Set(model.patterns.map(\.id)).count == 3)
            #expect(model.loadingPatterns == false)
        }
    }

    @Test
    func loadFromMissingFileYieldsNoPatternsAndCreatesNothing() async throws {
        try await withTempDir { home in
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))

            await model.loadPatterns()

            #expect(model.patterns.isEmpty)
            #expect(FileManager.default.fileExists(atPath: globalFile(in: home).path) == false)
        }
    }

    @Test
    func loadOfUndecodableFileClearsPatterns() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()
            #expect(model.patterns.map(\.value) == ["a"])

            try Data([0xFF, 0xFE, 0x41]).write(to: file)
            await model.loadPatterns()

            #expect(model.patterns.isEmpty)
        }
    }

    @Test(arguments: ExcludesFileStyle.allCases)
    func excludesFileValueResolvesAgainstHomeDirectory(style: ExcludesFileStyle) async throws {
        try await withTempDir { home in
            try write("only\n", to: style.fileURL(home: home))
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: style.configValue(home: home)))

            await model.loadPatterns()

            #expect(model.patterns.map(\.value) == ["only"])
        }
    }

    @Test
    func unsetExcludesFileFallsBackToGlobalFileAndConfiguresGit() async throws {
        try await withTempDir { home in
            try write("fallback\n", to: globalFile(in: home))
            let config = FakeGitConfig(excludesFile: nil)
            let model = makeModel(home: home, config: config)

            await model.loadPatterns()
            await model.loadPatterns()

            #expect(model.patterns.map(\.value) == ["fallback"])
            #expect(config.recordedSets == [["--global", "core.excludesfile", "~/.gitignore_global"]])
        }
    }

    @Test
    func configFailureClearsPatternsAndLeavesFileUntouched() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\nb\n", to: file)
            let config = FakeGitConfig(excludesFile: "~/.gitignore_global")
            let model = makeModel(home: home, config: config)
            await model.loadPatterns()
            #expect(model.patterns.map(\.value) == ["a", "b"])

            config.setFailing(true)
            await model.loadPatterns()

            #expect(model.patterns.isEmpty)
            #expect(model.loadingPatterns == false)
            #expect(try String(contentsOf: file, encoding: .utf8) == "a\nb\n")
        }
    }

    @Test
    func getPatternFindsByIdentifier() async throws {
        try await withTempDir { home in
            try write("a\nb\n", to: globalFile(in: home))
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()

            let second = model.patterns[1]

            #expect(model.getPattern(for: second.id)?.value == "b")
            #expect(model.getPattern(for: UUID()) == nil)
        }
    }

    @Test
    func addPatternAppendsEmptyPatternAndEditingItIsSaved() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()

            model.addPattern()

            #expect(model.patterns.map(\.value) == ["a", ""])

            model.patterns[1].value = "b"

            await waitForContent(file, "a\nb\n")
        }
    }

    @Test
    func savingReordersPatternsKeepingTheCommentsThatFollowThem() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("# header\n\n*.log\n# about tmp\ntmp/\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()

            model.patterns.swapAt(0, 1)

            await waitForContent(file, "# header\n\ntmp/\n*.log\n# about tmp\n")
        }
    }

    @Test
    func addingTheFirstPatternToACommentOnlyFileKeepsEveryComment() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("# header\n\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()
            #expect(model.patterns.isEmpty)

            model.patterns.append(GlobPattern(value: "*.log"))

            await waitForContent(file, "# header\n\n*.log\n")
        }
    }

    @Test
    func removingPatternsClearsSelectionAndKeepsOrphanedComments() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("# header\n\n*.log\n# about tmp\ntmp/\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()
            let log = model.patterns[0]
            model.selection = [log.id]

            model.removePatterns(model.selection)

            #expect(model.patterns.map(\.value) == ["tmp/"])
            #expect(model.selection.isEmpty)
            await waitForContent(file, "# header\n\ntmp/\n# about tmp\n")
        }
    }

    @Test
    func removeWithoutMatchingIdentifiersKeepsPatternsButClearsSelection() async throws {
        try await withTempDir { home in
            try write("a\nb\n", to: globalFile(in: home))
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()
            model.selection = [model.patterns[0].id]

            model.removePatterns(nil)

            #expect(model.patterns.map(\.value) == ["a", "b"])
            #expect(model.selection.isEmpty)

            model.selection = [model.patterns[1].id]
            model.removePatterns([UUID()])

            #expect(model.patterns.map(\.value) == ["a", "b"])
            #expect(model.selection.isEmpty)
        }
    }

    @Test
    func savingWithoutExistingFileCreatesItWithAllPatterns() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))

            model.patterns = [GlobPattern(value: "a"), GlobPattern(value: "b")]

            await waitForLines(file, ["a", "b"])
        }
    }

    @Test
    func savingCollapsesBlankRunsAndKeepsSingleTrailingNewline() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\n\n\n\nb\n\n\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()

            let current = model.patterns
            model.patterns = current

            await waitForContent(file, "a\n\nb\n")
        }
    }

    @Test
    func savingTrimsLeadingBlankLinesAndPatternWhitespace() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("\n\n# top\n a \n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.loadPatterns()

            let current = model.patterns
            model.patterns = current

            await waitForContent(file, "# top\na\n")
        }
    }

    @Test
    func externalWriteToIgnoreFileReloadsPatternsAfterStart() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.start()
            #expect(model.patterns.map(\.value) == ["a"])

            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data("a\n# note\nb\nc\n".utf8))
            try handle.close()

            await waitForExpectation(timeout: .seconds(15), {
                model.patterns.map(\.value) == ["a", "b", "c"]
            }, onTimeout: {})
            #expect(model.patterns.map(\.value) == ["a", "b", "c"])
        }
    }

    @Test
    func startWithoutAnIgnoreFileLoadsNothing() async throws {
        try await withTempDir { home in
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))

            await model.start()

            #expect(model.patterns.isEmpty)
            #expect(FileManager.default.fileExists(atPath: globalFile(in: home).path) == false)
        }
    }

    @Test
    func startWithFailingConfigLoadsNothing() async throws {
        try await withTempDir { home in
            try write("a\n", to: globalFile(in: home))
            let config = FakeGitConfig(excludesFile: "~/.gitignore_global")
            config.setFailing(true)
            let model = makeModel(home: home, config: config)

            await model.start()

            #expect(model.patterns.isEmpty)
            #expect(model.loadingPatterns == false)
        }
    }

    @Test
    func savingAfterStartRestartsTheFileMonitor() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\n", to: file)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/.gitignore_global"))
            await model.start()

            model.addPattern()
            model.patterns[1].value = "b"

            await waitForContent(file, "a\nb\n")
            try await Task.sleep(for: .milliseconds(200))
            #expect(model.patterns.map(\.value) == ["a", "b"])
        }
    }

    @Test
    func savingWithFailingConfigLeavesTheFileUntouched() async throws {
        try await withTempDir { home in
            let file = globalFile(in: home)
            try write("a\n", to: file)
            let config = FakeGitConfig(excludesFile: "~/.gitignore_global")
            let model = makeModel(home: home, config: config)
            await model.loadPatterns()

            config.setFailing(true)
            model.patterns = [GlobPattern(value: "z")]
            try await Task.sleep(for: .milliseconds(200))

            #expect(try String(contentsOf: file, encoding: .utf8) == "a\n")
        }
    }

    @Test
    func savingWhenTheIgnorePathIsADirectoryKeepsTheDirectory() async throws {
        try await withTempDir { home in
            let directory = home.appending(path: "ignore-dir")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let model = makeModel(home: home, config: FakeGitConfig(excludesFile: "~/ignore-dir"))

            model.patterns = [GlobPattern(value: "a")]
            try await Task.sleep(for: .milliseconds(200))

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
    }
}
