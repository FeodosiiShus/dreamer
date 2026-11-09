import Foundation
import Testing
@testable import Dreamder

private struct FuzzySearchUIModelCoverageItem: FuzzySearchable, Equatable {
    let searchableString: String
}

@MainActor
@Suite(.uiGate)
struct FuzzySearchUIModelCoverageTests {
    private static let names = ["a-b-c", "ContentView.swift", "abc", "Package.swift"]

    private static var items: [FuzzySearchUIModelCoverageItem] {
        names.map { FuzzySearchUIModelCoverageItem(searchableString: $0) }
    }

    private func makeModel() -> FuzzySearchUIModel<FuzzySearchUIModelCoverageItem> {
        FuzzySearchUIModel<FuzzySearchUIModelCoverageItem>(debounceTime: .milliseconds(1))
    }

    @Test
    func itemsStartNil() {
        #expect(makeModel().items == nil)
    }

    @Test
    func nonEmptyQueryPublishesMatchesRankedByWeight() async throws {
        let model = makeModel()
        model.searchTextUpdated(searchText: "abc", allItems: Self.items)
        try await eventually { model.items != nil }
        #expect(model.items?.map(\.searchableString) == ["abc", "a-b-c"])
    }

    @Test
    func queryWithoutMatchesPublishesEmptyList() async throws {
        let model = makeModel()
        model.searchTextUpdated(searchText: "zzz", allItems: Self.items)
        try await eventually { model.items != nil }
        #expect(model.items?.isEmpty == true)
    }

    @Test
    func emptyQueryResetsItemsToNil() async throws {
        let model = makeModel()
        model.searchTextUpdated(searchText: "cv", allItems: Self.items)
        try await eventually { model.items != nil }
        #expect(model.items?.map(\.searchableString) == ["ContentView.swift"])

        model.searchTextUpdated(searchText: "", allItems: Self.items)
        try await eventually { model.items == nil }
        #expect(model.items == nil)
    }

    @Test
    func laterItemListsAreSearched() async throws {
        let model = makeModel()
        model.searchTextUpdated(searchText: "abc", allItems: Self.items)
        try await eventually { model.items?.count == 2 }

        model.searchTextUpdated(
            searchText: "abc",
            allItems: [FuzzySearchUIModelCoverageItem(searchableString: "xabcx")]
        )
        try await eventually { model.items?.map(\.searchableString) == ["xabcx"] }
    }

    @Test
    func defaultDebounceStillDeliversResults() async throws {
        let model = FuzzySearchUIModel<FuzzySearchUIModelCoverageItem>()
        model.searchTextUpdated(searchText: "abc", allItems: Self.items)
        try await eventually { model.items != nil }
        #expect(model.items?.count == 2)
    }

    @Test
    func modelIsReleasedWhileSearchTaskIsIdle() async throws {
        weak var released: FuzzySearchUIModel<FuzzySearchUIModelCoverageItem>?
        do {
            let model = makeModel()
            released = model
            model.searchTextUpdated(searchText: "abc", allItems: Self.items)
            try await eventually { model.items != nil }
        }
        try await eventually { released == nil }
        #expect(released == nil)
    }
}
