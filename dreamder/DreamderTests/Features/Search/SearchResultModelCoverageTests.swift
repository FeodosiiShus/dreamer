import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SearchResultModelCoverageTests {
    private func makeFile(_ name: String = "a.swift") -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func makeMatch(file: CEWorkspaceFile, line: String = "let value = 42") throws -> SearchResultMatchModel {
        let keywordRange = try #require(line.range(of: "value"))
        return SearchResultMatchModel(
            rangeWithinFile: keywordRange,
            file: file,
            lineContent: line,
            keywordRange: keywordRange
        )
    }

    @Test
    func initStoresFileScoreAndDefaultsToNoMatches() {
        let file = makeFile()
        let model = SearchResultModel(file: file, score: 0.5)
        #expect(model.file === file)
        #expect(model.score == 0.5)
        #expect(model.lineMatches.isEmpty)
    }

    @Test
    func initStoresGivenMatches() throws {
        let file = makeFile()
        let match = try makeMatch(file: file)
        let model = SearchResultModel(file: file, score: 1, lineMatches: [match])
        #expect(model.lineMatches == [match])
    }

    @Test
    func equalityComparesFileAndMatchesButNotScore() throws {
        let file = makeFile()
        let match = try makeMatch(file: file)
        let first = SearchResultModel(file: file, score: 1, lineMatches: [match])
        let twin = SearchResultModel(file: file, score: 9, lineMatches: [match])
        #expect(first == twin)

        twin.lineMatches = []
        #expect(first != twin)

        twin.lineMatches = [match]
        twin.file = makeFile("b.swift")
        #expect(first != twin)
    }

    @Test
    func equalModelsHashAlikeAndCollapseInSets() throws {
        let file = makeFile()
        let match = try makeMatch(file: file)
        let first = SearchResultModel(file: file, score: 1, lineMatches: [match])
        let twin = SearchResultModel(file: file, score: 2, lineMatches: [match])
        let other = SearchResultModel(file: makeFile("b.swift"), score: 1)

        #expect(first.hashValue == twin.hashValue)
        #expect(Set([first, twin, other]).count == 2)
    }
}
