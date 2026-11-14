import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CommitToolWindowAmendBindingTests {
    @Test
    func theAmendBindingReadsTheModelAndItsSetterPrefillsAndRestoresTheMessage() async throws {
        try await withTempDir { directory in
            let rig = try await CommitToolWindowCoverageRig.make(in: directory, scenario: .singleModified)
            defer { rig.close() }
            let binding = rig.actions.amendBinding
            #expect(binding.wrappedValue == false)

            binding.wrappedValue = true
            try await eventually(timeout: .seconds(20)) { rig.viewModel.message == "initial" }
            #expect(rig.viewModel.amend)
            #expect(binding.wrappedValue)

            binding.wrappedValue = false
            try await eventually(timeout: .seconds(20)) { rig.viewModel.message.isEmpty }
            #expect(rig.viewModel.amend == false)
            #expect(binding.wrappedValue == false)
        }
    }
}
