import Foundation
import Synchronization
import Testing
@testable import Dreamder

final class ProjectNavigatorListingRecorder: WorkspaceFileSystem, Sendable {
    private let listed = Mutex<[String]>([])
    private let disk = DiskWorkspaceFileSystem()

    var listedDirectories: [String] {
        listed.withLock { $0 }
    }

    func entries(in directory: URL) -> [WorkspaceFileEntry] {
        listed.withLock { $0.append(directory.lastPathComponent) }
        return disk.entries(in: directory)
    }

    func entry(at url: URL) -> WorkspaceFileEntry? {
        disk.entry(at: url)
    }
}

@Suite
struct ProjectNavigatorFilterMatchesTests {
    static let rootID = "/tree/root"

    private func makeTree(_ files: [String], folders: [String] = [], in root: URL) throws {
        for folder in folders {
            try FileManager.default.createDirectory(
                at: root.appending(path: folder),
                withIntermediateDirectories: true
            )
        }
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "content".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func treeAncestors(
        of text: String,
        files: [String],
        folders: [String] = [],
        hidden: Set<String> = [],
        withScope: Bool = true,
        recorder: ProjectNavigatorListingRecorder = ProjectNavigatorListingRecorder(),
        prepare: (URL) throws -> Void = { _ in }
    ) async throws -> Set<String> {
        var result: Set<String> = []
        try await withTempDir { root in
            try makeTree(files, folders: folders, in: root)
            try prepare(root)
            let source = ProjectNavigatorTreeSource(
                rootURL: root,
                fileSystem: recorder,
                hiddenNames: hidden,
                scope: withScope ? WorkspaceFileScope(rootURL: root) : nil
            )
            let matches = await ProjectNavigatorFilterMatches.resolve(
                text: text,
                rootID: Self.rootID,
                candidates: .tree(source)
            )
            result = matches.ancestorIDs
        }
        return result
    }

    private func changedAncestors(
        of text: String,
        ids: [String],
        rootID: String = ProjectNavigatorFilterMatchesTests.rootID
    ) async -> Set<String> {
        let matches = await ProjectNavigatorFilterMatches.resolve(
            text: text,
            rootID: rootID,
            candidates: .changedIDs(ids)
        )
        return matches.ancestorIDs
    }

    @Test
    func aNameFilterListsEveryDirectoryAboveAMatchingFile() async throws {
        let ancestors = try await treeAncestors(
            of: "main",
            files: ["a.txt", "src/deep/main.swift", "src/util.swift", "lib/x.txt"]
        )

        #expect(ancestors == ["/tree/root/src", "/tree/root/src/deep"])
    }

    @Test
    func aMatchingFolderListsOnlyTheDirectoriesAboveIt() async throws {
        let ancestors = try await treeAncestors(of: "deep", files: ["src/deep/x.txt", "src/other/y.txt"])

        #expect(ancestors == ["/tree/root/src"])
    }

    @Test
    func aMatchingEmptyFolderKeepsItsParentsReachable() async throws {
        let ancestors = try await treeAncestors(of: "target", files: ["a.txt"], folders: ["a1/b/target", "other"])

        #expect(ancestors == ["/tree/root/a1", "/tree/root/a1/b"])
    }

    @Test
    func aMatchingFolderIsNotDescended() async throws {
        let recorder = ProjectNavigatorListingRecorder()

        let ancestors = try await treeAncestors(of: "src", files: ["src/deep/x.txt"], recorder: recorder)

        #expect(ancestors.isEmpty)
        #expect(!recorder.listedDirectories.contains("src"))
        #expect(!recorder.listedDirectories.contains("deep"))
    }

    @Test
    func matchingIgnoresCase() async throws {
        let ancestors = try await treeAncestors(of: "main", files: ["Sources/Main.swift"])

        #expect(ancestors == ["/tree/root/Sources"])
    }

    @Test
    func filesIgnoredByGitStillMatch() async throws {
        let ancestors = try await treeAncestors(of: "secret", files: ["src/secret.txt", "keep.txt"]) { root in
            try "secret.txt\n".write(to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        }

        #expect(ancestors == ["/tree/root/src"])
    }

    @Test
    func symlinksMatchByTheirOwnName() async throws {
        let ancestors = try await treeAncestors(of: "shortcut", files: ["src/real.txt"]) { root in
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "src/shortcut"),
                withDestinationURL: root.appending(path: "src/real.txt")
            )
        }

        #expect(ancestors == ["/tree/root/src"])
    }

    @Test
    func excludedFoldersAreNeverListed() async throws {
        let recorder = ProjectNavigatorListingRecorder()

        let ancestors = try await treeAncestors(
            of: ".js",
            files: ["src/a.js", "node_modules/pkg/i.js"],
            recorder: recorder
        )

        #expect(ancestors == ["/tree/root/src"])
        #expect(recorder.listedDirectories.contains("src"))
        #expect(!recorder.listedDirectories.contains("node_modules"))
        #expect(!recorder.listedDirectories.contains("pkg"))
    }

