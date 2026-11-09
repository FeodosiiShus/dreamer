import Foundation
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

extension LanguageServerDiscoveryTrustTests {
    private static let workspaceTypeScript = "/project/node_modules/typescript/lib/tsserver.js"
    private static let installedFiles: Set<String> = [
        "/mise/bin/tsserver",
        "/mise/node_modules/typescript/lib/tsserver.js"
    ]

    private func typeScriptOptions(
        trusted: Bool,
        files: Set<String>,
        serverExecutable: String? = nil,
        searchPaths: [String] = ["/mise/bin"]
    ) -> LSPAny? {
        LanguageServerDiscovery.initializationOptions(
            for: .typescript,
            workspacePath: "/project",
            workspaceTrusted: trusted,
            serverExecutable: serverExecutable,
            searchPaths: searchPaths,
            inlayHints: InlayHintSettings(),
            fileExists: { files.contains($0) },
            resolveSymlinks: { $0 == "/mise/bin/tsserver" ? "/mise/node_modules/typescript/bin/tsserver" : $0 }
        )
    }

    private func expectedOptions(tsserver: String?) -> LSPAny {
        var options: [String: LSPAny] = [
            "preferences": InlayHintServerPreferences.preferences(for: InlayHintSettings())
        ]
        if let tsserver {
            options["tsserver"] = .hash(["path": .string(tsserver)])
        }
        return .hash(options)
    }

    @Test
    func untrustedWorkspacesNeverLoadTheirOwnTypeScript() {
        let files = Self.installedFiles.union([Self.workspaceTypeScript])
        let untrusted = typeScriptOptions(trusted: false, files: files)
        #expect(untrusted == expectedOptions(tsserver: "/mise/node_modules/typescript/lib/tsserver.js"))
    }

    @Test
    func trustedWorkspacesKeepTheirOwnTypeScript() {
        let files = Self.installedFiles.union([Self.workspaceTypeScript])
        #expect(typeScriptOptions(trusted: true, files: files) == expectedOptions(tsserver: nil))
        #expect(
            typeScriptOptions(trusted: true, files: Self.installedFiles)
                == expectedOptions(tsserver: "/mise/node_modules/typescript/lib/tsserver.js")
        )
    }

    @Test
    func untrustedWorkspacesFallBackToTheServersBundledTypeScript() {
        let nested = "/npm/lib/node_modules/typescript-language-server/node_modules/typescript/lib/tsserver.js"
        let hoisted = "/npm/lib/node_modules/typescript/lib/tsserver.js"
        let serverPath = "/npm/bin/typescript-language-server"
        let resolving: (String) -> String = { _ in "/npm/lib/node_modules/typescript-language-server/lib/cli.mjs" }
        func options(_ files: Set<String>, trusted: Bool = false, executable: String? = serverPath) -> LSPAny? {
            LanguageServerDiscovery.initializationOptions(
                for: .typescript,
                workspacePath: "/project",
                workspaceTrusted: trusted,
                serverExecutable: executable,
                searchPaths: [],
                inlayHints: InlayHintSettings(),
                fileExists: { files.contains($0) || $0 == Self.workspaceTypeScript },
                resolveSymlinks: resolving
            )
        }

        #expect(options([nested, hoisted]) == expectedOptions(tsserver: nested))
        #expect(options([hoisted]) == expectedOptions(tsserver: hoisted))
        #expect(options([]) == expectedOptions(tsserver: nil))
        #expect(options([nested], executable: nil) == expectedOptions(tsserver: nil))
        #expect(options([nested], trusted: true) == expectedOptions(tsserver: nil))
    }

    @Test
    func theBundledLookupNeedsAServerInstalledAsTypeScriptLanguageServer() {
        let files: Set<String> = ["/other/node_modules/typescript/lib/tsserver.js", "/typescript/lib/tsserver.js"]
        #expect(LanguageServerDiscovery.bundledTypeScriptServer(
            forServerAt: "/other/bin/vtsls",
            fileExists: { files.contains($0) },
            resolveSymlinks: { $0 }
        ) == nil)
        #expect(LanguageServerDiscovery.bundledTypeScriptServer(
            forServerAt: "/typescript-language-server",
            fileExists: { files.contains($0) },
            resolveSymlinks: { $0 }
        ) == nil)
    }

    @Test
    func resolvedOptionsForAnUntrustedWorkspaceUseTheBundledServerOnDisk() async throws {
        try await withTempDir { directory in
            let package = directory.appending(path: "lib/node_modules/typescript-language-server")
            let executable = package.appending(path: "lib/cli.mjs")
            let bundled = package.appending(path: "node_modules/typescript/lib/tsserver.js")
            let workspace = directory.appending(path: "project")
            try makeScript(at: executable)
            try makeScript(at: bundled)
            try makeScript(at: workspace.appending(path: "node_modules/typescript/lib/tsserver.js"))
            let expected = LanguageServerDiscovery.symlinkResolved(bundled.path(percentEncoded: false))
            let workspacePath = workspace.path(percentEncoded: false)

            let untrusted = await LanguageServerDiscovery.resolvedInitializationOptions(
                for: .typescript,
                workspacePath: workspacePath,
                serverExecutable: executable.path(percentEncoded: false),
                searchPaths: [],
                inlayHints: InlayHintSettings()
            )
            let trusted = await LanguageServerDiscovery.resolvedInitializationOptions(
                for: .typescript,
                workspacePath: workspacePath,
                workspaceTrusted: true,
                serverExecutable: executable.path(percentEncoded: false),
                searchPaths: [],
                inlayHints: InlayHintSettings()
            )

            #expect(untrusted == expectedOptions(tsserver: expected))
            #expect(trusted == expectedOptions(tsserver: nil))
        }
    }
}
