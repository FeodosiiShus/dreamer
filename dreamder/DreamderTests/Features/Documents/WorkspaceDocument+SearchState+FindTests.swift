//
//  WorkspaceDocument+SearchState+FindTests.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 26.01.24.
//

import XCTest
@testable import Dreamder

@MainActor
final class FindTests: XCTestCase {
    private var directory: URL!
    private var files: [CEWorkspaceFile] = []
    private var mockWorkspace: WorkspaceDocument!
    private var searchState: WorkspaceDocument.SearchState!

    // MARK: - Setup
    /// A mock WorkspaceDocument is created
    /// 3 mock files are added to the index
    /// which will be removed in the teardown function
    override func setUp() async throws {
        directory = try makeTempDirectory()

        mockWorkspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
        searchState = mockWorkspace.searchState

        // Add a few files
        let folder1 = directory.appending(path: "Folder 2")
        let folder2 = directory.appending(path: "Longer Folder With Some 💯 Special Chars ⁉️")
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)

        let fileURLs = [
            directory.appending(path: "File 1.txt"),
            folder1.appending(path: "Documentation.docc"),
            folder2.appending(path: "Makefile")
        ]

        for index in 0..<fileURLs.count {
            if index % 2 == 0 {
                try String("Loren Ipsum.").write(to: fileURLs[index], atomically: true, encoding: .utf8)
            } else {
                try String("Aperiam*asperiores").write(to: fileURLs[index], atomically: true, encoding: .utf8)
            }
        }

        files = fileURLs.map { CEWorkspaceFile(url: $0) }

        let parent1 = CEWorkspaceFile(url: folder1)
        let parent2 = CEWorkspaceFile(url: folder2)
        files[1].parent = parent1
        files[2].parent = parent2

        mockWorkspace.searchState?.addProjectToIndex()

        // The following code also tests whether the workspace is indexed correctly
        // Wait until the index is up to date and flushed
        let startTime = Date()
        let timeoutInSeconds = 2.0
        while searchState.indexStatus != .done {
            // Check every 0.1 seconds for index completion
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            if Date().timeIntervalSince(startTime) > timeoutInSeconds {
                XCTFail("TIMEOUT: Indexing took to long or did not complete.")
                return
            }
        }

        // Retrieve indexed documents from the indexer
        guard let documentsInIndex = searchState.indexer?.documents() else {
            XCTFail("No documents are in the index")
            return
        }

