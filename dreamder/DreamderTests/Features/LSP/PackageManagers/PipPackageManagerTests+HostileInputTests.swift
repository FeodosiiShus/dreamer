import Foundation
import Testing
@testable import Dreamder

extension PipPackageManagerTests {
    @Test
    func hostileEntryNamesAreRejectedBeforeAnyStepExists() {
        for name in Self.hostileNames {
            let source = PackageManagerFixtures.source(type: .pip, entryName: name)
            #expect(unsafeInstall(source) == "PackageManagerError.unsafeValue", "\(name)")
        }
    }

    @Test
    func hostilePackageNamesAndVersionsAreRejected() {
        for value in Self.hostileArguments {
            let name = PackageManagerFixtures.source(type: .pip, pkgName: value)
            #expect(unsafeInstall(name) == "PackageManagerError.unsafeValue", "name \(value)")
            let version = PackageManagerFixtures.source(type: .pip, version: value)
            #expect(unsafeInstall(version) == "PackageManagerError.unsafeValue", "version \(value)")
        }
    }

    @Test
    func hostileExtrasAreRejected() {
        for value in Self.hostileArguments {
            for version in ["latest", "1.0.0"] {
                let source = PackageManagerFixtures.source(type: .pip, version: version, options: ["extra": value])
                #expect(unsafeInstall(source) == "PackageManagerError.unsafeValue", "extra \(value) \(version)")
            }
        }
    }

    @Test
    func latestSkipsTheVersionPinSoNoVersionValidationApplies() throws {
        let source = PackageManagerFixtures.source(type: .pip, version: "Latest")
        #expect(unsafeInstall(source) == "none")
        let installSteps = try steps(in: URL(filePath: "/tmp/ls"), source: source)
        #expect(installSteps.count == 4)
    }

    @Test
    func theBuilderItselfThrowsForHostileValues() {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = PackageManagerFixtures.source(type: .pip, options: ["extra": "a;b"])

        let failure = thrownError { try manager.runPipInstall(source, in: URL(filePath: "/tmp/ls/tool")) }
        #expect(errorKind(failure) == "PackageManagerError.unsafeValue")
    }

    @Test
    func hostileEntryNamesNeverTouchTheFileSystemOutsideTheInstallRoot() async throws {
        try await withTempDir { base in
            let root = base.appending(path: "Language Servers", directoryHint: .isDirectory)
            let sibling = base.appending(path: "sibling", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            let sentinel = sibling.appending(path: "requirements.txt")
            try Data("keep".utf8).write(to: sentinel)
            let shell = ScriptedProcesses()

            for name in ["../sibling", "..", ".", "../sibling/requirements.txt"] {
                let source = PackageManagerFixtures.source(type: .pip, entryName: name)
                #expect(unsafeInstall(source, root: root) == "PackageManagerError.unsafeValue", "\(name)")
            }

            #expect(shell.invocations.isEmpty)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)

            let installSteps = try steps(in: root)
            let outcome = await runStep(try stepNamed(Self.initializeName, in: installSteps), shell: shell)
            #expect(outcome.error == nil)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        }
    }

    @Test
    func isInstalledAcceptsTheFirstWorkingPipCommand() async {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let version = "pip 24.0 from /usr/lib/python3/site-packages (python 3.12)\n"
        let shell = ScriptedProcesses { _ in FakeProcessRunner.output(version) }

        let step = manager.isInstalled(method: .unknown)
        let outcome = await runStep(step, shell: shell)

        #expect(step.confirmation.message == nil)
        #expect(outcome.error == nil)
        #expect(shell.arguments == [["pip3", "--version"]])
        #expect(shell.workingDirectories == [nil])
    }

    @Test
    func isInstalledFallsBackToPythonModulePip() async {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let shell = ScriptedProcesses { command in
            if command == "pip3 --version" {
                return ScriptedProcesses.failing(127)
            }
            return FakeProcessRunner.output("pip 23.3.1 from /x\n")
        }

        let outcome = await runStep(manager.isInstalled(method: .unknown), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.arguments == [["pip3", "--version"], ["python3", "-m", "pip", "--version"]])
    }

    @Test
    func isInstalledFailsWithoutAWorkingPip() async {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let missing = ScriptedProcesses { _ in ScriptedProcesses.failing(127) }
        let missingOutcome = await runStep(manager.isInstalled(method: .unknown), shell: missing)
        #expect(errorKind(missingOutcome.error) == "PackageManagerError.packageManagerNotInstalled")
        #expect(missing.arguments == [["pip3", "--version"], ["python3", "-m", "pip", "--version"]])

        let garbage = ScriptedProcesses { _ in FakeProcessRunner.output("not pip at all\n") }
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

            let customPath = customBin.appending(path: "tool").path(percentEncoded: false)
            #expect(manager.getBinaryPath(for: "tool") == customPath)
        }
    }
}
