import Foundation

nonisolated enum NewItemKind: Sendable, Equatable {
    case file
    case directory

    var noun: String {
        switch self {
        case .file: "file"
        case .directory: "directory"
        }
    }
}

nonisolated enum NewItemNameError: Error, Equatable, Sendable {
    case empty
    case invalidName(String)
    case fileExists(String)
    case directoryExists(String)
    case outsideProject

    func message(for kind: NewItemKind) -> String {
        switch self {
        case .empty:
            "Specify a \(kind.noun) name"
        case .invalidName(let name):
            "'\(name)' is an invalid \(kind.noun) name"
        case .fileExists(let name):
            "A file with the name '\(name)' already exists"
        case .directoryExists(let name):
            "A directory with the name '\(name)' already exists"
        case .outsideProject:
            "The \(kind.noun) must be created inside the project"
        }
    }
}

nonisolated struct NewItemPlan: Sendable, Equatable {
    let kind: NewItemKind
    let target: URL
    let directoriesToCreate: [URL]

    var anchor: URL {
        (directoriesToCreate.first ?? target).deletingLastPathComponent()
    }

    var containingDirectory: URL {
        target.deletingLastPathComponent()
    }
}

nonisolated struct NewItemNameValidator: Sendable {
    let rootURL: URL
    let parentURL: URL
    let kind: NewItemKind
    let homeURL: URL

    init(
        rootURL: URL,
        parentURL: URL,
        kind: NewItemKind,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.rootURL = rootURL
        self.parentURL = parentURL
        self.kind = kind
        self.homeURL = homeURL
    }

    func errorMessage(for input: String) -> String? {
        switch plan(for: input) {
        case .success:
            nil
        case .failure(let error):
            error.message(for: kind)
        }
    }

    func plan(for input: String) -> Result<NewItemPlan, NewItemNameError> {
        let tokens = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
        guard !tokens.isEmpty else { return .failure(.empty) }

        var current = parentURL
        var missing: [URL] = []
        for (index, token) in tokens.enumerated() {
            let isLast = index == tokens.count - 1
            if isLast, token == "." || token == ".." {
                return .failure(.invalidName(token))
            }
            if index == 0, token == "~" {
                current = homeURL
                continue
            }
            if token == ".." {
                if !missing.isEmpty { missing.removeLast() }
                current = current.deletingLastPathComponent()
                continue
            }
            if token == "." { continue }
            guard token.isValidFilename, !token.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .failure(.invalidName(token))
            }
            let child = current.appending(path: token)
            if missing.isEmpty {
                switch existence(of: child) {
                case .file:
                    return .failure(.fileExists(token))
                case .directory:
                    if isLast { return .failure(.directoryExists(token)) }
                case .absent:
                    if !isLast { missing.append(child) }
                }
            } else if !isLast {
                missing.append(child)
            }
            current = child
        }
        guard isInsideProject(current) else { return .failure(.outsideProject) }
        return .success(NewItemPlan(kind: kind, target: current, directoriesToCreate: missing))
    }

    private enum Existence {
        case absent
        case file
        case directory
    }

    private func existence(of url: URL) -> Existence {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .absent }
        return isDirectory.boolValue ? .directory : .file
    }

    private func isInsideProject(_ url: URL) -> Bool {
        var rootPath = rootURL.path
        while rootPath.count > 1, rootPath.hasSuffix("/") { rootPath.removeLast() }
        return url.path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }
}
