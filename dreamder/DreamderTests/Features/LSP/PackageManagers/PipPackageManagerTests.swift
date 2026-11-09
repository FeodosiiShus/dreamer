import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct PipPackageManagerTests {
    static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using pip"
    private static let requirementsName = "Update requirements.txt"
    private static let verifyName = "Verify Installation"
    static let hostileNames = [
        "../../x", "a;rm -rf ~", "-rf", "..", ".", "", "a/b", "a\u{0}b", "a b", "$(touch x)", "`id`"
    ]
    static let hostileArguments = [
        "", "-rf", "a;rm -rf ~", "a b", "$(touch x)", "`id`", "a\u{0}b", "a\"b", "a'b", "a=b", "a:b", "a|b", "a&b"
    ]

    func steps(
        in root: URL,
        source: PackageSource = PackageManagerFixtures.source(type: .pip)
    ) throws -> [PackageManagerInstallStep] {
        try PipPackageManager(installationDirectory: root).install(method: .standardPackage(source: source))
    }

    func unsafeInstall(_ source: PackageSource, root: URL = URL(filePath: "/tmp/ls")) -> String {
        let manager = PipPackageManager(installationDirectory: root)
        return errorKind(thrownError { try manager.install(method: .standardPackage(source: source)) })
    }

    private func createVenvPip(in package: URL) throws -> String {
        let venvBin = package.appending(path: "venv/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: venvBin, withIntermediateDirectories: true)
        let pip = venvBin.appending(path: "pip")
        try Data().write(to: pip)
        return pip.path(percentEncoded: false)
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
            let failure = thrownError { try manager.install(method: method) }
            #expect(errorKind(failure) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func installListsTheFourStepsAndAsksBeforeInstalling() throws {
        let installSteps = try steps(in: URL(filePath: "/tmp/ls"))

        let expectedNames = [Self.initializeName, Self.installName, Self.requirementsName, Self.verifyName]
        #expect(installSteps.map { $0.name } == expectedNames)
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
            let shell = ScriptedProcesses()

            let outcome = await runStep(try stepNamed(Self.initializeName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [["python", "-m", "venv", "venv"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
            let requirements = try String(contentsOf: package.appending(path: "requirements.txt"), encoding: .utf8)
            #expect(requirements == "# Package requirements\n")
        }
    }

    @Test
    func initializeKeepsARequirementsFileCreatedByTheVirtualEnvironmentStep() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let requirements = root.appending(path: "tool-entry/requirements.txt")
            let shell = ScriptedProcesses { _ in
                try? Data("existing\n".utf8).write(to: requirements)
                return FakeProcessRunner.output("")
            }

            let outcome = await runStep(try stepNamed(Self.initializeName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(try String(contentsOf: requirements, encoding: .utf8) == "existing\n")
        }
    }

    @Test
    func initializeStopsWhenTheVirtualEnvironmentCannotBeCreated() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(1) }

            let outcome = await runStep(try stepNamed(Self.initializeName, in: installSteps), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 1)")
            let requirements = root.appending(path: "tool-entry/requirements.txt")
            #expect(!FileManager.default.fileExists(atPath: requirements.path(percentEncoded: false)))
        }
    }

    @Test
    func pipInstallCommandPutsExtrasBeforeTheVersionConstraint() async throws {
        let pip = ["python3", "-m", "pip", "install"]
        let cases: [(PackageSource, [String])] = [
            (PackageManagerFixtures.source(type: .pip, version: "latest"), pip + ["tool"]),
            (PackageManagerFixtures.source(type: .pip, version: "LATEST"), pip + ["tool"]),
            (PackageManagerFixtures.source(type: .pip, version: "1.0.0"), pip + ["tool==1.0.0"]),
            (
                PackageManagerFixtures.source(type: .pip, version: "1.0.0", options: ["extra": "a,b"]),
                pip + ["tool[a,b]==1.0.0"]
            ),
            (
                PackageManagerFixtures.source(type: .pip, version: "latest", options: ["extra": "a"]),
                pip + ["tool[a]"]
            )
        ]
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/Application Support/tool")

        for (source, expected) in cases {
            let shell = ScriptedProcesses()
            let outcome = await runStep(try manager.runPipInstall(source, in: package), shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.arguments == [expected])
            #expect(shell.workingDirectories == ["/tmp/ls/Application Support/tool"])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
            #expect(outcome.statuses == [expected.joined(separator: " ")])
        }
    }

    @Test
    func oddButAllowedValuesArriveAsSingleArguments() async throws {
        let manager = PipPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = PackageManagerFixtures.source(
            type: .pip,
            pkgName: "my_tool-x.y",
            version: "1.0.0+local~1",
            options: ["extra": "a,b-c"]
        )
        let shell = ScriptedProcesses()

        let package = URL(filePath: "/tmp/ls/tool")
        let outcome = await runStep(try manager.runPipInstall(source, in: package), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.arguments == [["python3", "-m", "pip", "install", "my_tool-x.y[a,b-c]==1.0.0+local~1"]])
    }

    @Test
    func pipInstallUsesThePipOfTheVirtualEnvironmentWhenItExists() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            let venvPip = try createVenvPip(in: package)
            let installSteps = try steps(in: root)
            let shell = ScriptedProcesses()

            let outcome = await runStep(try stepNamed(Self.installName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [[venvPip, "install", "tool==1.0.0"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
            #expect(venvPip == package.path(percentEncoded: false) + "/venv/bin/pip")
        }
    }

    @Test
    func requirementsAndVerifyStepsUseTheVirtualEnvironmentPipToo() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            let venvPip = try createVenvPip(in: package)
            let installSteps = try steps(in: root)
            let shell = ScriptedProcesses { _ in FakeProcessRunner.output("tool==1.0.0\n") }

            let requirements = await runStep(try stepNamed(Self.requirementsName, in: installSteps), shell: shell)
            let verify = await runStep(try stepNamed(Self.verifyName, in: installSteps), shell: shell)

            #expect(requirements.error == nil)
            #expect(verify.error == nil)
            #expect(shell.arguments == [[venvPip, "freeze"], [venvPip, "list", "--format=freeze"]])
        }
    }

    @Test
    func updateRequirementsWritesTheFrozenPackages() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let shell = ScriptedProcesses { _ in FakeProcessRunner.output("tool==1.0.0\ndep==2.3\n") }

            let outcome = await runStep(try stepNamed(Self.requirementsName, in: installSteps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [["python3", "-m", "pip", "freeze"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
            #expect(outcome.statuses.last == "Writing requirements to requirements.txt")
            let requirements = try String(contentsOf: package.appending(path: "requirements.txt"), encoding: .utf8)
            #expect(requirements == "tool==1.0.0\ndep==2.3\n")
        }
    }

    @Test
    func updateRequirementsFailsWhenThePackageDirectoryIsMissing() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let shell = ScriptedProcesses { _ in FakeProcessRunner.output("tool==1.0.0\n") }

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
                let shell = ScriptedProcesses { _ in FakeProcessRunner.output(listing) }

                let outcome = await runStep(try stepNamed(Self.verifyName, in: installSteps), shell: shell)

                #expect(outcome.error == nil, "\(name)")
                let package = root.appending(path: "tool-entry").path(percentEncoded: false)
                #expect(shell.arguments == [["python3", "-m", "pip", "list", "--format=freeze"]])
                #expect(shell.workingDirectories == [package])
            }
        }
    }

    @Test
    func verifyFailsWhenThePackageIsNotListed() async throws {
        try await withTempDir { root in
            let installSteps = try steps(in: root)
            let shell = ScriptedProcesses { _ in FakeProcessRunner.output("other==1\ntool-extras==2\n") }

            let outcome = await runStep(try stepNamed(Self.verifyName, in: installSteps), shell: shell)

            #expect(installationFailureMessage(outcome.error) == "Package tool not found in pip list")
        }
    }
}
