import Foundation
import Testing
@testable import Dreamder

@Suite
struct FindModelTests {
    private func model(
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

    private func locations(of model: FindModel, in text: String) throws -> [Int] {
        let regex = try #require(model.compileMatcher())
        return model.findMatches(in: text, using: regex).map(\.range.location)
    }

    private func wholeWord(_ text: String, _ location: Int, _ length: Int) -> Bool {
        FindModel.isWholeWord(in: text as NSString, range: NSRange(location: location, length: length))
    }

    @Test
    func defaultsMatchIntelliJFindModel() {
        let model = FindModel()
        #expect(model.stringToFind.isEmpty)
        #expect(model.stringToReplace.isEmpty)
        #expect(model.isProjectScope)
        #expect(model.isWithSubdirectories)
        #expect(!model.isCaseSensitive)
        #expect(!model.isRegularExpressions)
        #expect(!model.isWholeWordsOnly)
        #expect(!model.isMultiline)
        #expect(!model.isPreserveCase)
        #expect(model.directoryName == nil)
        #expect(model.fileFilter == nil)
    }

    @Test
    func initStringToFindSetsMultilineWhenTheTextHasALineBreak() {
        var model = FindModel()
        model.initStringToFind("single line")
        #expect(model.stringToFind == "single line")
        #expect(!model.isMultiline)

        model.initStringToFind("first\nsecond")
        #expect(model.stringToFind == "first\nsecond")
        #expect(model.isMultiline)
    }

    @Test
    func initStringToFindIgnoresEmptyText() {
        var model = FindModel()
        model.stringToFind = "kept"
        model.initStringToFind("")
        model.initStringToFind(nil)
        #expect(model.stringToFind == "kept")
        #expect(!model.isMultiline)
    }

    @Test
    func compileRegExpIsCaseInsensitiveUnlessCaseSensitive() throws {
        let insensitive = try #require(model(find: "foo").compileRegExp())
        #expect(insensitive.firstMatch(in: "FOO", range: NSRange(location: 0, length: 3)) != nil)

        let caseSensitive = model(find: "foo") { $0.isCaseSensitive = true }
        let sensitive = try #require(caseSensitive.compileRegExp())
        #expect(sensitive.firstMatch(in: "FOO", range: NSRange(location: 0, length: 3)) == nil)
        #expect(sensitive.firstMatch(in: "foo", range: NSRange(location: 0, length: 3)) != nil)
    }

    @Test
    func compileRegExpAnchorsMatchAtLineBoundaries() throws {
        let regex = try #require(model(find: "^b$").compileRegExp())
        let text = "a\nb\nc"
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        #expect(matches.map(\.range.location) == [2])
    }

    @Test
    func compileRegExpReturnsNilForInvalidPatterns() {
        #expect(model(find: "(").compileRegExp() == nil)
        #expect(model(find: "[a-").compileRegExp() == nil)
    }

    @Test
    func compileMatcherIsNilForAnEmptyQuery() {
        #expect(model(find: "").compileMatcher() == nil)
        let regexModel = model(find: "") { $0.isRegularExpressions = true }
        #expect(regexModel.compileMatcher() == nil)
    }

    @Test
    func compileMatcherTreatsPlainTextLiterally() throws {
        let literal = model(find: "a.b(c)")
        #expect(try locations(of: literal, in: "xa.b(c) axb(c)") == [1])
    }

    @Test
    func compileMatcherInterpretsRegularExpressionsWhenEnabled() throws {
        let regex = model(find: "a.b") { $0.isRegularExpressions = true }
        #expect(try locations(of: regex, in: "a.b axb") == [0, 4])
    }

    @Test
    func compileMatcherHonoursTheWordAnchors() throws {
        let start = model(find: "foo") { $0.textAnchor = .wordStart }
        #expect(try locations(of: start, in: "foobar afoo foo") == [0, 12])

        let end = model(find: "foo") { $0.textAnchor = .wordEnd }
        #expect(try locations(of: end, in: "foobar afoo foo") == [8, 12])
    }

    @Test
    func wholeWordsOnlyRejectsMatchesInsideIdentifiers() throws {
        let words = model(find: "foo") { $0.isWholeWordsOnly = true }
        #expect(try locations(of: words, in: "foobar foo xfoo foo_ foo") == [7, 21])
    }

    @Test
    func wholeWordsOnlyResumesAfterARejectedMatch() throws {
        let words = model(find: "foo") { $0.isWholeWordsOnly = true }
        #expect(try locations(of: words, in: "foofoo foo") == [7])
    }

    @Test
    func isWholeWordFollowsFindManagerBase() {
        #expect(wholeWord("foo bar", 0, 3))
        #expect(!wholeWord("foobar", 0, 3))
        #expect(!wholeWord("foo_bar", 0, 3))
        #expect(!wholeWord("barfoo", 3, 3))
        #expect(wholeWord("(foo)", 1, 3))
        #expect(wholeWord("a.foo", 2, 3))
        #expect(wholeWord("foo", 0, 3))
    }

    @Test
    func isWholeWordTreatsAnEscapedLetterAsAWordBoundary() {
        #expect(wholeWord("\\nfoo", 2, 3))
        #expect(!wholeWord("nfoo", 1, 3))
    }

    @Test
    func isWholeWordForNonIdentifierMatchesComparesNeighbours() {
        #expect(!wholeWord("a+++b", 1, 2))
        #expect(wholeWord("a ++ b", 2, 2))
    }

    @Test
    func isWholeWordRejectsOutOfBoundsRanges() {
        #expect(!wholeWord("foo", 2, 5))
        #expect(!wholeWord("foo", -1, 2))
    }

    @Test
    func replaceAllSubstitutesLiteralText() throws {
        let literal = model(find: "ipsum", replace: "$1 dolor")
        let regex = try #require(literal.compileMatcher())
        let result = try literal.replaceAll(in: "Ipsum and IPSUM", using: regex)
        #expect(result.text == "$1 dolor and $1 dolor")
        #expect(result.replacedCount == 2)
    }

    @Test
    func replaceAllReturnsTheTextUntouchedWithoutMatches() throws {
        let literal = model(find: "zzz", replace: "x")
        let regex = try #require(literal.compileMatcher())
        let result = try literal.replaceAll(in: "abc", using: regex)
        #expect(result == FindModel.Replacement(text: "abc", replacedCount: 0))
    }

    @Test
    func replaceAllExpandsRegularExpressionTemplates() throws {
        let regexModel = model(find: "(\\w+)@(\\w+)", replace: "$2 at \\U$1\\E") { $0.isRegularExpressions = true }
        let regex = try #require(regexModel.compileMatcher())
        let result = try regexModel.replaceAll(in: "a@b and c@d", using: regex)
        #expect(result.text == "b at A and d at C")
        #expect(result.replacedCount == 2)
    }

    @Test
    func replaceAllInsertsAtZeroLengthMatches() throws {
        let regexModel = model(find: "^", replace: "// ") { $0.isRegularExpressions = true }
        let regex = try #require(regexModel.compileMatcher())
        let result = try regexModel.replaceAll(in: "a\nb", using: regex)
        #expect(result.text == "// a\n// b")
    }

    @Test
    func replaceAllAppliesPreserveCase() throws {
        let preserving = model(find: "foo", replace: "bar") { $0.isPreserveCase = true }
        let regex = try #require(preserving.compileMatcher())
        let result = try preserving.replaceAll(in: "Foo FOO foo", using: regex)
        #expect(result.text == "Bar BAR bar")
    }

    @Test
    func replaceAllAppliesPreserveCaseAfterTheRegularExpressionTemplate() throws {
        let combined = model(find: "(\\w+)-x", replace: "new_$1") {
            $0.isRegularExpressions = true
            $0.isPreserveCase = true
        }
        let regex = try #require(combined.compileMatcher())
        let result = try combined.replaceAll(in: "OLD-x", using: regex)
        #expect(result.text == "NEW_old")
    }

    @Test
    func replaceAllHonoursTheRestrictedRange() throws {
        let literal = model(find: "foo", replace: "x")
        let regex = try #require(literal.compileMatcher())
        let result = try literal.replaceAll(in: "foo foo foo", using: regex, range: NSRange(location: 4, length: 3))
        #expect(result.text == "foo x foo")
        #expect(result.replacedCount == 1)
    }

    @Test
    func replaceAllRespectsWholeWordsOnly() throws {
        let words = model(find: "foo", replace: "x") { $0.isWholeWordsOnly = true }
        let regex = try #require(words.compileMatcher())
        let result = try words.replaceAll(in: "foobar foo", using: regex)
        #expect(result.text == "foobar x")
        #expect(result.replacedCount == 1)
    }

    @Test
    func replaceAllThrowsForMalformedTemplates() throws {
        let broken = model(find: "(a)", replace: "$9") { $0.isRegularExpressions = true }
        let regex = try #require(broken.compileMatcher())
        #expect(throws: RegexReplacement.TemplateError.self) {
            try broken.replaceAll(in: "a", using: regex)
        }
    }

