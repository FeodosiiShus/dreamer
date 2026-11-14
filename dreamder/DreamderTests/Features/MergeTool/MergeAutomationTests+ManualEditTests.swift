import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    @Test
    func resolveAfterAManualEditKeepsTheEditUnlessTheConfirmationIsYes() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("resolve:\(blockID):left")

            #expect(MergeAutomation.pendingAnswer == nil)
            #expect(model.resultText == "draft")
            #expect(model.isResultEdited)
            #expect(model.merge?.conflictCount == 1)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("resolve:\(blockID):left")

            #expect(model.resultText.contains("epsilon\nzeta-main\neta"))
            #expect(model.isResultEdited == false)
            #expect(model.merge?.conflictCount == 0)
        }
    }

    @Test
    func applyNonConflictingAfterAManualEditKeepsTheEditUnlessTheConfirmationIsYes() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("applyNonConflicting:all")

            #expect(MergeAutomation.pendingAnswer == nil)
            #expect(model.resultText == "draft")
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("applyNonConflicting:all")

            #expect(model.resultText.contains("feature-added"))
            #expect(model.isResultEdited == false)
        }
    }
}
