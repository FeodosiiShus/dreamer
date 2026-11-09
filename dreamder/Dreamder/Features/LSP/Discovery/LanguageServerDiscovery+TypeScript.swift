import Foundation
import LanguageServerProtocol

nonisolated extension LanguageServerDiscovery {
    static let typeScriptLanguages: Set<LSPLanguage> = [
        .typescript, .javascript, .typescriptreact, .javascriptreact
    ]

    static func resolvedInitializationOptions(
        for language: LSPLanguage,
        workspacePath: String,
        workspaceTrusted: Bool = false,
        serverExecutable: String? = nil,
        searchPaths: [String],
        inlayHints: InlayHintSettings,
        runner: any ProcessRunning = ProcessRunner(),
        environment: [String: String]? = nil
    ) async -> LSPAny? {
        guard typeScriptLanguages.contains(language) else { return nil }
        var resolvedLaunchers: [String: String] = [:]
        for directory in searchPaths {
            let launcher = (directory as NSString).appendingPathComponent("tsserver")
            guard FileManager.default.fileExists(atPath: launcher) else { continue }
            resolvedLaunchers[launcher] = await resolveLauncher(
                launcher,
                workspacePath: nil,
                runner: runner,
                environment: environment
            )
        }
        let launchers = resolvedLaunchers
        return initializationOptions(
            for: language,
            workspacePath: workspacePath,
            workspaceTrusted: workspaceTrusted,
            serverExecutable: serverExecutable,
            searchPaths: searchPaths,
            inlayHints: inlayHints,
            resolveSymlinks: { launchers[$0] ?? symlinkResolved($0) }
        )
    }

    static func initializationOptions(
        for language: LSPLanguage,
        workspacePath: String,
        workspaceTrusted: Bool = false,
        serverExecutable: String? = nil,
        searchPaths: [String],
        inlayHints: InlayHintSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        resolveSymlinks: (String) -> String = { symlinkResolved($0) }
    ) -> LSPAny? {
        guard typeScriptLanguages.contains(language) else { return nil }
        var options: [String: LSPAny] = [
            "preferences": InlayHintServerPreferences.preferences(for: inlayHints)
        ]
        let workspaceServer = (workspacePath as NSString)
            .appendingPathComponent("node_modules/typescript/lib/tsserver.js")
        let usesWorkspaceTypeScript = workspaceTrusted && fileExists(workspaceServer)
        if !usesWorkspaceTypeScript,
           let server = installedTypeScriptServer(
            searchPaths: searchPaths,
            fileExists: fileExists,
            resolveSymlinks: resolveSymlinks
           ) ?? untrustedFallbackTypeScriptServer(
            workspaceTrusted: workspaceTrusted,
            serverExecutable: serverExecutable,
            fileExists: fileExists,
            resolveSymlinks: resolveSymlinks
           ) {
            options["tsserver"] = .hash(["path": .string(server)])
        }
        return .hash(options)
    }

    static func untrustedFallbackTypeScriptServer(
        workspaceTrusted: Bool,
        serverExecutable: String?,
        fileExists: (String) -> Bool,
        resolveSymlinks: (String) -> String
    ) -> String? {
        guard !workspaceTrusted, let serverExecutable else { return nil }
        return bundledTypeScriptServer(
            forServerAt: serverExecutable,
            fileExists: fileExists,
            resolveSymlinks: resolveSymlinks
        )
    }

    static func bundledTypeScriptServer(
        forServerAt executable: String,
        fileExists: (String) -> Bool,
        resolveSymlinks: (String) -> String
    ) -> String? {
        var directory = (resolveSymlinks(executable) as NSString).deletingLastPathComponent
        while directory.count > 1 {
            if (directory as NSString).lastPathComponent == "typescript-language-server" {
                let hoisted = ((directory as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent("typescript/lib/tsserver.js")
                let nested = (directory as NSString).appendingPathComponent("node_modules/typescript/lib/tsserver.js")
                return [nested, hoisted].first(where: fileExists)
            }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return nil
    }

    static func installedTypeScriptServer(
        searchPaths: [String],
        fileExists: (String) -> Bool,
        resolveSymlinks: (String) -> String
    ) -> String? {
        for directory in searchPaths {
            let launcher = (directory as NSString).appendingPathComponent("tsserver")
            guard fileExists(launcher) else { continue }
            let packageRoot = ((resolveSymlinks(launcher) as NSString)
                .deletingLastPathComponent as NSString)
                .deletingLastPathComponent
            let candidates = [
                (packageRoot as NSString).appendingPathComponent("lib/tsserver.js"),
                ((directory as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent("typescript/lib/tsserver.js"),
                ((directory as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent("lib/node_modules/typescript/lib/tsserver.js")
            ]
            if let server = candidates.first(where: fileExists) {
                return server
            }
        }
        return nil
    }

    static func symlinkResolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    static func resolveLauncher(
        _ path: String,
        workspacePath: String?,
        runner: any ProcessRunning = ProcessRunner(),
        environment: [String: String]? = nil
    ) async -> String {
        let resolved = symlinkResolved(path)
        guard (resolved as NSString).lastPathComponent == "mise" else { return resolved }
        let processEnvironment: [String: String]
        if let environment {
            processEnvironment = environment
        } else {
            processEnvironment = await LSPProcessEnvironment.shared.resolve().environment
        }
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: resolved),
            arguments: ["which", (path as NSString).lastPathComponent],
            workingDirectory: workspacePath.map { URL(fileURLWithPath: $0) },
            environment: processEnvironment,
            timeout: .seconds(10)
        )
        guard let output = try? await runner.run(invocation), output.succeeded else { return resolved }
        let target = output.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return resolved }
        return symlinkResolved(target)
    }
}
