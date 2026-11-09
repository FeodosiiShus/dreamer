import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct NPMPackageManagerTests {
    static let initializeName = "Initialize Directory Structure"
    private static let installName = "Install Package Using npm"
    private static let verifyName = "Verify Installation"
    static let english = Locale(identifier: "en_US")
    static let hostileNames = [
        "../../x", "a;rm -rf ~", "-rf", "..", ".", "", "a/b", "a\u{0}b", "a b", "$(touch x)", "`id`"
    ]
    static let hostileArguments = [
        "", "-rf", "a;rm -rf ~", "a b", "$(touch x)", "`id`", "a\u{0}b", "a\"b", "a'b", "a=b", "a:b", "a|b", "a&b"
    ]

    func manager(_ root: URL = URL(filePath: "/tmp/ls")) -> NPMPackageManager {
        NPMPackageManager(installationDirectory: root, locale: Self.english)
    }

    func npmSource(
        pkgName: String = "tool",
        entryName: String = "tool-entry",
        version: String = "1.0.0",
        options: [String: String] = [:]
    ) -> PackageSource {
        PackageManagerFixtures.source(
            type: .npm, pkgName: pkgName, entryName: entryName, version: version, options: options
        )
    }

    func unsafeInstall(_ source: PackageSource, root: URL = URL(filePath: "/tmp/ls")) -> String {
        errorKind(thrownError { try manager(root).install(method: .standardPackage(source: source)) })
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
            let failure = thrownError { try manager().install(method: method) }
            #expect(errorKind(failure) == "PackageManagerError.invalidConfiguration")
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
            let shell = ScriptedProcesses()

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [["npm", "init", "--yes", "--scope=dreamder"]])
            #expect(shell.workingDirectories == [package.path(percentEncoded: false)])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
            let packageJsonPath = package.appending(path: "package.json").path(percentEncoded: false)
            let lockPath = package.appending(path: "package-lock.json").path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: packageJsonPath))
            #expect(!FileManager.default.fileExists(atPath: lockPath))
            let npmrc = try String(contentsOf: package.appending(path: ".npmrc"), encoding: .utf8)
            #expect(npmrc == "install-strategy=shallow")
        }
    }

    @Test
    func initializeKeepsAnNpmrcCreatedByNpmInit() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            let npmrc = package.appending(path: ".npmrc")
            let steps = try manager(root).install(method: .standardPackage(source: npmSource()))
            let shell = ScriptedProcesses { _ in
                try? Data("custom=1".utf8).write(to: npmrc)
                return FakeProcessRunner.output("")
            }

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(try String(contentsOf: npmrc, encoding: .utf8) == "custom=1")
        }
    }

    @Test
    func initializeCreatesMissingDirectories() async throws {
        try await withTempDir { root in
            let steps = try manager(root).install(method: .standardPackage(source: npmSource()))

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps))

            #expect(outcome.error == nil)
            let npmrcPath = root.appending(path: "tool-entry/.npmrc").path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: npmrcPath))
        }
    }

    @Test
    func initializeStopsWhenNpmInitFails() async throws {
        try await withTempDir { root in
            let steps = try manager(root).install(method: .standardPackage(source: npmSource()))
            let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(3) }

            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 3)")
            let npmrcPath = root.appending(path: "tool-entry/.npmrc").path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: npmrcPath))
        }
    }

    @Test
    func npmInstallCommandListsTheMainAndExtraPackages() async throws {
        let cases: [(PackageSource, [String])] = [
            (npmSource(), ["npm", "install", "tool@1.0.0"]),
            (npmSource(options: ["dev": "TRUE"]), ["npm", "install", "tool@1.0.0", "--save-dev"]),
            (npmSource(options: ["dev": "false"]), ["npm", "install", "tool@1.0.0"]),
            (npmSource(options: ["dev": "true; rm -rf ~"]), ["npm", "install", "tool@1.0.0"]),
            (npmSource(options: ["extraPackages": "a, b"]), ["npm", "install", "tool@1.0.0", "a", "b"]),
            (npmSource(options: ["extraPackages": "a,,b"]), ["npm", "install", "tool@1.0.0", "a", "b"]),
            (npmSource(options: ["extraPackages": ","]), ["npm", "install", "tool@1.0.0"]),
            (
                npmSource(options: ["dev": "true", "extraPackages": "typescript"]),
                ["npm", "install", "tool@1.0.0", "--save-dev", "typescript"]
            )
        ]
        let package = URL(filePath: "/tmp/ls/Application Support/tool")

        for (source, expected) in cases {
            let shell = ScriptedProcesses()
            let outcome = await runStep(try manager().runNpmInstall(source, installDir: package), shell: shell)
            #expect(outcome.error == nil)
            #expect(shell.arguments == [expected])
            #expect(shell.workingDirectories == ["/tmp/ls/Application Support/tool"])
            #expect(shell.invocations.map(\.executable) == [PackageManagerProgressModel.envExecutable])
            #expect(outcome.statuses == [expected.joined(separator: " ")])
        }
    }

    @Test
    func oddButAllowedValuesArriveAsSingleArguments() async throws {
        let package = URL(filePath: "/tmp/ls/tool")
        let source = npmSource(
            pkgName: "@types/node",
            version: "^1.2.3",
            options: ["extraPackages": "x@~2.0.0, @a/b@^1,y"]
        )
        let shell = ScriptedProcesses()

        let outcome = await runStep(try manager().runNpmInstall(source, installDir: package), shell: shell)

        #expect(outcome.error == nil)
        #expect(shell.arguments == [["npm", "install", "@types/node@^1.2.3", "x@~2.0.0", "@a/b@^1", "y"]])
    }

    @Test
    func confirmationMessageListsEveryPackageWithAProperList() throws {
        let package = URL(filePath: "/tmp/ls/tool")
        let single = try manager().runNpmInstall(npmSource(), installDir: package)
        #expect(
            single.confirmation.message
                == "This requires the npm package tool@1.0.0.\nAllow Dreamder to install this package?"
        )

        let pair = try manager().runNpmInstall(npmSource(options: ["extraPackages": "a"]), installDir: package)
        #expect(
            pair.confirmation.message
                == "This requires the npm packages tool@1.0.0 and a.\nAllow Dreamder to install these packages?"
        )

        let many = try manager().runNpmInstall(npmSource(options: ["extraPackages": "a,b"]), installDir: package)
        #expect(
            many.confirmation.message
                == "This requires the npm packages tool@1.0.0, a, and b.\nAllow Dreamder to install these packages?"
        )
    }

    @Test
    func aFailedInstallRemovesNodeModulesAndRethrows() async throws {
        try await withTempDir { root in
            let package = root.appending(path: "tool-entry")
            let modules = package.appending(path: "node_modules/partial", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
            let shell = ScriptedProcesses { _ in ScriptedProcesses.failing(1) }

            let outcome = await runStep(try manager(root).runNpmInstall(npmSource(), installDir: package), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 1)")
            let modulesPath = package.appending(path: "node_modules").path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: modulesPath))
        }
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
