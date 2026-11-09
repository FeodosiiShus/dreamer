import Foundation
import Testing
@testable import Dreamder

@Suite
struct RelocatedFileEventsRescanTests {
    private func event(_ path: String, _ type: FSEvent) -> DirectoryEventStream.Event {
        DirectoryEventStream.Event(path: path, eventType: type)
    }

    private func makePolicy(_ root: URL, excluded: Set<String> = []) -> WatchExclusionPolicy {
        WatchExclusionPolicy(folderURL: root, rules: ExclusionRules(rootURL: root, excluded: excluded))
    }

    @Test
    func aRescanOfTheRootIsReportedAtTheWorkspacePath() throws {
        try withTempDir { root in
            let policy = makePolicy(root)

            let relocated = RelocatedFileEvents(
                [event(policy.canonicalRootPath, .mustRescan)],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.rescanRoots == [policy.rootPath])
            #expect(relocated.events.map(\.eventType) == [.mustRescan])
            #expect(relocated.treeParents.isEmpty)
        }
    }

    @Test
    func aRescanOfASubdirectoryIsReportedAtItsWorkspacePathOnceNoMatterHowOftenItRepeats() throws {
        try withTempDir { root in
            let policy = makePolicy(root)
            let sub = "\(policy.canonicalRootPath)/sub"

            let relocated = RelocatedFileEvents(
                [event(sub, .mustRescan), event(sub, .mustRescan), event("\(sub)/a.txt", .itemCreated)],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.rescanRoots == ["\(policy.rootPath)/sub"])
            #expect(relocated.treeParents == ["\(policy.rootPath)/sub"])
        }
    }

    @Test
    func otherEventTypesNeverRequestARescan() throws {
        try withTempDir { root in
            let policy = makePolicy(root)
            let types: [FSEvent] = [
                .changeInDirectory, .itemChangedOwner, .itemCreated, .itemCloned, .itemModified, .itemRemoved,
                .itemRenamed
            ]

            let relocated = RelocatedFileEvents(
                types.map { event("\(policy.canonicalRootPath)/a", $0) },
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.events.count == types.count)
            #expect(relocated.rescanRoots.isEmpty)
        }
    }

    @Test
    func aRescanInsideAnExcludedDirectoryIsDropped() throws {
        try withTempDir { root in
            let policy = makePolicy(root, excluded: ["generated"])

            let relocated = RelocatedFileEvents(
                [event("\(policy.canonicalRootPath)/generated/inner", .mustRescan)],
                folderPath: policy.rootPath,
                policy: policy
            )

            #expect(relocated.events.isEmpty)
            #expect(relocated.rescanRoots.isEmpty)
        }
    }
}
