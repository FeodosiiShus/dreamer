import Foundation
import LanguageServerProtocol

struct LanguageServerCandidate: Equatable {
    let executable: String
    let arguments: [String]

    init(_ executable: String, _ arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }
}

enum LanguageServerDiscovery {
    static func candidates(for language: LanguageIdentifier) -> [LanguageServerCandidate] {
        switch language {
        case .swift, .objc:
            return [LanguageServerCandidate("sourcekit-lsp")]
        case .c, .cpp, .objcpp:
            return [LanguageServerCandidate("clangd"), LanguageServerCandidate("sourcekit-lsp")]
        case .typescript, .javascript, .typescriptreact, .javascriptreact:
            return [
                LanguageServerCandidate("typescript-language-server", ["--stdio"]),
                LanguageServerCandidate("vtsls", ["--stdio"])
            ]
        case .python:
            return [
                LanguageServerCandidate("basedpyright-langserver", ["--stdio"]),
                LanguageServerCandidate("pyright-langserver", ["--stdio"]),
                LanguageServerCandidate("pylsp")
            ]
        case .go:
            return [LanguageServerCandidate("gopls")]
        case .rust:
            return [LanguageServerCandidate("rust-analyzer")]
        case .json:
            return [LanguageServerCandidate("vscode-json-language-server", ["--stdio"])]
        case .css, .scss, .less:
            return [LanguageServerCandidate("vscode-css-language-server", ["--stdio"])]
        case .html:
            return [LanguageServerCandidate("vscode-html-language-server", ["--stdio"])]
        default:
            return []
        }
    }

    static var allCandidates: [LanguageServerCandidate] {
        var seen = Set<String>()
        var result: [LanguageServerCandidate] = []
        for language in LanguageIdentifier.allCases {
            for candidate in candidates(for: language) where seen.insert(candidate.executable).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    static func arguments(forExecutablePath path: String) -> [String] {
        let name = (path as NSString).lastPathComponent
        return allCandidates.first { $0.executable == name }?.arguments ?? []
    }

    static func resolve(
        _ candidate: LanguageServerCandidate,
        in searchPaths: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        for directory in searchPaths {
            let path = (directory as NSString).appendingPathComponent(candidate.executable)
            if isExecutable(path) {
                return path
            }
        }
        return nil
    }

    static func binary(
        for language: LanguageIdentifier,
        searchPaths: [String],
        environment: [String: String]?,
        isExecutable: (String) -> Bool,
        xcrunFind: (String) -> String? = { _ in nil }
    ) -> LanguageServerBinary? {
        for candidate in candidates(for: language) {
            var execPath = resolve(candidate, in: searchPaths, isExecutable: isExecutable)
            if execPath == nil, candidate.executable == "sourcekit-lsp" {
                execPath = xcrunFind(candidate.executable)
            }
            if let execPath {
                return LanguageServerBinary(execPath: execPath, args: candidate.arguments, env: environment)
            }
        }
        return nil
    }

    static func binary(for language: LanguageIdentifier) async -> LanguageServerBinary? {
        guard !candidates(for: language).isEmpty else { return nil }
        let environment = LSPProcessEnvironment.shared
        return await withCheckedContinuation { (continuation: CheckedContinuation<LanguageServerBinary?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: LanguageServerDiscovery.binary(
                    for: language,
                    searchPaths: environment.searchPaths,
                    environment: environment.environment,
                    isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                    xcrunFind: environment.xcrunFind
                ))
            }
        }
    }

    static let typeScriptLanguages: Set<LanguageIdentifier> = [
        .typescript, .javascript, .typescriptreact, .javascriptreact
    ]

    static func initializationOptions(
        for language: LanguageIdentifier,
        workspacePath: String,
        searchPaths: [String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        resolveSymlinks: (String) -> String = { resolveLauncher($0, workspacePath: nil) }
    ) -> LSPAny? {
        guard typeScriptLanguages.contains(language) else { return nil }
        var options: [String: LSPAny] = [
            "preferences": .hash(["includeInlayParameterNameHints": .string("literals")])
        ]
        let workspaceServer = (workspacePath as NSString).appendingPathComponent("node_modules/typescript/lib/tsserver.js")
        if !fileExists(workspaceServer),
           let server = installedTypeScriptServer(
            searchPaths: searchPaths,
            fileExists: fileExists,
            resolveSymlinks: resolveSymlinks
           ) {
            options["tsserver"] = .hash(["path": .string(server)])
        }
        return .hash(options)
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

    static func resolveLauncher(_ path: String, workspacePath: String?) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard (resolved as NSString).lastPathComponent == "mise" else { return resolved }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = ["which", (path as NSString).lastPathComponent]
        if let workspacePath {
            process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        }
        process.environment = LSPProcessEnvironment.shared.environment
        let pipe = Pipe.closingOnExec()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return resolved }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let target = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !target.isEmpty else { return resolved }
        return URL(fileURLWithPath: target).resolvingSymlinksInPath().path
    }
}
