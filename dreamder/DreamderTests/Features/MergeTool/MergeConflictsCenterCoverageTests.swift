import AppKit
import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated private final class MergeConflictFlag: Sendable {
    private let state = Mutex(false)

    var isSet: Bool { state.withLock { $0 } }

    func set() {
        state.withLock { $0 = true }
    }
}

@MainActor
@Suite(.uiGate)
struct MergeConflictsCenterCoverageTests {
    private static let unmergedRecord = "u UU N... 100644 100644 100644 100644 h1 h2 h3 a.txt\u{0}"

    private func makeManager(_ root: URL) -> SourceControlManager {
        SourceControlManager(workspaceURL: root, editorManager: EditorManager())
    }

    private func scriptedCenter(root: URL, cancelOn argument: String?) -> MergeConflictsCenter {
        let unmerged = Self.unmergedRecord
        let runner = FakeProcessRunner { invocation in
            if let argument, invocation.arguments.contains(argument) {
                withUnsafeCurrentTask { (current: UnsafeCurrentTask?) in
                    current?.cancel()
                }
            }
            if invocation.arguments.contains("status") {
                return FakeProcessRunner.output(unmerged)
            }
            if invocation.arguments.contains("--abbrev-ref") {
                return FakeProcessRunner.output("main\n")
            }
            return FakeProcessRunner.output("")
        }
        let client = GitClient(
            directoryURL: root,
            shellClient: .live(),
            processRunner: runner,
            gitExecutable: URL(filePath: "/usr/bin/git")
        )
        return MergeConflictsCenter(makeRepository: { _ in
            MergeConflictRepository(gitClient: client, rootURL: root)
        })
    }

    @Test
    func workspaceKeyStandardizesThePath() {
        let key = MergeConflictsCenter.workspaceKey(URL(filePath: "/Users/dreamder-test/a/../b"))

        #expect(key == "/Users/dreamder-test/b")
    }

    @Test
    func unknownRootsHaveNoState() {
        let center = MergeConflictsCenter()
        let root = URL(filePath: "/Users/dreamder-test/unknown")

        #expect(center.state(for: root) == nil)
        #expect(center.entries(for: root).isEmpty)
        #expect(center.hasConflicts(rootURL: root) == false)
        #expect(center.states.isEmpty)
    }

    @Test
    func refreshPublishesConflictsAndTheirContextAndClearsThemAgain() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let center = MergeConflictsCenter()
            let manager = makeManager(dir)

            await center.refresh(manager: manager)

            #expect(center.entries(for: dir).map(\.path) == ["app/config.txt", "docs/notes.txt"])
            #expect(center.hasConflicts(rootURL: dir))
            #expect(center.state(for: dir)?.context?.summary == "Merging branch feature into branch main")

            try await fixture.run("checkout", "--ours", "--", "app/config.txt", "docs/notes.txt")
            try await fixture.run("add", "-A")
            await center.refresh(manager: manager)

            let state = try #require(center.state(for: dir))
            #expect(state.entries.isEmpty)
            #expect(state.context == nil)
            #expect(center.hasConflicts(rootURL: dir) == false)
        }
    }

    @Test
    func refreshUsesTheInjectedRepository() async throws {
        try await withTempDir { dir in
            let center = scriptedCenter(root: dir, cancelOn: nil)

            await center.refresh(manager: makeManager(dir))

            #expect(center.entries(for: dir).map(\.path) == ["a.txt"])
            #expect(center.state(for: dir)?.context?.operation == .unknown)
            #expect(center.state(for: dir)?.context?.yoursLabel == "main")
        }
    }

    @Test
    func refreshWithoutAMonitorPublishesWithoutOpeningAWindow() async throws {
        try await withTempDir { dir in
            let center = scriptedCenter(root: dir, cancelOn: nil)

            await center.refresh(manager: makeManager(dir), allowAutoOpen: true)

            #expect(center.entries(for: dir).map(\.path) == ["a.txt"])
        }
    }

    @Test
    func conflictsAppearingAfterTheFirstLoadFindNoWorkspaceToOpen() async throws {
        try await withTempDir { dir in
            let conflicted = MergeConflictFlag()
            let unmerged = Self.unmergedRecord
            let runner = FakeProcessRunner { invocation in
                if invocation.arguments.contains("status") {
                    return FakeProcessRunner.output(conflicted.isSet ? unmerged : "")
                }
                return FakeProcessRunner.output("main\n")
            }
            let client = GitClient(
                directoryURL: dir,
                shellClient: .live(),
                processRunner: runner,
                gitExecutable: URL(filePath: "/usr/bin/git")
            )
            let center = MergeConflictsCenter(makeRepository: { _ in
                MergeConflictRepository(gitClient: client, rootURL: dir)
            })
            let manager = makeManager(dir)

            center.monitor(manager)
            try await eventually { center.state(for: dir) != nil }
            #expect(center.hasConflicts(rootURL: dir) == false)

            conflicted.set()
            await center.refresh(manager: manager, allowAutoOpen: true)

            #expect(center.entries(for: dir).map(\.path) == ["a.txt"])
        }
    }

    @Test
    func refreshCancelledWhileReadingTheEntriesPublishesNothing() async throws {
        try await withTempDir { dir in
            let center = scriptedCenter(root: dir, cancelOn: "status")
            let manager = makeManager(dir)

            let task = Task { @MainActor in
                await center.refresh(manager: manager)
            }
            await task.value

            #expect(center.state(for: dir) == nil)
        }
    }

    @Test
    func refreshCancelledWhileReadingTheContextPublishesNothing() async throws {
        try await withTempDir { dir in
            let center = scriptedCenter(root: dir, cancelOn: "--abbrev-ref")
            let manager = makeManager(dir)

            let task = Task { @MainActor in
                await center.refresh(manager: manager)
            }
            await task.value

            #expect(center.state(for: dir) == nil)
            #expect(center.hasConflicts(rootURL: dir) == false)
        }
    }
}
