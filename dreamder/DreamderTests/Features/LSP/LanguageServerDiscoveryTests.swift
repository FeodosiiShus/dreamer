import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("Language server discovery")
struct LanguageServerDiscoveryTests {
    private func executableChecker(_ executables: Set<String>) -> (String) -> Bool {
        { path in executables.contains(path) }
    }

    @Test func candidateTableMatchesLanguages() {
        #expect(LanguageServerDiscovery.candidates(for: .swift).map(\.executable) == ["sourcekit-lsp"])
        #expect(LanguageServerDiscovery.candidates(for: .objc).map(\.executable) == ["sourcekit-lsp"])

        let typeScript = LanguageServerDiscovery.candidates(for: .typescript)
        #expect(typeScript.map(\.executable) == ["typescript-language-server", "vtsls"])
        #expect(typeScript.allSatisfy { $0.arguments == ["--stdio"] })

        #expect(LanguageServerDiscovery.candidates(for: .javascript).map(\.executable).first == "typescript-language-server")
        #expect(LanguageServerDiscovery.candidates(for: .typescriptreact).first?.executable == "typescript-language-server")
        #expect(LanguageServerDiscovery.candidates(for: .javascriptreact).first?.executable == "typescript-language-server")

        #expect(LanguageServerDiscovery.candidates(for: .python).map(\.executable) == [
            "basedpyright-langserver",
            "pyright-langserver",
            "pylsp"
        ])
        #expect(LanguageServerDiscovery.candidates(for: .go).map(\.executable) == ["gopls"])
        #expect(LanguageServerDiscovery.candidates(for: .rust).map(\.executable) == ["rust-analyzer"])
        #expect(LanguageServerDiscovery.candidates(for: .c).first?.executable == "clangd")
        #expect(LanguageServerDiscovery.candidates(for: .cpp).first?.executable == "clangd")
        #expect(LanguageServerDiscovery.candidates(for: .json).first?.arguments == ["--stdio"])
        #expect(LanguageServerDiscovery.candidates(for: .css).first?.executable == "vscode-css-language-server")
        #expect(LanguageServerDiscovery.candidates(for: .html).first?.executable == "vscode-html-language-server")
        #expect(LanguageServerDiscovery.candidates(for: .ruby).isEmpty)
    }

    @Test func argumentsComeFromCandidateTable() {
        #expect(LanguageServerDiscovery.arguments(forExecutablePath: "/opt/homebrew/bin/typescript-language-server") == ["--stdio"])
        #expect(LanguageServerDiscovery.arguments(forExecutablePath: "/usr/local/bin/gopls") == [])
        #expect(LanguageServerDiscovery.arguments(forExecutablePath: "/usr/local/bin/unknown-server") == [])
    }

    @Test func resolvesFromSearchPathOrder() {
        let binary = LanguageServerDiscovery.binary(
            for: .python,
            searchPaths: ["/opt/homebrew/bin", "/usr/local/bin"],
            environment: ["PATH": "/usr/local/bin"],
            isExecutable: executableChecker(["/usr/local/bin/pyright-langserver"])
        )
        #expect(binary?.execPath == "/usr/local/bin/pyright-langserver")
        #expect(binary?.args == ["--stdio"])
        #expect(binary?.env == ["PATH": "/usr/local/bin"])
    }

    @Test func prefersFirstAvailableCandidate() {
        let binary = LanguageServerDiscovery.binary(
            for: .python,
            searchPaths: ["/opt/homebrew/bin"],
            environment: nil,
            isExecutable: executableChecker([
                "/opt/homebrew/bin/basedpyright-langserver",
                "/opt/homebrew/bin/pyright-langserver"
            ])
        )
        #expect(binary?.execPath == "/opt/homebrew/bin/basedpyright-langserver")
    }

    @Test func fallsBackToXcrunForSourceKit() {
        let binary = LanguageServerDiscovery.binary(
            for: .swift,
            searchPaths: ["/usr/bin"],
            environment: nil,
            isExecutable: executableChecker([]),
            xcrunFind: { tool in tool == "sourcekit-lsp" ? "/toolchain/bin/sourcekit-lsp" : nil }
        )
        #expect(binary?.execPath == "/toolchain/bin/sourcekit-lsp")
        #expect(binary?.args == [])
    }

    @Test func returnsNilWhenNothingResolves() {
        let binary = LanguageServerDiscovery.binary(
            for: .rust,
            searchPaths: ["/usr/bin"],
            environment: nil,
            isExecutable: executableChecker([])
        )
        #expect(binary == nil)
    }

    @Test func searchPathsIncludeCommonInstallLocations() {
        let paths = LSPProcessEnvironment.composedSearchPaths(
            loginPath: "/custom/bin:/opt/homebrew/bin::",
            homeDirectory: "/Users/tester",
            npmGlobalBin: "/usr/local/npm/bin",
            extraDirectories: ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"]
        )
        #expect(paths.first == "/custom/bin")
        #expect(paths.contains("/opt/homebrew/bin"))
        #expect(paths.contains("/usr/local/bin"))
        #expect(paths.contains("/Users/tester/.local/bin"))
        #expect(paths.contains("/Users/tester/.cargo/bin"))
        #expect(paths.contains("/Users/tester/go/bin"))
        #expect(paths.contains("/Users/tester/.bun/bin"))
        #expect(paths.contains("/usr/local/npm/bin"))
        #expect(paths.filter { $0 == "/opt/homebrew/bin" }.count == 1)
        #expect(!paths.contains(""))
    }

    @Test func typeScriptServerGetsAnInstalledTsserverWhenTheWorkspaceHasNone() {
        let files: Set<String> = [
            "/mise/bin/tsserver",
            "/mise/node_modules/typescript/lib/tsserver.js"
        ]
        let resolve: (String) -> String = { path in
            path == "/mise/bin/tsserver" ? "/mise/node_modules/typescript/bin/tsserver" : path
        }
        let options = LanguageServerDiscovery.initializationOptions(
            for: .typescript,
            workspacePath: "/project",
            searchPaths: ["/empty", "/mise/bin"],
            fileExists: { files.contains($0) },
            resolveSymlinks: resolve
        )
        #expect(options == .hash([
            "preferences": .hash(["includeInlayParameterNameHints": .string("literals")]),
            "tsserver": .hash(["path": .string("/mise/node_modules/typescript/lib/tsserver.js")])
        ]))

        let withLocalTypeScript = LanguageServerDiscovery.initializationOptions(
            for: .javascript,
            workspacePath: "/project",
            searchPaths: ["/mise/bin"],
            fileExists: { files.union(["/project/node_modules/typescript/lib/tsserver.js"]).contains($0) },
            resolveSymlinks: resolve
        )
        #expect(withLocalTypeScript == .hash([
            "preferences": .hash(["includeInlayParameterNameHints": .string("literals")])
        ]))
        #expect(LanguageServerDiscovery.initializationOptions(
            for: .swift,
            workspacePath: "/project",
            searchPaths: ["/mise/bin"]
        ) == nil)
    }

    @Test func tsserverWrapperInNodeModulesBinFindsTheSiblingPackage() {
        let files: Set<String> = [
            "/mise/npm-typescript/node_modules/.bin/tsserver",
            "/mise/npm-typescript/node_modules/typescript/lib/tsserver.js"
        ]
        let server = LanguageServerDiscovery.installedTypeScriptServer(
            searchPaths: ["/mise/npm-typescript/node_modules/.bin"],
            fileExists: { files.contains($0) },
            resolveSymlinks: { $0 }
        )
        #expect(server == "/mise/npm-typescript/node_modules/typescript/lib/tsserver.js")
    }

    @Test func interactiveShellNoiseAroundThePathIsIgnored() {
        let output = "Last login: today\n\u{1B}]0;title\u{07}__DREAMDER_PATH__/a/bin:/b/bin__DREAMDER_END__% "
        #expect(LSPProcessEnvironment.extractMarkedPath(output) == "/a/bin:/b/bin")
        #expect(LSPProcessEnvironment.extractMarkedPath("no markers") == nil)
        #expect(LSPProcessEnvironment.extractMarkedPath("__DREAMDER_PATH____DREAMDER_END__") == nil)
    }
}
