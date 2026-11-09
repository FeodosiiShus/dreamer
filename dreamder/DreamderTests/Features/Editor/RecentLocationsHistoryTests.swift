import CodeEditSourceEditor
import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class RecentLocationsToggle: Sendable {
    private let storage: Mutex<Bool>

    init(_ value: Bool) {
        storage = Mutex(value)
    }

    var value: Bool {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

private final class RecentLocationsValidityCalls: Sendable {
    private let storage = Mutex(0)

    func record() {
        storage.withLock { $0 += 1 }
    }

    var count: Int {
        storage.withLock { $0 }
    }
}

private struct RecentLocationsHistoryHarness {
    var history: EditorLocationHistory
    var state: EditorPlace

    let state1 = recentLocationsPlace(line: 1)
    let state2 = recentLocationsPlace(line: 20)
    let state3 = recentLocationsPlace(line: 40)

    init(isFileValid: @escaping @Sendable (URL) -> Bool = { _ in true }) {
        history = EditorLocationHistory(isFileValid: isFileValid)
        state = recentLocationsPlace(line: 1)
    }

    mutating func makeNavigationChange(_ newState: EditorPlace) {
        history.recordBackPlace(state)
        state = newState
    }

    mutating func pushTwoStates() {
        state = state1
        makeNavigationChange(state2)
        makeNavigationChange(state3)
    }

    mutating func back() {
        if let target = history.back(from: state) {
            state = target
        }
    }

    mutating func forward() {
        if let target = history.forward(from: state) {
            state = target
        }
    }
}

private func recentLocationsPlace(_ file: String = "a.swift", line: Int, column: Int = 1) -> EditorPlace {
    EditorPlace(fileURL: URL(filePath: "/project/\(file)"), line: line, column: column)
}

@Suite
struct RecentLocationsHistoryTests {
    @Test("IdeDocumentHistoryTest.testNoHistoryRecording")
    func noHistoryRecording() {
        let harness = RecentLocationsHistoryHarness()

        #expect(!harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
    }

    @Test("IdeDocumentHistoryTest.testNavigationRecording")
    func navigationRecording() {
        var harness = RecentLocationsHistoryHarness()

        harness.makeNavigationChange(harness.state2)

        #expect(harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
        #expect(harness.history.backPlaces.count == 1)
    }

    @Test("IdeDocumentHistoryTest.testMergingForwardPlaces")
    func mergingForwardPlaces() {
        var harness = RecentLocationsHistoryHarness()
        harness.state = recentLocationsPlace(line: 5)

        harness.makeNavigationChange(recentLocationsPlace(line: 6))

        #expect(harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
        #expect(harness.history.backPlaces.count == 1)
    }

    @Test("IdeDocumentHistoryTest.testSimpleNavigation")
    func simpleNavigation() {
        var harness = RecentLocationsHistoryHarness()
        harness.pushTwoStates()

        #expect(!harness.history.isForwardAvailable)
        #expect(harness.history.isBackAvailable)

        harness.back()
        #expect(harness.history.isBackAvailable)
        #expect(harness.history.isForwardAvailable)
        #expect(harness.state == harness.state2)

        harness.back()
        #expect(!harness.history.isBackAvailable)
        #expect(harness.history.isForwardAvailable)
        #expect(harness.state == harness.state1)

        harness.forward()
        #expect(harness.history.isBackAvailable)
        #expect(harness.history.isForwardAvailable)
        #expect(harness.state == harness.state2)

        harness.forward()
        #expect(harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
        #expect(harness.state == harness.state3)
    }

    @Test("IdeDocumentHistoryTest.testQueueCutOff")
    func queueCutOff() {
        var harness = RecentLocationsHistoryHarness()
        harness.pushTwoStates()
        harness.back()

        #expect(harness.history.isBackAvailable)
        #expect(harness.history.isForwardAvailable)

        harness.makeNavigationChange(recentLocationsPlace(line: 60))

        #expect(harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)

        harness.back()
        #expect(harness.state == harness.state2)
        harness.back()
        #expect(harness.state == harness.state1)
        #expect(!harness.history.isBackAvailable)
    }

    @Test("IdeDocumentHistoryTest.testRemoveInvalid")
    func removeInvalid() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "gone.swift")
            try "x".write(to: file, atomically: true, encoding: .utf8)
            var history = EditorLocationHistory()
            history.recordBackPlace(EditorPlace(fileURL: file, line: 1, column: 1))
            history.recordBackPlace(EditorPlace(fileURL: file, line: 20, column: 1))
            history.recordChangePlace(EditorPlace(fileURL: file, line: 3, column: 1))
            _ = history.back(from: EditorPlace(fileURL: file, line: 40, column: 1))
            #expect(history.isBackAvailable)
            #expect(history.isForwardAvailable)
            #expect(!history.changePlaces.isEmpty)

            try FileManager.default.removeItem(at: file)
            history.removeInvalidPlaces()

            #expect(!history.isBackAvailable)
            #expect(!history.isForwardAvailable)
            #expect(history.changePlaces.isEmpty)
        }
    }

    @Test("IdeDocumentHistoryTest.testRemoveOptionallyIncludedFiles")
    func removeOptionallyIncludedFiles() {
        let included = RecentLocationsToggle(true)
        var harness = RecentLocationsHistoryHarness(isFileValid: { _ in included.value })
        harness.pushTwoStates()
        #expect(harness.history.isBackAvailable)

        included.value = false
        harness.history.removeInvalidPlaces()

        #expect(!harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
    }

    @Test("IdeDocumentHistoryTest.testOptionallyExcludedFileIsNotPushed")
    func optionallyExcludedFileIsNotPushed() {
        var harness = RecentLocationsHistoryHarness(isFileValid: { _ in false })

        harness.pushTwoStates()

        #expect(!harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
    }

    @Test("IdeDocumentHistoryTest.testExcludedFileIsNotPushed")
    func excludedFileIsNotPushed() {
        var harness = RecentLocationsHistoryHarness(isFileValid: { $0.lastPathComponent != "Light.swift" })
        harness.state = recentLocationsPlace("Light.swift", line: 1)

        harness.makeNavigationChange(recentLocationsPlace("Light.swift", line: 20))
        harness.makeNavigationChange(recentLocationsPlace("Light.swift", line: 40))

        #expect(!harness.history.isBackAvailable)
        #expect(!harness.history.isForwardAvailable)
    }

    @Test
    func defaultValidityChecksTheFileSystem() throws {
        try withTempDir { directory in
            let existing = directory.appending(path: "here.swift")
            try "x".write(to: existing, atomically: true, encoding: .utf8)
            let missing = directory.appending(path: "missing.swift")
            var history = EditorLocationHistory()

            history.recordBackPlace(EditorPlace(fileURL: missing, line: 1, column: 1))
            #expect(!history.isBackAvailable)
            history.recordBackPlace(EditorPlace(fileURL: existing, line: 1, column: 1))
            #expect(history.backPlaces == [EditorPlace(fileURL: existing, line: 1, column: 1)])
            #expect(EditorLocationHistory.fileExists(existing))
            #expect(!EditorLocationHistory.fileExists(missing))
        }
    }

    @Test
    func backQueueLimitDropsTheOldestPlace() {
        var history = EditorLocationHistory(backLimit: 3, isFileValid: { _ in true })

        for line in [1, 10, 20, 30, 40] {
            history.recordBackPlace(recentLocationsPlace(line: line))
        }

        #expect(history.backPlaces.map(\.line) == [20, 30, 40])
    }

    @Test
    func changeQueueLimitDropsTheOldestPlace() {
        var history = EditorLocationHistory(changeLimit: 2, isFileValid: { _ in true })

        for line in [1, 10, 20] {
            history.recordChangePlace(recentLocationsPlace(line: line))
        }

        #expect(history.changePlaces.map(\.line) == [10, 20])
    }

    @Test
    func defaultStackLimitMatchesTheEditorNavigationHistoryRegistryValue() {
        var history = EditorLocationHistory(isFileValid: { _ in true })

        for index in 0..<(EditorLocationHistory.defaultStackLimit + 10) {
            history.recordBackPlace(recentLocationsPlace(line: index * 10 + 1))
            history.recordChangePlace(recentLocationsPlace(line: index * 10 + 1))
        }

        #expect(EditorLocationHistory.defaultStackLimit == 150)
        #expect(history.backPlaces.count == 150)
        #expect(history.changePlaces.count == 150)
        #expect(history.backPlaces.first?.line == 101)
    }

    @Test
    func putLastOrMergeReplacesTheLastSimilarPlaceWithTheNewOne() {
        var history = EditorLocationHistory(isFileValid: { _ in true })

        history.recordBackPlace(recentLocationsPlace(line: 10, column: 2))
        history.recordBackPlace(recentLocationsPlace(line: 12, column: 7))
        history.recordChangePlace(recentLocationsPlace(line: 10, column: 2))
        history.recordChangePlace(recentLocationsPlace(line: 13, column: 9))

        #expect(history.backPlaces == [recentLocationsPlace(line: 12, column: 7)])
        #expect(history.changePlaces == [recentLocationsPlace(line: 13, column: 9)])
        #expect(history.backPlaces.first?.column == 7)
    }

    @Test
    func mergeOnlyLooksAtTheLastPlace() {
        var history = EditorLocationHistory(isFileValid: { _ in true })

        history.recordBackPlace(recentLocationsPlace(line: 10))
        history.recordBackPlace(recentLocationsPlace(line: 50))
        history.recordBackPlace(recentLocationsPlace(line: 11))

        #expect(history.backPlaces.map(\.line) == [10, 50, 11])
    }

    @Test
    func recordingABackPlaceDropsTheForwardStack() {
        var harness = RecentLocationsHistoryHarness()
        harness.pushTwoStates()
        harness.back()
        #expect(harness.history.forwardPlaces.count == 1)

        harness.history.recordBackPlace(recentLocationsPlace(line: 99))

        #expect(harness.history.forwardPlaces.isEmpty)
    }

    @Test
    func recordingAChangePlaceKeepsTheForwardStack() {
        var harness = RecentLocationsHistoryHarness()
        harness.pushTwoStates()
        harness.back()

        harness.history.recordChangePlace(recentLocationsPlace(line: 99))

        #expect(harness.history.forwardPlaces.count == 1)
    }

    @Test
    func backWithoutPlacesReturnsNothing() {
        var history = EditorLocationHistory(isFileValid: { _ in true })

        #expect(history.back(from: recentLocationsPlace(line: 1)) == nil)
        #expect(history.forward(from: recentLocationsPlace(line: 1)) == nil)
        #expect(!history.isForwardAvailable)
    }

    @Test
    func backWithoutACurrentPlaceDoesNotFillTheForwardStack() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        history.recordBackPlace(recentLocationsPlace(line: 5))

        let target = history.back(from: nil)

        #expect(target == recentLocationsPlace(line: 5))
        #expect(!history.isForwardAvailable)
        #expect(!history.isBackAvailable)
    }

    @Test
    func forwardWithoutACurrentPlaceDoesNotFillTheBackStack() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        history.recordBackPlace(recentLocationsPlace(line: 5))
        _ = history.back(from: recentLocationsPlace(line: 40))

        let target = history.forward(from: nil)

        #expect(target == recentLocationsPlace(line: 40))
        #expect(!history.isBackAvailable)
    }

    @Test
    func forwardSkipsPlacesThatAreTheSameAsTheCurrentPlace() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        history.recordBackPlace(recentLocationsPlace(line: 5))
        history.recordBackPlace(recentLocationsPlace(line: 25))
        _ = history.back(from: recentLocationsPlace(line: 60))
        _ = history.back(from: recentLocationsPlace(line: 25, column: 3))
        #expect(history.forwardPlaces.map(\.line) == [60, 25])

        let target = history.forward(from: recentLocationsPlace(line: 26))

        #expect(target == recentLocationsPlace(line: 60))
        #expect(history.forwardPlaces.isEmpty)
        #expect(history.backPlaces.map(\.line) == [26])
    }

    @Test
    func forwardKeepsTheLastPlaceEvenWhenItIsTheSameAsTheCurrentPlace() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        history.recordBackPlace(recentLocationsPlace(line: 5))
        _ = history.back(from: recentLocationsPlace(line: 25))

        let target = history.forward(from: recentLocationsPlace(line: 26))

        #expect(target == recentLocationsPlace(line: 25))
    }

    @Test
    func validityIsCheckedOncePerFilePerPass() {
        let calls = RecentLocationsValidityCalls()
        var history = EditorLocationHistory(isFileValid: { _ in
            calls.record()
            return true
        })
        for line in [1, 20, 40, 60] {
            history.recordBackPlace(recentLocationsPlace("a.swift", line: line))
            history.recordBackPlace(recentLocationsPlace("b.swift", line: line))
        }
        let before = calls.count

        history.removeInvalidPlaces()

        #expect(calls.count - before == 2)
    }

    @Test
    func recentPlacesListNewestFirstWithoutSimilarDuplicates() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        history.recordBackPlace(recentLocationsPlace("a.swift", line: 1))
        history.recordBackPlace(recentLocationsPlace("b.swift", line: 1))
        history.recordBackPlace(recentLocationsPlace("a.swift", line: 2))
        history.recordBackPlace(recentLocationsPlace("a.swift", line: 100))
        history.recordChangePlace(recentLocationsPlace("c.swift", line: 7))
        history.recordChangePlace(recentLocationsPlace("d.swift", line: 9))

        let navigation = history.recentPlaces(changed: false)
        let changed = history.recentPlaces(changed: true)

        #expect(navigation.map(\.fileURL.lastPathComponent) == ["a.swift", "a.swift", "b.swift"])
        #expect(navigation.map(\.line) == [100, 2, 1])
        #expect(changed.map(\.fileURL.lastPathComponent) == ["d.swift", "c.swift"])
    }

    @Test
    func recentPlacesStopAtTheLimit() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        for index in 0..<40 {
            history.recordBackPlace(recentLocationsPlace(line: index * 10 + 1))
        }

        #expect(EditorLocationHistory.recentLocationsLimit == 25)
        #expect(history.recentPlaces(changed: false).count == 25)
        #expect(history.recentPlaces(changed: false, limit: 3).map(\.line) == [391, 381, 371])
        #expect(history.recentPlaces(changed: true).isEmpty)
    }

    @Test
    func removingPlacesDropsEverySimilarPlace() {
        var history = EditorLocationHistory(isFileValid: { _ in true })
        history.recordBackPlace(recentLocationsPlace(line: 10))
        history.recordBackPlace(recentLocationsPlace(line: 50))
        history.recordBackPlace(recentLocationsPlace(line: 12))
        history.recordChangePlace(recentLocationsPlace(line: 10))
        history.recordChangePlace(recentLocationsPlace(line: 50))

        history.removeBackPlaces(sameAs: recentLocationsPlace(line: 11))
        history.removeChangePlaces(sameAs: recentLocationsPlace(line: 51))

        #expect(history.backPlaces.map(\.line) == [50])
        #expect(history.changePlaces.map(\.line) == [10])
    }
}

