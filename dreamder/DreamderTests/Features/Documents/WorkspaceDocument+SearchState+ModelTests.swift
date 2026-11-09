import XCTest
@testable import Dreamder

@MainActor
final class SearchStateModelTests: XCTestCase {
    private var directory: URL!
    private var workspace: WorkspaceDocument!
    private var searchState: WorkspaceDocument.SearchState!

    override func setUp() async throws {
        directory = try makeTempDirectory()
        workspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
        searchState = workspace.searchState

        let startTime = Date()
        while searchState.indexStatus != .done, Date().timeIntervalSince(startTime) < 2.0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDefaultsDescribeAPlainProjectSearch() {
        XCTAssertEqual(searchState.selectedMode, [.Find, .Text, .Containing])
        XCTAssertFalse(searchState.caseSensitive)
        XCTAssertFalse(searchState.isRegularExpression)
        XCTAssertFalse(searchState.wholeWordsOnly)
        XCTAssertEqual(searchState.directoryScopePath, "")
        XCTAssertEqual(searchState.fileMask, "")
        XCTAssertEqual(searchState.scopeDescription, "Project")
    }

    func testCaseSensitiveForwardsToTheFindModel() {
        searchState.caseSensitive = true
        XCTAssertTrue(searchState.findModel.isCaseSensitive)

        searchState.findModel.isCaseSensitive = false
        XCTAssertFalse(searchState.caseSensitive)
    }

    func testRegularExpressionToggleKeepsTheFindOrReplaceKind() {
        searchState.selectedMode = [.Replace, .Text, .Containing]

        searchState.isRegularExpression = true
        XCTAssertEqual(searchState.selectedMode, [.Replace, .RegularExpression])
        XCTAssertTrue(searchState.isRegularExpression)

        searchState.isRegularExpression = true
        XCTAssertEqual(searchState.selectedMode, [.Replace, .RegularExpression])

        searchState.isRegularExpression = false
        XCTAssertEqual(searchState.selectedMode, [.Replace, .Text, .Containing])

        searchState.isRegularExpression = false
        XCTAssertEqual(searchState.selectedMode, [.Replace, .Text, .Containing])
    }

    func testWholeWordsFollowsTheMatchingWordMode() {
        searchState.selectedMode[2] = .MatchingWord
        XCTAssertTrue(searchState.wholeWordsOnly)

        searchState.wholeWordsOnly = false
        XCTAssertFalse(searchState.wholeWordsOnly)
        XCTAssertFalse(searchState.findModel.isWholeWordsOnly)
        XCTAssertEqual(searchState.selectedMode, [.Find, .Text, .Containing])
    }

    func testWholeWordsToggleLeavesOtherMatchingModesAlone() {
        searchState.selectedMode[2] = .StartingWith

        searchState.wholeWordsOnly = true
        XCTAssertTrue(searchState.wholeWordsOnly)
        XCTAssertTrue(searchState.findModel.isWholeWordsOnly)
        XCTAssertEqual(searchState.selectedMode.third, .StartingWith)

        searchState.wholeWordsOnly = false
        XCTAssertFalse(searchState.wholeWordsOnly)
        XCTAssertEqual(searchState.selectedMode.third, .StartingWith)
    }

    func testWholeWordsToggleIsSafeInRegularExpressionMode() {
        searchState.selectedMode = [.Find, .RegularExpression]

        searchState.wholeWordsOnly = false
        XCTAssertFalse(searchState.wholeWordsOnly)
        XCTAssertEqual(searchState.selectedMode, [.Find, .RegularExpression])
    }

    func testDirectoryScopePathMapsEmptyTextToNil() {
        searchState.directoryScopePath = "src"
        XCTAssertEqual(searchState.findModel.directoryName, "src")
        XCTAssertEqual(searchState.directoryScopePath, "src")

        searchState.directoryScopePath = ""
        XCTAssertNil(searchState.findModel.directoryName)
        XCTAssertEqual(searchState.directoryScopePath, "")
    }

    func testFileMaskMapsEmptyTextToNil() {
        searchState.fileMask = "*.swift"
        XCTAssertEqual(searchState.findModel.fileFilter, "*.swift")
        XCTAssertEqual(searchState.fileMask, "*.swift")

        searchState.fileMask = ""
        XCTAssertNil(searchState.findModel.fileFilter)
        XCTAssertEqual(searchState.fileMask, "")
    }

    func testScopeDescriptionNamesTheDirectoryOnlyForDirectoryScope() {
        searchState.directoryScopePath = "src"
        XCTAssertEqual(searchState.scopeDescription, "Project")

        searchState.findModel.isProjectScope = false
        XCTAssertEqual(searchState.scopeDescription, "src")

        searchState.directoryScopePath = ""
        XCTAssertEqual(searchState.scopeDescription, "Project")
    }

    func testMakeFindModelCopiesTheTogglesAndTheMode() {
        searchState.caseSensitive = true
        searchState.findModel.isPreserveCase = true
        searchState.findModel.isProjectScope = false
        searchState.directoryScopePath = "src"
        searchState.findModel.isWithSubdirectories = false
        searchState.fileMask = "*.swift"
        searchState.replaceText = "stored"
        searchState.selectedMode = [.Replace, .Text, .MatchingWord]

        let model = searchState.makeFindModel(query: "needle")
        XCTAssertEqual(model.stringToFind, "needle")
        XCTAssertEqual(model.stringToReplace, "stored")
        XCTAssertTrue(model.isReplaceState)
        XCTAssertTrue(model.isCaseSensitive)
        XCTAssertTrue(model.isPreserveCase)
        XCTAssertTrue(model.isWholeWordsOnly)
        XCTAssertFalse(model.isRegularExpressions)
        XCTAssertFalse(model.isMultiline)
        XCTAssertFalse(model.isProjectScope)
        XCTAssertEqual(model.directoryName, "src")
        XCTAssertFalse(model.isWithSubdirectories)
        XCTAssertEqual(model.fileFilter, "*.swift")
        XCTAssertEqual(model.textAnchor, .anywhere)
    }

    func testMakeFindModelPrefersTheExplicitReplacement() {
        searchState.replaceText = "stored"
        XCTAssertEqual(searchState.makeFindModel(query: "a", replacement: "explicit").stringToReplace, "explicit")
        XCTAssertEqual(searchState.makeFindModel(query: "a", replacement: "").stringToReplace, "")
        XCTAssertFalse(searchState.makeFindModel(query: "a").isReplaceState)
    }

    func testMakeFindModelMapsTheWordAnchors() {
        searchState.selectedMode[2] = .StartingWith
        XCTAssertEqual(searchState.makeFindModel(query: "a").textAnchor, .wordStart)

        searchState.selectedMode[2] = .EndingWith
        XCTAssertEqual(searchState.makeFindModel(query: "a").textAnchor, .wordEnd)

        searchState.selectedMode[2] = .Containing
        XCTAssertEqual(searchState.makeFindModel(query: "a").textAnchor, .anywhere)
    }

    func testMakeFindModelIgnoresWordOptionsInRegularExpressionMode() {
        searchState.selectedMode[2] = .EndingWith
        searchState.findModel.isWholeWordsOnly = true
        searchState.isRegularExpression = true

        let model = searchState.makeFindModel(query: "a.b")
        XCTAssertTrue(model.isRegularExpressions)
        XCTAssertFalse(model.isWholeWordsOnly)
        XCTAssertEqual(model.textAnchor, .anywhere)
    }

    func testMakeFindModelEnablesMultilineForTextWithLineBreaks() {
        XCTAssertTrue(searchState.makeFindModel(query: "a\nb").isMultiline)
        XCTAssertFalse(searchState.makeFindModel(query: "ab").isMultiline)
        XCTAssertFalse(searchState.findModel.isMultiline)

        searchState.findModel.isMultiline = true
        XCTAssertTrue(searchState.makeFindModel(query: "ab").isMultiline)
    }

    func testGetRegexPatternReturnsTheRawQueryInRegularExpressionMode() {
        searchState.isRegularExpression = true
        XCTAssertEqual(searchState.getRegexPattern("  a.+b "), "  a.+b ")
    }

    func testClearResultsResetsTheCounts() {
        searchState.searchResultsCount = 4
        searchState.searchResultsFileCount = 2
        searchState.searchResult = [SearchResultModel(file: CEWorkspaceFile(url: directory), score: 1)]
        searchState.findNavigatorStatus = .found

        searchState.clearResults()

        XCTAssertTrue(searchState.searchResult.isEmpty)
        XCTAssertEqual(searchState.searchResultsCount, 0)
        XCTAssertEqual(searchState.searchResultsFileCount, 0)
        XCTAssertEqual(searchState.findNavigatorStatus, .none)
    }

    func testEmptyQueryProducesAnEmptyFoundState() async {
        searchState.searchResultsCount = 3
        await searchState.search("")

        XCTAssertEqual(searchState.findNavigatorStatus, .found)
        XCTAssertEqual(searchState.searchResultsCount, 0)
        XCTAssertTrue(searchState.searchResult.isEmpty)
    }

    func testInvalidFileMaskCannotFailBecauseEveryMetacharacterIsEscaped() async {
        searchState.fileMask = "[(*.{"
        await searchState.search("anything")
        XCTAssertEqual(searchState.findNavigatorStatus, .found)
    }

    func testSearchFailsWithoutAProject() async {
        workspace.tearDownFileScope()
        await searchState.search("anything")
        XCTAssertEqual(searchState.findNavigatorStatus, .failed(errorMessage: "No project is open."))
        XCTAssertTrue(searchState.searchResult.isEmpty)
    }
}
