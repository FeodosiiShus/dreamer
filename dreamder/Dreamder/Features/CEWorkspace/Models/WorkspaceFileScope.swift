import Foundation
import Synchronization

nonisolated struct WorkspaceFileSignature: Sendable, Equatable {
    let modified: Date?
    let size: Int
}

nonisolated struct WorkspaceFileEntry: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case file
        case directory
        case other
    }

    let url: URL
    let name: String
    let kind: Kind
    let signature: WorkspaceFileSignature
}

nonisolated protocol WorkspaceFileSystem: Sendable {
    func entries(in directory: URL) -> [WorkspaceFileEntry]
    func entry(at url: URL) -> WorkspaceFileEntry?
}

nonisolated struct DiskWorkspaceFileSystem: WorkspaceFileSystem {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .contentModificationDateKey,
        .fileSizeKey
    ]

    func entries(in directory: URL) -> [WorkspaceFileEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Self.keys,
            options: []
        ) else {
            return []
        }
        return urls.compactMap { url in
            Self.entry(for: url, reportedAs: directory.appending(path: url.lastPathComponent))
        }
    }

    func entry(at url: URL) -> WorkspaceFileEntry? {
        let reported = URL(fileURLWithPath: url.path(percentEncoded: false))
        return Self.entry(for: reported, reportedAs: reported)
    }

    private static func entry(for url: URL, reportedAs reportedURL: URL) -> WorkspaceFileEntry? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let kind: WorkspaceFileEntry.Kind
        if values.isSymbolicLink == true || values.isPackage == true {
            kind = .other
        } else if values.isDirectory == true {
            kind = .directory
        } else if values.isRegularFile == true {
            kind = .file
        } else {
            kind = .other
        }
        return WorkspaceFileEntry(
            url: reportedURL,
            name: reportedURL.lastPathComponent,
            kind: kind,
            signature: WorkspaceFileSignature(modified: values.contentModificationDate, size: values.fileSize ?? 0)
        )
    }
}

nonisolated enum WorkspaceFileChange: Sendable, Equatable {
    case reset
    case delta(updated: [URL], removed: [URL])
}

nonisolated struct WorkspaceRemovedPaths: Sendable {
    private let keys: Set<String>

    init(_ urls: [URL]) {
        keys = Set(urls.map(\.workspacePathKey))
    }

    func covers(_ url: URL) -> Bool {
        covers(key: url.workspacePathKey)
    }

    func covers(key: String) -> Bool {
        var current = Substring(key)
        while !keys.contains(String(current)) {
            guard let slash = current.lastIndex(of: "/") else { return false }
            current = current[..<slash]
        }
        return true
    }
}

