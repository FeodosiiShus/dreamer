import Foundation

nonisolated enum FolderSortMode: String, Sendable, CaseIterable {
    case name
    case type
}

enum ProjectNavigatorSorter {
    static func areInIncreasingOrder(
        _ lhs: CEWorkspaceFile,
        _ rhs: CEWorkspaceFile,
        mode: FolderSortMode,
        foldersOnTop: Bool
    ) -> Bool {
        if foldersOnTop, lhs.isFolder != rhs.isFolder {
            return lhs.isFolder
        }
        if mode == .type {
            let lhsType = typeKey(lhs)
            let rhsType = typeKey(rhs)
            if lhsType != rhsType {
                return lhsType < rhsType
            }
        }
        let order = lhs.name.caseInsensitiveCompare(rhs.name)
        if order != .orderedSame {
            return order == .orderedAscending
        }
        return lhs.name < rhs.name
    }

    private static func typeKey(_ file: CEWorkspaceFile) -> String {
        file.isFolder ? "" : file.url.pathExtension.lowercased()
    }
}

@MainActor
final class ProjectNavigatorSortModes {
    static let keyPrefix = "dreamder.projectNavigator.sortModes."

    private let defaults: UserDefaults
    private let rootPath: String
    private let key: String
    private(set) var modes: [String: FolderSortMode]

    init(rootURL: URL, defaults: UserDefaults = .standard) {
        var path = rootURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        self.defaults = defaults
        self.rootPath = path
        self.key = Self.keyPrefix + path
        let stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        self.modes = stored.compactMapValues { FolderSortMode(rawValue: $0) }
    }

    func mode(for folder: URL) -> FolderSortMode {
        modes[relativeKey(for: folder)] ?? .name
    }

    func set(_ mode: FolderSortMode, for folder: URL) {
        let folderKey = relativeKey(for: folder)
        if mode == .name {
            modes.removeValue(forKey: folderKey)
        } else {
            modes[folderKey] = mode
        }
        defaults.set(modes.mapValues(\.rawValue), forKey: key)
    }

    private func relativeKey(for folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        if path == rootPath { return "" }
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return path
    }
}
