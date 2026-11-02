import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP definition mapping")
struct LSPDefinitionMappingTests {
    private let range = LSPRange(start: Position(line: 4, character: 8), end: Position(line: 4, character: 12))
    private let uri = "file:///tmp/project/Sources/Model.swift"

    @Test func mapsSingleLocation() {
        let targets = LSPDefinitionMapping.targets(from: .optionA(Location(uri: uri, range: range)))
        #expect(targets == [LSPDefinitionTarget(uri: uri, range: range, selectionRange: range)])
    }

    @Test func mapsLocationArrays() {
        let second = Location(uri: "file:///tmp/project/Sources/Other.swift", range: .zero)
        let targets = LSPDefinitionMapping.targets(from: .optionB([Location(uri: uri, range: range), second]))
        #expect(targets.count == 2)
        #expect(targets[0].uri == uri)
        #expect(targets[1].uri == second.uri)
        #expect(targets[1].selectionRange == .zero)
    }

    @Test func mapsLocationLinksToSelectionRange() {
        let fullRange = LSPRange(start: Position(line: 0, character: 0), end: Position(line: 20, character: 1))
        let link = LocationLink(
            originSelectionRange: nil,
            targetUri: uri,
            targetRange: fullRange,
            targetSelectionRange: range
        )
        let targets = LSPDefinitionMapping.targets(from: .optionC([link]))
        #expect(targets.count == 1)
        #expect(targets[0].range == fullRange)
        #expect(targets[0].selectionRange == range)
    }

    @Test func mapsEmptyResponse() {
        #expect(LSPDefinitionMapping.targets(from: nil).isEmpty)
    }
}
