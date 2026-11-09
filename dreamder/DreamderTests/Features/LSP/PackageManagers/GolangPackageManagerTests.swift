import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GolangPackageManagerTests {
    private static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using go"
    private static let buildName = "Build From Source"
    static let unsafe = "PackageManagerError.unsafeValue"

    func goSource(
        pkgName: String = "github.com/acme/tool",
        entryName: String = "tool-entry",
        version: String = "v1.0.0",
        repositoryUrl: String? = nil,
        gitReference: PackageSource.GitReference? = nil,
        options: [String: String] = [:]
    ) -> PackageSource {
        PackageManagerFixtures.source(
            type: .golang,
            pkgName: pkgName,
            entryName: entryName,
            version: version,
            repositoryUrl: repositoryUrl,
            gitReference: gitReference,
            options: options
        )
    }

    func installErrorKind(_ manager: GolangPackageManager, _ source: PackageSource) -> String {
        errorKind(thrownError { try manager.install(method: .standardPackage(source: source)) })
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
            let failure = thrownError { try manager.install(method: method) }
            #expect(errorKind(failure) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func installAddsABuildStepOnlyForPackagesWithASubpath() throws {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let plain = try manager.install(method: .standardPackage(source: goSource()))
        #expect(plain.map { $0.name } == [Self.initializeName, Self.installName])
        #expect(plain.map { $0.confirmation.message } == [
            nil,
            "This requires installing the go package github.com/acme/tool@v1.0.0.\n"
                + "Allow Dreamder to install this package?"
        ])

        let subpathSource = goSource(options: ["subpath": "cmd/tool"])
        let withSubpath = try manager.install(method: .standardPackage(source: subpathSource))
        #expect(withSubpath.map { $0.name } == [Self.initializeName, Self.installName, Self.buildName])
        #expect(withSubpath.last?.confirmation.message == nil)
    }

    @Test
    func initializeCreatesTheDirectoryAndAGoModule() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let steps = try manager.install(method: .standardPackage(source: goSource()))
            let package = root.appending(path: "tool-entry")
            let shell = ScriptedProcesses()

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
            #expect(shell.arguments == [["go", "mod", "init", "dreamder.temp/placeholder"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
            #expect(outcome.statuses.last == "go mod init dreamder.temp/placeholder")
        }
    }

    @Test
    func initializeWipesAnExistingInstallationAndCreatesAFreshGoModule() async throws {
        try await withTempDir { root in
            let manager = GolangPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("module existing\n".utf8).write(to: package.appending(path: "go.mod"))
            let shell = ScriptedProcesses()

            let outcome = await runStep(manager.initialize(in: package), shell: shell)

            #expect(outcome.error == nil)
            #expect(outcome.statuses.first == "Removing existing installation.")
            #expect(shell.arguments == [["go", "mod", "init", "dreamder.temp/placeholder"]])
            let goModPath = package.appending(path: "go.mod").path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: goModPath))
        }
    }

    @Test
    func goInstallInstallsIntoThePackageBinDirectory() async throws {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/Application Support/tool")
        let shell = ScriptedProcesses()

        let outcome = await runStep(try manager.runGoInstall(goSource(), packagePath: package), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.arguments == [["go", "install", "github.com/acme/tool@v1.0.0"]])
        #expect(shell.workingDirectories == ["/tmp/ls/Application Support/tool"])
        let invocation = try #require(shell.invocations.first)
        #expect(invocation.executable == PackageManagerProgressModel.envExecutable)
        #expect(invocation.environment["GOBIN"] == "/tmp/ls/Application Support/tool/bin")
    }

    @Test
    func goInstallTargetFollowsTheGitReferenceAndRepository() async throws {
        let manager = GolangPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/tool")
        let cases: [(PackageSource, String)] = [
            (goSource(), "github.com/acme/tool@v1.0.0"),
            (
                goSource(repositoryUrl: "https://github.com/acme/tool", gitReference: .tag("v1.2.0")),
                "github.com/acme/tool@v1.2.0"
            ),
            (
                goSource(
                    pkgName: "golang.org/x/tools",
                    repositoryUrl: "https://golang.org/x/tools",
                    gitReference: .revision("abc123")
                ),
                "golang.org/x/tools@abc123"
            ),
            (
                goSource(
                    pkgName: "example.com/tool",
                    repositoryUrl: "https://git.example.com/tool",
                    gitReference: .tag("v2")
                ),
                "git.example.com/tool@v2"
            ),
            (goSource(pkgName: "example.com/tool", gitReference: .tag("v2")), "example.com/tool@v1.0.0"),
            (
                goSource(pkgName: "example.com/tool", repositoryUrl: "https://example.com/tool"),
                "example.com/tool@v1.0.0"
            ),
            (goSource(version: "v1.0.0-rc.1+build"), "github.com/acme/tool@v1.0.0-rc.1+build"),
            (
                goSource(repositoryUrl: "https://github.com/acme/tool", gitReference: .tag("v1.2.3^0")),
                "github.com/acme/tool@v1.2.3^0"
            )
        ]

        for (source, target) in cases {
            let step = try manager.runGoInstall(source, packagePath: package)
            let shell = ScriptedProcesses()
            let outcome = await runStep(step, shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.arguments == [["go", "install", target]], "\(target)")
            #expect(shell.workingDirectories == ["/tmp/ls/tool"], "\(target)")
            #expect(shell.invocations.first?.environment["GOBIN"] == "/tmp/ls/tool/bin", "\(target)")
            let message = "This requires installing the go package \(target).\nAllow Dreamder to install this package?"
            #expect(step.confirmation.message == message)
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
            let shell = ScriptedProcesses()

            let outcome = await runStep(
                try manager.buildBinary(goSource(), subpath: "cmd/tool", packagePath: package),
                shell: shell
            )

            #expect(outcome.error == nil)
            #expect(shell.arguments == [["go", "build", "-o", "bin/tool", "github.com/acme/tool/cmd/tool"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
            #expect(shell.invocations.first?.executable == PackageManagerProgressModel.envExecutable)
            #expect(isExecutable(binary))
        }
    }
}
