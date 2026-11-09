import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class BlockingFileSystem: WorkspaceFileSystem {
    private let inner = DiskWorkspaceFileSystem()
    private let gate = DispatchSemaphore(value: 0)
    private let entered = Mutex(0)

    var hasEntered: Bool {
        entered.withLock { $0 > 0 }
    }

    func release() {
        gate.signal()
    }

    func entries(in directory: URL) -> [WorkspaceFileEntry] {
        entered.withLock { $0 += 1 }
        _ = gate.wait(timeout: .now() + 20)
        gate.signal()
        return inner.entries(in: directory)
    }

    func entry(at url: URL) -> WorkspaceFileEntry? {
        inner.entry(at: url)
    }
}

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywhereTaskLifetimeTests {
    private func makeModel(workspace: WorkspaceDocument?) throws -> SearchEverywhereViewModel {
        let defaults = try IsolatedDefaults.require()
        return SearchEverywhereViewModel(
            workspace: workspace,
            defaults: defaults,
            recentFiles: SearchEverywhereRecentFilesStore(defaults: defaults),
            actions: { [] }
        )
    }

    @Test
    func releasingTheModelCancelsATextScanThatIsStillRunningInAFakeScope() async throws {
        try await withTempDir { dir in
            try touch(dir, "Notes.md", "the needle line\n")
            let fileSystem = BlockingFileSystem()
            let workspace = WorkspaceDocument()
            workspace.fileScope = WorkspaceFileScope(rootURL: dir, fileSystem: fileSystem)
            defer {
                fileSystem.release()
                workspace.tearDownFileScope()
            }
            var model: SearchEverywhereViewModel? = try makeModel(workspace: workspace)
            weak let released = model
            model?.start(on: .text)
            model?.query = "needle"
            model?.performSearch()
            model?.debounceTask?.cancel()
            let textTask = try #require(model?.textTask)
            try await eventually(timeout: .seconds(20)) { fileSystem.hasEntered }
            #expect(!textTask.isCancelled)

            model = nil

            try await eventually(timeout: .seconds(20)) { released == nil }
            #expect(textTask.isCancelled)
            fileSystem.release()
            await textTask.value
        }
    }

    @Test
    func releasingTheModelCancelsDebounceTextIndexAndPreviewTasks() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            var model: SearchEverywhereViewModel? = try makeModel(workspace: workspace)
            weak let released = model
            model?.showsPreview = true
            model?.start(on: .all)
            model?.query = "AppDelegate"
            try await eventually(timeout: .seconds(20)) { model?.selectedItem?.url != nil }

            model?.query = "AppDelegat"
            model?.performSearch()
            let debounceTask = try #require(model?.debounceTask)
            let textTask = try #require(model?.textTask)
            let indexTask = try #require(model?.indexTask)
            let previewTask = try #require(model?.previewTask)
            #expect(![debounceTask, textTask, indexTask, previewTask].contains { $0.isCancelled })

            model = nil

            try await eventually(timeout: .seconds(20)) { released == nil }
            #expect(debounceTask.isCancelled)
            #expect(textTask.isCancelled)
            #expect(indexTask.isCancelled)
            #expect(previewTask.isCancelled)
        }
    }

    @Test
    func aModelWithoutWorkspaceOrTasksIsReleasedCleanly() throws {
        var model: SearchEverywhereViewModel? = try makeModel(workspace: nil)
        weak let released = model

        model = nil

        #expect(released == nil)
    }
}