        // Verify that the setup function added the expected number of mock files to the index
        XCTAssertEqual(documentsInIndex.count, 3)
    }

    // MARK: - Tear down
    /// The mock directory along with the mock files will be removed
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testGetSearchTerm() {
        let query = "test*/Quer@#y"

        searchState.selectedMode[2] = .Containing
        XCTAssertEqual(searchState.getSearchTerm(query), "*test*quer*y*")

        searchState.selectedMode[2] = .StartingWith
        XCTAssertEqual(searchState.getSearchTerm(query), "test*quer*y*")

        searchState.selectedMode[2] = .EndingWith
        XCTAssertEqual(searchState.getSearchTerm(query), "*test*quer*y")

        searchState.selectedMode[2] = .MatchingWord
        XCTAssertEqual(searchState.getSearchTerm(query), "test*quer*y")

        searchState.caseSensitive = true
        XCTAssertEqual(searchState.getSearchTerm(query), "test*Quer*y")
    }

    func testStripSpecialCharacters() {
        let string = "test!@#Query"
        let strippedString = searchState.stripSpecialCharacters(from: string)
        XCTAssertEqual(strippedString, "test*Query")
    }

    func testGetRegexPattern() {
        let query = "@(test. !*#Query"

        searchState.selectedMode[2] = .Containing
        XCTAssertEqual(searchState.getRegexPattern(query), "@\\(test\\. !\\*#Query")

        searchState.selectedMode[2] = .StartingWith
        XCTAssertEqual(searchState.getRegexPattern(query), "\\b@\\(test\\. !\\*#Query")

        searchState.selectedMode[2] = .EndingWith
        XCTAssertEqual(searchState.getRegexPattern(query), "@\\(test\\. !\\*#Query\\b")

        searchState.selectedMode[2] = .MatchingWord
        XCTAssertEqual(searchState.getRegexPattern(query), "\\b@\\(test\\. !\\*#Query\\b")

        // Enabling case sensitivity shouldn't affect the regex pattern because if case sensitivity is enabled,
        // `NSRegularExpression.Options.caseInsensitive` is passed to `NSRegularExpression`.
        searchState.caseSensitive = true
        XCTAssertEqual(searchState.getRegexPattern(query), "\\b@\\(test\\. !\\*#Query\\b")
    }

    /// Tests the search functionality of the `WorkspaceDocument.SearchState` and `SearchIndexer`.
    func testSearch() async {
        await searchState.search("Ipsum")
        // Wait for the first search expectation to be fulfilled
        await waitForExpectation {
            searchState.searchResult.count == 2
        } onTimeout: {
            XCTFail("Search state did not find two results.")
        }

        await searchState.search("asperiores")
        await waitForExpectation {
            searchState.searchResult.count == 1
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }
    }

    /// Checks if the search still returns proper results,
    /// if the search term isn't a complete word
    func testSearchWithOptionContaining() async {
        await searchState.search("psu")
        await waitForExpectation {
            searchState.searchResult.count == 2
        } onTimeout: {
            XCTFail("Search state did not find two results.")
        }

        await searchState.search("erio")
        await waitForExpectation {
            searchState.searchResult.count == 1
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }
    }

    /// This test verifies the accuracy of the word search feature.
    /// It first checks for the presence of 'Ipsum,' as done in previous tests.
    /// Following that, it examines the occurrence of the fragment 'perior,'
    /// which is not a complete word in any of the documents
    func testSearchWithOptionMatchingWord() async {
        // Set the search option to 'Matching Word'
        searchState.selectedMode[2] = .MatchingWord

        await searchState.search("Ipsum")
        await waitForExpectation {
            searchState.searchResult.count == 2
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }

        // Check if incomplete words return no search results.
        await searchState.search("perior")
        await waitForExpectation {
            searchState.searchResult.isEmpty
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }
    }

    func testSearchWithOptionStartingWith() async {
        // Set the search option to 'Starting With'
        searchState.selectedMode[2] = .StartingWith

        await searchState.search("Ip")
        await waitForExpectation {
            searchState.searchResult.count == 2
        } onTimeout: {
            XCTFail("Search state did not find two results.")
        }

        await searchState.search("res")
        await waitForExpectation {
            searchState.searchResult.isEmpty
        } onTimeout: {
            XCTFail("Search state did not find two results.")
        }
    }

    func testSearchWithOptionEndingWith() async {
        // Set the search option to 'Ending with'
        searchState.selectedMode[2] = .EndingWith

        await searchState.search("um")
        await waitForExpectation {
            searchState.searchResult.count == 2
        } onTimeout: {
            XCTFail("Search state did not find two results.")
        }

        await searchState.search("asperi")
        await waitForExpectation {
            searchState.searchResult.isEmpty
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }
    }

    func testSearchWithOptionCaseSensitive() async {
        searchState.caseSensitive = true
        await searchState.search("ipsum")
        // Wait for the first search expectation to be fulfilled
        await waitForExpectation {
            // Expecting a result count of 0 due to the intentional use of a lowercase 'i'
            searchState.searchResult.isEmpty
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }

        await searchState.search("Asperiores")
        await waitForExpectation {
            // Anticipating zero results since the search is case-sensitive and we used an uppercase 'A'
            searchState.searchResult.isEmpty
        } onTimeout: {
            XCTFail("Search state did not find correct results.")
        }
    }

    func testSearchWithOptionRegularExpression() async {
        searchState.selectedMode = [.Find, .RegularExpression]

        await searchState.search("Ip\\w+m")
        XCTAssertEqual(searchState.findNavigatorStatus, .found)
        XCTAssertEqual(searchState.searchResult.count, 2)
        XCTAssertEqual(searchState.searchResultsCount, 2)

        await searchState.search("\\w+res$")
        XCTAssertEqual(searchState.searchResult.count, 1)
        XCTAssertEqual(searchState.searchResult.first?.file.url.lastPathComponent, "Documentation.docc")

        await searchState.search("A\\w+m\\*asp")
        XCTAssertEqual(searchState.searchResult.count, 1)

        await searchState.search("^Loren")
        XCTAssertEqual(searchState.searchResult.count, 2)
    }

    func testRegularExpressionWithoutIndexableWordsScansTheWorkspace() async {
        searchState.selectedMode = [.Find, .RegularExpression]

        await searchState.search("\\.$")
        XCTAssertEqual(searchState.searchResult.count, 2)
        XCTAssertEqual(searchState.searchResultsCount, 2)

        await searchState.search("[*]")
        XCTAssertEqual(searchState.searchResult.count, 1)
    }

    func testRegularExpressionIsCaseInsensitiveUnlessMatchCaseIsOn() async {
        searchState.selectedMode = [.Find, .RegularExpression]

        await searchState.search("ip.um")
        XCTAssertEqual(searchState.searchResult.count, 2)

        searchState.caseSensitive = true
        await searchState.search("ip.um")
        XCTAssertTrue(searchState.searchResult.isEmpty)

        await searchState.search("Ip.um")
        XCTAssertEqual(searchState.searchResult.count, 2)
    }

    func testInvalidRegularExpressionFailsTheSearch() async {
        searchState.selectedMode = [.Find, .RegularExpression]

        await searchState.search("Ips(")
        XCTAssertEqual(searchState.findNavigatorStatus, .failed(errorMessage: "Invalid regular expression."))
        XCTAssertTrue(searchState.searchResult.isEmpty)
    }

    func testSearchHighlightsTheRegularExpressionMatch() async throws {
        searchState.selectedMode = [.Find, .RegularExpression]

        await searchState.search("Ip\\w+m")
        let result = try XCTUnwrap(searchState.searchResult.first)
        let match = try XCTUnwrap(result.lineMatches.first)
        XCTAssertEqual(String(match.lineContent[match.keywordRange]), "Ipsum")
        XCTAssertEqual(match.lineContent, "Loren Ipsum.")
    }

    func testWholeWordsOptionIsIndependentOfTheTextMode() async {
        searchState.wholeWordsOnly = true
        XCTAssertTrue(searchState.wholeWordsOnly)

        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 2)

        await searchState.search("psum")
        XCTAssertTrue(searchState.searchResult.isEmpty)

        searchState.wholeWordsOnly = false
        await searchState.search("psum")
        XCTAssertEqual(searchState.searchResult.count, 2)
    }

    func testRegularExpressionToggleSwitchesTheSelectedMode() {
        searchState.isRegularExpression = true
        XCTAssertEqual(searchState.selectedMode, [.Find, .RegularExpression])
        XCTAssertEqual(searchState.getRegexPattern("a.b"), "a.b")

        searchState.isRegularExpression = false
        XCTAssertEqual(searchState.selectedMode, [.Find, .Text, .Containing])
        XCTAssertEqual(searchState.getRegexPattern("a.b"), "a\\.b")
    }

    func testDirectoryScopeLimitsTheSearch() async {
        searchState.findModel.isProjectScope = false
        searchState.directoryScopePath = "Folder 2"

        await searchState.search("asperiores")
        XCTAssertEqual(searchState.searchResult.count, 1)

        await searchState.search("Ipsum")
        XCTAssertTrue(searchState.searchResult.isEmpty)

        searchState.findModel.isProjectScope = true
        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 2)
    }

    func testDirectoryScopeWithoutSubdirectoriesOnlySearchesDirectChildren() async {
        searchState.findModel.isProjectScope = false
        searchState.directoryScopePath = directory.path
        searchState.findModel.isWithSubdirectories = false

        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 1)
        XCTAssertEqual(searchState.searchResult.first?.file.url.lastPathComponent, "File 1.txt")

        searchState.findModel.isWithSubdirectories = true
        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 2)
    }

    func testFileMaskLimitsTheSearch() async {
        searchState.fileMask = "*.txt"
        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 1)
        XCTAssertEqual(searchState.searchResult.first?.file.url.lastPathComponent, "File 1.txt")

        searchState.fileMask = "!*.txt"
        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 1)
        XCTAssertEqual(searchState.searchResult.first?.file.url.lastPathComponent, "Makefile")

        searchState.fileMask = "*.docc, Make*"
        await searchState.search("Ipsum")
        XCTAssertEqual(searchState.searchResult.count, 1)
    }

    func testFindModelReflectsTheFormOptions() {
        searchState.selectedMode = [.Replace, .Text, .StartingWith]
        searchState.caseSensitive = true
        searchState.findModel.isPreserveCase = true
        searchState.fileMask = "*.swift"
        searchState.replaceText = "replacement"

        let model = searchState.makeFindModel(query: "first\nsecond")
        XCTAssertEqual(model.stringToFind, "first\nsecond")
        XCTAssertEqual(model.stringToReplace, "replacement")
        XCTAssertTrue(model.isReplaceState)
        XCTAssertTrue(model.isCaseSensitive)
        XCTAssertTrue(model.isPreserveCase)
        XCTAssertTrue(model.isMultiline)
        XCTAssertFalse(model.isRegularExpressions)
        XCTAssertEqual(model.textAnchor, .wordStart)
        XCTAssertEqual(model.fileFilter, "*.swift")
    }

    func testReplaceWithRegularExpressionTemplate() async throws {
        searchState.selectedMode = [.Replace, .RegularExpression]

        try await searchState.findAndReplace(query: "Loren (?<word>Ip\\w+)", replacingTerm: "\\U${word}\\E!")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))

        let first = try String(contentsOf: directory.appending(path: "File 1.txt"), encoding: .utf8)
        XCTAssertEqual(first, "IPSUM!.")
    }

    func testReplaceWithMalformedTemplateLeavesFilesUntouched() async throws {
        searchState.selectedMode = [.Replace, .RegularExpression]

        try await searchState.findAndReplace(query: "(Ipsum)", replacingTerm: "$5")
        XCTAssertEqual(
            searchState.findNavigatorStatus,
            .failed(errorMessage: "Invalid replacement string: No group 5")
        )

        let first = try String(contentsOf: directory.appending(path: "File 1.txt"), encoding: .utf8)
        XCTAssertEqual(first, "Loren Ipsum.")
    }

    func testReplaceWithPreserveCase() async throws {
        searchState.findModel.isPreserveCase = true

        try await searchState.findAndReplace(query: "ipsum", replacingTerm: "dolor")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))

        let first = try String(contentsOf: directory.appending(path: "File 1.txt"), encoding: .utf8)
        XCTAssertEqual(first, "Loren Dolor.")
    }

    func testReplaceWithWholeWordsOnly() async throws {
        searchState.wholeWordsOnly = true

        try await searchState.findAndReplace(query: "Ipsu", replacingTerm: "X")
        XCTAssertEqual(
            searchState.findNavigatorStatus,
            .failed(errorMessage: "No files in the workspace matched: Ipsu")
        )

        try await searchState.findAndReplace(query: "Ipsum", replacingTerm: "X")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))

        let first = try String(contentsOf: directory.appending(path: "File 1.txt"), encoding: .utf8)
        XCTAssertEqual(first, "Loren X.")
    }

    func testReplaceHonoursTheFileMask() async throws {
        searchState.fileMask = "*.txt"

        try await searchState.findAndReplace(query: "Ipsum", replacingTerm: "X")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 1))

        let makefileURL = directory
            .appending(path: "Longer Folder With Some 💯 Special Chars ⁉️")
            .appending(path: "Makefile")
        let makefile = try String(contentsOf: makefileURL, encoding: .utf8)
        XCTAssertEqual(makefile, "Loren Ipsum.")
    }

    func testReplaceRangeReplacesOnlyTheGivenOccurrence() async throws {
        let fileURL = directory.appending(path: "File 1.txt")
        try "Ipsum Ipsum".write(to: fileURL, atomically: true, encoding: .utf8)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let second = try XCTUnwrap(content.range(of: "Ipsum", options: .backwards))

        searchState.replaceRange(file: fileURL, searchTerm: "Ipsum", replacingTerm: "X", keywordRange: second)

        let updated = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(updated, "Ipsum X")
    }

    func testReplaceOccurrencesInFileUsesTheRegularExpression() async throws {
        searchState.selectedMode = [.Replace, .RegularExpression]
        let fileURL = directory.appending(path: "File 1.txt")

        try await searchState.replaceOccurrencesInFile(fileURL: fileURL, query: "L(o)ren", replacingTerm: "$1-$1")

        let updated = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(updated, "o-o Ipsum.")
    }
}
