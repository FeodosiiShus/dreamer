import Foundation
import Testing
@testable import Dreamder

struct ExternalFormatterChooserCase: CustomTestStringConvertible, Sendable {
    let name: String
    let existing: [String]
    let file: String
    let selection: NSRange?
    let expected: ExternalFormatterKind?

    var testDescription: String { name }
}

@Suite("ExternalFormatterChooser")
struct ExternalFormatterChooserTests {
    static let root = URL(filePath: "/work/project", directoryHint: .isDirectory)
    static let prettier = "/work/project/node_modules/.bin/prettier"
    static let biome = "/work/project/node_modules/.bin/biome"
    static let selection = NSRange(location: 4, length: 10)

    static let cases: [ExternalFormatterChooserCase] = [
        ExternalFormatterChooserCase(
            name: "prettier present", existing: [prettier], file: "src/a.ts", selection: nil, expected: .prettier
        ),
        ExternalFormatterChooserCase(
            name: "biome only", existing: [biome], file: "src/a.ts", selection: nil, expected: .biome
        ),
        ExternalFormatterChooserCase(
            name: "both prefer prettier", existing: [prettier, biome], file: "src/a.ts", selection: nil,
            expected: .prettier
        ),
        ExternalFormatterChooserCase(
            name: "none", existing: [], file: "src/a.ts", selection: nil, expected: nil
        ),
        ExternalFormatterChooserCase(
            name: "unsupported extension", existing: [prettier, biome], file: "src/a.swift", selection: nil,
            expected: nil
        ),
        ExternalFormatterChooserCase(
            name: "no extension", existing: [prettier, biome], file: "Makefile", selection: nil, expected: nil
        ),
        ExternalFormatterChooserCase(
            name: "prettier only handles markdown", existing: [prettier, biome], file: "README.md", selection: nil,
            expected: .prettier
        ),
        ExternalFormatterChooserCase(
            name: "biome cannot handle markdown", existing: [biome], file: "README.md", selection: nil, expected: nil
        ),
        ExternalFormatterChooserCase(
            name: "uppercase extension", existing: [prettier], file: "Style.CSS", selection: nil, expected: .prettier
        ),
        ExternalFormatterChooserCase(
            name: "selection with prettier", existing: [prettier, biome], file: "src/a.ts", selection: selection,
            expected: .prettier
        ),
        ExternalFormatterChooserCase(
            name: "selection with biome falls back", existing: [biome], file: "src/a.ts", selection: selection,
            expected: nil
        ),
        ExternalFormatterChooserCase(
            name: "empty selection formats everything with biome", existing: [biome], file: "src/a.ts",
            selection: NSRange(location: 3, length: 0), expected: .biome
        ),
        ExternalFormatterChooserCase(
            name: "binary elsewhere", existing: ["/other/node_modules/.bin/prettier"], file: "src/a.ts",
            selection: nil, expected: nil
        )
    ]

    @Test(arguments: cases)
    func choosesTheFormatterTheWorkspaceInstallsAndTheFileTypeAllows(_ item: ExternalFormatterChooserCase) {
        let existing = Set(item.existing)

        let chosen = ExternalFormatterChooser.choose(
            root: Self.root,
            fileURL: Self.root.appending(path: item.file),
            selection: item.selection,
            fileExists: { existing.contains($0) }
        )

        #expect(chosen?.kind == item.expected)
    }

