import Foundation
import Testing
@testable import Dreamder

@Suite
struct SearchEverywhereResultOrderingTests {
    private func insert(
        newProvider: Int, newExact: Bool, newWeight: Int,
        itemProvider: Int, itemExact: Bool, itemWeight: Int
    ) -> Bool {
        SearchEverywhereRanking.shouldInsertAbove(
            newProviderPriority: newProvider,
            newIsExactMatch: newExact,
            newWeight: SearchEverywhereComposedWeight(newWeight),
            itemProviderPriority: itemProvider,
            itemIsExactMatch: itemExact,
            itemWeight: SearchEverywhereComposedWeight(itemWeight),
            prioritizeExactMatch: true
        )
    }

    private func insertComposed(newWeight: SearchEverywhereComposedWeight, itemWeight: SearchEverywhereComposedWeight) -> Bool {
        SearchEverywhereRanking.shouldInsertAbove(
            newProviderPriority: 0,
            newIsExactMatch: false,
            newWeight: newWeight,
            itemProviderPriority: 0,
            itemIsExactMatch: false,
            itemWeight: itemWeight,
            prioritizeExactMatch: true
        )
    }

    @Test
    func higherProviderPriorityAlwaysWins() {
        #expect(insert(newProvider: 5, newExact: false, newWeight: 0, itemProvider: 3, itemExact: true, itemWeight: 9999))
        #expect(!insert(newProvider: 3, newExact: true, newWeight: 9999, itemProvider: 5, itemExact: false, itemWeight: 0))
    }

    @Test
    func exactMatchWinsOverHigherWeightWithinSameProviderPriority() {
        #expect(insert(newProvider: 0, newExact: true, newWeight: 1, itemProvider: 0, itemExact: false, itemWeight: 9999))
        #expect(!insert(newProvider: 0, newExact: false, newWeight: 9999, itemProvider: 0, itemExact: true, itemWeight: 1))
    }

    @Test
    func weightBreaksTieWhenExactnessIsEqual() {
        #expect(insert(newProvider: 0, newExact: true, newWeight: 100, itemProvider: 0, itemExact: true, itemWeight: 50))
        #expect(!insert(newProvider: 0, newExact: true, newWeight: 50, itemProvider: 0, itemExact: true, itemWeight: 100))
        #expect(insert(newProvider: 0, newExact: false, newWeight: 100, itemProvider: 0, itemExact: false, itemWeight: 50))
        #expect(!insert(newProvider: 0, newExact: false, newWeight: 100, itemProvider: 0, itemExact: false, itemWeight: 100))
    }

    @Test
    func exactMatchIsIgnoredWhenNotPrioritized() {
        let result = SearchEverywhereRanking.shouldInsertAbove(
            newProviderPriority: 0,
            newIsExactMatch: true,
            newWeight: SearchEverywhereComposedWeight(1),
            itemProviderPriority: 0,
            itemIsExactMatch: false,
            itemWeight: SearchEverywhereComposedWeight(9999),
            prioritizeExactMatch: false
        )
        #expect(!result)
    }

    @Test
    func nextWeightComponentBreaksTieOfFirstComponent() throws {
        let recent7 = SearchEverywhereComposedWeight(match: 100, recency: 7)
        let recent3 = SearchEverywhereComposedWeight(match: 100, recency: 3)
        #expect(insertComposed(newWeight: recent7, itemWeight: recent3))
        #expect(!insertComposed(newWeight: recent3, itemWeight: recent7))
        #expect(!insertComposed(newWeight: SearchEverywhereComposedWeight(match: 50, recency: 999), itemWeight: SearchEverywhereComposedWeight(match: 100, recency: 0)))
    }
}

@Suite
struct SearchEverywhereProviderPriorityTests {
    @Test
    func prioritiesFollowTheEqualityCheckerTable() {
        #expect(SearchEverywhereProvider.topHit.priority == 9950)
        #expect(SearchEverywhereProvider.recentFiles.priority == 9930)
        #expect(SearchEverywhereProvider.classes.priority == 9900)
        #expect(SearchEverywhereProvider.files.priority == 9800)
        #expect(SearchEverywhereProvider.symbols.priority == 9700)
        #expect(SearchEverywhereProvider.runConfigurations.priority == 9650)
        #expect(SearchEverywhereProvider.actions.priority == 9600)
        #expect(SearchEverywhereProvider.nonIndexable.priority == 9000)
        #expect(SearchEverywhereProvider.text.priority == 8500)
    }

