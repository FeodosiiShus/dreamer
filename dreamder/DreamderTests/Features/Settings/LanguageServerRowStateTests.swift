import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerRowStateTests {
    @Test
    func dismissingTheRemovalConfirmationClearsItsFlag() {
        let state = LanguageServerRowState()
        state.requestRemoval()
        #expect(state.showingRemovalConfirmation)

        state.dismissRemovalConfirmation()

        #expect(state.showingRemovalConfirmation == false)
    }

    @Test
    func dismissingTheRemovalErrorClearsItsFlag() {
        let state = LanguageServerRowState()
        state.showingRemovalError = true

        state.dismissRemovalError()

        #expect(state.showingRemovalError == false)
    }
}