@Suite
struct RecentLocationsPlaceTests {
    @Test(arguments: [
        (1, 1, true),
        (1, 4, true),
        (1, 5, false),
        (5, 1, false),
        (5, 2, true),
        (100, 97, true),
        (100, 96, false)
    ])
    func placesWithinFourLinesAreTheSame(first: Int, second: Int, expected: Bool) {
        let lhs = recentLocationsPlace(line: first)
        let rhs = recentLocationsPlace(line: second)

        #expect(lhs.isSame(as: rhs) == expected)
        #expect(rhs.isSame(as: lhs) == expected)
    }

    @Test
    func columnsDoNotAffectSimilarity() {
        #expect(recentLocationsPlace(line: 3, column: 1).isSame(as: recentLocationsPlace(line: 3, column: 80)))
    }

    @Test
    func placesInDifferentFilesAreNeverTheSame() {
        #expect(!recentLocationsPlace("a.swift", line: 3).isSame(as: recentLocationsPlace("b.swift", line: 3)))
    }

    @Test
    func everyCaretMustBeCloseAndTheCaretCountMustMatch() {
        let url = URL(filePath: "/project/a.swift")
        let two = EditorPlace(fileURL: url, carets: [.init(line: 1, column: 1), .init(line: 30, column: 1)])
        let twoNearby = EditorPlace(fileURL: url, carets: [.init(line: 2, column: 5), .init(line: 32, column: 1)])
        let twoFar = EditorPlace(fileURL: url, carets: [.init(line: 2, column: 5), .init(line: 40, column: 1)])
        let one = EditorPlace(fileURL: url, line: 1, column: 1)
        let none = EditorPlace(fileURL: url, carets: [])

        #expect(two.isSame(as: twoNearby))
        #expect(!two.isSame(as: twoFar))
        #expect(!two.isSame(as: one))
        #expect(none.isSame(as: EditorPlace(fileURL: url, carets: [])))
        #expect(none.line == 1)
        #expect(none.column == 1)
    }

