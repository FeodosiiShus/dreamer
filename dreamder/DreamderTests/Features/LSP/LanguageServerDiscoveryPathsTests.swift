import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("Language server discovery paths")
struct LanguageServerDiscoveryPathsTests {
    private static let basePaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    private func fakeListing(_ listing: [String: [String]]) -> (String) -> [String] {
        { listing[$0] ?? [] }
    }

    private func searchPaths(
        workspace: String? = "/ws",
        registry: String? = "/reg",
        disabled: Set<String> = [],
        listing: [String: [String]] = ["/reg": ["jdtls-pkg", "kls", "taplo", "bash-ls", "yaml-ls"]]
    ) -> [String] {
        LanguageServerDiscovery.mergedSearchPaths(
            local: LanguageServerDiscovery.localSearchPaths(
                workspacePath: workspace,
                registryInstallPath: registry,
                disabledRegistryPackages: disabled,
                listDirectory: fakeListing(listing)
            ),
            base: Self.basePaths
        )
    }

    @Test func candidateTableCoversNewLanguages() {
        let table: [(LSPLanguage, [String], [[String]])] = [
            (.java, ["jdtls"], [[]]),
            (.kotlin, ["kotlin-language-server"], [[]]),
            (.yaml, ["yaml-language-server"], [["--stdio"]]),
            (.toml, ["taplo"], [["lsp", "stdio"]]),
            (.shellscript, ["bash-language-server"], [["start"]]),
            (.objcpp, ["clangd", "sourcekit-lsp"], [[], []]),
            (.scss, ["vscode-css-language-server"], [["--stdio"]]),
            (.less, ["vscode-css-language-server"], [["--stdio"]]),
            (.typescriptreact, ["typescript-language-server", "vtsls"], [["--stdio"], ["--stdio"]]),
            (LSPLanguage(.markdown), [], []),
            (LSPLanguage(.ruby), [], [])
        ]
        for (language, executables, arguments) in table {
            let candidates = LanguageServerDiscovery.candidates(for: language)
            #expect(candidates.map(\.executable) == executables, "\(language.rawValue)")
            #expect(candidates.map(\.arguments) == arguments, "\(language.rawValue)")
        }
    }

    @Test func argumentsComeFromTheCandidateTableForNewServers() {
        let table: [(String, [String])] = [
            ("/reg/pkg/bin/jdtls", []),
            ("/reg/pkg/bin/kotlin-language-server", []),
            ("/reg/pkg/node_modules/.bin/yaml-language-server", ["--stdio"]),
            ("/reg/pkg/bin/taplo", ["lsp", "stdio"]),
            ("/reg/pkg/node_modules/.bin/bash-language-server", ["start"]),
            ("taplo", ["lsp", "stdio"]),
            ("/reg/pkg/bin/clangd", []),
            ("/reg/pkg/bin/not-a-server", [])
        ]
        for (path, arguments) in table {
            #expect(LanguageServerDiscovery.arguments(forExecutablePath: path) == arguments, "\(path)")
        }
    }

    @Test func allCandidatesAreUniqueAndIncludeEveryServer() {
        let executables = LanguageServerDiscovery.allCandidates.map(\.executable)
        #expect(Set(executables).count == executables.count)
        for expected in [
            "sourcekit-lsp", "clangd", "typescript-language-server", "vtsls", "basedpyright-langserver",
            "pyright-langserver", "pylsp", "gopls", "rust-analyzer", "vscode-json-language-server",
            "vscode-css-language-server", "vscode-html-language-server", "jdtls", "kotlin-language-server",
            "yaml-language-server", "taplo", "bash-language-server"
        ] {
            #expect(executables.contains(expected), "\(expected)")
        }
        #expect(LanguageServerDiscovery.allCandidates.first { $0.executable == "taplo" }?.arguments == ["lsp", "stdio"])
    }

