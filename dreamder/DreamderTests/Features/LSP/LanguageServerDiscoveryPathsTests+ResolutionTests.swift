import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension LanguageServerDiscoveryPathsTests {
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
            [
                "/ws/.venv/bin/pyright-langserver",
                "/ws/venv/bin/pyright-langserver",
                "/reg/kls/venv/bin/pyright-langserver"
            ],
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

    @Test
    func projectLocalServerBeatsTheGlobalOneForEveryTypeScriptFlavour() {
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

    @Test
    func xcrunOnlyBacksSourceKitCandidates() {
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
        let goBinary = LanguageServerDiscovery.binary(
            for: .go,
            searchPaths: ["/usr/bin"],
            environment: nil,
            isExecutable: { _ in false },
            sourceKitFallback: fallback
        )
        #expect(goBinary == nil)
    }
}
