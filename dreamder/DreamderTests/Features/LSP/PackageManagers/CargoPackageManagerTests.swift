import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CargoPackageManagerTests {
    private static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using cargo"

    private func directory(_ root: URL) -> URL {
        root.appending(path: "tool-entry")
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
            #expect(errorKind(thrownError { try manager.install(method: method) }) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func installInitializesTheDirectoryThenInstallsThePackage() throws {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = PackageManagerFixtures.source(type: .cargo)

        let steps = try manager.install(method: .standardPackage(source: source))

        #expect(steps.map(\.name) == [Self.initializeName, Self.installName])
        #expect(steps.map { $0.confirmation.message } == [nil, "This requires the cargo package tool@1.0.0.\nAllow Dreamder to install this package?"])
    }

    @Test
    func initializeRecreatesThePackageDirectory() async throws {
        try await withTempDir { root in
            let manager = CargoPackageManager(installationDirectory: root)
            let steps = try manager.install(method: .standardPackage(source: PackageManagerFixtures.source(type: .cargo)))
            let package = directory(root)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("stale".utf8).write(to: package.appending(path: "stale.txt"))

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps))

            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: package.appending(path: "stale.txt").path(percentEncoded: false)))
            #expect(outcome.statuses == [
                "Removing existing installation.",
                "Creating directory: \(package.path(percentEncoded: false))"
            ])
        }
    }

    @Test
    func cargoInstallCommandFollowsTheSourceDescription() async throws {
        let repository = "https://github.com/acme/tool"
        let cases: [(PackageSource, String)] = [
            (PackageManagerFixtures.source(type: .cargo), "cargo install --root . tool@1.0.0"),
            (
                PackageManagerFixtures.source(type: .cargo, options: ["features": "a,b", "locked": "true"]),
                "cargo install --root . tool@1.0.0 --features a,b --locked"
            ),
            (
                PackageManagerFixtures.source(type: .cargo, options: ["locked": "false"]),
                "cargo install --root . tool@1.0.0"
            ),
            (
                PackageManagerFixtures.source(type: .cargo, repositoryUrl: repository, gitReference: .tag("v1")),
                "cargo install --root . --git \(repository) --tag v1"
            ),
            (
                PackageManagerFixtures.source(type: .cargo, repositoryUrl: repository, gitReference: .revision("abc123")),
                "cargo install --root . --git \(repository) --rev abc123"
            ),
            (
                PackageManagerFixtures.source(type: .cargo, repositoryUrl: repository),
                "cargo install --root . tool@1.0.0"
            ),
            (
                PackageManagerFixtures.source(type: .cargo, gitReference: .tag("v1")),
                "cargo install --root . tool@1.0.0"
            )
        ]
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/Application Support/tool")

        for (source, command) in cases {
            let shell = ScriptedShell()
            let outcome = await runStep(manager.runCargoInstall(source, in: package), shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"/tmp/ls/Application Support/tool\" && \(command)"])
        }
    }

    @Test
    func aFailingCargoInstallSurfacesTheShellError() async {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedShell { _ in ScriptedShell.failing(101) }

        let outcome = await runStep(
            manager.runCargoInstall(PackageManagerFixtures.source(type: .cargo), in: URL(filePath: "/tmp/ls/tool")),
            shell: shell
        )

        #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 101)")
    }

    @Test
    func isInstalledAcceptsCargoVersionOutput() async {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedShell { _ in FakeProcessRunner.output("cargo 1.80.0 (376290515 2024-07-16)\n") }

        let step = manager.isInstalled(method: .unknown)
        let outcome = await runStep(step, shell: shell)

        #expect(step.confirmation.message == nil)
        #expect(outcome.error == nil)
        #expect(shell.commands == ["cargo --version"])
    }

    @Test
    func isInstalledRejectsOtherOutputAndMissingCargo() async {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let unrelated = await runStep(
            manager.isInstalled(method: .unknown),
            shell: ScriptedShell { _ in FakeProcessRunner.output("zsh: command not found: cargo\n") }
        )
        #expect(errorKind(unrelated.error) == "PackageManagerError.packageManagerNotInstalled")

        let failing = await runStep(
            manager.isInstalled(method: .unknown),
            shell: ScriptedShell { _ in ScriptedShell.failing(127) }
        )
        #expect(errorKind(failing.error) == "ShellClientError.taskTerminated(code: 127)")
    }

    @Test
    func binaryPathIsTheBinDirectoryOfThePackage() {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/Language Servers"))
        #expect(manager.getBinaryPath(for: "tool") == "/tmp/Language Servers/tool/bin")
    }
}
