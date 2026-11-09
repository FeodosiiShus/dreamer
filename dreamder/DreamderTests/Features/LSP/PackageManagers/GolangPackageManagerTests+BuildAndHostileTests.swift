import Foundation
import Testing
@testable import Dreamder

extension GolangPackageManagerTests {
    @Test
    func buildBinaryBuildsTheRelativeSubpathForPackagesWithoutAnImportPath() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            let shell = ScriptedProcesses()

            let outcome = await runStep(
                try manager.buildBinary(goSource(pkgName: "tool"), subpath: "cmd/tool", packagePath: package),
                shell: shell
            )

            #expect(shell.arguments == [["go", "build", "-o", "bin/tool", "cmd/tool"]])
            #expect(FileManager.default.fileExists(atPath: package.appending(path: "bin").path(percentEncoded: false)))
            #expect(outcome.error != nil)
        }
    }

    @Test
    func buildBinaryPassesAllowedOddSubpathsAsOneArgument() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "Tool Entry")
            let shell = ScriptedProcesses()

            _ = await runStep(
                try manager.buildBinary(goSource(), subpath: "cmd/tool.v2~x", packagePath: package),
                shell: shell
            )

            #expect(shell.arguments == [["go", "build", "-o", "bin/tool.v2~x", "github.com/acme/tool/cmd/tool.v2~x"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
        }
    }

    @Test
    func buildBinaryStopsWhenTheCompilerFails() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(2) }
            let package = root.appending(path: "tool-entry")

            let outcome = await runStep(
                try manager.buildBinary(goSource(), subpath: "cmd/tool", packagePath: package),
                shell: shell
            )

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 2)")
        }
    }

    @Test
    func isInstalledRequiresConfirmationAndAGoVersion() async {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let good = ScriptedProcesses { _ in FakeProcessRunner.output("go version go1.22.1 darwin/arm64\n") }
        let step = manager.isInstalled(method: .unknown)
        let goodOutcome = await runStep(step, shell: good)
        #expect(step.confirmation.message == "This package requires go to install. Allow Dreamder to run go commands?")
        #expect(goodOutcome.error == nil)
        #expect(good.arguments == [["go", "version"]])
        #expect(good.invocations.first?.executable == PackageManagerProgressModel.envExecutable)

        let unrelated = ScriptedProcesses { _ in FakeProcessRunner.output("go: unknown\n") }
        let unrelatedOutcome = await runStep(manager.isInstalled(method: .unknown), shell: unrelated)
        #expect(errorKind(unrelatedOutcome.error) == "PackageManagerError.packageManagerNotInstalled")

        let missing = ScriptedProcesses { _ in ScriptedProcesses.failing(127) }
        let missingOutcome = await runStep(manager.isInstalled(method: .unknown), shell: missing)
        #expect(errorKind(missingOutcome.error) == "ShellClientError.taskTerminated(code: 127)")
    }

    @Test
    func binaryPathPrefersTheBinaryNamedAfterThePackage() throws {
        try withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let binDirectory = root.appending(path: "github.com/acme/tool/bin")
            #expect(manager.getBinaryPath(for: "github.com/acme/tool") == binDirectory.path(percentEncoded: false))

            try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
            try Data().write(to: binDirectory.appending(path: "tool"))

            #expect(
                manager.getBinaryPath(for: "github.com/acme/tool")
                    == binDirectory.appending(path: "tool").path(percentEncoded: false)
            )
        }
    }

    @Test
    func hostileEntryNamesAreRejectedAndNothingOutsideTheInstallRootChanges() async throws {
        let hostileNames = [
            "../../x", "../outside", "a;rm -rf ~", "-rf", "..", ".", "", "a/b", "a\u{0}b", "a b", "$(touch x)", "`id`"
        ]
        try withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let outside = directory.appending(path: "outside", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let sentinel = outside.appending(path: "keep.txt")
            try Data("keep".utf8).write(to: sentinel)
            let manager = GolangPackageManager(installationDirectory: root)

            for name in hostileNames {
                let source = goSource(entryName: name, options: ["subpath": "cmd/tool"])
                #expect(installErrorKind(manager, source) == Self.unsafe, "\(name)")
            }

            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
            let outsidePath = outside.path(percentEncoded: false)
            let outsideEntries = try FileManager.default.contentsOfDirectory(atPath: outsidePath)
            #expect(outsideEntries == ["keep.txt"])
        }
    }

    @Test
    func hostilePackageNamesVersionsAndReferencesAreRejectedUpFront() {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/tool")
        let hostile: [PackageSource] = [
            goSource(pkgName: "-evil"),
            goSource(pkgName: "../../x"),
            goSource(pkgName: "a/../b"),
            goSource(pkgName: "/abs"),
            goSource(pkgName: "github.com/a b"),
            goSource(pkgName: "github.com/a;b"),
            goSource(pkgName: "$(id)"),
            goSource(pkgName: "`id`"),
            goSource(pkgName: "github.com/x\u{0}y"),
            goSource(version: "v1;touch x"),
            goSource(version: "v1 0"),
            goSource(version: "$(id)"),
            goSource(version: "v1\nx"),
            goSource(version: "v1'x"),
            goSource(repositoryUrl: "https://github.com/acme/tool", gitReference: .tag("v1;x")),
            goSource(repositoryUrl: "https://github.com/acme/tool", gitReference: .revision("$(id)")),
            goSource(repositoryUrl: "https://github.com/acme/tool", gitReference: .tag("a b")),
            goSource(pkgName: "example.com/tool", repositoryUrl: "https://evil.com/x y", gitReference: .tag("v1")),
            goSource(pkgName: "example.com/tool", repositoryUrl: "http://evil.com/x", gitReference: .tag("v1")),
            goSource(pkgName: "example.com/tool", repositoryUrl: "https://evil.com/$(id)", gitReference: .tag("v1")),
            goSource(pkgName: "example.com/tool", repositoryUrl: "https://evil.com/x;y", gitReference: .tag("v1")),
            goSource(pkgName: "example.com/tool", repositoryUrl: "ext::sh -c touch% x", gitReference: .tag("v1")),
            goSource(pkgName: "example.com/tool", repositoryUrl: "https://evil.com/../x", gitReference: .tag("v1"))
        ]

        for source in hostile {
            #expect(installErrorKind(manager, source) == Self.unsafe, "\(source.pkgName)@\(source.version)")
            #expect(errorKind(thrownError { try manager.runGoInstall(source, packagePath: package) }) == Self.unsafe)
        }
    }

    @Test
    func hostileSubpathsAreRejectedBeforeAnyStepExists() async throws {
        let hostileSubpaths = [
            ".", "..", "cmd/..", "cmd/tool/", "", "-x", "cmd/-x", "a b", "$(x)/tool", "cmd/tool;x", "cmd/tool\u{0}x",
            "cmd/`id`", "cmd/tool'x", "../x", "cmd/../x", "../../x"
        ]
        try withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")

            for subpath in hostileSubpaths {
                let source = goSource(options: ["subpath": subpath])
                #expect(installErrorKind(manager, source) == Self.unsafe, "\(subpath)")
                let failure = thrownError { try manager.buildBinary(source, subpath: subpath, packagePath: package) }
                #expect(errorKind(failure) == Self.unsafe, "\(subpath)")
            }

            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
        }
    }

    @Test
    func rejectedSubpathsNeverRunAProcessOrCreateTheBinDirectory() async throws {
        try withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            let source = goSource(options: ["subpath": ".."])

            let failure = thrownError { try manager.buildBinary(source, subpath: "..", packagePath: package) }

            #expect(errorKind(failure) == Self.unsafe)
            #expect(!FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
        }
    }
}