    @Test
    func noRestartIsNeededWhenOnlyReplacementFieldsDiffer() {
        let old = model(find: "foo", replace: "a")
        var changedReplacement = old
        changedReplacement.stringToReplace = "b"
        changedReplacement.isPreserveCase = true
        changedReplacement.isReplaceState = true
        #expect(changedReplacement.noRestartSearchNeeded(comparedTo: old))
        #expect(old.noRestartSearchNeeded(comparedTo: old))
    }

    @Test
    func restartIsNeededWhenASearchFieldDiffers() {
        let old = model(find: "foo")
        var changed = old
        changed.isCaseSensitive = true
        #expect(!changed.noRestartSearchNeeded(comparedTo: old))

        changed = old
        changed.stringToFind = "bar"
        #expect(!changed.noRestartSearchNeeded(comparedTo: old))

        changed = old
        changed.fileFilter = "*.swift"
        #expect(!changed.noRestartSearchNeeded(comparedTo: old))
    }

    @Test
    func projectScopeHasNoDirectoryScope() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let withDirectoryOnly = model(find: "x") { $0.directoryName = "src" }
        #expect(withDirectoryOnly.makeScope(projectRoot: root) == nil)

        let blankDirectory = model(find: "x") {
            $0.isProjectScope = false
            $0.directoryName = "  "
        }
        #expect(blankDirectory.makeScope(projectRoot: root) == nil)

