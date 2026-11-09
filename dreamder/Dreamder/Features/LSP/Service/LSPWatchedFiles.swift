import Foundation
import LanguageServerProtocol

nonisolated enum LSPGlob {
    static func regexPattern(for glob: String) -> String {
        var result = "^"
        let characters = Array(glob)
        var index = 0
        var braceDepth = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    index += 2
                    if index < characters.count, characters[index] == "/" {
                        result += "(?:.*/)?"
                        index += 1
                    } else {
                        result += ".*"
                    }
                    continue
                }
                result += "[^/]*"
            case "?":
                result += "[^/]"
            case "{":
                braceDepth += 1
                result += "(?:"
            case "}":
                if braceDepth > 0 {
                    braceDepth -= 1
                    result += ")"
                } else {
                    result += "\\}"
                }
            case ",":
                result += braceDepth > 0 ? "|" : ","
            case "[":
                if let close = characters[(index + 1)...].firstIndex(of: "]"), close > index + 1 {
                    var body = String(characters[(index + 1)..<close])
                    if body.hasPrefix("!") {
                        body = "^" + body.dropFirst()
                    }
                    result += "[" + body.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                    index = close
                } else {
                    result += "\\["
                }
            case "/":
                result += "/"
            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        return result + "$"
    }

    static func matches(_ glob: String, path: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: regexPattern(for: glob)) else { return false }
        let range = NSRange(path.startIndex..., in: path)
        return expression.firstMatch(in: path, range: range) != nil
    }
}

nonisolated struct LSPFileChange: Equatable, Sendable {
    let path: String
    let type: FileChangeType
}

nonisolated struct LSPFileStamp: Equatable, Sendable {
    let modified: TimeInterval
    let isDirectory: Bool
}

nonisolated struct LSPFileChangeTracker: Sendable {
    private var listings: [String: [String: LSPFileStamp]] = [:]

    var trackedDirectories: Set<String> {
        Set(listings.keys)
    }

    mutating func seed(_ directory: String, children: [String: LSPFileStamp]) {
        listings[directory] = children
    }

    mutating func update(_ directory: String, children: [String: LSPFileStamp]) -> [LSPFileChange] {
        guard let previous = listings[directory] else {
            listings[directory] = children
            return []
        }
        listings[directory] = children
        var changes: [LSPFileChange] = []
        for (path, stamp) in children.sorted(by: { $0.key < $1.key }) {
            guard let old = previous[path] else {
                changes.append(LSPFileChange(path: path, type: .created))
                continue
            }
            if old != stamp, !stamp.isDirectory {
                changes.append(LSPFileChange(path: path, type: .changed))
            }
        }
        for path in previous.keys.sorted() where children[path] == nil {
            changes.append(LSPFileChange(path: path, type: .deleted))
            forget(path)
        }
        return changes
    }

    mutating func modify(_ path: String, stamp: LSPFileStamp) -> LSPFileChange? {
        let directory = (path as NSString).deletingLastPathComponent
        guard let previous = listings[directory]?[path],
              stamp.modified != 0,
              !stamp.isDirectory,
              previous != stamp else {
            return nil
        }
        listings[directory]?[path] = stamp
        return LSPFileChange(path: path, type: .changed)
    }

    private mutating func forget(_ path: String) {
        let prefix = path + "/"
        for directory in listings.keys where directory == path || directory.hasPrefix(prefix) {
            listings.removeValue(forKey: directory)
        }
    }

    @concurrent
    static func stamps(of paths: [String]) async -> [String: LSPFileStamp] {
        var result: [String: LSPFileStamp] = [:]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        for path in paths {
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys)
            result[path] = LSPFileStamp(
                modified: values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0,
                isDirectory: values?.isDirectory ?? false
            )
        }
        return result
    }
}

