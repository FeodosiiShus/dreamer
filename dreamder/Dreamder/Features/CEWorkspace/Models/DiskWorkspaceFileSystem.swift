import Foundation

nonisolated extension WorkspaceFileSystem {
    func existingEntry(at url: URL) -> WorkspaceFileEntry? {
        guard let entry = entry(at: url), entry.name == url.lastPathComponent else { return nil }
        return entry
    }
}

nonisolated struct DiskWorkspaceFileSystem: WorkspaceFileSystem {
    private static let keys: [URLResourceKey] = [
        .nameKey,
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
        guard let values = try? url.resourceValues(forKeys: Set(keys)), let name = values.name else { return nil }
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
            name: name,
            kind: kind,
            signature: WorkspaceFileSignature(modified: values.contentModificationDate, size: values.fileSize ?? 0)
        )
    }
}