    @Test
    func sectionKindsMapToTheirProviders() {
        #expect(SearchEverywhereSectionKind.recent.provider == .recentFiles)
        #expect(SearchEverywhereSectionKind.files.provider == .files)
        #expect(SearchEverywhereSectionKind.classes.provider == .classes)
        #expect(SearchEverywhereSectionKind.symbols.provider == .symbols)
        #expect(SearchEverywhereSectionKind.actions.provider == .actions)
        #expect(SearchEverywhereSectionKind.text.provider == .text)
    }

    @Test
    func mixedListOrdersByProviderPriorityBeforeWeight() {
        let candidates = [
            candidate("text", .text, "text", match: 90000),
            candidate("action", .actions, "action", match: 80000),
            candidate("symbol", .symbols, "symbol", match: 70000),
            candidate("file", .files, "file", match: 60000),
            candidate("class", .classes, "class", match: 50000),
            candidate("recent", .recentFiles, "recent", match: 10)
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["recent", "class", "file", "symbol", "action", "text"])
    }

    @Test
    func exactMatchIsHoistedAboveHeavierSiblingsOfTheSameProvider() {
        let candidates = [
            candidate("heavy", .files, "AppDelegateExtras.swift", match: 15000),
            candidate("exact", .files, "App.swift", match: 100, exact: true),
            candidate("light", .files, "Another.swift", match: 200)
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["exact", "heavy", "light"])
    }

    @Test
    func exactMatchDoesNotCrossProviderPriority() {
        let candidates = [
            candidate("exactFile", .files, "App.swift", match: 1, exact: true),
            candidate("partialClass", .classes, "AppKit", match: 1)
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["partialClass", "exactFile"])
    }

    @Test
    func recencyBreaksMatchTiesAmongRecentFiles() {
        let candidates = [
            candidate("old", .recentFiles, "Alpha.swift", match: 100, recency: 1),
            candidate("new", .recentFiles, "Beta.swift", match: 100, recency: 3),
            candidate("mid", .recentFiles, "Gamma.swift", match: 100, recency: 2),
            candidate("best", .recentFiles, "Zeta.swift", match: 500, recency: 0)
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["best", "new", "mid", "old"])
    }

    @Test
    func equalWeightsFallBackToNaturalTitleOrder() {
        let candidates = [
            candidate("b", .symbols, "item10", match: 5),
            candidate("a", .symbols, "item2", match: 5)
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["a", "b"])
    }

    @Test
    func textHitsKeepDiscoveryOrder() {
        let candidates = [
            candidate("t1", .text, "zzz", match: 0),
            candidate("t2", .text, "aaa", match: 0),
            candidate("t3", .text, "mmm", match: 0)
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order == [0, 1, 2])
    }

    @Test
    func equalWeightsAndTitlesKeepDiscoveryOrderOfNonTextProviders() {
        let candidates = [
            candidate("second", .files, "Main.swift", match: 5, key: "file:b/Main.swift"),
            candidate("first", .files, "Main.swift", match: 5, key: "file:a/Main.swift")
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order == [0, 1])
    }

    @Test
    func perProviderLimitCapsEachProviderSeparately() {
        let files = (0..<5).map { candidate("f\($0)", .files, "file\($0)", match: 100 - $0) }
        let classes = (0..<5).map { candidate("c\($0)", .classes, "class\($0)", match: 100 - $0) }
        let candidates = files + classes

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 2)

        #expect(order.map { candidates[$0].id } == ["c0", "c1", "f0", "f1"])
    }

    @Test
    func contiguousRunsGroupNeighboursOfTheSameElement() {
        let runs = SearchEverywhereRanking.contiguousRuns(["a", "a", "b", "a"])

        #expect(runs.map(\.element) == ["a", "b", "a"])
        #expect(runs.map(\.range) == [0..<2, 2..<3, 3..<4])
        #expect(SearchEverywhereRanking.contiguousRuns([String]()).isEmpty)
    }
}

@Suite
struct SearchEverywhereExactMatchTests {
    @Test
    func degreeInTheExactRangeIsExact() {
        #expect(SearchEverywhereRanking.isInExactMatchDegreeRange(15_000))
        #expect(SearchEverywhereRanking.isInExactMatchDegreeRange(14_000))
        #expect(!SearchEverywhereRanking.isInExactMatchDegreeRange(13_999))
    }

    @Test
    func presentableTextEqualToTheQueryIsExact() {
        #expect(SearchEverywhereRanking.isExactMatch(degree: 0, presentableText: "AppDelegate", inputQuery: "AppDelegate", isFile: false))
        #expect(!SearchEverywhereRanking.isExactMatch(degree: 0, presentableText: "AppDelegate", inputQuery: "appdelegate", isFile: false))
    }

