import Foundation
import LanguageServerProtocol

nonisolated struct LanguageServerCandidate: Equatable {
    let executable: String
    let arguments: [String]

    init(_ executable: String, _ arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }
}

nonisolated enum LanguageServerDiscovery {
    static func candidates(for language: LSPLanguage) -> [LanguageServerCandidate] {
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
        case .java:
            return [LanguageServerCandidate("jdtls")]
        case .kotlin:
            return [LanguageServerCandidate("kotlin-language-server")]
        case .yaml:
            return [LanguageServerCandidate("yaml-language-server", ["--stdio"])]
        case .toml:
            return [LanguageServerCandidate("taplo", ["lsp", "stdio"])]
        case .shellscript:
            return [LanguageServerCandidate("bash-language-server", ["start"])]
        default:
            return []
        }
    }

    static var allCandidates: [LanguageServerCandidate] {
        var seen = Set<String>()
        var result: [LanguageServerCandidate] = []
        for language in LSPLanguage.known {
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
        for language: LSPLanguage,
        searchPaths: [String],
        environment: [String: String]?,
        isExecutable: (String) -> Bool,
        sourceKitFallback: String? = nil
    ) -> LanguageServerBinary? {
        for candidate in candidates(for: language) {
            var execPath = resolve(candidate, in: searchPaths, isExecutable: isExecutable)
            if execPath == nil, candidate.executable == "sourcekit-lsp" {
                execPath = sourceKitFallback
            }
            if let execPath {
                return LanguageServerBinary(execPath: execPath, args: candidate.arguments, env: environment)
            }
        }
        return nil
    }

    static let workspaceBinDirectories = ["node_modules/.bin", ".venv/bin", "venv/bin"]
    static let registryPackageBinDirectories = ["bin", "node_modules/.bin", "venv/bin"]

    static let untrustedNotice = UntrustedWorkspaceServerNotice()

    static func workspaceSearchPaths(workspacePath: String?) -> [String] {
        guard let workspacePath, !workspacePath.isEmpty else { return [] }
        return workspaceBinDirectories.map { (workspacePath as NSString).appendingPathComponent($0) }
    }

    static func isInsideWorkspace(
        _ path: String,
        workspacePath: String,
        resolveSymlinks: (String) -> String
    ) -> Bool {
        let root = resolveSymlinks(workspacePath)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return resolveSymlinks(path).hasPrefix(prefix)
    }

    static func confinedToWorkspace(
        workspacePath: String?,
        isExecutable: @escaping (String) -> Bool,
        resolveSymlinks: @escaping (String) -> String = { symlinkResolved($0) }
    ) -> (String) -> Bool {
        let directories = Set(workspaceSearchPaths(workspacePath: workspacePath))
        return { path in
            guard isExecutable(path) else { return false }
            guard let workspacePath, directories.contains((path as NSString).deletingLastPathComponent) else {
                return true
            }
            return isInsideWorkspace(path, workspacePath: workspacePath, resolveSymlinks: resolveSymlinks)
        }
    }

    static func blockedWorkspaceServer(
        for language: LSPLanguage,
        workspacePath: String?,
        searchPaths: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        let workspaceDirectories = workspaceSearchPaths(workspacePath: workspacePath)
        guard !workspaceDirectories.isEmpty else { return nil }
        for candidate in candidates(for: language) {
            if let path = resolve(candidate, in: workspaceDirectories, isExecutable: isExecutable) {
                return path
            }
            if resolve(candidate, in: searchPaths, isExecutable: isExecutable) != nil {
                return nil
            }
        }
        return nil
    }

    static func localSearchPaths(
        workspacePath: String?,
        workspaceTrusted: Bool,
        registryInstallPath: String?,
        disabledRegistryPackages: Set<String> = [],
        listDirectory: (String) -> [String]
    ) -> [String] {
        var directories: [String] = []
        if workspaceTrusted {
            directories.append(contentsOf: workspaceSearchPaths(workspacePath: workspacePath))
        }
        if let registryInstallPath, !registryInstallPath.isEmpty {
            directories.append(registryInstallPath)
            let packages = listDirectory(registryInstallPath).sorted()
            for package in packages where !disabledRegistryPackages.contains(package) {
                let packagePath = (registryInstallPath as NSString).appendingPathComponent(package)
                directories.append(contentsOf: registryPackageBinDirectories.map {
                    (packagePath as NSString).appendingPathComponent($0)
                })
            }
        }
        return directories
    }

    static func mergedSearchPaths(local: [String], base: [String]) -> [String] {
        var seen = Set<String>()
        return (local + base).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func directoryContents(atPath path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    @concurrent
    static func binary(
        for language: LSPLanguage,
        workspacePath: String?,
        workspaceTrusted: Bool,
        registryInstallPath: String?,
        disabledRegistryPackages: Set<String> = [],
        notice: UntrustedWorkspaceServerNotice = untrustedNotice
    ) async -> LanguageServerBinary? {
        let serverCandidates = candidates(for: language)
        guard !serverCandidates.isEmpty else { return nil }
        let environment = LSPProcessEnvironment.shared
        let resolved = await environment.resolve()
        var sourceKit: String?
        if serverCandidates.contains(where: { $0.executable == "sourcekit-lsp" }) {
            sourceKit = await environment.xcrunFind("sourcekit-lsp")
        }
        let searchPaths = mergedSearchPaths(
            local: localSearchPaths(
                workspacePath: workspacePath,
                workspaceTrusted: workspaceTrusted,
                registryInstallPath: registryInstallPath,
                disabledRegistryPackages: disabledRegistryPackages,
                listDirectory: { directoryContents(atPath: $0) }
            ),
            base: resolved.searchPaths
        )
        var processEnvironment = resolved.environment
        processEnvironment["PATH"] = searchPaths.joined(separator: ":")
        let isExecutable = confinedToWorkspace(
            workspacePath: workspacePath,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
        if !workspaceTrusted,
           let workspacePath,
           let blocked = blockedWorkspaceServer(
            for: language,
            workspacePath: workspacePath,
            searchPaths: searchPaths,
            isExecutable: isExecutable
           ) {
            notice.note(workspacePath: workspacePath, executable: blocked)
        }
        return binary(
            for: language,
            searchPaths: searchPaths,
            environment: processEnvironment,
            isExecutable: isExecutable,
            sourceKitFallback: sourceKit
        )
    }
}
