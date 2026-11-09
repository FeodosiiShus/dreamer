import Foundation
import Testing
@testable import Dreamder

extension GithubPackageManagerTests {
    @Test
    func decompressUnzipsArchivesAndMakesTheBinaryExecutable() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let archive = StoredZip.make(entries: [(name: "tool", contents: "#!/bin/sh\n")])
            try archive.write(to: package.appending(path: "tool.zip"))
            let shell = ScriptedProcesses()

            let steps = try binarySteps(manager: manager, file: "tool.zip")
            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(outcome.statuses == [
                "Decompressing tool.zip",
                "Decompressed to '\(package.path(percentEncoded: false))'"
            ])
            #expect(shell.invocations.isEmpty)
            let binary = package.appending(path: "tool")
            #expect(try String(contentsOf: binary, encoding: .utf8) == "#!/bin/sh\n")
            #expect(isExecutable(binary))
            let archivePath = package.appending(path: "tool.zip").path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: archivePath))
        }
    }

    @Test
    func decompressFailsForCorruptZipArchives() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("not a zip".utf8).write(to: package.appending(path: "tool.zip"))
            let steps = try binarySteps(manager: manager, file: "tool.zip")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps))

            #expect(outcome.error != nil)
        }
    }

    @Test
    func decompressUsesTheMatchingCommandLineTool() async throws {
        let cases: [(file: String, command: [String])] = [
            ("tool.tar.gz", ["tar", "-xzf"]),
            ("tool.tar", ["tar", "-xf"]),
            ("tool.gz", ["gunzip", "-f"])
        ]
        for (file, command) in cases {
            try await withTempDir { directory in
                let root = try PackageManagerFixtures.installRoot(in: directory)
                let manager = GithubPackageManager(installationDirectory: root)
                let package = root.appending(path: "tool-entry")
                try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
                let shell = ScriptedProcesses()
                let steps = try binarySteps(manager: manager, file: file)

                let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

                #expect(outcome.error == nil, "\(file)")
                let packagePath = package.path(percentEncoded: false)
                #expect(shell.arguments == [command + ["\(packagePath)/\(file)"]], "\(file)")
                #expect(shell.workingDirectories == [packagePath], "\(file)")
                #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable], "\(file)")
            }
        }
    }

    @Test
    func gunzipOutputBecomesExecutable() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let binary = package.appending(path: "tool")
            let shell = ScriptedProcesses { command in
                if command.hasPrefix("gunzip") {
                    try Data("binary".utf8).write(to: binary)
                }
                return FakeProcessRunner.output("")
            }
            let steps = try binarySteps(manager: manager, file: "tool.gz")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(isExecutable(binary))
        }
    }

    @Test
    func decompressSurfacesExtractionFailures() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(2) }
            let steps = try binarySteps(manager: manager, file: "tool.tar.gz")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 2)")
        }
    }

    @Test
    func decompressLeavesPlainBinariesExecutable() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let binary = package.appending(path: "tool")
            try Data("binary".utf8).write(to: binary)
            let shell = ScriptedProcesses()
            let steps = try binarySteps(manager: manager, file: "tool")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.invocations.isEmpty)
            #expect(isExecutable(binary))
        }
    }

    @Test
    func cloneRunsGitInsideTheEntryDirectory() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses()
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make"))

            let outcome = await runStep(try stepNamed(Self.cloneName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [["git", "clone", Self.repository]])
            #expect(shell.workingDirectories == [root.appending(path: "tool-entry").path(percentEncoded: false)])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
        }
    }

    @Test
    func sourceBuildRunsTheRegistryCommandInsideTheClone() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses()
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make install"))

            let outcome = await runStep(try stepNamed(Self.buildName, in: steps), shell: shell)

            let clone = root.appending(path: "tool-entry/tool").path(percentEncoded: false)
            #expect(outcome.error == nil)
            #expect(shell.arguments == [["make", "install"]])
            #expect(shell.workingDirectories == [clone])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
        }
    }

    @Test
    func sourceBuildFailuresAreReportedAsInstallationFailures() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(2) }
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make"))

            let outcome = await runStep(try stepNamed(Self.buildName, in: steps), shell: shell)

            #expect(installationFailureMessage(outcome.error) == "Source build failed.")
        }
    }

    @Test
    func multiLineBuildCommandsRunAsSeparateInvocationsInOrder() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses()
            let command = "make\n\n  \n  make   install \n"
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: command))

            let step = try stepNamed(Self.buildName, in: steps)
            let outcome = await runStep(step, shell: shell)

            let clone = root.appending(path: "tool-entry/tool").path(percentEncoded: false)
            #expect(outcome.error == nil)
            #expect(shell.arguments == [["make"], ["make", "install"]])
            #expect(shell.workingDirectories == [clone, clone])
            #expect(outcome.statuses == ["make", "make install"])
            #expect(step.confirmation.message == "This step will run the following to finish installing:\n`\(command)`")
        }
    }

    @Test
    func buildFlagsArriveAsLiteralArguments() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses()
            let command = "cmake -DCMAKE_BUILD_TYPE=Release -B build -DX=a:b,c/d^e\ncargo build --release -j4"
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: command))

            let outcome = await runStep(try stepNamed(Self.buildName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [
                ["cmake", "-DCMAKE_BUILD_TYPE=Release", "-B", "build", "-DX=a:b,c/d^e"],
                ["cargo", "build", "--release", "-j4"]
            ])
        }
    }

    @Test
    func aFailingSecondBuildLineStopsTheBuildAsInstallationFailure() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses { command in
                command == "make install" ? ScriptedProcesses.failing(2) : FakeProcessRunner.output("")
            }
            let command = "make\nmake install\nmake clean"
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: command))

            let outcome = await runStep(try stepNamed(Self.buildName, in: steps), shell: shell)

            #expect(installationFailureMessage(outcome.error) == "Source build failed.")
            #expect(shell.arguments == [["make"], ["make", "install"]])
        }
    }
}
