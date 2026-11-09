import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct NPMPackageManagerTests {
    private static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using npm"
    private static let verifyName = "Verify Installation"
    private static let english = Locale(identifier: "en_US")

    private func manager(_ root: URL = URL(filePath: "/tmp/ls")) -> NPMPackageManager {
        NPMPackageManager(installationDirectory: root, locale: Self.english)
    }

    private func npmSource(
        version: String = "1.0.0",
        options: [String: String] = [:]
    ) -> PackageSource {
        PackageManagerFixtures.source(type: .npm, version: version, options: options)
    }

    private func writePackageJson(_ json: String, in package: URL) throws {
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: package.appending(path: "package.json"))
    }

    private func verify(
        dependencies: String?,
        requested version: String = "1.0.0",
        installedModules: Bool = true
    ) async throws -> StepOutcome {
        try await withTempDirResult { root in
            let package = root.appending(path: "tool-entry")
            if let dependencies {
                try writePackageJson(#"{ "name": "x", "dependencies": \#(dependencies) }"#, in: package)
            }
            if installedModules {
                try FileManager.default.createDirectory(
                    at: package.appending(path: "node_modules/tool", directoryHint: .isDirectory),
                    withIntermediateDirectories: true
                )
            }
            let steps = try manager(root).install(method: .standardPackage(source: npmSource(version: version)))
            return await runStep(try stepNamed(Self.verifyName, in: steps))
        }
    }

    @Test
    func installRejectsEverythingButStandardPackages() {
        let source = npmSource()
        let rejected: [InstallationMethod] = [
            .unknown,
            .sourceBuild(source: source, command: "make"),
            .binaryDownload(source: source, url: URL(filePath: "/tmp/tool.zip"))
        ]
        for method in rejected {
            #expect(errorKind(thrownError { try manager().install(method: method) }) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func installListsInitializeInstallAndVerify() throws {
        let steps = try manager().install(method: .standardPackage(source: npmSource()))

        #expect(steps.map { $0.name } == [Self.initializeName, Self.installName, Self.verifyName])
        #expect(steps.map { $0.confirmation.message } == [
            nil,
            "This requires the npm package tool@1.0.0.\nAllow Dreamder to install this package?",
            nil
        ])
    }

    @Test
    func initializeStartsAFreshNpmProject() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            try writePackageJson("{}", in: package)
            try Data("{}".utf8).write(to: package.appending(path: "package-lock.json"))
            let steps = try manager(root).install(method: .standardPackage(source: npmSource()))
            let shell = ScriptedShell()

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(package.path(percentEncoded: false))\" && npm init --yes --scope=dreamder"])
            #expect(!FileManager.default.fileExists(atPath: package.appending(path: "package.json").path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: package.appending(path: "package-lock.json").path(percentEncoded: false)))
            let npmrc = try String(contentsOf: package.appending(path: ".npmrc"), encoding: .utf8)
            #expect(npmrc == "install-strategy=shallow")
        }
    }

    @Test
    func initializeCreatesMissingDirectories() async throws {
        try await withTempDir { root in
            let steps = try manager(root).install(method: .standardPackage(source: npmSource()))

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps))

            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: root.appending(path: "tool-entry/.npmrc").path(percentEncoded: false)))
        }
    }

    @Test
    func npmInstallCommandListsTheMainAndExtraPackages() async {
        let cases: [(PackageSource, String)] = [
            (npmSource(), "npm install tool@1.0.0"),
            (npmSource(options: ["dev": "TRUE"]), "npm install tool@1.0.0 --save-dev"),
            (npmSource(options: ["dev": "false"]), "npm install tool@1.0.0"),
            (npmSource(options: ["extraPackages": "a, b"]), "npm install tool@1.0.0 a b"),
            (npmSource(options: ["dev": "true", "extraPackages": "typescript"]), "npm install tool@1.0.0 --save-dev typescript")
        ]
        let package = URL(filePath: "/tmp/ls/Application Support/tool")

        for (source, command) in cases {
            let shell = ScriptedShell()
            let outcome = await runStep(manager().runNpmInstall(source, installDir: package), shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"/tmp/ls/Application Support/tool\" && \(command)"])
        }
    }

    @Test
    func confirmationMessageListsEveryPackageWithAProperList() {
        let single = manager().runNpmInstall(npmSource(), installDir: URL(filePath: "/tmp/ls/tool"))
        #expect(single.confirmation.message == "This requires the npm package tool@1.0.0.\nAllow Dreamder to install this package?")

        let pair = manager().runNpmInstall(npmSource(options: ["extraPackages": "a"]), installDir: URL(filePath: "/tmp/ls/tool"))
        #expect(pair.confirmation.message == "This requires the npm packages tool@1.0.0 and a.\nAllow Dreamder to install these packages?")

        let many = manager().runNpmInstall(npmSource(options: ["extraPackages": "a,b"]), installDir: URL(filePath: "/tmp/ls/tool"))
        #expect(many.confirmation.message == "This requires the npm packages tool@1.0.0, a, and b.\nAllow Dreamder to install these packages?")
    }

    @Test
    func aFailedInstallRemovesNodeModulesAndRethrows() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            let modules = package.appending(path: "node_modules/partial", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
            let shell = ScriptedShell { _ in ScriptedShell.failing(1) }

            let outcome = await runStep(manager(root).runNpmInstall(npmSource(), installDir: package), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 1)")
            #expect(!FileManager.default.fileExists(atPath: package.appending(path: "node_modules").path(percentEncoded: false)))
        }
    }

    @Test
    func isInstalledRequiresConfirmationAndASemanticVersion() async {
        let good = ScriptedShell { _ in FakeProcessRunner.output("10.2.4\n") }
        let step = manager().isInstalled(method: .unknown)
        let goodOutcome = await runStep(step, shell: good)
        #expect(step.confirmation.message == "This package requires npm to install. Allow Dreamder to run npm commands?")
        #expect(goodOutcome.error == nil)
        #expect(good.commands == ["npm --version"])

        for output in ["v10.2.4", "10.2", "command not found: npm"] {
            let shell = ScriptedShell { _ in FakeProcessRunner.output(output + "\n") }
            let outcome = await runStep(manager().isInstalled(method: .unknown), shell: shell)
            #expect(errorKind(outcome.error) == "PackageManagerError.packageManagerNotInstalled", "\(output)")
        }

        let failing = ScriptedShell { _ in ScriptedShell.failing(127) }
        let failingOutcome = await runStep(manager().isInstalled(method: .unknown), shell: failing)
        #expect(errorKind(failingOutcome.error) == "ShellClientError.taskTerminated(code: 127)")
    }

    @Test
    func binaryPathIsTheNodeModulesBinEntry() {
        let path = manager(URL(filePath: "/tmp/Language Servers")).getBinaryPath(for: "tool")
        #expect(path == "/tmp/Language Servers/tool/node_modules/.bin/tool")
    }

    @Test
    func verifyPassesWhenPackageJsonAndNodeModulesAgree() async throws {
        #expect(try await verify(dependencies: #"{ "tool": "1.0.0" }"#).error == nil)
        #expect(try await verify(dependencies: #"{ "tool": "^1.0.0" }"#).error == nil)
        #expect(try await verify(dependencies: #"{ "tool": "~1.0.0" }"#, requested: "^1.0.0").error == nil)
        #expect(try await verify(dependencies: #"{ "tool": ">=1.0.0" }"#).error == nil)
    }

    @Test
    func verifyFailsWithoutThePackageInPackageJson() async throws {
        let missingFile = try await verify(dependencies: nil)
        #expect(installationFailureMessage(missingFile.error) == "Package not found in package.json")

        let otherDependency = try await verify(dependencies: #"{ "other": "1.0.0" }"#)
        #expect(installationFailureMessage(otherDependency.error) == "Package not found in package.json")
    }

    @Test
    func verifyFailsOnAVersionMismatch() async throws {
        let outcome = try await verify(dependencies: #"{ "tool": "2.0.0" }"#)
        #expect(installationFailureMessage(outcome.error) == "Version mismatch: Expected 1.0.0, but found 2.0.0")
    }

    @Test
    func verifyFailsWhenTheModuleWasNotInstalled() async throws {
        let outcome = try await verify(dependencies: #"{ "tool": "1.0.0" }"#, installedModules: false)
        #expect(installationFailureMessage(outcome.error) == "Package not found in node_modules")
    }
}

@MainActor
private func withTempDirResult<Result>(_ body: (URL) async throws -> Result) async throws -> Result {
    let directory = try makeTemporaryDirectory(label: "NPMPackageManagerTests")
    defer { removeTemporaryDirectory(directory) }
    return try await body(directory)
}