    @Test
    func anExcludedFolderStillMatchesByItsOwnNameWithoutBeingListed() async throws {
        let recorder = ProjectNavigatorListingRecorder()

        let ancestors = try await treeAncestors(of: "node_mod", files: ["node_modules/pkg/i.js"], recorder: recorder)

        #expect(ancestors.isEmpty)
        #expect(!recorder.listedDirectories.contains("node_modules"))
    }

    @Test
    func withoutAFileScopeNothingIsExcluded() async throws {
        let ancestors = try await treeAncestors(of: "i.js", files: ["node_modules/pkg/i.js"], withScope: false)

        #expect(ancestors == ["/tree/root/node_modules", "/tree/root/node_modules/pkg"])
    }

    @Test
    func hiddenNamesAreNeitherMatchedNorListed() async throws {
        let recorder = ProjectNavigatorListingRecorder()

        let ancestors = try await treeAncestors(
            of: "head",
            files: [".git/head.txt", "src/head.txt"],
            hidden: [".git"],
            recorder: recorder
        )

        #expect(ancestors == ["/tree/root/src"])
        #expect(!recorder.listedDirectories.contains(".git"))
    }

    @Test
    func aFilterWithoutMatchesHasNoAncestors() async throws {
        let ancestors = try await treeAncestors(of: "zzz", files: ["src/a.js", "b.txt"])

        #expect(ancestors.isEmpty)
    }

    @Test
    func aCancelledResolutionStopsListingAndReturnsWhatItFound() async throws {
        var result: Set<String> = ["unset"]
        try await withTempDir { root in
            try makeTree(["src/main.swift"], in: root)
            let source = ProjectNavigatorTreeSource(
                rootURL: root,
                fileSystem: ProjectNavigatorListingRecorder(),
                hiddenNames: [],
                scope: nil
            )
            let task = Task { () -> ProjectNavigatorFilterMatches in
                withUnsafeCurrentTask { $0?.cancel() }
                return await ProjectNavigatorFilterMatches.resolve(
                    text: "main",
                    rootID: Self.rootID,
                    candidates: .tree(source)
                )
            }
            result = await task.value.ancestorIDs
        }

        #expect(result.isEmpty)
    }

    @Test
    func changedFilesListTheirAncestorsWhenTheNameFilterIsBlank() async {
        let ancestors = await changedAncestors(
            of: "",
            ids: ["/tree/root/src/a.swift", "/tree/root/b.txt", "/tree/root/x/y/z.txt"]
        )

        #expect(ancestors == ["/tree/root/src", "/tree/root/x", "/tree/root/x/y"])
    }

    @Test
    func aNameFilterNarrowsTheChangedFiles() async {
        let ancestors = await changedAncestors(
            of: "a.sw",
            ids: ["/tree/root/src/a.swift", "/tree/root/x/y/z.txt"]
        )

        #expect(ancestors == ["/tree/root/src"])
    }

    @Test
    func theChangedFilesFilterMarksItselfAsSourceControl() async {
        let matches = await ProjectNavigatorFilterMatches.resolve(
            text: "",
            rootID: Self.rootID,
            candidates: .changedIDs([])
        )

        #expect(matches.sourceControl)
        #expect(matches.isActive)
        #expect(matches.ancestorIDs.isEmpty)
    }

    @Test
    func aTrailingSlashOnTheRootIDIsIgnored() async {
        let ancestors = await changedAncestors(
            of: "",
            ids: ["/tree/root/src/a.swift"],
            rootID: "/tree/root/"
        )

        #expect(ancestors == ["/tree/root/src"])
    }

    @Test
    func blankAndInactiveFiltersAreRecognised() {
        let blank = ProjectNavigatorFilterMatches(text: "  ", sourceControl: false, ancestorIDs: [])
        let blankSourceControl = ProjectNavigatorFilterMatches(text: "  ", sourceControl: true, ancestorIDs: [])
        let named = ProjectNavigatorFilterMatches(text: "Main", sourceControl: false, ancestorIDs: [])

        #expect(ProjectNavigatorFilterMatches.inactive.isBlank)
        #expect(!ProjectNavigatorFilterMatches.inactive.isActive)
        #expect(blank.isBlank && !blank.isActive)
        #expect(blankSourceControl.isActive)
        #expect(blankSourceControl.matches(name: "anything"))
        #expect(named.isActive && !named.isBlank)
        #expect(named.matches(name: "main.swift"))
        #expect(!named.matches(name: "util.swift"))
    }
}
