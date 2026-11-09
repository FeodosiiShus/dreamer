import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LSPCacheTests {
    private let uriA = "file:///tmp/cache/a.swift"
    private let uriB = "file:///tmp/cache/b.swift"

    private func key(
        _ uri: String,
        _ requestType: String = "hover",
        line: Int? = nil,
        version: Int? = nil,
        extra: AnyHashable? = nil
    ) -> CacheKey {
        CacheKey(
            uri: uri,
            requestType: requestType,
            position: line.map { Position(line: $0, character: 1) },
            documentVersion: version,
            extraData: extra
        )
    }

    @Test
    func storedValuesAreReturnedForTheSameKey() {
        let cache = LSPCache()
        let stored = key(uriA, line: 3, version: 2)

        cache.set(key: stored, value: ["one", "two"])

        #expect(cache.get(key: stored, as: [String].self) == ["one", "two"])
        #expect(cache.get(key: key(uriA, line: 3, version: 2), as: [String].self) == ["one", "two"])
    }

    @Test
    func missingKeysAndWrongTypesReturnNil() {
        let cache = LSPCache()
        let stored = key(uriA)
        cache.set(key: stored, value: ["one"])

        #expect(cache.get(key: key(uriB), as: [String].self) == nil)
        #expect(cache.get(key: stored, as: Int.self) == nil)
    }

    @Test
    func settingTheSameKeyAgainReplacesTheValue() {
        let cache = LSPCache()
        let stored = key(uriA)
        cache.set(key: stored, value: 1)
        cache.set(key: stored, value: 2)

        #expect(cache.get(key: stored, as: Int.self) == 2)
    }

    @Test
    func overflowingTheCapacityEvictsTheOldestEntriesOnly() {
        let cache = LSPCache()
        for line in 0...LSPCache.capacity {
            cache.set(key: key(uriA, line: line), value: line)
        }
        cache.set(key: key(uriB), value: -1)

        #expect(cache.get(key: key(uriA, line: 0), as: Int.self) == nil)
        #expect(cache.get(key: key(uriA, line: 1), as: Int.self) == nil)
        #expect(cache.get(key: key(uriA, line: LSPCache.capacity), as: Int.self) == LSPCache.capacity)
        #expect(cache.get(key: key(uriB), as: Int.self) == -1)

        cache.invalidate(uri: uriA)

        #expect(cache.get(key: key(uriA, line: LSPCache.capacity), as: Int.self) == nil)
        #expect(cache.get(key: key(uriB), as: Int.self) == -1)
    }

    @Test
    func replacingAnEntryRefreshesItsPositionInTheEvictionOrder() {
        let cache = LSPCache()
        cache.set(key: key(uriA, line: 0), value: 0)
        for line in 1..<LSPCache.capacity {
            cache.set(key: key(uriA, line: line), value: line)
        }
        cache.set(key: key(uriA, line: 0), value: 100)
        cache.set(key: key(uriB), value: -1)

        #expect(cache.get(key: key(uriA, line: 0), as: Int.self) == 100)
        #expect(cache.get(key: key(uriA, line: 1), as: Int.self) == nil)
    }

    @Test
    func invalidatingAKeyRemovesOnlyThatEntry() {
        let cache = LSPCache()
        let first = key(uriA, line: 1)
        let second = key(uriA, line: 2)
        cache.set(key: first, value: 1)
        cache.set(key: second, value: 2)

        cache.invalidate(key: first)

        #expect(cache.get(key: first, as: Int.self) == nil)
        #expect(cache.get(key: second, as: Int.self) == 2)
    }

    @Test
    func invalidatingAKeyThatWasNeverStoredIsHarmless() {
        let cache = LSPCache()
        let other = key(uriB)
        cache.set(key: other, value: 1)

        cache.invalidate(key: key(uriA))

        #expect(cache.get(key: other, as: Int.self) == 1)
    }

    @Test
    func invalidatingAURIRemovesEveryEntryOfThatURIOnly() {
        let cache = LSPCache()
        let aKeys = [
            key(uriA, "hover", line: 1),
            key(uriA, "references", line: 1, extra: true),
            key(uriA, "completion", version: 4)
        ]
        let bKey = key(uriB, "hover", line: 1)
        for (index, aKey) in aKeys.enumerated() {
            cache.set(key: aKey, value: index)
        }
        cache.set(key: bKey, value: 99)

        cache.invalidate(uri: uriA)

        for aKey in aKeys {
            #expect(cache.get(key: aKey, as: Int.self) == nil)
        }
        #expect(cache.get(key: bKey, as: Int.self) == 99)
    }

    @Test
    func invalidatingAnUnknownURIIsHarmlessAndTheURICanBeFilledAgain() {
        let cache = LSPCache()
        let stored = key(uriA)

        cache.invalidate(uri: uriA)
        cache.set(key: stored, value: 5)
        cache.invalidate(uri: uriA)
        cache.invalidate(uri: uriA)
        cache.set(key: stored, value: 6)

        #expect(cache.get(key: stored, as: Int.self) == 6)
    }

    @Test
    func invalidatingAKeyThenItsURIKeepsTrackingConsistent() {
        let cache = LSPCache()
        let first = key(uriA, line: 1)
        let second = key(uriA, line: 2)
        cache.set(key: first, value: 1)
        cache.set(key: second, value: 2)

        cache.invalidate(key: first)
        cache.invalidate(uri: uriA)

        #expect(cache.get(key: second, as: Int.self) == nil)
    }

    @Test
    func descriptionsAreDistinctPerPositionVersionExtraDataAndRequestType() {
        let keys = [
            key(uriA),
            key(uriA, "definition"),
            key(uriA, line: 1),
            key(uriA, line: 2),
            key(uriA, version: 1),
            key(uriA, version: 2),
            key(uriA, line: 1, version: 1),
            key(uriA, extra: true),
            key(uriA, extra: false),
            key(uriB)
        ]

        #expect(Set(keys.map(\.description)).count == keys.count)
        #expect(Set(keys).count == keys.count)
    }

    @Test
    func descriptionJoinsEveryPresentPart() {
        #expect(key(uriA).description == "\(uriA)|hover")
        #expect(key(uriA, line: 4).description == "\(uriA)|hover|4:1")
        #expect(key(uriA, line: 4, version: 7).description == "\(uriA)|hover|4:1|v7")
        #expect(key(uriA, "references", line: 4, version: 7, extra: true).description == "\(uriA)|references|4:1|v7|true")
    }

    @Test
    func cacheEntriesRememberTheirTypeAndOnlyCastToIt() {
        let entry = LSPCache.CacheEntry(5)

        let storesInt = entry.type == Int.self
        #expect(storesInt)
        #expect(entry.getValue(as: Int.self) == 5)
        #expect(entry.getValue(as: String.self) == nil)
    }
}
