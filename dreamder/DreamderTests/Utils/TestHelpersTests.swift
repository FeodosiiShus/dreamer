import Foundation
import Testing

@Suite(.isolatedDefaults)
struct IsolatedDefaultsTests {
    @Test
    func traitProvidesAFreshSuitePerTest() throws {
        let defaults = try IsolatedDefaults.require()
        #expect(defaults.object(forKey: "isolated.key") == nil)
        defaults.set("value", forKey: "isolated.key")
        #expect(defaults.string(forKey: "isolated.key") == "value")
    }

    @Test
    func traitDoesNotShareStateBetweenTests() throws {
        let defaults = try IsolatedDefaults.require()
        #expect(defaults.object(forKey: "isolated.key") == nil)
        defaults.set(1, forKey: "isolated.key")
    }

    @Test(arguments: [1, 2, 3])
    func parameterizedCasesEachGetTheirOwnSuite(value: Int) throws {
        let defaults = try IsolatedDefaults.require()
        #expect(defaults.object(forKey: "isolated.argument") == nil)
        defaults.set(value, forKey: "isolated.argument")
    }

    @Test
    func requireFailsOutsideAnIsolatedScope() {
        IsolatedDefaults.$current.withValue(nil) {
            #expect(throws: IsolatedDefaultsError.outsideIsolatedScope) {
                try IsolatedDefaults.require()
            }
        }
    }

    @Test
    func closureFormExposesTheSuiteAsCurrent() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("x", forKey: "closure.key")
            #expect(IsolatedDefaults.current === defaults)
            #expect(defaults.string(forKey: "closure.key") == "x")
        }
    }

    @Test
    func removingTheSuiteDropsItsValues() throws {
        let created = try makeIsolatedDefaults()
        created.defaults.set("y", forKey: "removal.key")
        #expect(created.defaults.string(forKey: "removal.key") == "y")
        removeIsolatedDefaults(created.defaults, suiteName: created.suiteName)
        let reopened = try #require(UserDefaults(suiteName: created.suiteName))
        #expect(reopened.object(forKey: "removal.key") == nil)
        removeIsolatedDefaults(reopened, suiteName: created.suiteName)
    }
}

@Suite
struct TemporaryDirectoryTests {
    @Test
    func directoryExistsInsideTheBodyAndIsRemovedAfterwards() throws {
        var captured: URL?
        try withTempDir { dir in
            captured = dir
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false), isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            try "x".write(to: dir.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        }
        let removed = try #require(captured)
        #expect(!FileManager.default.fileExists(atPath: removed.path(percentEncoded: false)))
    }

    @Test
    func directoryIsRemovedWhenTheBodyThrows() async throws {
        struct Failure: Error {}
        var captured: URL?
        await #expect(throws: Failure.self) {
            try await withTempDir { dir in
                captured = dir
                throw Failure()
            }
        }
        let removed = try #require(captured)
        #expect(!FileManager.default.fileExists(atPath: removed.path(percentEncoded: false)))
    }

    @Test
    func everyCallGetsADistinctDirectoryInsideTheTemporaryDirectory() throws {
        let first = try makeTemporaryDirectory(label: "same")
        let second = try makeTemporaryDirectory(label: "same")
        defer {
            removeTemporaryDirectory(first)
            removeTemporaryDirectory(second)
        }
        #expect(first != second)
        let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path(percentEncoded: false)
        #expect(first.path(percentEncoded: false).hasPrefix(temporaryRoot))
    }

    @Test
    func labelsAreSanitizedIntoASingleFileName() throws {
        let url = try makeTemporaryDirectory(label: "DreamderTests/Some Test.swift:[a?b]")
        defer { removeTemporaryDirectory(url) }
        #expect(url.deletingLastPathComponent().resolvingSymlinksInPath()
            == FileManager.default.temporaryDirectory.resolvingSymlinksInPath())
    }
}