nonisolated final class WorkspaceFileScope: Sendable {
    static let maxIndexableTextSize = 4_000_000
    static let excludedFileNames: Set<String> = [".DS_Store"]
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "ico", "icns", "bmp", "tif", "tiff", "webp", "heic", "psd", "sketch",
        "pdf", "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "jar", "war", "aar", "apk", "ipa", "dmg", "pkg",
        "class", "o", "obj", "a", "lib", "dylib", "so", "dll", "exe", "bin", "dSYM", "pyc", "wasm",
        "mp3", "mp4", "m4a", "mov", "avi", "mkv", "wav", "flac", "ogg", "webm",
        "woff", "woff2", "ttf", "otf", "eot", "xcuserstate", "sqlite", "db", "car", "nib"
    ]

    private static let eventBatchLimit = 2000
    private static let sniffLength = 8192
    private static let maxScanAttempts = 3
    private typealias Subscriber = AsyncStream<WorkspaceFileChange>.Continuation

    private enum FullList {
        case ready([URL])
        case running(Task<[URL], Never>)
    }

    private struct Filter: Sendable {
        let rules: ExclusionRules
        let globs: GitignoreRuleSet
    }

    private struct State {
        var globs: GitignoreRuleSet = .empty
        var files: [URL]?
        var paths: Set<String> = []
        var generation = 0
        var inFlight: Task<[URL], Never>?
        var subscribers: [UUID: Subscriber] = [:]
        var signatures: [String: WorkspaceFileSignature] = [:]

        mutating func store(_ list: [URL]) {
            files = list
            paths = Set(list.map(\.workspacePathKey))
        }

        mutating func apply(updated: [URL], removed: [URL]) {
            if !removed.isEmpty {
                let removedPaths = WorkspaceRemovedPaths(removed)
                files?.removeAll { removedPaths.covers($0) }
                paths = Set((files ?? []).map(\.workspacePathKey))
                signatures = signatures.filter { !removedPaths.covers(key: $0.key) }
            }
            for url in updated where paths.insert(url.workspacePathKey).inserted {
                files?.append(url)
            }
        }
    }

    let rootURL: URL
    private let rootPath: String
    private let rootPrefixes: [String]
    private let fileSystem: any WorkspaceFileSystem
    private let exclusionRules: @Sendable () -> ExclusionRules
    private let gitignore: GitignoreMatcher
    private let state = Mutex<State>(State())
    private let watcher = Mutex<DirectoryEventStream?>(nil)

    init(
        rootURL: URL,
        fileSystem: any WorkspaceFileSystem = DiskWorkspaceFileSystem(),
        exclusionRules: (@Sendable () -> ExclusionRules)? = nil
    ) {
        self.rootURL = rootURL
        var path = rootURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        self.rootPath = path
        var prefixes: [String] = [path]
        for candidate in [
            rootURL.standardizedFileURL.path(percentEncoded: false),
            rootURL.resolvingSymlinksInPath().path(percentEncoded: false)
        ] where !prefixes.contains(candidate) {
            prefixes.append(candidate)
        }
        for candidate in prefixes where !candidate.hasPrefix("/private/") {
            prefixes.append("/private" + candidate)
        }
        self.rootPrefixes = prefixes
        self.fileSystem = fileSystem
        self.exclusionRules = exclusionRules ?? { ExcludedDirectories.rules(covering: rootURL) }
        self.gitignore = GitignoreMatcher(rootURL: rootURL)
    }

    func setIgnoreGlobs(_ globs: [String]) {
        let rules = GitignoreRuleSet(lines: globs)
        let changed = state.withLock { state -> Bool in
            guard state.globs != rules else { return false }
            state.globs = rules
            return true
        }
        if changed { invalidate() }
    }

    func reload() {
        gitignore.reset()
        invalidate()
    }

    func startWatching() {
        let rootPath = rootPath
        watcher.withLock { stream in
            guard stream == nil else { return }
            stream = DirectoryEventStream(directory: rootPath) { [weak self] events in
                self?.handle(events: events)
            }
        }
    }

    func stopWatching() {
        watcher.withLock { stream in
            stream?.cancel()
            stream = nil
        }
    }

    func cleanUp() {
        stopWatching()
        let (task, subscribers) = state.withLock { state -> (Task<[URL], Never>?, [Subscriber]) in
            let task = state.inFlight
            let subscribers = Array(state.subscribers.values)
            state.inFlight = nil
            state.subscribers = [:]
            state.files = nil
            state.paths = []
            state.signatures = [:]
            return (task, subscribers)
        }
        task?.cancel()
        subscribers.forEach { $0.finish() }
    }

    func changes() -> AsyncStream<WorkspaceFileChange> {
        let id = UUID()
        return AsyncStream { continuation in
            state.withLock { $0.subscribers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
            }
        }
    }

    func cachedFiles() -> [URL]? {
        state.withLock { $0.files }
    }

    @concurrent
    func enumerateFiles(limit: Int? = nil) async -> [URL] {
        guard let limit else {
            switch fullList() {
            case .ready(let files): return files
            case .running(let task): return await task.value
            }
        }
        if let cached = cachedFiles() { return Array(cached.prefix(limit)) }
        return scan(from: rootURL, limit: limit)
    }

    @concurrent
    func applyModifiedFiles(_ urls: Set<URL>) async {
        handleModified(urls)
    }

    @concurrent
    func refreshDirectories(_ directories: [URL]) async {
        for directory in directories {
            refreshDirectory(directory)
        }
    }

    func isExcluded(_ url: URL, isDirectory: Bool? = nil) -> Bool {
        isExcluded(url, isDirectory: isDirectory, filter: currentFilter())
    }

    func relativePath(of url: URL) -> String? {
        gitignore.relativePath(of: url)
    }

    func isIndexableText(_ url: URL) -> Bool {
        if Self.binaryExtensions.contains(url.pathExtension.lowercased()) { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size <= UInt64(Self.maxIndexableTextSize),
              (try? handle.seek(toOffset: 0)) != nil else {
            return false
        }
        let head = (try? handle.read(upToCount: Self.sniffLength)) ?? Data()
        return !head.contains(0)
    }

    func handle(events: [DirectoryEventStream.Event]) {
        var observed: [String: (url: URL, types: Set<FSEvent>)] = [:]
        for event in events {
            switch event.eventType {
            case .rootChanged:
                reload()
                return
            case .changeInDirectory, .itemChangedOwner:
                continue
            case .itemCreated, .itemCloned, .itemModified, .itemRemoved, .itemRenamed:
                break
            }
            guard let url = relocated(event.path),
                  let relative = gitignore.relativePath(of: url), !relative.isEmpty else { continue }
            let components = relative.split(separator: "/")
            if relative == ".git/info/exclude" || components.last == ".gitignore" {
                reload()
                return
            }
            if components.first == ".git" { continue }
            observed[relative, default: (url, [])].types.insert(event.eventType)
        }
        guard !observed.isEmpty else { return }
        guard observed.count <= Self.eventBatchLimit else {
            invalidate()
            return
        }

        let filter = currentFilter()
        var updated: [URL] = []
        var signatures: [String: WorkspaceFileSignature] = [:]
        var removed: [URL] = []
        var directories: [URL] = []
        for relative in observed.keys.sorted() {
            guard let (url, types) = observed[relative] else { continue }
            guard let entry = fileSystem.entry(at: url) else {
                removed.append(url)
                continue
            }
            switch entry.kind {
            case .file:
                if isExcluded(url, isDirectory: false, filter: filter) {
                    removed.append(url)
                } else {
                    updated.append(url)
                    signatures[url.workspacePathKey] = entry.signature
                }
            case .directory:
                let isNew = !types.isDisjoint(with: [.itemCreated, .itemRenamed, .itemCloned])
                if isNew, !isExcluded(url, isDirectory: true, filter: filter) {
                    directories.append(url)
                }
            case .other:
                removed.append(url)
            }
        }
        for directory in directories {
            updated.append(contentsOf: scan(from: directory, limit: nil))
        }
        commit(updated: updated, removed: removed, signatures: signatures)
    }

    func handleModified(_ urls: Set<URL>) {
        let filter = currentFilter()
        var updated: [URL] = []
        var signatures: [String: WorkspaceFileSignature] = [:]
        for candidate in urls.sorted(by: { $0.path < $1.path }) {
            guard let relative = gitignore.relativePath(of: candidate), !relative.isEmpty,
                  relative.split(separator: "/").first != ".git" else { continue }
            let url = rootURL.appending(path: relative)
            guard let entry = fileSystem.entry(at: url), entry.kind == .file,
                  !isExcluded(url, isDirectory: false, filter: filter) else { continue }
            updated.append(url)
            signatures[url.workspacePathKey] = entry.signature
        }
        commit(updated: updated, removed: [], signatures: signatures)
    }

    private func refreshDirectory(_ directory: URL) {
        guard let relative = gitignore.relativePath(of: directory) else { return }
        let filter = currentFilter()
        let directoryURL = relative.isEmpty ? rootURL : rootURL.appending(path: relative, directoryHint: .isDirectory)
        if !relative.isEmpty, isExcluded(directoryURL, isDirectory: true, filter: filter) { return }

        let directoryChain = chain(forDirectory: relative)
        var fileNames: Set<String> = []
        var directoryNames: Set<String> = []
        var files: [URL] = []
        var directories: [WorkspaceFileEntry] = []
        for entry in fileSystem.entries(in: directoryURL) {
            let childRelative = relative.isEmpty ? entry.name : relative + "/" + entry.name
            switch entry.kind {
            case .file:
                guard !isExcluded(
                    relative: childRelative, name: entry.name, isDirectory: false, filter: filter, chain: directoryChain
                ) else { continue }
                fileNames.insert(entry.name)
                files.append(entry.url)
            case .directory:
                guard !isExcluded(
                    relative: childRelative, name: entry.name, isDirectory: true, filter: filter, chain: directoryChain
                ) else { continue }
                directoryNames.insert(entry.name)
                directories.append(entry)
            case .other:
                continue
            }
        }

        let snapshot = state.withLock { state -> (files: [URL], paths: Set<String>)? in
            guard let files = state.files else {
                state.generation += 1
                return nil
            }
            return (files, state.paths)
        }
        guard let snapshot else { return }

        let prefix = directoryURL.workspacePathKey + "/"
        var removed: [URL] = []
        var removedDirectories: Set<String> = []
        var knownDirectories: Set<String> = []
        for url in snapshot.files {
            let path = url.workspacePathKey
            guard path.hasPrefix(prefix) else { continue }
            let remainder = path.dropFirst(prefix.count)
            if let slash = remainder.firstIndex(of: "/") {
                let first = String(remainder[..<slash])
                if directoryNames.contains(first) {
                    knownDirectories.insert(first)
                } else if removedDirectories.insert(first).inserted {
                    removed.append(directoryURL.appending(path: first, directoryHint: .isDirectory))
                }
            } else if !fileNames.contains(String(remainder)) {
                removed.append(url)
            }
        }

        var updated = files.filter { !snapshot.paths.contains($0.workspacePathKey) }
        for entry in directories where !knownDirectories.contains(entry.name) {
            updated.append(contentsOf: scan(from: entry.url, limit: nil))
        }
        commit(updated: updated, removed: removed)
    }

    private func commit(updated: [URL], removed: [URL], signatures: [String: WorkspaceFileSignature] = [:]) {
        guard !updated.isEmpty || !removed.isEmpty else { return }
        let outcome = state.withLock { state -> (subscribers: [Subscriber], fresh: [URL])? in
            guard state.files != nil else {
                state.generation += 1
                return nil
            }
            state.apply(updated: updated, removed: removed)
            var fresh: [URL] = []
            for url in updated {
                let key = url.workspacePathKey
                if let signature = signatures[key] {
                    guard state.signatures[key] != signature else { continue }
                    state.signatures[key] = signature
                }
                fresh.append(url)
            }
            return (Array(state.subscribers.values), fresh)
        }
        guard let outcome, !outcome.fresh.isEmpty || !removed.isEmpty else { return }
        let change = WorkspaceFileChange.delta(updated: outcome.fresh, removed: removed)
        outcome.subscribers.forEach { $0.yield(change) }
    }

    private func invalidate() {
        let subscribers = state.withLock { state -> [Subscriber] in
            state.files = nil
            state.paths = []
            state.signatures = [:]
            state.generation += 1
            return Array(state.subscribers.values)
        }
        subscribers.forEach { $0.yield(.reset) }
    }

    private func relocated(_ path: String) -> URL? {
        for prefix in rootPrefixes {
            if path == prefix { return URL(fileURLWithPath: rootPath, isDirectory: true) }
            if path.hasPrefix(prefix + "/") {
                return URL(fileURLWithPath: rootPath + path.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private func fullList() -> FullList {
        state.withLock { state -> FullList in
            if let files = state.files { return .ready(files) }
            if let inFlight = state.inFlight { return .running(inFlight) }
            let task = Task { [self] in self.buildCache() }
            state.inFlight = task
            return .running(task)
        }
    }

    private func buildCache() -> [URL] {
        var attempt = 0
        var files: [URL] = []
        var isFinal = false
        while !isFinal {
            attempt += 1
            let generation = state.withLock { $0.generation }
            files = scan(from: rootURL, limit: nil)
            isFinal = state.withLock { state -> Bool in
                let isStable = state.generation == generation || attempt >= Self.maxScanAttempts || Task.isCancelled
                guard isStable else { return false }
                if !Task.isCancelled { state.store(files) }
                state.inFlight = nil
                return true
            }
        }
        return files
    }

    private func currentFilter() -> Filter {
        Filter(rules: exclusionRules(), globs: state.withLock { $0.globs })
    }

    private func chain(forDirectory relative: String) -> GitignoreMatcher.Chain {
        var chain = gitignore.rootChain()
        var prefix = ""
        for component in relative.split(separator: "/") {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
            chain = gitignore.descend(chain, into: prefix)
        }
        return chain
    }

    private func scan(from directory: URL, limit: Int?) -> [URL] {
        guard let relative = gitignore.relativePath(of: directory) else { return [] }
        var files: [URL] = []
        walk(
            directory,
            relative: relative,
            chain: chain(forDirectory: relative),
            filter: currentFilter(),
            limit: limit,
            files: &files
        )
        return files
    }

    private func walk(
        _ directory: URL,
        relative: String,
        chain: GitignoreMatcher.Chain,
        filter: Filter,
        limit: Int?,
        files: inout [URL]
    ) {
        let entries = fileSystem.entries(in: directory).sorted { $0.name < $1.name }
        for entry in entries {
            if Task.isCancelled { return }
            if let limit, files.count >= limit { return }
            let childRelative = relative.isEmpty ? entry.name : relative + "/" + entry.name
            switch entry.kind {
            case .directory:
                guard !isExcluded(
                    relative: childRelative, name: entry.name, isDirectory: true, filter: filter, chain: chain
                ) else { continue }
                walk(
                    entry.url,
                    relative: childRelative,
                    chain: gitignore.descend(chain, into: childRelative),
                    filter: filter,
                    limit: limit,
                    files: &files
                )
            case .file:
                guard !isExcluded(
                    relative: childRelative, name: entry.name, isDirectory: false, filter: filter, chain: chain
                ) else { continue }
                files.append(entry.url)
            case .other:
                continue
            }
        }
    }

    private func isExcluded(
        relative: String,
        name: String,
        isDirectory: Bool,
        filter: Filter,
        chain: GitignoreMatcher.Chain
    ) -> Bool {
        if isDirectory {
            if filter.rules.isExclusionRoot(relativePath: relative, name: name) { return true }
        } else if Self.excludedFileNames.contains(name) {
            return true
        }
        if chain.isIgnored(relativePath: relative, isDirectory: isDirectory) { return true }
        return filter.globs.isIgnored(relativePath: relative, isDirectory: isDirectory)
    }

    private func isExcluded(_ url: URL, isDirectory: Bool?, filter: Filter) -> Bool {
        guard let relative = gitignore.relativePath(of: url), !relative.isEmpty else { return false }
        let components = relative.split(separator: "/").map(String.init)
        var chain = gitignore.rootChain()
        var prefix = ""
        for (index, name) in components.enumerated() {
            let isLast = index == components.count - 1
            prefix = prefix.isEmpty ? name : prefix + "/" + name
            let isDirectoryEntry = isLast ? (isDirectory ?? resolvesToDirectory(url)) : true
            if isExcluded(
                relative: prefix, name: name, isDirectory: isDirectoryEntry, filter: filter, chain: chain
            ) {
                return true
            }
            if !isLast { chain = gitignore.descend(chain, into: prefix) }
        }
        return false
    }

    private func resolvesToDirectory(_ url: URL) -> Bool {
        url.hasDirectoryPath || fileSystem.entry(at: url)?.kind == .directory
    }
}

nonisolated extension URL {
    var workspacePathKey: String {
        var key = path(percentEncoded: false)
        while key.count > 1, key.hasSuffix("/") { key.removeLast() }
        return key
    }
}

@MainActor
final class WorkspaceFileScopeObserver: CEWorkspaceFileManagerObserver {
    private let scope: WorkspaceFileScope

    init(scope: WorkspaceFileScope) {
        self.scope = scope
    }

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        let directories = updatedItems.filter(\.isFolder).map(\.url)
        guard !directories.isEmpty else { return }
        let scope = scope
        Task { await scope.refreshDirectories(directories) }
    }
}

extension WorkspaceFileScopeObserver {
    func fileManagerModifiedFiles(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        let scope = scope
        Task { await scope.applyModifiedFiles(urls) }
    }
}
