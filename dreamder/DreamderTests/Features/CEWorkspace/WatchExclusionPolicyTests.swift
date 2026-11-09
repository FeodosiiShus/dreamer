import Foundation
import Testing
@testable import Dreamder

@Suite
struct WatchExclusionPolicyTests {
    private static let virtualRoot = URL(fileURLWithPath: "/virtual/project", isDirectory: true)

    private func makePolicy(
        _ root: URL,
        excluded: Set<String> = [],
        cancelled: Set<String> = []
    ) -> WatchExclusionPolicy {
        WatchExclusionPolicy(
            folderURL: root,
            rules: ExclusionRules(rootURL: root, excluded: excluded, cancelledDefaults: cancelled)
        )
    }

    private func makeDirectories(_ names: [String], in root: URL) throws {
        for name in names {
            try FileManager.default.createDirectory(
                at: root.appending(path: name, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }

    @Test
    func streamExclusionPathsListPresentRootsBeforeAbsentOnesAndFillEightSlots() throws {
        try withTempDir { root in
            try makeDirectories([".git/objects", "node_modules", "build"], in: root)
            let policy = makePolicy(root)
            let paths = policy.streamExclusionPaths()

            let base = policy.streamRootPath
            let present = [".git/objects", "node_modules", "build"].map { "\(base)/\($0)" }
            let absent = [".build", "dist", "target", "DerivedData", ".gradle"].map { "\(base)/\($0)" }
            #expect(paths.count == WatchExclusionPolicy.streamPathLimit)
            #expect(Array(paths.prefix(3)) == present)
            #expect(Array(paths.suffix(5)) == absent)
        }
    }

    @Test
    func userExcludedRootsComeFirstAndTheLimitDropsTheLastDefaults() {
        let policy = makePolicy(Self.virtualRoot, excluded: ["pkg/b", "pkg/a"])
        let paths = policy.streamExclusionPaths(fileExists: { _ in false })

        #expect(paths == [
            "/virtual/project/pkg/a",
            "/virtual/project/pkg/b",
            "/virtual/project/.git/objects",
            "/virtual/project/node_modules",
            "/virtual/project/.build",
            "/virtual/project/build",
            "/virtual/project/dist",
            "/virtual/project/target"
        ])
    }

    @Test
    func cancelledDefaultsAndDuplicatesAreNotListed() {
        let cancelled = makePolicy(Self.virtualRoot, cancelled: ["node_modules"])
            .streamExclusionPaths(fileExists: { _ in true })
        #expect(cancelled.contains("/virtual/project/node_modules") == false)
        #expect(cancelled.count == 7)

        let duplicated = makePolicy(Self.virtualRoot, excluded: ["node_modules"])
            .streamExclusionPaths(fileExists: { _ in true })
        #expect(duplicated.filter { $0 == "/virtual/project/node_modules" }.count == 1)
        #expect(duplicated.first == "/virtual/project/node_modules")
    }

    @Test
    func rootPathDropsTrailingSlashesAndTheCanonicalRootResolvesSymlinks() throws {
        try withTempDir { dir in
            let real = dir.appending(path: "real", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
            let link = dir.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            let linked = makePolicy(link)
            let direct = makePolicy(real)
            #expect(linked.rootPath.hasSuffix("/link"))
            #expect(linked.canonicalRootPath == direct.canonicalRootPath)
            #expect(linked.canonicalRootPath.hasSuffix("/real"))
            #expect(linked.streamRootPath == direct.streamRootPath)
            #expect(linked.streamRootPath.hasSuffix("/real"))
            #expect(direct.rootPath.hasSuffix("/") == false)
        }
    }

    @Test
    func directoriesUnderExcludedRootsAreExcluded() {
        let policy = makePolicy(Self.virtualRoot, excluded: ["gen/out"])

        #expect(policy.isDirectoryExcluded("/virtual/project/node_modules"))
        #expect(policy.isDirectoryExcluded("/virtual/project/node_modules/react/lib"))
        #expect(policy.isDirectoryExcluded("/virtual/project/.git/objects/ab"))
        #expect(policy.isDirectoryExcluded("/virtual/project/build"))
        #expect(policy.isDirectoryExcluded("/virtual/project/gen/out/sub"))
        #expect(policy.isDirectoryExcluded("/virtual/project/packages/x/node_modules/y"))
    }

    @Test
    func ordinaryDirectoriesAndPathsOutsideTheRootAreNotExcluded() {
        let policy = makePolicy(Self.virtualRoot, excluded: ["gen/out"])

        #expect(policy.isDirectoryExcluded("/virtual/project") == false)
        #expect(policy.isDirectoryExcluded("/virtual/project/src") == false)
        #expect(policy.isDirectoryExcluded("/virtual/project/.git") == false)
        #expect(policy.isDirectoryExcluded("/virtual/project/src/build") == false)
        #expect(policy.isDirectoryExcluded("/virtual/project/gen") == false)
        #expect(policy.isDirectoryExcluded("/virtual/other/node_modules") == false)
        #expect(policy.isDirectoryExcluded("/virtual/project-two/node_modules") == false)
    }

    @Test
    func cancelledDefaultsStopExcludingNodeModules() {
        let policy = makePolicy(Self.virtualRoot, cancelled: ["node_modules"])

        #expect(policy.isDirectoryExcluded("/virtual/project/node_modules") == false)
        #expect(policy.isDirectoryExcluded("/virtual/project/node_modules/react") == false)
    }
}
