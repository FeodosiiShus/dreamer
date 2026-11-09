import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CargoPackageManagerTests {
    static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using cargo"
    static let repository = "https://github.com/acme/tool"
    static let hostileNames = [
        "../../x", "a;rm -rf ~", "-rf", "..", ".", "", "a/b", "a\u{0}b", "a b", "$(touch x)", "`id`"
    ]
    static let hostileArguments = [
        "", "-rf", "a;rm -rf ~", "a b", "$(touch x)", "`id`", "a\u{0}b", "a\"b", "a'b", "a=b", "a:b", "a|b", "a&b"
    ]

    private func directory(_ root: URL) -> URL {
        root.appending(path: "tool-entry")
    }

    func unsafeInstall(_ source: PackageSource, root: URL = URL(filePath: "/tmp/ls")) -> String {
        let manager = CargoPackageManager(installationDirectory: root)
        return errorKind(thrownError { try manager.install(method: .standardPackage(source: source)) })
    }

    @Test
    func installRejectsEverythingButStandardPackages() {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = PackageManagerFixtures.source(type: .cargo)
        let rejected: [InstallationMethod] = [
            .unknown,
            .sourceBuild(source: source, command: "make"),
            .binaryDownload(source: source, url: URL(filePath: "/tmp/tool.zip"))
        ]
        for method in rejected {
            let failure = thrownError { try manager.install(method: method) }
            #expect(errorKind(failure) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func installInitializesTheDirectoryThenInstallsThePackage() throws {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = PackageManagerFixtures.source(type: .cargo)

        let steps = try manager.install(method: .standardPackage(source: source))

        #expect(steps.map(\.name) == [Self.initializeName, Self.installName])
        #expect(steps.map { $0.confirmation.message } == [
            nil,
            "This requires the cargo package tool@1.0.0.\nAllow Dreamder to install this package?"
        ])
    }

    @Test
    func initializeRecreatesThePackageDirectory() async throws {
        try await withTempDir { root in
            let manager = CargoPackageManager(installationDirectory: root)
            let source = PackageManagerFixtures.source(type: .cargo)
            let steps = try manager.install(method: .standardPackage(source: source))
            let package = directory(root)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("stale".utf8).write(to: package.appending(path: "stale.txt"))

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps))

            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
            let stalePath = package.appending(path: "stale.txt").path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: stalePath))
            #expect(outcome.statuses == [
                "Removing existing installation.",
                "Creating directory: \(package.path(percentEncoded: false))"
            ])
        }
    }

    @Test
    func cargoInstallCommandFollowsTheSourceDescription() async throws {
        let repository = Self.repository
        let cases: [(PackageSource, [String])] = [
            (PackageManagerFixtures.source(type: .cargo), ["cargo", "install", "--root", ".", "tool@1.0.0"]),
            (
                PackageManagerFixtures.source(type: .cargo, options: ["features": "a,b", "locked": "true"]),
                ["cargo", "install", "--root", ".", "tool@1.0.0", "--features", "a,b", "--locked"]
            ),
            (
                PackageManagerFixtures.source(type: .cargo, options: ["locked": "false"]),
                ["cargo", "install", "--root", ".", "tool@1.0.0"]
            ),
            (
                PackageManagerFixtures.source(type: .cargo, repositoryUrl: repository, gitReference: .tag("v1")),
                ["cargo", "install", "--root", ".", "--git", repository, "--tag", "v1"]
            ),
            (
                PackageManagerFixtures.source(
                    type: .cargo, repositoryUrl: repository, gitReference: .revision("abc123")
                ),
                ["cargo", "install", "--root", ".", "--git", repository, "--rev", "abc123"]
            ),
            (
                PackageManagerFixtures.source(
                    type: .cargo,
                    repositoryUrl: repository,
                    gitReference: .tag("v1"),
                    options: ["features": "x,y", "locked": "true"]
                ),
                ["cargo", "install", "--root", ".", "--git", repository, "--tag", "v1", "--features", "x,y", "--locked"]
            ),
            (
                PackageManagerFixtures.source(type: .cargo, repositoryUrl: repository),
                ["cargo", "install", "--root", ".", "tool@1.0.0"]
            ),
            (
                PackageManagerFixtures.source(type: .cargo, gitReference: .tag("v1")),
                ["cargo", "install", "--root", ".", "tool@1.0.0"]
            )
        ]
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/Application Support/tool")

        for (source, expected) in cases {
            let shell = ScriptedProcesses()
            let outcome = await runStep(try manager.runCargoInstall(source, in: package), shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.arguments == [expected])
            #expect(shell.workingDirectories == ["/tmp/ls/Application Support/tool"])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
            #expect(outcome.statuses == [expected.joined(separator: " ")])
        }
    }

    @Test
    func oddButAllowedValuesArriveAsSingleArguments() async throws {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/tool")
        let shell = ScriptedProcesses()
        let source = PackageManagerFixtures.source(
            type: .cargo,
            pkgName: "cargo-tool_x+y",
            version: "^1.2.3-rc.1+build",
            options: ["features": "x,y,z/w"]
        )

        let outcome = await runStep(try manager.runCargoInstall(source, in: package), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.arguments == [[
            "cargo", "install", "--root", ".", "cargo-tool_x+y@^1.2.3-rc.1+build", "--features", "x,y,z/w"
        ]])
    }

    @Test
    func aFailingCargoInstallSurfacesTheShellError() async throws {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(101) }

        let outcome = await runStep(
            try manager.runCargoInstall(PackageManagerFixtures.source(type: .cargo), in: URL(filePath: "/tmp/ls/tool")),
            shell: shell
        )

        #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 101)")
    }

    @Test
    func isInstalledAcceptsCargoVersionOutput() async {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedProcesses { _ in FakeProcessRunner.output("cargo 1.80.0 (376290515 2024-07-16)\n") }

        let step = manager.isInstalled(method: .unknown)
        let outcome = await runStep(step, shell: shell)

        #expect(step.confirmation.message == nil)
        #expect(outcome.error == nil)
        #expect(shell.arguments == [["cargo", "--version"]])
        #expect(shell.workingDirectories == [nil])
        #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
    }

    @Test
    func isInstalledRejectsOtherOutputAndMissingCargo() async {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let unrelated = await runStep(
            manager.isInstalled(method: .unknown),
            shell: ScriptedProcesses { _ in FakeProcessRunner.output("zsh: command not found: cargo\n") }
        )
        #expect(errorKind(unrelated.error) == "PackageManagerError.packageManagerNotInstalled")

        let failing = await runStep(
            manager.isInstalled(method: .unknown),
            shell: ScriptedProcesses { _ in ScriptedProcesses.failing(127) }
        )
        #expect(errorKind(failing.error) == "ShellClientError.taskTerminated(code: 127)")
    }

    @Test
    func binaryPathIsTheBinDirectoryOfThePackage() {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/Language Servers"))
        #expect(manager.getBinaryPath(for: "tool") == "/tmp/Language Servers/tool/bin")
    }
}
