import Foundation
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct DirectoryListingTests {
    private final class Recorder: Sendable {
        private let storage = Mutex<[(id: String, onMain: Bool)]>([])

        var diagnostics: FileManagerDiagnostics {
            FileManagerDiagnostics(
                directoryListed: { [self] id, onMain in storage.withLock { $0.append((id, onMain)) } },
                directoryRebuilt: { _ in }
            )
        }

        var calls: [(id: String, onMain: Bool)] {
            storage.withLock { $0 }
        }
    }

    private func populate(_ root: URL, directories: [String] = [], files: [String] = []) throws {
        for name in directories {
            try FileManager.default.createDirectory(
                at: root.appending(path: name, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        for name in files {
            try Data("x".utf8).write(to: root.appending(path: name))
        }
    }

    @Test
    func entriesListFoldersFirstInNaturalOrderAndSkipIgnoredNames() throws {
        try withTempDir { root in
            try populate(
                root,
                directories: ["zdir", "adir"],
                files: ["file10.txt", "file2.txt", "file1.txt", ".DS_Store"]
            )

            let listing = try DirectoryListing.read(
                directoryID: root.path(percentEncoded: false),
                at: root,
                ignoring: [".DS_Store"]
            )

            #expect(listing.entries.map(\.url.lastPathComponent) == [
                "adir", "zdir", "file1.txt", "file2.txt", "file10.txt"
            ])
            #expect(listing.entries.map(\.isDirectory) == [true, true, false, false, false])
        }
    }

    @Test
    func entryIdentifiersAndURLsDeriveFromTheDirectoryIdentifier() throws {
        try withTempDir { root in
            try populate(root, directories: ["sub dir"], files: ["a #1.txt"])
            let directoryID = root.path(percentEncoded: false).withoutTrailingSlashes

            let listing = try DirectoryListing.read(directoryID: directoryID, at: root, ignoring: [])

            #expect(listing.directoryID == directoryID)
            #expect(listing.entries.map(\.id) == ["\(directoryID)/sub dir", "\(directoryID)/a #1.txt"])
            #expect(listing.entries.map { $0.url.path(percentEncoded: false) } == listing.entries.map(\.id))
            #expect(DirectoryListing.childURL(of: directoryID, named: "a #1.txt").relativePath == "\(directoryID)/a #1.txt")
        }
    }

    @Test
    func symlinksToDirectoriesAreDirectoriesAndOtherLinksAreFiles() throws {
        try withTempDir { root in
            try populate(root, directories: ["target"], files: ["plain.txt"])
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "linked-dir"),
                withDestinationURL: root.appending(path: "target")
            )
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "linked-file"),
                withDestinationURL: root.appending(path: "plain.txt")
            )
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "dangling"),
                withDestinationURL: root.appending(path: "missing")
            )

            let listing = try DirectoryListing.read(
                directoryID: root.path(percentEncoded: false),
                at: root,
                ignoring: []
            )
            let kinds = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.url.lastPathComponent, $0.isDirectory) })

            #expect(kinds == [
                "target": true,
                "linked-dir": true,
                "plain.txt": false,
                "linked-file": false,
                "dangling": false
            ])
        }
    }

    @Test
    func listingReportsTheThreadItRanOn() async throws {
        try await withTempDir { root in
            try populate(root, files: ["a.txt"])
            let recorder = Recorder()
            let id = root.path(percentEncoded: false)

            let offMain = await Task.detached {
                try? DirectoryListing.read(directoryID: id, at: root, ignoring: [], diagnostics: recorder.diagnostics)
            }.value
            #expect(offMain?.entries.count == 1)
            let onMain = await MainActor.run {
                try? DirectoryListing.read(directoryID: id, at: root, ignoring: [], diagnostics: recorder.diagnostics)
            }
            #expect(onMain?.entries.count == 1)

            #expect(recorder.calls.map { $0.id } == [id, id])
            #expect(recorder.calls.map { $0.onMain } == [false, true])
        }
    }

    @Test
    func readingAMissingDirectoryThrowsAfterReportingTheAttempt() throws {
        try withTempDir { root in
            let recorder = Recorder()
            let missing = root.appending(path: "missing", directoryHint: .isDirectory)

            #expect(throws: (any Error).self) {
                try DirectoryListing.read(
                    directoryID: missing.path(percentEncoded: false),
                    at: missing,
                    ignoring: [],
                    diagnostics: recorder.diagnostics
                )
            }
            #expect(recorder.calls.count == 1)
        }
    }

    @Test
    func silentDiagnosticsDoNothing() {
        FileManagerDiagnostics.silent.directoryListed("/x", true)
        FileManagerDiagnostics.silent.directoryRebuilt("/x")
    }

    @Test
    func naturalKeysOrderNumbersNumericallyAndFallBackToTheName() {
        func precedes(_ lhs: String, _ rhs: String) -> Bool {
            DirectoryListing.NaturalKey(lhs).precedes(DirectoryListing.NaturalKey(rhs))
        }

        #expect(precedes("file2", "file10"))
        #expect(precedes("file10", "file2") == false)
        #expect(precedes("adir", "zdir"))
        #expect(precedes("zdir", "adir") == false)
        #expect(precedes("ab", "a1"))
        #expect(precedes("a1", "ab") == false)
        #expect(precedes("same", "same") == false)
    }

    @Test
    func trailingSlashesAreStrippedExceptForTheRoot() {
        #expect("/a/b///".withoutTrailingSlashes == "/a/b")
        #expect("/a/b".withoutTrailingSlashes == "/a/b")
        #expect("/".withoutTrailingSlashes == "/")
        #expect("".withoutTrailingSlashes == "")
    }
}
