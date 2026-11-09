import Foundation
import Testing
@testable import Dreamder

@Suite("FindModel coverage")
struct FindModelCoverageTests {
    @Test
    func rangeAtTheEndOfTheTextStartsAWordWhenThePreviousCharacterIsNotIdentifier() {
        #expect(FindModel.isWholeWord(in: "foo " as NSString, range: NSRange(location: 4, length: 0)))
    }

    @Test
    func rangeAtTheEndOfTheTextDoesNotStartAWordAfterAnIdentifierCharacter() {
        #expect(!FindModel.isWholeWord(in: "foo" as NSString, range: NSRange(location: 3, length: 0)))
    }

    @Test
    func relativeDirectoryWithoutProjectRootResolvesAgainstTheWorkingDirectory() throws {
        var model = FindModel()
        model.isProjectScope = false
        model.directoryName = "relative-src"
        let scope = try #require(model.makeScope(projectRoot: nil))
        let expected = URL(fileURLWithPath: "relative-src", isDirectory: true).standardizedFileURL.path
        #expect(scope.directoryPaths.first == expected)
    }

    @Test
    func directoryScopeKeepsTheSymlinkAndItsResolvedTarget() throws {
        try withTempDir { dir in
            let real = dir.appending(path: "real", directoryHint: .isDirectory)
            let link = dir.appending(path: "link", directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            var model = FindModel()
            model.isProjectScope = false
            model.directoryName = link.path
            let scope = try #require(model.makeScope(projectRoot: nil))
            #expect(scope.directoryPaths.count == 2)
            #expect(scope.directoryPaths.contains { $0.hasSuffix("/real") })
            #expect(scope.contains(link.appending(path: "a.txt")))
        }
    }
}

@Suite("PreserveCase coverage")
struct PreserveCaseCoverageTests {
    @Test
    func singleCharacterFoundStringOnlyAdjustsTheFirstLetter() {
        #expect(PreserveCase.replaceWithCaseRespect("foo", foundString: "A") == "Foo")
        #expect(PreserveCase.replaceWithCaseRespect("FOO", foundString: "a") == "fOO")
    }
}

@Suite("RegexReplacement coverage")
struct RegexReplacementCoverageTests {
    private func replace(pattern: String, in text: String, with template: String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        let match = try #require(regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)))
        return try RegexReplacement.createReplacement(template: template, match: match, in: nsText, regex: regex)
    }

    @Test
    func caseRegionRestartedAtTheSameOffsetTakesTheLastDirection() throws {
        #expect(try replace(pattern: "(\\w+)", in: "JOHN", with: "\\U\\L$1") == "john")
        #expect(try replace(pattern: "(\\w+)", in: "john", with: "\\L\\U$1") == "JOHN")
    }
}

@MainActor
@Suite("SearchModeModel coverage", .uiGate)
struct SearchModeModelCoverageTests {
    @Test
    func modeKindPredicates() {
        #expect([SearchModeModel.Replace, .Text, .Containing].isReplaceMode)
        #expect(![SearchModeModel.Find, .Text, .Containing].isReplaceMode)
        #expect(![SearchModeModel]().isReplaceMode)
        #expect([SearchModeModel.Find, .RegularExpression].isRegularExpressionMode)
        #expect(![SearchModeModel.Find].isRegularExpressionMode)
        #expect(![SearchModeModel.Find, .Text, .Containing].isRegularExpressionMode)
    }

    @Test
    func matchingModeIsTheThirdElement() {
        #expect([SearchModeModel.Find, .Text, .MatchingWord].matchingMode == .MatchingWord)
        #expect([SearchModeModel.Find, .RegularExpression].matchingMode == nil)
    }

    @Test
    func switchingRegularExpressionKeepsTheModeKind() {
        #expect([SearchModeModel.Replace, .Text, .Containing].switchingRegularExpression(true) == [.Replace, .RegularExpression])
        #expect([SearchModeModel.Replace, .RegularExpression].switchingRegularExpression(false) == [.Replace, .Text, .Containing])
    }

    @Test
    func switchingRegularExpressionOnAnEmptySelectionDefaultsToFind() {
        let empty = [SearchModeModel]()
        #expect(empty.switchingRegularExpression(true) == [.Find, .RegularExpression])
        #expect(empty.switchingRegularExpression(false) == [.Find, .Text, .Containing])
    }

    @Test
    func switchingMatchingModeReplacesTheThirdElementOnly() {
        #expect([SearchModeModel.Find, .Text, .Containing].switchingMatchingMode(.EndingWith) == [.Find, .Text, .EndingWith])
        #expect([SearchModeModel.Replace].switchingMatchingMode(.EndingWith) == [.Replace])
    }

    @Test
    func equalityComparesTitleChildrenAndHighlight() {
        #expect(SearchModeModel.Text == SearchModeModel.Text)
        #expect(SearchModeModel.Text != SearchModeModel.References)
        let renamed = SearchModeModel(title: "Text", children: [], needSelectionHighlight: false)
        #expect(renamed != SearchModeModel.Text)
        let highlighted = SearchModeModel(title: "Containing", children: [], needSelectionHighlight: true)
        #expect(highlighted != SearchModeModel.Containing)
        #expect(Set([SearchModeModel.Find, .Find, .Replace]).count == 2)
    }

    @Test
    func modeListsMatchTheFindMenus() {
        #expect(SearchModeModel.SearchModes == [.Find, .Replace])
        #expect(SearchModeModel.ReplaceModes == [.Text, .RegularExpression])
        #expect(SearchModeModel.TextMatchingModes == [.Containing, .MatchingWord, .StartingWith, .EndingWith])
        #expect(SearchModeModel.FindModes == [.Text, .References, .Definitions, .RegularExpression, .CallHierarchy])
        #expect(SearchModeModel.Find.children == SearchModeModel.FindModes)
        #expect(SearchModeModel.Replace.children == SearchModeModel.ReplaceModes)
    }
}

@Suite("String lengthOfMatchingPrefix coverage")
struct LengthOfMatchingPrefixCoverageTests {
    private let accented = FuzzySearchCharacter(content: "É", normalisedContent: "e")

    @Test
    func indexPastTheEndHasNoMatch() {
        #expect("hello".lengthOfMatchingPrefix(prefix: accented, startingAt: 99) == nil)
    }

    @Test
    func contentIsPreferredAndNormalisedContentIsTheFallback() {
        #expect("Éa".lengthOfMatchingPrefix(prefix: accented, startingAt: 0) == 1)
        #expect("ea".lengthOfMatchingPrefix(prefix: accented, startingAt: 0) == 1)
        #expect("xea".lengthOfMatchingPrefix(prefix: accented, startingAt: 1) == 1)
        #expect("xea".lengthOfMatchingPrefix(prefix: accented, startingAt: 0) == nil)
    }
}
