import Foundation

nonisolated enum UntrustedWorkspaceServerPolicy {
    static let permittedServers: [LSPLanguage: Set<String>] = [
        .typescript: ["typescript-language-server"]
    ]

    static func permitsServer(for language: LSPLanguage, executable path: String, workspaceTrusted: Bool) -> Bool {
        workspaceTrusted || permittedServers[language.serverFamily]?.contains(executableName(path)) == true
    }

    static func failureMessage(forExecutable path: String) -> String {
        "Safe Mode: the \(executableName(path)) language server was not started. Trust the project to use it."
    }

    private static func executableName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

nonisolated struct UntrustedWorkspaceServerError: Error, Equatable {
    let language: LSPLanguage
}
