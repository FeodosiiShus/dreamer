import CoreServices
import Foundation
import Testing
@testable import Dreamder

struct SearchIndexerCoverageTests {
    private func documentURL(_ name: String = "doc.txt") -> URL {
        URL(filePath: "/dreamder-indexer-tests/\(UUID().uuidString)/\(name)")
    }

    private func schemelessURL() throws -> URL {
        try #require(URL(string: "relative/path.txt"))
    }

    private func makeIndex(_ properties: SearchIndexer.CreateProperties = SearchIndexer.CreateProperties()) throws
        -> SearchIndexer {
        try #require(SearchIndexer.Memory.create(properties: properties))
    }

    private func withRawIndex<R>(_ analysis: [CFString: Any], _ body: (SKIndex) -> R) throws -> R {
        let data = NSMutableData()
        let index = try #require(
            SKIndexCreateWithMutableData(data, nil, kSKIndexInverted, analysis as CFDictionary)
        ).takeUnretainedValue()
        defer { SKIndexClose(index) }
        return body(index)
    }

    @Test
    func fileBackedIndexKeepsItsDocumentsAfterSaveAndReopen() throws {
        try withTempDir { dir in
            let location = dir.appending(path: "index.sk")
            let created = try #require(SearchIndexer.File.create(fileURL: location))
            let document = documentURL()
            #expect(created.fileURL == location)
            #expect(created.addFileWithText(document, text: "persisted needle"))
            #expect(created.getAsData() == nil)
            created.save()
            created.close()

            let reopened = try #require(SearchIndexer.File.openIndex(fileURL: location, writeable: false))
            #expect(reopened.fileURL == location)
            #expect(reopened.documents() == [document])
            #expect(reopened.search("needle").map(\.url) == [document])
            reopened.close()
        }
    }

    @Test
    func creatingOverAnExistingIndexFileFails() throws {
        try withTempDir { dir in
            let location = dir.appending(path: "index.sk")
            let created = try #require(SearchIndexer.File.create(fileURL: location))
            created.save()
            created.close()

            #expect(SearchIndexer.File.create(fileURL: location) == nil)
        }
    }

    @Test
    func openingAMissingIndexFileFails() throws {
        try withTempDir { dir in
            #expect(SearchIndexer.File.openIndex(fileURL: dir.appending(path: "missing.sk"), writeable: false) == nil)
        }
    }

    @Test
    func memoryIndexHasNoFileAndSavingItChangesNothing() throws {
        let index = try makeIndex()
        let document = documentURL()
        #expect(index.addFileWithText(document, text: "alpha"))
        index.flush()

        index.save()

        #expect(index.fileURL == nil)
        #expect(index.documents() == [document])
    }

    @Test
    func anUnknownIndexTypeCannotBeCreated() {
        #expect(SearchIndexer.Memory.create(properties: SearchIndexer.CreateProperties(indexType: .unknown)) == nil)
    }

    @Test
    func dataThatIsNotAnIndexCannotBeLoaded() {
        let garbage = Data(String(repeating: "not an index ", count: 20).utf8)
        #expect(SearchIndexer.Memory.loadFromData(data: garbage) == nil)
    }

    @Test
    func stopWordsComeFromTheIndexAnalysisProperties() throws {
        let configured = try withRawIndex([kSKStopWords: Set(["the", "and"])]) { SearchIndexer.stopWords(of: $0) }
        let unconfigured = try withRawIndex([:]) { SearchIndexer.stopWords(of: $0) }

        #expect(configured == ["the", "and"])
        #expect(unconfigured.isEmpty)
    }

    @Test
    func termsListEveryTermWithItsFrequency() throws {
        let index = try makeIndex()
        let document = documentURL()
        #expect(index.addFileWithText(document, text: "hello world hello"))
        index.flush()

        let counts = Dictionary(index.terms(for: document).map { ($0.term, $0.count) }, uniquingKeysWith: +)

        #expect(counts == ["hello": 2, "world": 1])
        #expect(index.termCount(for: document) == 3)
        #expect(!index.isEmpty(for: document))
    }

    @Test
    func stopWordsNeverAppearAmongTheTerms() throws {
        let index = try makeIndex(SearchIndexer.CreateProperties(stopWords: ["the"]))
        let document = documentURL()
        #expect(index.addFileWithText(document, text: "the quick the fox"))
        index.flush()

        let terms = Set(index.terms(for: document).map(\.term))

        #expect(terms == ["quick", "fox"])
    }

    @Test
    func aDocumentWithoutTextIsEmpty() throws {
        let index = try makeIndex()
        let empty = documentURL()
        #expect(index.addFileWithText(empty, text: ""))
        index.flush()

        #expect(index.isEmpty(for: empty))
        #expect(index.termCount(for: empty) == 0)
        #expect(index.terms(for: empty).isEmpty)
    }

    @Test
    func unknownDocumentsHaveNoTerms() throws {
        let index = try makeIndex()
        #expect(index.addFileWithText(documentURL(), text: "alpha"))
        index.flush()
        let unknown = documentURL("unknown.txt")

        #expect(index.terms(for: unknown).isEmpty)
        #expect(index.termCount(for: unknown) == 0)
        #expect(index.isEmpty(for: unknown))
    }

    @Test
    func documentsCanBeFilteredByTheirTermState() throws {
        let index = try makeIndex()
        let filled = documentURL("filled.txt")
        let empty = documentURL("empty.txt")
        #expect(index.addFileWithText(filled, text: "alpha beta"))
        #expect(index.addFileWithText(empty, text: ""))
        index.flush()

        #expect(index.documents(termState: .notEmpty) == [filled])
        #expect(index.documents(termState: .empty) == [empty])
        #expect(Set(index.documents(termState: .all)) == [filled, empty])
        #expect(Set(index.documents()) == [filled, empty])
        #expect(index.cleanUp() == 1)
        index.flush()
        #expect(index.documents() == [filled])
    }

    @Test
    func aClosedIndexAnswersEverythingWithNothing() throws {
        let index = try makeIndex()
        let document = documentURL()
        #expect(index.addFileWithText(document, text: "alpha"))
        index.flush()

        index.close()
        index.close()

        #expect(index.documents().isEmpty)
        #expect(index.termCount(for: document) == 0)
        #expect(index.terms(for: document).isEmpty)
        #expect(!index.removeDocument(url: document))
        #expect(!index.addFileWithText(document, text: "beta"))
        #expect(!index.addFile(fileURL: document))
        #expect(index.documentState(document) == kSKDocumentStateNotIndexed)
        #expect(!index.documentIndexed(document))
        #expect(index.search("alpha").isEmpty)
        #expect(index.cleanUp() == 0)
    }

    @Test
    func urlsWithoutASchemeCannotBeIndexedOrQueried() throws {
        let index = try makeIndex()
        let relative = try schemelessURL()

        #expect(!index.addFileWithText(relative, text: "alpha"))
        #expect(!index.addFile(fileURL: relative))
        #expect(!index.removeDocument(url: relative))
        #expect(index.documentState(relative) == kSKDocumentStateNotIndexed)
        #expect(index.termCount(for: relative) == 0)
        #expect(index.terms(for: relative).isEmpty)
    }

    @Test
    func textCanBeAddedByURLString() throws {
        let index = try makeIndex()
        let document = documentURL()

        #expect(index.addFileWithText(textURL: document.absoluteString, text: "gamma"))
        #expect(!index.addFileWithText(textURL: "", text: "gamma"))
        index.flush()

        #expect(index.documentIndexed(document))
        #expect(index.documentState(document) == kSKDocumentStateIndexed)
    }

    @Test
    func onlyExistingFoldersAreAddedAsFolders() throws {
        try withTempDir { dir in
            let index = try makeIndex()
            let file = dir.appending(path: "plain.txt")
            try "plain text".write(to: file, atomically: true, encoding: .utf8)

            #expect(index.addFolderContent(folderURL: file).isEmpty)
            #expect(index.addFolderContent(folderURL: dir.appending(path: "missing")).isEmpty)
            let added = index.addFolderContent(folderURL: dir)
            #expect(added.map { $0.resolvingSymlinksInPath().path } == [file.resolvingSymlinksInPath().path])
        }
    }

    @Test
    func mimeTypesAreDetectedFromTheExtensionOnly() throws {
        let index = try makeIndex()

        #expect(index.detectMimeType(URL(filePath: "/dreamder-indexer-tests/notes.txt")) == "text/plain")
        #expect(index.detectMimeType(URL(filePath: "/dreamder-indexer-tests/no-extension")) == nil)
        #expect(index.detectMimeType(URL(filePath: "/dreamder-indexer-tests/file.zzqqxx9")) == nil)
    }

    @Test
    func searchIsReturnedInChunksUntilNothingIsLeft() throws {
        let index = try makeIndex()
        let documents = (0..<3).map { documentURL("doc\($0).txt") }
        for document in documents {
            #expect(index.addFileWithText(document, text: "hello"))
        }
        index.flush()
        let search = index.progressiveSearch(query: "hello")

        let first = search.getNextSearchResultsChunk(limit: 2)
        let second = search.getNextSearchResultsChunk(limit: 2)

        #expect(first.moreResultsAvailable)
        #expect(first.results.count == 2)
        #expect(!second.moreResultsAvailable)
        #expect(Set(first.results.map(\.url)).union(second.results.map(\.url)) == Set(documents))
    }

    @Test
    func aCancelledSearchYieldsNothing() throws {
        let index = try makeIndex()
        #expect(index.addFileWithText(documentURL(), text: "hello"))
        index.flush()
        let search = index.progressiveSearch(query: "hello")

        search.cancel()
        let results = search.getNextSearchResultsChunk()

        #expect(results.results.isEmpty)
        #expect(!results.moreResultsAvailable)
    }

    @Test
    func aSearchStartedOnAClosedIndexNeverFindsAnything() throws {
        let index = try makeIndex()
        #expect(index.addFileWithText(documentURL(), text: "hello"))
        index.flush()
        index.close()
        let search = index.progressiveSearch(query: "hello")

        search.cancel()
        let results = search.getNextSearchResultsChunk()

        #expect(results.results.isEmpty)
        #expect(!results.moreResultsAvailable)
    }

    @Test
    func closingTheIndexEndsRunningSearches() throws {
        let index = try makeIndex()
        #expect(index.addFileWithText(documentURL(), text: "hello"))
        index.flush()
        let search = index.progressiveSearch(query: "hello")

        index.close()
        let results = search.getNextSearchResultsChunk()

        #expect(results.results.isEmpty)
        #expect(!results.moreResultsAvailable)
    }
}
