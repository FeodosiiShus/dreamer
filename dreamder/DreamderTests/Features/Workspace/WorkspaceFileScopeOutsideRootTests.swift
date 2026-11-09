import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class OutsideDirectoryFileSystem: WorkspaceFileSystem {
    private let root: URL
    private let outside: URL
    private let listed = Mutex<[String]>([])

    init(root: URL, outside: URL) {
        self.root = root
        self.outside = outside
    }

    var outsideListings: Int {
        let outsidePath = outside.path(percentEncoded: false)
        return listed.withLock { paths in paths.filter { $0 == outsidePath }.count }
    }

    func entries(in directory: URL) -> [WorkspaceFileEntry] {
        let path = directory.path(percentEncoded: false)
        listed.withLock { $0.append(path) }
        guard path == root.path(percentEncoded: false) else { return [] }
        let signature = WorkspaceFileSignature(modified: nil, size: 0)
        return [WorkspaceFileEntry(url: outside, name: "elsewhere", kind: .directory, signature: signature)]
    }

    func entry(at url: URL) -> WorkspaceFileEntry? {
        nil
    }
}

@Suite("WorkspaceFileScope outside the root")
struct WorkspaceFileScopeOutsideRootTests {
    @Test
    func aNewDirectoryOutsideTheRootIsNeverScanned() async throws {
        try await withTempDir { directory in
            let root = directory.appending(path: "root", directoryHint: .isDirectory)
            let outside = directory.appending(path: "outside", directoryHint: .isDirectory)
            let fileSystem = OutsideDirectoryFileSystem(root: root, outside: outside)
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)
            _ = await scope.enumerateFiles(limit: nil)
            let listingsAfterTheFirstScan = fileSystem.outsideListings

            await scope.refreshDirectories([root])

            #expect(fileSystem.outsideListings == listingsAfterTheFirstScan)
            #expect(scope.cachedFiles() == [])
        }
    }
}