nonisolated enum LSPWatchedFilesFilter {
    static func events(
        for changes: [LSPFileChange],
        watchers: [FileSystemWatcher],
        workspacePath: String
    ) -> [FileEvent] {
        guard !watchers.isEmpty else { return [] }
        let rootPrefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        return changes.compactMap { change in
            let relative = change.path.hasPrefix(rootPrefix) ? String(change.path.dropFirst(rootPrefix.count)) : nil
            let watched = watchers.contains { watcher in
                guard (watcher.kind ?? .all).contains(watchKind(for: change.type)) else { return false }
                return LSPGlob.matches(watcher.globPattern, path: change.path)
                    || relative.map { LSPGlob.matches(watcher.globPattern, path: $0) } ?? false
            }
            guard watched else { return nil }
            return FileEvent(uri: URL(fileURLWithPath: change.path).absoluteString, type: change.type)
        }
    }

    static func watchKind(for type: FileChangeType) -> WatchKind {
        switch type {
        case .created:
            return .create
        case .changed:
            return .change
        case .deleted:
            return .delete
        }
    }
}

@MainActor
final class LSPWatchedFilesForwarder: CEWorkspaceFileManagerObserver {
    typealias StampProvider = @Sendable ([String]) async -> [String: LSPFileStamp]

    private weak var fileManager: CEWorkspaceFileManager?
    private let workspacePath: String
    private let watchers: () -> [FileSystemWatcher]
    private let send: (DidChangeWatchedFilesParams) async -> Void
    private let stamps: StampProvider
    private var tracker = LSPFileChangeTracker()
    private var chain: Task<Void, Never>?

    init(
        fileManager: CEWorkspaceFileManager,
        workspacePath: String,
        watchers: @escaping () -> [FileSystemWatcher],
        send: @escaping (DidChangeWatchedFilesParams) async -> Void,
        stamps: @escaping StampProvider = { await LSPFileChangeTracker.stamps(of: $0) }
    ) {
        self.fileManager = fileManager
        self.workspacePath = workspacePath
        self.watchers = watchers
        self.send = send
        self.stamps = stamps
    }

    func start() {
        guard let fileManager else { return }
        let snapshot = fileManager.childrenMap
        fileManager.addObserver(self)
        enqueue { forwarder in
            for (directory, children) in snapshot {
                let listing = await forwarder.stamps(children)
                forwarder.tracker.seed(directory, children: listing)
            }
        }
    }

    func stop() {
        fileManager?.removeObserver(self)
        chain?.cancel()
        chain = nil
    }

    func settle() async {
        await chain?.value
    }

    func fileManagerModifiedFiles(_ urls: Set<URL>) {
        let paths = urls.map(\.path).sorted()
        guard !paths.isEmpty else { return }
        enqueue { forwarder in
            let listing = await forwarder.stamps(paths)
            let changes = paths.compactMap { path in
                listing[path].flatMap { forwarder.tracker.modify(path, stamp: $0) }
            }
            await forwarder.forward(changes)
        }
    }

    private func forward(_ changes: [LSPFileChange]) async {
        let events = LSPWatchedFilesFilter.events(
            for: changes,
            watchers: watchers(),
            workspacePath: workspacePath
        )
        guard !events.isEmpty else { return }
        await send(DidChangeWatchedFilesParams(changes: events))
    }

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        guard let fileManager else { return }
        let directories = updatedItems.compactMap { item -> (String, [String])? in
            fileManager.childrenMap[item.id].map { (item.id, $0) }
        }.sorted { $0.0 < $1.0 }
        guard !directories.isEmpty else { return }
        enqueue { forwarder in
            var changes: [LSPFileChange] = []
            for (directory, children) in directories {
                let listing = await forwarder.stamps(children)
                changes.append(contentsOf: forwarder.tracker.update(directory, children: listing))
            }
            await forwarder.forward(changes)
        }
    }

    private func enqueue(_ operation: @escaping @MainActor (LSPWatchedFilesForwarder) async -> Void) {
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await operation(self)
        }
    }
}
