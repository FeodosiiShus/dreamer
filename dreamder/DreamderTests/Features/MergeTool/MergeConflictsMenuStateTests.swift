import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct MergeConflictsMenuStateTests {
    @Test
    func refreshWithoutAnActiveWorkspaceReportsNoUnmergedFiles() {
        let store = MergeConflictsMenuState.Store()
        store.refresh()
        #expect(store.hasUnmergedFiles == false)
    }

    @Test
    func startIsIdempotentAndKeepsReportingNoUnmergedFiles() async throws {
        let store = MergeConflictsMenuState.Store()
        store.start()
        store.start()
        try await Task.sleep(for: .milliseconds(50))
        store.refresh()
        #expect(store.hasUnmergedFiles == false)
    }
}
