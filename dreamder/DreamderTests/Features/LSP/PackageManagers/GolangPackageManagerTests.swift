import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GolangPackageManagerTests {
    private static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using go"
    private static let buildName = "Build From Source"

    private func goSource(
        pkgName: String = "github.com/acme/tool",
        version: String = "v1.0.0",
        repositoryUrl: String? = nil,
        gitReference: PackageSource.GitReference? = nil,
        options: [String: String] = [:]
    ) -> PackageSource {
        PackageManagerFixtures.source(
            type: .golang,
            pkgName: pkgName,
            version: version,
            repositoryUrl: repositoryUrl,
            gitReference: gitReference,
            options: options
        )
    }

    @Test
    func installRejectsEverythingButStandardPackages() {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let source = goSource()
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
    func installAddsABuildStepOnlyForPackagesWithASubpath() throws {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let plain = try manager.install(method: .standardPackage(source: goSource()))
        #expect(plain.map { $0.name } == [Self.initializeName, Self.installName])
        #expect(plain.map { $0.confirmation.message } == [
            nil,
            "This requires installing the go package github.com/acme/tool@v1.0.0.\nAllow Dreamder to install this package?"
        ])

        let withSubpath = try manager.install(method: .standardPackage(source: goSource(options: ["subpath": "cmd/tool"])))
        #expect(withSubpath.map { $0.name } == [Self.initializeName, Self.installName, Self.buildName])
        #expect(withSubpath.last?.confirmation.message == nil)
    }

    @Test
    func initializeCreatesTheDirectoryAndAGoModule() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let steps = try manager.install(method: .standardPackage(source: goSource()))
            let package = root.appending(path: "tool-entry")
            let shell = ScriptedShell()

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && go mod init dreamder.temp/placeholder"])
        }
    }

    @Test
    func goInstallInstallsIntoThePackageBinDirectory() async {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/Application Support/tool")
        let shell = ScriptedShell()

        let outcome = await runStep(manager.runGoInstall(goSource(), packagePath: package), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.commands == [
            "cd \"/tmp/ls/Application Support/tool\" && env GOBIN=/tmp/ls/Application Support/tool/bin go install github.com/acme/tool@v1.0.0"
        ])
    }

    @Test
    func goInstallTargetFollowsTheGitReferenceAndRepository() async {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/tool")
        let cases: [(PackageSource, String)] = [
            (goSource(), "github.com/acme/tool@v1.0.0"),
            (
                goSource(repositoryUrl: "https://github.com/acme/tool", gitReference: .tag("v1.2.0")),
                "github.com/acme/tool@v1.2.0"
            ),
            (
                goSource(pkgName: "golang.org/x/tools", repositoryUrl: "https://golang.org/x/tools", gitReference: .revision("abc123")),
                "golang.org/x/tools@abc123"
            ),
            (
                goSource(pkgName: "example.com/tool", repositoryUrl: "https://git.example.com/tool", gitReference: .tag("v2")),
                "git.example.com/tool@v2"
            ),
            (goSource(pkgName: "example.com/tool", gitReference: .tag("v2")), "example.com/tool@v1.0.0"),
            (goSource(pkgName: "example.com/tool", repositoryUrl: "https://example.com/tool"), "example.com/tool@v1.0.0")
        ]

        for (source, target) in cases {
            let step = manager.runGoInstall(source, packagePath: package)
            let shell = ScriptedShell()
            let outcome = await runStep(step, shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"/tmp/ls/tool\" && env GOBIN=/tmp/ls/tool/bin go install \(target)"], "\(target)")
            #expect(step.confirmation.message == "This requires installing the go package \(target).\nAllow Dreamder to install this package?")
        }
    }

    @Test
    func buildBinaryCompilesTheSubpathIntoBinAndMakesItExecutable() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            let bin = package.appending(path: "bin", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let binary = bin.appending(path: "tool")
            try Data("binary".utf8).write(to: binary)
            #expect(!isExecutable(binary))
            let shell = ScriptedShell()

            let outcome = await runStep(
                manager.buildBinary(goSource(options: ["subpath": "cmd/tool"]), packagePath: package),
                shell: shell
            )

            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && go build -o bin/tool github.com/acme/tool/cmd/tool"])
            #expect(isExecutable(binary))
        }
    }

    @Test
    func buildBinaryBuildsTheRelativeSubpathForPackagesWithoutAnImportPath() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            let shell = ScriptedShell()

            let outcome = await runStep(
                manager.buildBinary(goSource(pkgName: "tool", options: ["subpath": "cmd/tool"]), packagePath: package),
                shell: shell
            )

            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && go build -o bin/tool cmd/tool"])
            #expect(FileManager.default.fileExists(atPath: package.appending(path: "bin").path(percentEncoded: false)))
            #expect(outcome.error != nil)
        }
    }

    @Test
    func buildBinaryStopsWhenTheCompilerFails() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let shell = ScriptedShell { _ in ScriptedShell.failing(2) }

            let outcome = await runStep(
                manager.buildBinary(goSource(options: ["subpath": "cmd/tool"]), packagePath: root.appending(path: "tool-entry")),
                shell: shell
            )

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 2)")
        }
    }

    @Test
    func isInstalledRequiresConfirmationAndAGoVersion() async {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let good = ScriptedShell { _ in FakeProcessRunner.output("go version go1.22.1 darwin/arm64\n") }
        let step = manager.isInstalled(method: .unknown)
        let goodOutcome = await runStep(step, shell: good)
        #expect(step.confirmation.message == "This package requires go to install. Allow Dreamder to run go commands?")
        #expect(goodOutcome.error == nil)
        #expect(good.commands == ["go version"])

        let unrelated = ScriptedShell { _ in FakeProcessRunner.output("go: unknown\n") }
        let unrelatedOutcome = await runStep(manager.isInstalled(method: .unknown), shell: unrelated)
        #expect(errorKind(unrelatedOutcome.error) == "PackageManagerError.packageManagerNotInstalled")

        let missing = ScriptedShell { _ in ScriptedShell.failing(127) }
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
}
