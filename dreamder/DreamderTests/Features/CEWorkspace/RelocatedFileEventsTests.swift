import Foundation
import Testing
@testable import Dreamder

@Suite
struct RelocatedFileEventsTests {
    private func event(_ path: String, _ type: FSEvent = .itemCreated) -> DirectoryEventStream.Event {
        DirectoryEventStream.Event(path: path, eventType: type)
    }

    private func makePolicy(_ root: URL, excluded: Set<String> = []) -> WatchExclusionPolicy {
        WatchExclusionPolicy(folderURL: root, rules: ExclusionRules(rootURL: root, excluded: excluded))
    }

    @Test
    func eventsUnderASymlinkedRootAreRelocatedToTheWorkspacePath() throws {
        try withTempDir { dir in
            let real = dir.appending(path: "real", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: real.appending(path: "src", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            let link = dir.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let policy = makePolicy(link)
            let canonical = policy.canonicalRootPath

            let relocated = RelocatedFileEvents(
                [
                    event("\(canonical)/src/a b.txt"),
                    event("\(canonical)/src/gone.txt", .itemRemoved)
                ],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.events.map(\.path) == ["\(policy.rootPath)/src/a b.txt", "\(policy.rootPath)/src/gone.txt"])
            #expect(relocated.events.map(\.eventType) == [.itemCreated, .itemRemoved])
            #expect(relocated.treeParents == ["\(policy.rootPath)/src"])
        }
    }

    @Test
    func theRootItselfMapsToTheWorkspacePathAndForeignPathsStayUntouched() throws {
        try withTempDir { root in
            let policy = makePolicy(root)
            let relocated = RelocatedFileEvents(
                [
                    event(policy.canonicalRootPath, .rootChanged),
                    event("/definitely/elsewhere/file"),
                    event("no-slash"),
                    event("/top")
                ],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.events.map(\.path) == [
                policy.rootPath,
                "/definitely/elsewhere/file",
                "no-slash",
                "/top"
            ])
            #expect(relocated.treeParents == ["/definitely/elsewhere", "no-slash", "/"])
        }
    }

    @Test
    func eventsUnderExcludedRootsAreDroppedButTheRootsThemselvesAndGitMetadataAreKept() throws {
        try withTempDir { root in
            let policy = makePolicy(root, excluded: ["generated"])
            let base = policy.canonicalRootPath
            let relocated = RelocatedFileEvents(
                [
                    event("\(base)/node_modules/react/index.js"),
                    event("\(base)/node_modules/react"),
                    event("\(base)/node_modules"),
                    event("\(base)/.git/objects/ab/cdef"),
                    event("\(base)/.git/index", .itemModified),
                    event("\(base)/generated/out.swift"),
                    event("\(base)/src/main.swift")
                ],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.events.map(\.path) == [
                "\(policy.rootPath)/node_modules",
                "\(policy.rootPath)/.git/index",
                "\(policy.rootPath)/src/main.swift"
            ])
            #expect(relocated.treeParents == [policy.rootPath, "\(policy.rootPath)/src"])
        }
    }

    @Test
    func onlyStructuralEventTypesMakeTheirParentDirectoryDirty() throws {
        try withTempDir { root in
            let policy = makePolicy(root)
            let structural: [FSEvent] = [.itemCreated, .itemCloned, .itemRemoved, .itemRenamed]
            let passive: [FSEvent] = [.changeInDirectory, .itemChangedOwner, .itemModified, .rootChanged]

            for type in structural {
                let relocated = RelocatedFileEvents(
                    [event("\(policy.canonicalRootPath)/a", type)],
                    folderPath: policy.rootPath,
                    policy: policy
                )
                #expect(relocated.treeParents == [policy.rootPath], "\(type)")
            }
            for type in passive {
                let relocated = RelocatedFileEvents(
                    [event("\(policy.canonicalRootPath)/a", type)],
                    folderPath: policy.rootPath,
                    policy: policy
                )
                #expect(relocated.events.count == 1)
                #expect(relocated.treeParents.isEmpty, "\(type)")
            }
        }
    }

    @Test
    func manyEventsInOneDirectoryCollapseIntoOneDirtyParent() throws {
        try withTempDir { root in
            let policy = makePolicy(root)
            let base = policy.canonicalRootPath
            let relocated = RelocatedFileEvents(
                (0..<500).map { event("\(base)/file\($0).txt") } + (0..<20).map { event("\(base)/node_modules/m\($0)") },
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.events.count == 500)
            #expect(relocated.treeParents == [policy.rootPath])
        }
    }

    @Test
    func modifiedRegularFilesAreCollectedOnceAndSkipExcludedGitAndNonFilePaths() throws {
        try withTempDir { root in
            for name in ["a.txt", "node_modules/dep.js", ".git/index"] {
                let url = root.appending(path: name)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("x".utf8).write(to: url)
            }
            let policy = makePolicy(root)
            let base = policy.canonicalRootPath
            let relocated = RelocatedFileEvents(
                (0..<50).map { _ in event("\(base)/a.txt", .itemModified) } + [
                    event("\(base)/node_modules/dep.js", .itemModified),
                    event("\(base)/.git/index", .itemModified),
                    event("\(base)/missing.txt", .itemModified),
                    event(base, .itemModified),
                    event("\(base)/created.txt", .itemCreated)
                ],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.modifiedFiles == ["\(policy.rootPath)/a.txt"])
        }
    }
}