        let missingDirectory = model(find: "x") { $0.isProjectScope = false }
        #expect(missingDirectory.makeScope(projectRoot: root) == nil)
    }

    @Test
    func directoryScopeIncludesSubdirectoriesByDefault() throws {
        let root = URL(fileURLWithPath: "/tmp/project")
        let scoped = model(find: "x") {
            $0.isProjectScope = false
            $0.directoryName = "src"
        }
        let scope = try #require(scoped.makeScope(projectRoot: root))
        #expect(scope.contains(URL(fileURLWithPath: "/tmp/project/src/a.swift")))
        #expect(scope.contains(URL(fileURLWithPath: "/tmp/project/src/deep/er/a.swift")))
        #expect(!scope.contains(URL(fileURLWithPath: "/tmp/project/srcx/a.swift")))
        #expect(!scope.contains(URL(fileURLWithPath: "/tmp/project/a.swift")))
    }

    @Test
    func directoryScopeWithoutSubdirectoriesOnlyMatchesDirectChildren() throws {
        let root = URL(fileURLWithPath: "/tmp/project")
        let scoped = model(find: "x") {
            $0.isProjectScope = false
            $0.directoryName = "src"
            $0.isWithSubdirectories = false
        }
        let scope = try #require(scoped.makeScope(projectRoot: root))
        #expect(scope.contains(URL(fileURLWithPath: "/tmp/project/src/a.swift")))
        #expect(!scope.contains(URL(fileURLWithPath: "/tmp/project/src/deep/a.swift")))
    }

    @Test
    func absoluteDirectoryNamesIgnoreTheProjectRoot() throws {
        let scoped = model(find: "x") {
            $0.isProjectScope = false
            $0.directoryName = "/var/data"
        }
        let scope = try #require(scoped.makeScope(projectRoot: URL(fileURLWithPath: "/tmp/project")))
        #expect(scope.contains(URL(fileURLWithPath: "/var/data/a.txt")))
        #expect(!scope.contains(URL(fileURLWithPath: "/tmp/project/data/a.txt")))
    }

    @Test
    func acceptsCombinesScopeAndFileMask() throws {
        let root = URL(fileURLWithPath: "/tmp/project")
        let scoped = model(find: "x") {
            $0.isProjectScope = false
            $0.directoryName = "src"
        }
        let scope = try #require(scoped.makeScope(projectRoot: root))
        let mask = try FileMask(filter: "*.swift, !*Tests.swift")
        #expect(scoped.accepts(URL(fileURLWithPath: "/tmp/project/src/a.swift"), scope: scope, mask: mask))
        #expect(!scoped.accepts(URL(fileURLWithPath: "/tmp/project/src/aTests.swift"), scope: scope, mask: mask))
        #expect(!scoped.accepts(URL(fileURLWithPath: "/tmp/project/lib/a.swift"), scope: scope, mask: mask))
        #expect(scoped.accepts(URL(fileURLWithPath: "/tmp/project/lib/a.swift"), scope: nil, mask: mask))
    }
}