    @Test
    func fileNameEqualToTheQueryWithoutExtensionIsExact() {
        #expect(SearchEverywhereRanking.isExactMatch(degree: 0, presentableText: "AppDelegate.swift", inputQuery: "AppDelegate", isFile: true))
        #expect(!SearchEverywhereRanking.isExactMatch(degree: 0, presentableText: "AppDelegate.swift", inputQuery: "AppDelegate", isFile: false))
        #expect(!SearchEverywhereRanking.isExactMatch(degree: 0, presentableText: "AppDelegateExtras.swift", inputQuery: "AppDelegate", isFile: true))
        #expect(!SearchEverywhereRanking.isExactMatch(degree: 0, presentableText: "AppDelegate.swift", inputQuery: "AppDelegate.sw", isFile: true))
    }

    @Test
    func directoriesAreExactOnlyThroughTheItemVerdict() {
        #expect(!SearchEverywhereRanking.isExactMatch(
            isExactMatchFromItem: false,
            presentableText: "Sources",
            inputQuery: "Sources",
            isFile: true,
            inputQueryHasNoExtension: true,
            isDirectory: true
        ))
        #expect(SearchEverywhereRanking.isExactMatch(
            isExactMatchFromItem: true,
            presentableText: "Sources",
            inputQuery: "src",
            isFile: true,
            inputQueryHasNoExtension: true,
            isDirectory: true
        ))
    }
}

@Suite
struct SearchEverywhereEqualityTests {
    @Test
    func fileAlreadyShownAsRecentIsNotShownUnderFiles() {
        let candidates = [
            candidate("recent", .recentFiles, "AppDelegate.swift", match: 100, recency: 2, key: "file:Sources/AppDelegate.swift"),
            candidate("file", .files, "AppDelegate.swift", match: 100, key: "file:Sources/AppDelegate.swift"),
            candidate("other", .files, "Other.swift", match: 90, key: "file:Sources/Other.swift")
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["recent", "other"])
    }

    @Test
    func recentFileStaysEvenWhenItArrivesAfterTheFile() {
        let candidates = [
            candidate("file", .files, "AppDelegate.swift", match: 100, key: "file:a"),
            candidate("recent", .recentFiles, "AppDelegate.swift", match: 100, recency: 1, key: "file:a")
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["recent"])
    }

    @Test
    func identicalActionsCollapseToTheHigherWeightedRow() {
        let candidates = [
            candidate("app", .actions, "About Dreamder", match: 50, key: "action:performAction:|About Dreamder"),
            candidate("window", .actions, "About Dreamder", match: 80, key: "action:performAction:|About Dreamder"),
            candidate("zoom", .actions, "Zoom", match: 10, key: "action:performAction:|Zoom")
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["window", "zoom"])
    }

    @Test
    func identicalActionsWithEqualWeightKeepTheFirstRow() {
        let candidates = [
            candidate("app", .actions, "About Dreamder", match: 50, key: "action:performAction:|About Dreamder"),
            candidate("window", .actions, "About Dreamder", match: 50, key: "action:performAction:|About Dreamder")
        ]

        #expect(SearchEverywhereRanking.deduplicated(candidates) == [0])
    }

    @Test
    func classAndSymbolForTheSameDeclarationCollapseToTheClass() {
        let candidates = [
            candidate("symbol", .symbols, "AppDelegate", match: 100, key: "symbol:a:3:AppDelegate"),
            candidate("class", .classes, "AppDelegate", match: 100, key: "symbol:a:3:AppDelegate")
        ]

        let order = SearchEverywhereRanking.rank(candidates, limitPerProvider: 8)

        #expect(order.map { candidates[$0].id } == ["class"])
    }

    @Test
    func candidatesWithoutAnEqualityKeyAreNeverCollapsed() {
        let candidates = [
            candidate("t1", .text, "same", match: 0),
            candidate("t2", .text, "same", match: 0)
        ]

        #expect(SearchEverywhereRanking.deduplicated(candidates) == [0, 1])
    }
}

private func candidate(
    _ id: String,
    _ provider: SearchEverywhereProvider,
    _ title: String,
    match: Int,
    recency: Int? = nil,
    exact: Bool = false,
    key: String? = nil
) -> SearchEverywhereCandidate {
    let weight: SearchEverywhereComposedWeight
    if let recency {
        weight = SearchEverywhereComposedWeight(match: match, recency: recency)
    } else {
        weight = SearchEverywhereComposedWeight(match)
    }
    return SearchEverywhereCandidate(
        id: id,
        provider: provider,
        title: title,
        weight: weight,
        isExactMatch: exact,
        equalityKey: key
    )
}