    @Test
    func placesStandardizeTheirFileURL() {
        let direct = EditorPlace(fileURL: URL(filePath: "/project/a.swift"), line: 1, column: 1)
        let detour = EditorPlace(fileURL: URL(filePath: "/project/x/../a.swift"), line: 1, column: 1)

        #expect(direct == detour)
    }

    @Test
    func positionsClampToOneBasedCoordinatesAndFallBackToTheFirstColumn() {
        let url = URL(filePath: "/project/a.swift")
        let clamped = EditorPlace(fileURL: url, positions: [CursorPosition(range: NSRange(location: 4, length: 0))])
        let positioned = EditorPlace(
            fileURL: url,
            positions: [CursorPosition(line: 7, column: 3), CursorPosition(line: 9, column: 1)]
        )
        let empty = EditorPlace(fileURL: url, positions: [])

        #expect(clamped.carets == [EditorPlace.Caret(line: 1, column: 1)])
        #expect(positioned.carets == [EditorPlace.Caret(line: 7, column: 3), EditorPlace.Caret(line: 9, column: 1)])
        #expect(positioned.line == 7)
        #expect(positioned.column == 3)
        #expect(empty.carets == [EditorPlace.Caret(line: 1, column: 1)])
    }

    @Test(arguments: [
        (4, 6, "x", 4, 7),
        (4, 6, "", 4, 6),
        (4, 6, "ab\ncd", 5, 3),
        (4, 6, "ab\n", 5, 1),
        (4, 6, "\n\nz", 6, 2),
        (1, 1, "a\r\nbc", 2, 3),
        (1, 1, "\u{1F600}", 1, 3)
    ])
    func caretAdvancesByTheInsertedText(
        line: Int,
        column: Int,
        inserted: String,
        expectedLine: Int,
        expectedColumn: Int
    ) {
        let caret = EditorPlace.Caret(line: line, column: column)

        #expect(caret.advanced(byInserting: inserted) == EditorPlace.Caret(line: expectedLine, column: expectedColumn))
    }
}
