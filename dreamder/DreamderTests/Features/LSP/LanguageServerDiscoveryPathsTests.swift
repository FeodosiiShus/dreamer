import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("Language server discovery paths")
struct LanguageServerDiscoveryPathsTests {
    private static let basePaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    func fakeListing(_ listing: [String: [String]]) -> (String) -> [String] {
        { listing[$0] ?? [] }
    }

    func searchPaths(
        workspace: String? = "/ws",
        trusted: Bool = true,
        registry: String? = "/reg",
        disabled: Set<String> = [],
        listing: [String: [String]] = ["/reg": ["jdtls-pkg", "kls", "taplo", "bash-ls", "yaml-ls"]]
    ) -> [String] {
        LanguageServerDiscovery.mergedSearchPaths(
            local: LanguageServerDiscovery.localSearchPaths(
                workspacePath: workspace,
                workspaceTrusted: trusted,
                registryInstallPath: registry,
                disabledRegistryPackages: disabled,
                listDirectory: fakeListing(listing)
            ),
            base: Self.basePaths
        )
    }

    @Test
    func candidateTableCoversNewLanguages() {
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

    @Test
    func argumentsComeFromTheCandidateTableForNewServers() {
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

    @Test
    func allCandidatesAreUniqueAndIncludeEveryServer() {
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

    @Test
    func localSearchPathsFollowTheDocumentedOrder() {
        let local = LanguageServerDiscovery.localSearchPaths(
            workspacePath: "/ws",
            workspaceTrusted: true,
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

    @Test
    func localSearchPathsConstantsMatchTheDirectoriesUsed() {
        #expect(LanguageServerDiscovery.workspaceBinDirectories == ["node_modules/.bin", ".venv/bin", "venv/bin"])
        #expect(LanguageServerDiscovery.registryPackageBinDirectories == ["bin", "node_modules/.bin", "venv/bin"])
    }

    @Test
    func missingOrEmptyRootsContributeNothing() {
        var listed: [String] = []
        let recording: (String) -> [String] = { listed.append($0); return ["pkg"] }
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: nil,
            workspaceTrusted: true,
            registryInstallPath: nil,
            listDirectory: recording
        ).isEmpty)
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: "",
            workspaceTrusted: true,
            registryInstallPath: "",
            listDirectory: recording
        ).isEmpty)
        #expect(listed.isEmpty)
    }

    @Test
    func workspaceOnlyAndRegistryOnlyRoots() {
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: "/ws",
            workspaceTrusted: true,
            registryInstallPath: nil,
            listDirectory: { _ in ["ignored"] }
        ) == ["/ws/node_modules/.bin", "/ws/.venv/bin", "/ws/venv/bin"])
        #expect(LanguageServerDiscovery.localSearchPaths(
            workspacePath: nil,
            workspaceTrusted: true,
            registryInstallPath: "/reg",
            listDirectory: { _ in [] }
        ) == ["/reg"])
    }

    @Test
    func disabledPackagesAreSkippedEntirely() {
        let local = LanguageServerDiscovery.localSearchPaths(
            workspacePath: nil,
            workspaceTrusted: true,
            registryInstallPath: "/reg",
            disabledRegistryPackages: ["a", "b"],
            listDirectory: { _ in ["a", "b"] }
        )
        #expect(local == ["/reg"])
    }

    @Test
    func mergedSearchPathsDedupeAndDropEmptyEntries() {
        let merged = LanguageServerDiscovery.mergedSearchPaths(
            local: ["/a", "", "/b", "/a"],
            base: ["/b", "/c", "", "/a", "/d"]
        )
        #expect(merged == ["/a", "/b", "/c", "/d"])
        #expect(LanguageServerDiscovery.mergedSearchPaths(local: [], base: []).isEmpty)
    }
}
