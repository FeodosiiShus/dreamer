import Foundation
import Testing
@testable import Dreamder

extension NPMPackageManagerTests {
    @Test
    func hostileEntryNamesAreRejectedBeforeAnyStepExists() {
        for name in Self.hostileNames {
            #expect(unsafeInstall(npmSource(entryName: name)) == "PackageManagerError.unsafeValue", "\(name)")
        }
    }

    @Test
    func hostilePackageNamesAndVersionsAreRejected() {
        for value in Self.hostileArguments {
            #expect(unsafeInstall(npmSource(pkgName: value)) == "PackageManagerError.unsafeValue", "name \(value)")
            #expect(unsafeInstall(npmSource(version: value)) == "PackageManagerError.unsafeValue", "version \(value)")
        }
    }

    @Test
    func hostileExtraPackagesAreRejectedIncludingBlankEntries() {
        let plainHostile = Self.hostileArguments.filter { !$0.isEmpty && !$0.contains(",") }
        let hostile = plainHostile + ["a, ", "a, ,b", " ", "a,\t,b"]
        for value in hostile {
            let source = npmSource(options: ["extraPackages": value])
            #expect(unsafeInstall(source) == "PackageManagerError.unsafeValue", "extra \(value)")
        }
    }

    @Test
    func theBuilderItselfThrowsForHostileValues() {
        let package = URL(filePath: "/tmp/ls/tool")
        let source = npmSource(options: ["extraPackages": "ok, $(touch x)"])

        let failure = thrownError { try manager().runNpmInstall(source, installDir: package) }
        #expect(errorKind(failure) == "PackageManagerError.unsafeValue")
    }

    @Test
    func hostileEntryNamesNeverTouchTheFileSystemOutsideTheInstallRoot() async throws {
        try await withTempDir { base in
            let root = base.appending(path: "Language Servers", directoryHint: .isDirectory)
            let sibling = base.appending(path: "sibling", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            let sentinel = sibling.appending(path: "package.json")
            try Data("keep".utf8).write(to: sentinel)
            let shell = ScriptedProcesses()

            for name in ["../sibling", "..", ".", "../sibling/package.json"] {
                let kind = unsafeInstall(npmSource(entryName: name), root: root)
                #expect(kind == "PackageManagerError.unsafeValue", "\(name)")
            }

            #expect(shell.invocations.isEmpty)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)

            let steps = try manager(root).install(method: .standardPackage(source: npmSource()))
            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)
            #expect(outcome.error == nil)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        }
    }

    @Test
    func isInstalledRequiresConfirmationAndASemanticVersion() async {
        let good = ScriptedProcesses { _ in FakeProcessRunner.output("10.2.4\n") }
        let step = manager().isInstalled(method: .unknown)
        let goodOutcome = await runStep(step, shell: good)
        #expect(
            step.confirmation.message == "This package requires npm to install. Allow Dreamder to run npm commands?"
        )
        #expect(goodOutcome.error == nil)
        #expect(good.arguments == [["npm", "--version"]])
        #expect(good.workingDirectories == [nil])

        for output in ["v10.2.4", "10.2", "command not found: npm"] {
            let shell = ScriptedProcesses { _ in FakeProcessRunner.output(output + "\n") }
            let outcome = await runStep(manager().isInstalled(method: .unknown), shell: shell)
            #expect(errorKind(outcome.error) == "PackageManagerError.packageManagerNotInstalled", "\(output)")
        }

        let failing = ScriptedProcesses { _ in ScriptedProcesses.failing(127) }
        let failingOutcome = await runStep(manager().isInstalled(method: .unknown), shell: failing)
        #expect(errorKind(failingOutcome.error) == "ShellClientError.taskTerminated(code: 127)")
    }

    @Test
    func binaryPathIsTheNodeModulesBinEntry() {
        let path = manager(URL(filePath: "/tmp/Language Servers")).getBinaryPath(for: "tool")
        #expect(path == "/tmp/Language Servers/tool/node_modules/.bin/tool")
    }
}
