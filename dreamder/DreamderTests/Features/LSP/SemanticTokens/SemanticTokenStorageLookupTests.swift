import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct SemanticTokenStorageLookupTests {
    private let tokens = [
        SemanticToken(line: 0, char: 0, length: 10, type: 0, modifiers: 0),
        SemanticToken(line: 1, char: 2, length: 5, type: 2, modifiers: 3),
        SemanticToken(line: 3, char: 8, length: 10, type: 1, modifiers: 0)
    ]

    private func range(_ startLine: Int, _ startChar: Int, _ endLine: Int, _ endChar: Int) -> LSPRange {
        LSPRange(
            start: Position(line: startLine, character: startChar),
            end: Position(line: endLine, character: endChar)
        )
    }

    private func loadedStorage() -> SemanticTokenStorage {
        let storage = SemanticTokenStorage()
        storage.setData(SemanticTokens(tokens: tokens))
        return storage
    }

    @Test
    func emptyStorageHasNoTokensInAnyRange() {
        #expect(SemanticTokenStorage().getTokensFor(range: range(0, 0, 10, 0)).isEmpty)
    }

    @Test
    func storageWithoutTokensHasNoTokensInAnyRange() {
        let storage = SemanticTokenStorage()
        storage.setData(SemanticTokens(tokens: []))

        #expect(storage.getTokensFor(range: range(0, 0, 10, 0)).isEmpty)
    }

    @Test
    func rangeCoveringEveryTokenReturnsAllOfThem() {
        #expect(loadedStorage().getTokensFor(range: range(0, 0, 4, 0)) == tokens)
    }

    @Test
    func rangeStartingMidDocumentReturnsTheTokensFromThatPosition() {
        #expect(loadedStorage().getTokensFor(range: range(1, 0, 4, 0)) == Array(tokens.dropFirst()))
    }

    @Test
    func tokensStartingBeforeTheRangeEndAreIncludedEvenWhenTheyExtendPastIt() {
        #expect(loadedStorage().getTokensFor(range: range(0, 0, 3, 9)) == tokens)
    }

    @Test
    func rangeAfterTheLastTokenHasNoTokens() {
        #expect(loadedStorage().getTokensFor(range: range(4, 0, 6, 0)).isEmpty)
    }

    @Test
    func rangeEndingBeforeTheFirstCandidateTokenEndsHasNoTokens() {
        #expect(loadedStorage().getTokensFor(range: range(0, 0, 0, 5)).isEmpty)
    }

    @Test
    func lowerBoundIsTheFirstTokenInsideTheRange() {
        let storage = loadedStorage()

        #expect(storage.findLowerBound(in: range(0, 0, 4, 0), data: tokens[...]) == 0)
        #expect(storage.findLowerBound(in: range(1, 0, 4, 0), data: tokens[...]) == 1)
        #expect(storage.findLowerBound(in: range(1, 3, 4, 0), data: tokens[...]) == 2)
        #expect(storage.findLowerBound(in: range(4, 0, 5, 0), data: tokens[...]) == nil)
        #expect(storage.findLowerBound(in: range(0, 0, 0, 5), data: tokens[...]) == nil)
        #expect(storage.findLowerBound(in: range(0, 0, 4, 0), data: ArraySlice<SemanticToken>()) == nil)
    }
}
