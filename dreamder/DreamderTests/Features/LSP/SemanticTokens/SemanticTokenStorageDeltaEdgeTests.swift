import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct SemanticTokenStorageDeltaEdgeTests {
    private let tokens = [
        SemanticToken(line: 0, char: 0, length: 10, type: 0, modifiers: 0),
        SemanticToken(line: 1, char: 2, length: 5, type: 2, modifiers: 3),
        SemanticToken(line: 3, char: 8, length: 10, type: 1, modifiers: 0)
    ]

    private func makeDelta(json: String) throws -> SemanticTokensDelta {
        try JSONDecoder().decode(SemanticTokensDelta.self, from: Data(json.utf8))
    }

    private func loadedStorage() -> SemanticTokenStorage {
        let storage = SemanticTokenStorage()
        storage.setData(SemanticTokens(tokens: tokens))
        return storage
    }

    @Test
    func applyingADeltaWithoutStoredDataChangesNothingAndInvalidatesNothing() throws {
        let storage = SemanticTokenStorage()
        let delta = try makeDelta(json: "{\"resultId\": \"1\", \"edits\": [{\"start\": 0, \"deleteCount\": 0}]}")

        #expect(storage.applyDelta(delta).isEmpty)
        #expect(storage.state == nil)
    }

    @Test
    func deleteEditWithoutDataRemovesTheTokensAndInvalidatesOnlyTheRemovedOnes() throws {
        let storage = loadedStorage()
        let delta = try makeDelta(json: "{\"resultId\": \"2\", \"edits\": [{\"start\": 5, \"deleteCount\": 5}]}")

        let invalidated = storage.applyDelta(delta)

        let state = try #require(storage.state)
        #expect(state.resultId == "2")
        #expect(state.tokens.count == 2)
        #expect(state.tokens[0] == tokens[0])
        #expect(state.tokens[1] == SemanticToken(line: 2, char: 8, length: 10, type: 1, modifiers: 0))
        #expect(!invalidated.isEmpty)
    }

    @Test
    func insertEditWithoutDataKeepsTheTokensAndInvalidatesOnlyTheTouchedOnes() throws {
        let storage = loadedStorage()
        let delta = try makeDelta(json: "{\"resultId\": \"3\", \"edits\": [{\"start\": 5, \"deleteCount\": 0}]}")

        _ = storage.applyDelta(delta)

        let state = try #require(storage.state)
        #expect(state.resultId == "3")
        #expect(state.tokens == tokens)
    }
}
