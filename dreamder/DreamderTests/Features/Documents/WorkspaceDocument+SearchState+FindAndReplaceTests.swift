//
//  WorkspaceDocument+SearchState+FindAndReplaceTests.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 26.01.24.
//

import XCTest
@testable import Dreamder

@MainActor
final class FindAndReplaceTests: XCTestCase { // swiftlint:disable:this type_body_length
    private var directory: URL!
    private var files: [CEWorkspaceFile] = []
    private var mockWorkspace: WorkspaceDocument!
    private var searchState: WorkspaceDocument.SearchState!

    private var folder1File: CEWorkspaceFile?
    private var folder2File: CEWorkspaceFile?

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
        folder1File = CEWorkspaceFile(url: folder1)
        let folder2 = directory.appending(path: "Longer Folder With Some 💯 Special Chars ⁉️")
        folder2File = CEWorkspaceFile(url: folder2)
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)

        let fileURLs = [
            directory.appending(path: "File 1.txt"),
            folder1.appending(path: "Documentation.docc"),
            folder2.appending(path: "Makefile")
        ]

        for index in 0..<fileURLs.count {
            if index % 2 == 0 {
                try String("Loren Ipsum").write(to: fileURLs[index], atomically: true, encoding: .utf8)
            } else {
                try String("Aperiam asperiores").write(to: fileURLs[index], atomically: true, encoding: .utf8)
            }
        }

        files = fileURLs.map { CEWorkspaceFile(url: $0) }

        files[1].parent = folder1File
        files[2].parent = folder2File

        mockWorkspace.searchState?.addProjectToIndex()

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline,
              !(searchState.indexStatus == .done && searchState.indexer?.documents().count == 3) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(searchState.indexStatus, .done)
        XCTAssertEqual(searchState.indexer?.documents().count, 3)
    }

    // MARK: - Tear down
    /// The mock directory along with the mock files will be removed
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func findAndReplace(query: String, replacingTerm: String) async {
        searchState.searchQuery = query
        searchState.replaceText = replacingTerm
        await searchState.search(query)
        await searchState.replaceAll()
    }

    private func resultCount(for query: String) async -> Int {
        await searchState.search(query)
        return searchState.searchResult.count
    }

    func testFindAndReplace() async {
        await findAndReplace(query: "Ipsum", replacingTerm: "muspi")

        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))
        let remaining = await resultCount(for: "Ipsum")
        let replaced = await resultCount(for: "muspi")
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(replaced, 2)
    }

    func testFindAndReplaceWithOptionContaining() async {
        await findAndReplace(query: "psu", replacingTerm: "OOO")

        let replaced = await resultCount(for: "IOOOm")
        XCTAssertEqual(replaced, 2)
    }

    func testFindAndReplaceWithOptionMatchingWord() async {
        searchState.selectedMode[2] = .MatchingWord

        await findAndReplace(query: "psu", replacingTerm: "OOO")
        XCTAssertEqual(searchState.findNavigatorStatus, .found)
        XCTAssertTrue(searchState.searchResult.isEmpty)
        let partial = await resultCount(for: "IOOOm")
        XCTAssertEqual(partial, 0)

        await findAndReplace(query: "Ipsum", replacingTerm: "OOO")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))
        let replaced = await resultCount(for: "OOO")
        XCTAssertEqual(replaced, 2)
    }

    func testFindAndReplaceWithOptionStartingWith() async {
        searchState.selectedMode[2] = .StartingWith

        await findAndReplace(query: "psum", replacingTerm: "OOO")
        XCTAssertEqual(searchState.findNavigatorStatus, .found)
        let unchanged = await resultCount(for: "OOO")
        XCTAssertEqual(unchanged, 0)

        await findAndReplace(query: "Ipsu", replacingTerm: "OOO")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))
        let replaced = await resultCount(for: "OOOm")
        XCTAssertEqual(replaced, 2)
    }

    func testFindAndReplaceWithOptionEndingWith() async {
        searchState.selectedMode[2] = .EndingWith

        await findAndReplace(query: "Ipsu", replacingTerm: "OOO")
        XCTAssertEqual(searchState.findNavigatorStatus, .found)
        let unchanged = await resultCount(for: "OOO")
        XCTAssertEqual(unchanged, 0)

        await findAndReplace(query: "sum", replacingTerm: "OOO")
        XCTAssertEqual(searchState.findNavigatorStatus, .replaced(updatedFiles: 2))
        let replaced = await resultCount(for: "IpOOO")
        XCTAssertEqual(replaced, 2)
    }
}
