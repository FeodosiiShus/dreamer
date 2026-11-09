import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct PipPackageManagerTests {
    private static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using pip"
    private static let requirementsName = "Update requirements.txt"
    private static let verifyName = "Verify Installation"

    private func steps(
        in root: URL,
        source: PackageSource = PackageManagerFixtures.source(type: .pip)
    ) throws -> [PackageManagerInstallStep] {
        try PipPackageManager(installationDirectory: root).install(method: .standardPackage(source: source))
    }

    @Test
    func installRejectsEverythingButStandardPackages() {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = PackageManagerFixtures.source(type: .pip)
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
    func installListsTheFourStepsAndAsksBeforeInstalling() throws {
        let installSteps = try steps(in: URL(filePath: "/tmp/ls"))

        #expect(installSteps.map { $0.name } == [Self.initializeName, Self.installName, Self.requirementsName, Self.verifyName])
        #expect(installSteps.map { $0.confirmation.message } == [
            nil,
            "This requires the pip package tool.\nAllow Dreamder to install this package?",
            nil,
            nil
        ])
    }

    @Test
    func initializeCreatesAVirtualEnvironmentAndARequirementsFile() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let package = root.appending(path: "tool-entry")
            let shell = ScriptedShell()

            let outcome = await runStep(try stepNamed(Self.initializeName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && python -m venv venv"])
            let requirements = try String(contentsOf: package.appending(path: "requirements.txt"), encoding: .utf8)
            #expect(requirements == "# Package requirements\n")
        }
    }

    @Test
    func initializeStopsWhenTheVirtualEnvironmentCannotBeCreated() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let shell = ScriptedShell { _ in ScriptedShell.failing(1) }

            let outcome = await runStep(try stepNamed(Self.initializeName, in: installSteps), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 1)")
            let requirements = root.appending(path: "tool-entry/requirements.txt")
            #expect(!FileManager.default.fileExists(atPath: requirements.path(percentEncoded: false)))
        }
    }

    @Test
    func pipInstallCommandPutsExtrasBeforeTheVersionConstraint() async throws {
        let cases: [(PackageSource, String)] = [
            (PackageManagerFixtures.source(type: .pip, version: "latest"), "python3 -m pip install tool"),
            (PackageManagerFixtures.source(type: .pip, version: "LATEST"), "python3 -m pip install tool"),
            (PackageManagerFixtures.source(type: .pip, version: "1.0.0"), "python3 -m pip install tool==1.0.0"),
            (
                PackageManagerFixtures.source(type: .pip, version: "1.0.0", options: ["extra": "a,b"]),
                "python3 -m pip install tool[a,b]==1.0.0"
            ),
            (
                PackageManagerFixtures.source(type: .pip, version: "latest", options: ["extra": "a"]),
                "python3 -m pip install tool[a]"
            )
        ]
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/Application Support/tool")

        for (source, command) in cases {
            let shell = ScriptedShell()
            let outcome = await runStep(manager.runPipInstall(source, in: package), shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"/tmp/ls/Application Support/tool\" && \(command)"])
        }
    }

    @Test
    func pipInstallUsesThePipOfTheVirtualEnvironmentWhenItExists() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            let venvBin = package.appending(path: "venv/bin", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: venvBin, withIntermediateDirectories: true)
            try Data().write(to: venvBin.appending(path: "pip"))
            let installSteps = try steps(in: root)
            let shell = ScriptedShell()

            let outcome = await runStep(try stepNamed(Self.installName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && venv/bin/pip install tool==1.0.0"])
        }
    }

    @Test
    func updateRequirementsWritesTheFrozenPackages() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let shell = ScriptedShell { _ in FakeProcessRunner.output("tool==1.0.0\ndep==2.3\n") }

            let outcome = await runStep(try stepNamed(Self.requirementsName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && python3 -m pip freeze"])
            #expect(outcome.statuses.last == "Writing requirements to requirements.txt")
            let requirements = try String(contentsOf: package.appending(path: "requirements.txt"), encoding: .utf8)
            #expect(requirements == "tool==1.0.0\ndep==2.3\n")
        }
    }

    @Test
    func updateRequirementsFailsWhenThePackageDirectoryIsMissing() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let shell = ScriptedShell { _ in FakeProcessRunner.output("tool==1.0.0\n") }

            let outcome = await runStep(try stepNamed(Self.requirementsName, in: installSteps), shell: shell)

            #expect(outcome.error != nil)
        }
    }

    @Test
    func verifyAcceptsNormalizedPackageNames() async throws {
        let cases: [(String, String)] = [
            ("tool", "other==1\nTool==1.0.0\n"),
            ("my-tool", "my_tool==1.2\n"),
            ("my_tool", "my-tool==1.2\n"),
            ("MY-Tool", "my_tool==1.2\n")
        ]
        try await withTempDir { root in
            for (name, listing) in cases {
                let source = PackageManagerFixtures.source(type: .pip, pkgName: name)
                let installSteps = try steps(in: root, source: source)
                let shell = ScriptedShell { _ in FakeProcessRunner.output(listing) }

                let outcome = await runStep(try stepNamed(Self.verifyName, in: installSteps), shell: shell)

                #expect(outcome.error == nil, "\(name)")
                let package = root.appending(path: "tool-entry").path(percentEncoded: false)
                #expect(shell.commands == ["cd \"\(package)\" && python3 -m pip list --format=freeze"])
            }
        }
    }

    @Test
    func verifyFailsWhenThePackageIsNotListed() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let shell = ScriptedShell { _ in FakeProcessRunner.output("other==1\ntool-extras==2\n") }

            let outcome = await runStep(try stepNamed(Self.verifyName, in: installSteps), shell: shell)

            #expect(installationFailureMessage(outcome.error) == "Package tool not found in pip list")
        }
    }

    @Test
    func isInstalledAcceptsTheFirstWorkingPipCommand() async {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedShell { _ in FakeProcessRunner.output("pip 24.0 from /usr/lib/python3/site-packages (python 3.12)\n") }

        let step = manager.isInstalled(method: .unknown)
        let outcome = await runStep(step, shell: shell)

        #expect(step.confirmation.message == nil)
        #expect(outcome.error == nil)
        #expect(shell.commands == ["pip3 --version"])
    }

    @Test
    func isInstalledFallsBackToPythonModulePip() async {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedShell { command in
            command == "pip3 --version" ? ScriptedShell.failing(127) : FakeProcessRunner.output("pip 23.3.1 from /x\n")
        }

        let outcome = await runStep(manager.isInstalled(method: .unknown), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.commands == ["pip3 --version", "python3 -m pip --version"])
    }

    @Test
    func isInstalledFailsWithoutAWorkingPip() async {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let missing = ScriptedShell { _ in ScriptedShell.failing(127) }
        let missingOutcome = await runStep(manager.isInstalled(method: .unknown), shell: missing)
        #expect(errorKind(missingOutcome.error) == "PackageManagerError.packageManagerNotInstalled")
        #expect(missing.commands == ["pip3 --version", "python3 -m pip --version"])

        let garbage = ScriptedShell { _ in FakeProcessRunner.output("not pip at all\n") }
        let garbageOutcome = await runStep(manager.isInstalled(method: .unknown), shell: garbage)
        #expect(errorKind(garbageOutcome.error) == "PackageManagerError.packageManagerNotInstalled")
    }

    @Test
    func binaryPathPrefersAPackageLocalBinary() throws {
        try withTempDir { root in
            let manager = PipPackageManager(installationDirectory: root)
            let venvPath = root.appending(path: "tool/venv/bin/tool").path(percentEncoded: false)
            #expect(manager.getBinaryPath(for: "tool") == venvPath)

            let customBin = root.appending(path: "tool/bin", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: customBin, withIntermediateDirectories: true)
            try Data().write(to: customBin.appending(path: "tool"))

            #expect(manager.getBinaryPath(for: "tool") == customBin.appending(path: "tool").path(percentEncoded: false))
        }
    }
}
