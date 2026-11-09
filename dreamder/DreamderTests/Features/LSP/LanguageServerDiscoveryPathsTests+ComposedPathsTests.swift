import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension LanguageServerDiscoveryPathsTests {
    @Test
    func composedSearchPathsStartWithMiseAndAsdfShimsAndStillDedupe() {
        let paths = LSPProcessEnvironment.composedSearchPaths(
            loginPath: "/Users/tester/.asdf/shims:/custom/bin:/Users/tester/.local/share/mise/shims:/custom/bin",
            homeDirectory: "/Users/tester",
            npmGlobalBin: "/npm/bin",
            extraDirectories: ["/extra", "/npm/bin"]
        )
        #expect(paths.prefix(3) == [
            "/Users/tester/.local/share/mise/shims",
            "/Users/tester/.asdf/shims",
            "/custom/bin"
        ])
        #expect(Set(paths).count == paths.count)
        #expect(paths.filter { $0 == "/npm/bin" }.count == 1)
        #expect(paths.contains("/extra"))
        #expect(!paths.contains(""))
    }

    @Test
    func composedSearchPathsWithoutLoginPathStillHaveTheShimsFirst() {
        let paths = LSPProcessEnvironment.composedSearchPaths(loginPath: nil, homeDirectory: "/h")
        #expect(paths.prefix(3) == ["/h/.local/share/mise/shims", "/h/.asdf/shims", "/opt/homebrew/bin"])
    }

    @Test
    func directoryContentsListsEntriesAndToleratesMissingDirectories() throws {
        try withTempDir { directory in
            try Data().write(to: directory.appending(path: "first"))
            try FileManager.default.createDirectory(
                at: directory.appending(path: "second"),
                withIntermediateDirectories: false
            )
            let listed = LanguageServerDiscovery.directoryContents(atPath: directory.path(percentEncoded: false))
            #expect(listed.sorted() == ["first", "second"])
            let missing = directory.appending(path: "missing").path(percentEncoded: false)
            #expect(LanguageServerDiscovery.directoryContents(atPath: missing).isEmpty)
        }
    }

    @Test
    func concurrentLookupWithoutCandidatesReturnsNil() async {
        let binary = await LanguageServerDiscovery.binary(
            for: LSPLanguage(.ruby),
            workspacePath: nil,
            workspaceTrusted: false,
            registryInstallPath: nil
        )
        #expect(binary == nil)
    }

    @Test
    func concurrentLookupFindsAnExecutableInsideARegistryPackage() async throws {
        try await withTempDir { directory in
            let packageBin = directory.appending(path: "pkg/bin")
            try FileManager.default.createDirectory(at: packageBin, withIntermediateDirectories: true)
            let script = packageBin.appending(path: "gopls")
            try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: script.path(percentEncoded: false)
            )

            let registry = directory.path(percentEncoded: false)
            let binary = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: nil,
                workspaceTrusted: false,
                registryInstallPath: registry
            )
            let expected = ((registry as NSString).appendingPathComponent("pkg/bin") as NSString)
                .appendingPathComponent("gopls")
            #expect(binary?.execPath == expected)
            #expect(binary?.args == [])
            #expect(binary?.env?["PATH"]?.hasPrefix(registry + ":") == true)

            let disabled = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: nil,
                workspaceTrusted: false,
                registryInstallPath: registry,
                disabledRegistryPackages: ["pkg"]
            )
            #expect(disabled?.execPath != expected)
        }
    }
}
