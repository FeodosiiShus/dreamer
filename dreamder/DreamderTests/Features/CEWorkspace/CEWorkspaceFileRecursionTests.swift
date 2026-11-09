import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceFileRecursionTests {
    private struct Tree {
        let manager: CEWorkspaceFileManager
        let top: CEWorkspaceFile
        let nested: CEWorkspaceFile
        let deepest: CEWorkspaceFile
    }

    private func write(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
    }

    private func load(_ file: CEWorkspaceFile, in manager: CEWorkspaceFileManager) async throws {
        _ = manager.childrenOfFile(file)
        try await eventually { manager.pendingLoads.isEmpty }
    }

    private func makeTree(in dir: URL) async throws -> Tree {
        try write(dir.appending(path: "a.txt"))
        try write(dir.appending(path: "sub/b.txt"))
        try write(dir.appending(path: "sub/deep/c.txt"))
        let manager = CEWorkspaceFileManager(folderUrl: dir, ignoredFilesAndFolders: [], sourceControlManager: nil)
        manager.fsEventStream?.cancel()
        let sub = try #require(manager.getFile("\(manager.workspaceItem.id)/sub"))
        try await load(sub, in: manager)
        let deep = try #require(manager.getFile("\(sub.id)/deep"))
        try await load(deep, in: manager)
        let leaf = try #require(manager.getFile("\(deep.id)/c.txt"))
        return Tree(manager: manager, top: sub, nested: deep, deepest: leaf)
    }

    @Test
    func siblingsAreCollectedFromTheAncestorTheHeightPointsAt() async throws {
        try await withTempDir { dir in
            let tree = try await makeTree(in: dir)
            let leaf = tree.deepest

            @MainActor
            func names(_ height: Int, ignoringFolders: Bool) -> [String] {
                leaf.flattenedSiblings(withHeight: height, ignoringFolders: ignoringFolders, using: tree.manager)
                    .map { $0.name }
            }

            #expect(names(0, ignoringFolders: true).isEmpty)
            #expect(names(1, ignoringFolders: true).isEmpty)
            #expect(names(2, ignoringFolders: true) == ["b.txt"])
            #expect(names(2, ignoringFolders: false) == ["sub", "deep", "b.txt"])
            #expect(names(3, ignoringFolders: true) == ["b.txt", "a.txt"])
        }
    }

    @Test
    func aHeightBeyondTheRootStopsAtTheRoot() async throws {
        try await withTempDir { dir in
            let tree = try await makeTree(in: dir)

            let names = tree.deepest
                .flattenedSiblings(withHeight: 10, ignoringFolders: true, using: tree.manager)
                .map { $0.name }

            #expect(names == ["c.txt", "b.txt", "a.txt"])
        }
    }

    @Test
    func flatteningStopsAtTheDepthAndReturnsFilesAsThemselves() async throws {
        try await withTempDir { dir in
            let tree = try await makeTree(in: dir)
            let manager = tree.manager

            @MainActor
            func flatten(_ file: CEWorkspaceFile, depth: Int, ignoringFolders: Bool) -> [CEWorkspaceFile] {
                file.flattenedChildren(withDepth: depth, ignoringFolders: ignoringFolders, using: manager)
            }

            #expect(flatten(tree.top, depth: 0, ignoringFolders: false).isEmpty)
            #expect(flatten(tree.deepest, depth: 1, ignoringFolders: true) == [tree.deepest])
            #expect(flatten(tree.nested, depth: 1, ignoringFolders: false) == [tree.nested])
            #expect(flatten(tree.nested, depth: 2, ignoringFolders: true) == [tree.deepest])
        }
    }
}