    @Test
    func chosenFormatterCarriesExecutableRootFileAndOnlyANonEmptySelection() throws {
        let fileURL = Self.root.appending(path: "src/a.ts")

        let whole = try #require(ExternalFormatterChooser.choose(
            root: Self.root,
            fileURL: fileURL,
            selection: NSRange(location: 2, length: 0),
            fileExists: { $0 == Self.prettier }
        ))
        let ranged = try #require(ExternalFormatterChooser.choose(
            root: Self.root,
            fileURL: fileURL,
            selection: Self.selection,
            fileExists: { $0 == Self.prettier }
        ))

        #expect(whole.executable.path(percentEncoded: false) == Self.prettier)
        #expect(whole.root == Self.root)
        #expect(whole.fileURL == fileURL)
        #expect(whole.selection == nil)
        #expect(ranged.selection == Self.selection)
    }

    @Test
    func prettierArgumentsUseStdinFilepathAndUTF16RangeOffsets() {
        let fileURL = Self.root.appending(path: "src/a.ts")
        let executable = URL(filePath: Self.prettier)

        let whole = ExternalFormatter(kind: .prettier, executable: executable, root: Self.root, fileURL: fileURL, selection: nil)
        let ranged = ExternalFormatter(kind: .prettier, executable: executable, root: Self.root, fileURL: fileURL, selection: Self.selection)

        #expect(whole.arguments == ["--stdin-filepath", "/work/project/src/a.ts"])
        #expect(ranged.arguments == [
            "--stdin-filepath", "/work/project/src/a.ts", "--range-start", "4", "--range-end", "14"
        ])
    }

    @Test
    func biomeArgumentsFormatFromStdin() {
        let fileURL = Self.root.appending(path: "src/a.ts")

        let formatter = ExternalFormatter(
            kind: .biome,
            executable: URL(filePath: Self.biome),
            root: Self.root,
            fileURL: fileURL,
            selection: nil
        )

        #expect(formatter.arguments == ["format", "--stdin-file-path=/work/project/src/a.ts"])
    }

    @Test
    func everyKindHasABinaryNameRangeSupportAndExtensions() {
        #expect(ExternalFormatterKind.prettier.binaryName == "prettier")
        #expect(ExternalFormatterKind.biome.binaryName == "biome")
        #expect(ExternalFormatterKind.prettier.supportsRange)
        #expect(!ExternalFormatterKind.biome.supportsRange)
        #expect(ExternalFormatterKind.biome.handledExtensions.isSubset(of: ExternalFormatterKind.prettier.handledExtensions))
        #expect(ExternalFormatterKind.allCases == [.prettier, .biome])
    }
}

@Suite("ExternalFormatterRunner")
struct ExternalFormatterRunnerTests {
    private let formatter = ExternalFormatter(
        kind: .prettier,
        executable: URL(filePath: "/work/project/node_modules/.bin/prettier"),
        root: URL(filePath: "/work/project", directoryHint: .isDirectory),
        fileURL: URL(filePath: "/work/project/src/a.ts"),
        selection: nil
    )

    private struct LaunchFailure: Error {}

    @Test
    func invocationPipesTheTextThroughStdinInTheWorkspaceRootWithATimeout() {
        let runner = ExternalFormatterRunner(
            runner: FakeProcessRunner { _ in FakeProcessRunner.output("") },
            environment: ["PATH": "/opt/node/bin"],
            timeout: .seconds(7)
        )

        let invocation = runner.invocation(for: formatter, text: "let  x=1\n")

        #expect(invocation.executable == formatter.executable)
        #expect(invocation.arguments == ["--stdin-filepath", "/work/project/src/a.ts"])
        #expect(invocation.workingDirectory == formatter.root)
        #expect(invocation.environment == ["PATH": "/opt/node/bin"])
        #expect(invocation.standardInput == Data("let  x=1\n".utf8))
        #expect(invocation.timeout == Duration.seconds(7))
    }

    @Test
    func defaultTimeoutIsThirtySeconds() {
        let runner = ExternalFormatterRunner(runner: FakeProcessRunner { _ in FakeProcessRunner.output("") })

        #expect(runner.timeout == .seconds(30))
        #expect(runner.environment.isEmpty)
    }

    @Test
    func successfulRunReturnsTheFormattedStdout() async {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("let x = 1;\n") }

        let outcome = await ExternalFormatterRunner(runner: fake).format(formatter, text: "let  x=1\n")

        #expect(outcome == .formatted("let x = 1;\n"))
        #expect(fake.invocations.count == 1)
    }

    @Test
    func nonZeroExitReportsTrimmedStderr() async {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("partial", stderr: "  SyntaxError: boom\n", exitCode: 2) }

        let outcome = await ExternalFormatterRunner(runner: fake).format(formatter, text: "x")

        #expect(outcome == .failed("SyntaxError: boom"))
    }

    @Test
    func nonZeroExitWithoutStderrNamesTheExitCode() async {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 3) }

        let outcome = await ExternalFormatterRunner(runner: fake).format(formatter, text: "x")

        #expect(outcome == .failed("prettier exited with code 3"))
    }

    @Test
    func signalTerminationIsAFailure() async {
        let fake = FakeProcessRunner { _ in
            ProcessOutput(exitCode: 0, terminatedBySignal: true, standardOutput: Data("x".utf8))
        }

        let outcome = await ExternalFormatterRunner(runner: fake).format(formatter, text: "x")

        #expect(outcome == .failed("prettier exited with code 0"))
    }

    @Test
    func launchErrorsAreReportedWithTheFormatterName() async {
        let fake = FakeProcessRunner { _ in throw LaunchFailure() }

        let outcome = await ExternalFormatterRunner(runner: fake).format(formatter, text: "x")

        guard case .failed(let message) = outcome else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.hasPrefix("prettier: "))
    }
}
