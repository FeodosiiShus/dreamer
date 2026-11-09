import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindEvaluateFileTests {
    private typealias Search = WorkspaceDocument.SearchState

    private static let virtualURL = URL(fileURLWithPath: "/tmp/FindEvaluateFileTests-virtual.txt")

    private func makeModel(
        find: String,
        replace: String = "",
        configure: (inout FindModel) -> Void = { _ in }
    ) -> FindModel {
        var model = FindModel()
        model.stringToFind = find
        model.stringToReplace = replace
        configure(&model)
        return model
    }

    private func evaluate(
        text: String,
        model: FindModel,
        withReplacements: Bool
    ) throws -> FileEvaluation {
        let regex = try #require(model.compileMatcher())
        return Search.evaluateFile(
            at: Self.virtualURL,
            model: model,
            regex: regex,
            withReplacements: withReplacements,
            unsavedText: text
        )
    }

    private func matches(_ evaluation: FileEvaluation) -> [SearchResultMatchModel] {
        let file = CEWorkspaceFile(url: Self.virtualURL)
        return evaluation.hits.map {
            SearchResultMatchModel(
                rangeWithinFile: $0.snapshot.rangeWithinFile,
                file: file,
                lineContent: $0.snapshot.lineContent,
                keywordRange: $0.snapshot.keywordRange,
                usage: $0.usage
            )
        }
    }

    private func previews(
        text: String,
        find: String,
        replace: String,
        withReplacements: Bool = true,
        configure: (inout FindModel) -> Void = { _ in }
    ) throws -> [SearchResultMatchModel] {
        let model = makeModel(find: find, replace: replace, configure: configure)
        return matches(try evaluate(text: text, model: model, withReplacements: withReplacements))
    }

    @Test
    func hitsCarrySnapshotsRangesAndOneBasedPositions() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try "alpha foo\n  beta foo gamma\n".write(to: url, atomically: true, encoding: .utf8)
            let model = makeModel(find: "foo")
            let regex = try #require(model.compileMatcher())

            let evaluation = Search.evaluateFile(at: url, model: model, regex: regex)

            #expect(evaluation.hits.count == 2)
            let first = try evaluation.hits.required(at: 0)
            #expect(first.snapshot.lineContent == "alpha foo")
            #expect(String(first.snapshot.lineContent[first.snapshot.keywordRange]) == "foo")
            #expect(first.usage.range == NSRange(location: 6, length: 3))
            #expect(first.usage.start == FindTextPosition(line: 1, column: 7))
            #expect(first.usage.end == FindTextPosition(line: 1, column: 10))
            #expect(first.usage.replacement == nil)

            let second = try evaluation.hits.required(at: 1)
            #expect(second.snapshot.lineContent == "beta foo gamma")
            #expect(String(second.snapshot.lineContent[second.snapshot.keywordRange]) == "foo")
            #expect(second.usage.range == NSRange(location: 17, length: 3))
            #expect(second.usage.start == FindTextPosition(line: 2, column: 8))
            #expect(second.usage.end == FindTextPosition(line: 2, column: 11))
        }
    }

    @Test
    func unsavedTextOverridesTheDiskContent() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "a.txt")
            try "foo".write(to: url, atomically: true, encoding: .utf8)
            let model = makeModel(find: "foo")
            let regex = try #require(model.compileMatcher())

            let fromDisk = Search.evaluateFile(at: url, model: model, regex: regex)
            let fromBuffer = Search.evaluateFile(at: url, model: model, regex: regex, unsavedText: "xx foo foo")
            let bufferOnly = Search.evaluateFile(at: url, model: model, regex: regex, unsavedText: "nothing")

            #expect(fromDisk.hits.count == 1)
            #expect(fromBuffer.hits.map(\.usage.range) == [NSRange(location: 3, length: 3), NSRange(location: 7, length: 3)])
            #expect(bufferOnly.hits.isEmpty)
        }
    }

    @Test
    func unreadableFilesYieldNoHits() throws {
        try withTempDir { dir in
            let model = makeModel(find: "foo")
            let regex = try #require(model.compileMatcher())

            let binaryExtension = dir.appending(path: "a.png")
            try "foo".write(to: binaryExtension, atomically: true, encoding: .utf8)
            let withNul = dir.appending(path: "nul.txt")
            try Data([0x66, 0x6F, 0x6F, 0x00]).write(to: withNul)
            let missing = dir.appending(path: "missing.txt")

            for url in [binaryExtension, withNul, missing] {
                #expect(Search.evaluateFile(at: url, model: model, regex: regex).hits.isEmpty)
            }
        }
    }

    @Test
    func zeroLengthMatchesAreSkipped() throws {
        let model = makeModel(find: "x*") { $0.isRegularExpressions = true }
        let evaluation = try evaluate(text: "axb", model: model, withReplacements: false)
        #expect(evaluation.hits.map(\.usage.range) == [NSRange(location: 1, length: 1)])
    }

    @Test
    func plainReplacementPreviewReplacesTheKeyword() throws {
        let found = try previews(text: "x foo y", find: "foo", replace: "bar")
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.replacementDisplay == "bar")
        #expect(match.replacementPreviewLine == "x bar y")
        #expect(match.usage?.replacement == "bar")
    }

    @Test
    func regexGroupPreviewSwapsTheGroups() throws {
        let found = try previews(text: "key=42", find: "(\\w+)=(\\d+)", replace: "$2=$1") {
            $0.isRegularExpressions = true
        }
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.replacementDisplay == "42=key")
        #expect(match.replacementPreviewLine == "42=key")
    }

    @Test
    func caseConversionPreviewUppercasesTheGroup() throws {
        let found = try previews(text: "key=42", find: "(\\w+)=", replace: "\\U$1\\E=") {
            $0.isRegularExpressions = true
        }
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.replacementDisplay == "KEY=")
        #expect(match.replacementPreviewLine == "KEY=42")
    }

    @Test
    func preserveCasePreviewFollowsEachMatch() throws {
        let found = try previews(text: "Foo FOO foo", find: "foo", replace: "bar") {
            $0.isPreserveCase = true
        }
        #expect(found.map(\.replacementDisplay) == ["Bar", "BAR", "bar"])
        #expect(found.map(\.replacementPreviewLine) == ["Bar FOO foo", "Foo BAR foo", "Foo FOO bar"])
    }

    @Test
    func newlineInTheReplacementIsShownWithTheLineBreakGlyph() throws {
        let found = try previews(text: "a;b", find: ";", replace: "\n")
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.usage?.replacement == "\n")
        #expect(match.replacementDisplay == "⏎")
        #expect(match.replacementPreviewLine == "a⏎b")
    }

    @Test
    func emptyReplacementPreviewDeletesTheKeyword() throws {
        let found = try previews(text: "a foo b", find: "foo", replace: "")
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.replacementDisplay == "")
        #expect(match.replacementPreviewLine == "a  b")
    }

    @Test
    func longReplacementPreviewIsTruncatedWithAnEllipsis() throws {
        let long = String(repeating: "z", count: FileMatchSnapshot.maxKeywordLength + 10)
        let found = try previews(text: "a foo b", find: "foo", replace: long)
        let expected = String(repeating: "z", count: FileMatchSnapshot.maxKeywordLength) + "…"
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.usage?.replacement == long)
        #expect(match.replacementDisplay == expected)
        #expect(match.replacementPreviewLine == "a " + expected + " b")
    }

    @Test
    func findModeHasNoReplacementPreview() throws {
        let found = try previews(text: "a foo b", find: "foo", replace: "bar", withReplacements: false)
        #expect(found.count == 1)
        let match = try found.required(at: 0)
        #expect(match.usage?.replacement == nil)
        #expect(match.replacementDisplay == nil)
        #expect(match.replacementPreviewLine == nil)
    }

    @Test
    func templateErrorLeavesNoPreview() throws {
        let found = try previews(text: "aa", find: "(a)", replace: "$5") {
            $0.isRegularExpressions = true
        }
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.replacementPreviewLine == nil })
    }

    @Test
    func replacementIssueIsNilForAValidTemplate() throws {
        let model = makeModel(find: "(a)", replace: "$1$1") { $0.isRegularExpressions = true }
        let regex = try #require(model.compileMatcher())
        #expect(Search.replacementIssue(for: model, regex: regex) == nil)
    }

    @Test
    func replacementIssueNamesAMissingGroup() throws {
        let model = makeModel(find: "(a)", replace: "$5") { $0.isRegularExpressions = true }
        let regex = try #require(model.compileMatcher())
        #expect(Search.replacementIssue(for: model, regex: regex) == "No group 5")
    }

    @Test
    func replacementIssueIgnoresPlainModels() throws {
        let model = makeModel(find: "(a)", replace: "$5")
        let regex = try #require(model.compileMatcher())
        #expect(Search.replacementIssue(for: model, regex: regex) == nil)
    }
}
