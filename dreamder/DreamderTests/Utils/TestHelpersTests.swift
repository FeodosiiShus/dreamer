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
        IsolatedDefaults.$currentSuiteName.withValue(nil) {
            #expect(throws: IsolatedDefaultsError.outsideIsolatedScope) {
                try IsolatedDefaults.require()
            }
        }
    }

    @Test
    func closureFormExposesTheSuiteAsCurrent() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("x", forKey: "closure.key")
            let current = try IsolatedDefaults.require()
            #expect(current.string(forKey: "closure.key") == "x")
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
    }

    @Test
    func suiteNamesComeFromTheBoundedPool() throws {
        let created = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(created.defaults, suiteName: created.suiteName) }
        let prefix = "dreamder.tests.isolated." + TestShard.suiteFragment
        #expect(created.suiteName.hasPrefix(prefix))
        #expect(Int(created.suiteName.dropFirst(prefix.count)) != nil)
    }
}

@Suite
struct IsolatedDefaultsPoolTests {
    @Test
    func aReleasedSuiteNameIsReusedAndComesBackEmpty() throws {
        let pool = IsolatedDefaultsPool(prefix: "dreamder.tests.poolcheck.reuse.")
        let name = pool.acquire()
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set("kept", forKey: "pool.key")
        #expect(defaults.string(forKey: "pool.key") == "kept")

        pool.release(name)
        let reused = pool.acquire()
        defer { pool.release(reused) }

        #expect(reused == name)
        let reopened = try #require(UserDefaults(suiteName: reused))
        #expect(reopened.object(forKey: "pool.key") == nil)
    }

    @Test
    func suiteNamesHeldAtTheSameTimeAreDistinct() {
        let pool = IsolatedDefaultsPool(prefix: "dreamder.tests.poolcheck.distinct.")
        let names = (0..<5).map { _ in pool.acquire() }
        defer { names.forEach(pool.release) }
        #expect(Set(names).count == names.count)
    }

    @Test
    func concurrentAcquisitionsNeverShareAName() async {
        let pool = IsolatedDefaultsPool(prefix: "dreamder.tests.poolcheck.concurrent.")
        let count = 32
        let names = await withTaskGroup(of: String.self) { group in
            for _ in 0..<count {
                group.addTask { pool.acquire() }
            }
            return await group.reduce(into: [String]()) { $0.append($1) }
        }
        #expect(Set(names).count == count)

        names.forEach(pool.release)
        let afterwards = (0..<count).map { _ in pool.acquire() }
        defer { afterwards.forEach(pool.release) }
        #expect(Set(afterwards) == Set(names))
    }

    @Test
    func releasingTwiceOrReleasingAForeignNameNeverHandsOutADuplicate() {
        let pool = IsolatedDefaultsPool(prefix: "dreamder.tests.poolcheck.foreign.")
        let held = pool.acquire()
        let released = pool.acquire()
        pool.release(released)
        pool.release(released)
        pool.release("dreamder.tests.poolcheck.foreign.not-a-number")
        pool.release("somebody.else.0")

        let first = pool.acquire()
        let second = pool.acquire()
        defer { [held, first, second].forEach(pool.release) }
        #expect(Set([held, first, second]).count == 3)
        #expect(first == released)
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
    func directoryIsRemovedWhenTheBodyThrows() throws {
        struct Failure: Error {}
        var captured: URL?
        #expect(throws: Failure.self) {
            try withTempDir { dir in
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

    private func writeKeys(referencing directory: URL, into defaults: UserDefaults) -> [String] {
        let path = directory.path(percentEncoded: false)
        let barePath = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        let keys = [
            "workspaceState-" + directory.absoluteString,
            "dreamder.recentFiles." + barePath,
            "NSOutlineView Items /private" + barePath,
            "NSWindow Frame " + directory.appending(path: "sub folder/a b.txt").absoluteString,
            "NSWindow Frame /private" + barePath + "/child",
        ]
        for key in keys {
            defaults.set("value", forKey: key)
        }
        return keys
    }

    @Test
    func standardDefaultsKeysOfATemporaryDirectoryAreGoneAfterWithTempDir() throws {
        let unrelatedKey = "dreamder.tests.helpers.unrelated.\(UUID().uuidString)"
        UserDefaults.standard.set("kept", forKey: unrelatedKey)
        defer { UserDefaults.standard.removeObject(forKey: unrelatedKey) }
        var written: [String] = []
        try withTempDir { dir in
            written = writeKeys(referencing: dir, into: .standard)
            for key in written {
                #expect(UserDefaults.standard.string(forKey: key) == "value")
            }
        }
        #expect(written.count == 5)
        for key in written {
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
        #expect(UserDefaults.standard.string(forKey: unrelatedKey) == "kept")
    }

    @Test
    func standardDefaultsKeysAreAlsoRemovedByTheAsyncWithTempDir() async throws {
        var written: [String] = []
        try await withTempDir { dir in
            written = writeKeys(referencing: dir, into: .standard)
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(written.count == 5)
        for key in written {
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
    }

    @Test
    func standardDefaultsKeysAreRemovedWhenTheBodyThrows() throws {
        struct Failure: Error {}
        var written: [String] = []
        #expect(throws: Failure.self) {
            try withTempDir { dir in
                written = writeKeys(referencing: dir, into: .standard)
                throw Failure()
            }
        }
        #expect(written.count == 5)
        for key in written {
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
    }

    @Test
    func removingATemporaryDirectoryKeepsTheKeysOfOtherDirectories() throws {
        let first = try makeTemporaryDirectory(label: "defaultsFirst")
        let second = try makeTemporaryDirectory(label: "defaultsSecond")
        defer { removeTemporaryDirectory(second) }
        let firstKeys = writeKeys(referencing: first, into: .standard)
        let secondKeys = writeKeys(referencing: second, into: .standard)

        removeTemporaryDirectory(first)

        for key in firstKeys {
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
        for key in secondKeys {
            #expect(UserDefaults.standard.string(forKey: key) == "value")
        }
    }

    @Test
    func keysAreRemovedEvenWhenTheDirectoryIsAlreadyGone() throws {
        let directory = try makeTemporaryDirectory(label: "defaultsGone")
        try FileManager.default.removeItem(at: directory)
        let keys = writeKeys(referencing: directory, into: .standard)

        removeTemporaryDirectory(directory)

        for key in keys {
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
    }

    @Test
    func removeStandardDefaultsKeysOnlyTouchesTheGivenDefaults() throws {
        let directory = try makeTemporaryDirectory(label: "defaultsScoped")
        defer { removeTemporaryDirectory(directory) }
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let keys = writeKeys(referencing: directory, into: isolated.defaults)
        isolated.defaults.set("kept", forKey: "unrelated")

        removeDefaultsKeys(referencing: directory, in: isolated.defaults, domain: isolated.suiteName)

        for key in keys {
            #expect(isolated.defaults.object(forKey: key) == nil)
        }
        #expect(isolated.defaults.string(forKey: "unrelated") == "kept")
    }
}
