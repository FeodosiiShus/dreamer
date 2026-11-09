import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct LanguageServerDiscoveryDefaultsTests {
    private func makeMiseLayout(in directory: URL) throws -> (launcher: URL, target: URL) {
        let miseDirectory = directory.appending(path: "mise-bin")
        let shims = directory.appending(path: "shims")
        let package = directory.appending(path: "pkg/node_modules/typescript")
        for folder in [miseDirectory, shims, package.appending(path: "bin")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let mise = miseDirectory.appending(path: "mise")
        try Data("#!/bin/sh\n".utf8).write(to: mise)
        let target = package.appending(path: "bin/tsserver")
        try Data("#!/bin/sh\n".utf8).write(to: target)
        let launcher = shims.appending(path: "tsserver")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: mise)
        return (launcher, target)
    }

    @Test
    func miseLauncherResolutionWithoutAnInjectedEnvironmentUsesTheSharedLoginEnvironment() async throws {
        try await withTempDir { directory in
            let layout = try makeMiseLayout(in: directory)
            let runner = FakeProcessRunner { _ in
                FakeProcessRunner.output(layout.target.path(percentEncoded: false) + "\n")
            }

            let resolved = await LanguageServerDiscovery.resolveLauncher(
                layout.launcher.path(percentEncoded: false),
                workspacePath: nil,
                runner: runner
            )

            #expect(resolved == layout.target.path(percentEncoded: false))
            let invocation = try #require(runner.invocations.first)
            let shared = await LSPProcessEnvironment.shared.resolve().environment
            #expect(invocation.environment == shared)
        }
    }

    @Test
    func searchDirectoriesWithoutATsserverLauncherAreSkippedWithoutSpawningProcesses() async throws {
        try await withTempDir { directory in
            let empty = directory.appending(path: "empty-bin")
            try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("") }

            let options = await LanguageServerDiscovery.resolvedInitializationOptions(
                for: .typescript,
                workspacePath: directory.path(percentEncoded: false),
                searchPaths: [empty.path(percentEncoded: false), "/dreamder-missing-bin"],
                inlayHints: InlayHintSettings(),
                runner: runner,
                environment: [:]
            )

            #expect(options == .hash(["preferences": InlayHintServerPreferences.preferences(for: InlayHintSettings())]))
            #expect(runner.invocations.isEmpty)
        }
    }

    @Test
    func swiftLookupAsksTheSharedEnvironmentForSourceKitLSP() async {
        let binary = await LanguageServerDiscovery.binary(
            for: .swift,
            workspacePath: nil,
            workspaceTrusted: false,
            registryInstallPath: nil
        )

        #expect(binary?.execPath.hasSuffix("sourcekit-lsp") == true)
    }
}