    @Test func localSearchPathsFollowTheDocumentedOrder() {
        let local = LanguageServerDiscovery.localSearchPaths(
            workspacePath: "/ws",
            registryInstallPath: "/reg",
            disabledRegistryPackages: ["off"],
            listDirectory: fakeListing(["/reg": ["zeta", "off", "alpha"]])
        )
        #expect(local == [
            "/ws/node_modules/.bin",
            "/ws/.venv/bin",
            "/ws/venv/bin",
            "/reg",
            "/reg/alpha/bin",
            "/reg/alpha/node_modules/.bin",
            "/reg/alpha/venv/bin",
            "/reg/zeta/bin",
            "/reg/zeta/node_modules/.bin",
            "/reg/zeta/venv/bin"
        ])
    }

    @Test func localSearchPathsConstantsMatchTheDirectoriesUsed() {
        #expect(LanguageServerDiscovery.workspaceBinDirectories == ["node_modules/.bin", ".venv/bin", "venv/bin"])
        #expect(LanguageServerDiscovery.registryPackageBinDirectories == ["bin", "node_modules/.bin", "venv/bin"])
    }

    @Test func missingOrEmptyRootsContributeNothing() {
        var listed: [String] = []
        let recording: (String) -> [String] = { listed.append($0); return ["pkg"] }
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: nil,
            registryInstallPath: nil,
            listDirectory: recording
        ).isEmpty)
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: "",
            registryInstallPath: "",
            listDirectory: recording
        ).isEmpty)
        #expect(listed.isEmpty)
    }

    @Test func workspaceOnlyAndRegistryOnlyRoots() {
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: "/ws",
            registryInstallPath: nil,
            listDirectory: { _ in ["ignored"] }
        ) == ["/ws/node_modules/.bin", "/ws/.venv/bin", "/ws/venv/bin"])
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: nil,
            registryInstallPath: "/reg",
            listDirectory: { _ in [] }
        ) == ["/reg"])
    }

    @Test func disabledPackagesAreSkippedEntirely() {
        let local = LanguageServerDiscovery.localSearchPaths(
            workspacePath: nil,
            registryInstallPath: "/reg",
            disabledRegistryPackages: ["a", "b"],
            listDirectory: { _ in ["a", "b"] }
        )
        #expect(local == ["/reg"])
    }

    @Test func mergedSearchPathsDedupeAndDropEmptyEntries() {
        let merged = LanguageServerDiscovery.mergedSearchPaths(
            local: ["/a", "", "/b", "/a"],
            base: ["/b", "/c", "", "/a", "/d"]
        )
        #expect(merged == ["/a", "/b", "/c", "/d"])
        #expect(LanguageServerDiscovery.mergedSearchPaths(local: [], base: []).isEmpty)
    }

    struct ResolutionRow: Sendable {
        let language: LSPLanguage
        let executables: Set<String>
        let expectedPath: String
        let expectedArguments: [String]
        let workspace: String?
        let disabled: Set<String>

        init(
            _ language: LSPLanguage,
            _ executables: Set<String>,
            expects expectedPath: String,
            arguments: [String] = [],
            workspace: String? = "/ws",
            disabled: Set<String> = []
        ) {
            self.language = language
            self.executables = executables
            self.expectedPath = expectedPath
            self.expectedArguments = arguments
            self.workspace = workspace
            self.disabled = disabled
        }
    }

    static let resolutionRows: [ResolutionRow] = [
        ResolutionRow(
            .typescript,
            ["/ws/node_modules/.bin/typescript-language-server", "/opt/homebrew/bin/typescript-language-server"],
            expects: "/ws/node_modules/.bin/typescript-language-server",
            arguments: ["--stdio"]
        ),
        ResolutionRow(
            .python,
            ["/ws/.venv/bin/pyright-langserver", "/ws/venv/bin/pyright-langserver", "/reg/kls/venv/bin/pyright-langserver"],
            expects: "/ws/.venv/bin/pyright-langserver",
            arguments: ["--stdio"]
        ),
        ResolutionRow(
            .python,
            ["/ws/venv/bin/pylsp", "/usr/local/bin/pylsp"],
            expects: "/ws/venv/bin/pylsp"
        ),
        ResolutionRow(
            .java,
            ["/reg/jdtls-pkg/bin/jdtls", "/opt/homebrew/bin/jdtls"],
            expects: "/reg/jdtls-pkg/bin/jdtls"
        ),
        ResolutionRow(
            .kotlin,
            ["/reg/kls/bin/kotlin-language-server", "/usr/local/bin/kotlin-language-server"],
            expects: "/reg/kls/bin/kotlin-language-server"
        ),
        ResolutionRow(
            .toml,
            ["/reg/taplo/bin/taplo", "/opt/homebrew/bin/taplo"],
            expects: "/reg/taplo/bin/taplo",
            arguments: ["lsp", "stdio"]
        ),
        ResolutionRow(
            .shellscript,
            ["/reg/bash-ls/node_modules/.bin/bash-language-server"],
            expects: "/reg/bash-ls/node_modules/.bin/bash-language-server",
            arguments: ["start"]
        ),
        ResolutionRow(
            .yaml,
            ["/reg/yaml-ls/venv/bin/yaml-language-server", "/opt/homebrew/bin/yaml-language-server"],
            expects: "/reg/yaml-ls/venv/bin/yaml-language-server",
            arguments: ["--stdio"]
        ),
        ResolutionRow(
            .go,
            ["/reg/taplo/bin/gopls", "/opt/homebrew/bin/gopls", "/usr/local/bin/gopls"],
            expects: "/reg/taplo/bin/gopls"
        ),
        ResolutionRow(
            .go,
            ["/reg/gopls", "/opt/homebrew/bin/gopls"],
            expects: "/reg/gopls"
        ),
        ResolutionRow(
            .go,
            ["/opt/homebrew/bin/gopls", "/usr/local/bin/gopls"],
            expects: "/opt/homebrew/bin/gopls"
        ),
        ResolutionRow(
            .go,
            ["/usr/local/bin/gopls"],
            expects: "/usr/local/bin/gopls",
            workspace: nil
        ),
        ResolutionRow(
            .kotlin,
            ["/reg/kls/bin/kotlin-language-server", "/usr/local/bin/kotlin-language-server"],
            expects: "/usr/local/bin/kotlin-language-server",
            disabled: ["kls"]
        ),
        ResolutionRow(
            .javascript,
            ["/ws/node_modules/.bin/vtsls", "/opt/homebrew/bin/typescript-language-server"],
            expects: "/opt/homebrew/bin/typescript-language-server",
            arguments: ["--stdio"]
        )
    ]

    @Test(arguments: resolutionRows)
    func resolutionPicksTheHighestPriorityDirectory(row: ResolutionRow) {
        let binary = LanguageServerDiscovery.binary(
            for: row.language,
            searchPaths: searchPaths(workspace: row.workspace, disabled: row.disabled),
            environment: ["PATH": "/p"],
            isExecutable: { row.executables.contains($0) }
        )
        #expect(binary?.execPath == row.expectedPath)
        #expect(binary?.args == row.expectedArguments)
        #expect(binary?.env == ["PATH": "/p"])
    }

    @Test func projectLocalServerBeatsTheGlobalOneForEveryTypeScriptFlavour() {
        let executables: Set<String> = [
            "/ws/node_modules/.bin/typescript-language-server",
            "/opt/homebrew/bin/typescript-language-server"
        ]
        for language in [LSPLanguage.typescript, .javascript, .typescriptreact, .javascriptreact] {
            let binary = LanguageServerDiscovery.binary(
                for: language,
                searchPaths: searchPaths(),
                environment: nil,
                isExecutable: { executables.contains($0) }
            )
            #expect(binary?.execPath == "/ws/node_modules/.bin/typescript-language-server", "\(language.rawValue)")
        }
    }

    @Test func xcrunOnlyBacksSourceKitCandidates() {
        let fallback = "/toolchain/sourcekit-lsp"
        let cpp = LanguageServerDiscovery.binary(
            for: .cpp,
            searchPaths: ["/usr/bin"],
            environment: nil,
            isExecutable: { _ in false },
            sourceKitFallback: fallback
        )
        #expect(cpp?.execPath == "/toolchain/sourcekit-lsp")
        let preferred = LanguageServerDiscovery.binary(
            for: .cpp,
            searchPaths: ["/usr/bin"],
            environment: nil,
            isExecutable: { $0 == "/usr/bin/clangd" },
            sourceKitFallback: fallback
        )
        #expect(preferred?.execPath == "/usr/bin/clangd")
        let go = LanguageServerDiscovery.binary(
            for: .go,
            searchPaths: ["/usr/bin"],
            environment: nil,
            isExecutable: { _ in false },
            sourceKitFallback: fallback
        )
        #expect(go == nil)
    }

    @Test func composedSearchPathsStartWithMiseAndAsdfShimsAndStillDedupe() {
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

    @Test func composedSearchPathsWithoutLoginPathStillHaveTheShimsFirst() {
        let paths = LSPProcessEnvironment.composedSearchPaths(loginPath: nil, homeDirectory: "/h")
        #expect(paths.prefix(3) == ["/h/.local/share/mise/shims", "/h/.asdf/shims", "/opt/homebrew/bin"])
    }

    @Test func directoryContentsListsEntriesAndToleratesMissingDirectories() throws {
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

    @Test func concurrentLookupWithoutCandidatesReturnsNil() async {
        let binary = await LanguageServerDiscovery.binary(
            for: LSPLanguage(.ruby),
            workspacePath: nil,
            registryInstallPath: nil
        )
        #expect(binary == nil)
    }

    @Test func concurrentLookupFindsAnExecutableInsideARegistryPackage() async throws {
        try await withTempDir { directory in
            let packageBin = directory.appending(path: "pkg/bin")
            try FileManager.default.createDirectory(at: packageBin, withIntermediateDirectories: true)
            let script = packageBin.appending(path: "gopls")
            try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))

            let registry = directory.path(percentEncoded: false)
            let binary = await LanguageServerDiscovery.binary(
                for: .go,
                workspacePath: nil,
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
                registryInstallPath: registry,
                disabledRegistryPackages: ["pkg"]
            )
            #expect(disabled?.execPath != expected)
        }
    }
}
