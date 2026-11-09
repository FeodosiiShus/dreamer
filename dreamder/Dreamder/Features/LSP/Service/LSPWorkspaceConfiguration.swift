import Foundation
import LanguageServerProtocol

nonisolated struct LSPWorkspaceConfiguration: Sendable, Equatable {
    var settings: [String: LSPAny]

    init(settings: [String: LSPAny] = [:]) {
        self.settings = settings
    }

    func value(for item: ConfigurationItem) -> LSPAny? {
        guard let section = item.section, !section.isEmpty else {
            return settings.isEmpty ? nil : .hash(settings)
        }
        let path = section.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        return Self.lookup(ArraySlice(path), in: settings)
    }

    private static func lookup(_ path: ArraySlice<String>, in settings: [String: LSPAny]) -> LSPAny? {
        for length in stride(from: path.count, through: 1, by: -1) {
            let key = path.prefix(length).joined(separator: ".")
            guard let value = settings[key] else { continue }
            if length == path.count {
                return value
            }
            if case .hash(let nested) = value, let resolved = lookup(path.dropFirst(length), in: nested) {
                return resolved
            }
        }
        return nil
    }
}

nonisolated enum LSPWorkspaceFolders {
    static func uri(forWorkspacePath path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: false).absoluteString
    }

    static func folder(forWorkspacePath path: String) -> WorkspaceFolder {
        WorkspaceFolder(
            uri: uri(forWorkspacePath: path),
            name: URL(fileURLWithPath: path).lastPathComponent
        )
    }
}
