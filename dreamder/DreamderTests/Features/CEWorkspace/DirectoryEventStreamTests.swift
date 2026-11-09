import Foundation
import Synchronization
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DirectoryEventStreamTests {
    private final class Collector: Sendable {
        private let storage = Mutex<[DirectoryEventStream.Event]>([])

        func add(_ events: [DirectoryEventStream.Event]) {
            storage.withLock { $0.append(contentsOf: events) }
        }

        var events: [DirectoryEventStream.Event] {
            storage.withLock { $0 }
        }

        func sawEvent(suffix: String, type: FSEvent? = nil) -> Bool {
            events.contains { $0.path.hasSuffix(suffix) && (type == nil || $0.eventType == type) }
        }
    }

    private func makeDirectories(_ names: [String], in root: URL) throws {
        for name in names {
            try FileManager.default.createDirectory(
                at: root.appending(path: name, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }

    @Test
    func fileEventsAreDeliveredWithTheirTypes() async throws {
        try await withTempDir { dir in
            let collector = Collector()
            let stream = DirectoryEventStream(directory: dir.path(percentEncoded: false)) { collector.add($0) }
            defer { stream.cancel() }
            try await Task.sleep(for: .milliseconds(300))

            let file = dir.appending(path: "created.txt")
            try "one".write(to: file, atomically: false, encoding: .utf8)
            try await eventually { collector.sawEvent(suffix: "/created.txt", type: .itemCreated) }

            try "two".write(to: file, atomically: false, encoding: .utf8)
            try await eventually { collector.sawEvent(suffix: "/created.txt", type: .itemModified) }

            let renamed = dir.appending(path: "renamed.txt")
            try FileManager.default.moveItem(at: file, to: renamed)
            try await eventually { collector.sawEvent(suffix: "/renamed.txt", type: .itemRenamed) }

            try FileManager.default.removeItem(at: renamed)
            try await eventually { collector.sawEvent(suffix: "/renamed.txt", type: .itemRemoved) }
        }
    }

    @Test
    func excludedDirectoriesNeverReachTheCallbackWhileTheRestOfTheTreeDoes() async throws {
        try await withTempDir { dir in
            try makeDirectories(["node_modules", "src"], in: dir)
            let policy = WatchExclusionPolicy(folderURL: dir, rules: ExclusionRules(rootURL: dir))
            let collector = Collector()
            let stream = DirectoryEventStream(
                directory: dir.path(percentEncoded: false),
                exclusionPaths: policy.streamExclusionPaths()
            ) { collector.add($0) }
            defer { stream.cancel() }
            try await Task.sleep(for: .milliseconds(300))

            try "x".write(to: dir.appending(path: "node_modules/dep.js"), atomically: false, encoding: .utf8)
            try "y".write(to: dir.appending(path: "src/main.swift"), atomically: false, encoding: .utf8)

            try await eventually { collector.sawEvent(suffix: "/src/main.swift") }
            #expect(collector.events.contains { $0.path.contains("/node_modules/") } == false)
        }
    }

    @Test
    func withoutExclusionPathsEventsUnderNodeModulesAreDelivered() async throws {
        try await withTempDir { dir in
            try makeDirectories(["node_modules"], in: dir)
            let collector = Collector()
            let stream = DirectoryEventStream(directory: dir.path(percentEncoded: false)) { collector.add($0) }
            defer { stream.cancel() }
            try await Task.sleep(for: .milliseconds(300))

            try "x".write(to: dir.appending(path: "node_modules/dep.js"), atomically: false, encoding: .utf8)

            try await eventually { collector.sawEvent(suffix: "/node_modules/dep.js") }
        }
    }

    @Test
    func cancelStopsDeliveryAndMayBeCalledAgain() async throws {
        try await withTempDir { dir in
            let collector = Collector()
            let stream = DirectoryEventStream(directory: dir.path(percentEncoded: false)) { collector.add($0) }
            try await Task.sleep(for: .milliseconds(300))

            stream.cancel()
            stream.cancel()
            try "x".write(to: dir.appending(path: "late.txt"), atomically: false, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(500))

            #expect(collector.sawEvent(suffix: "/late.txt") == false)
        }
    }

    @Test
    func streamCreationFailsWithoutDirectoriesToWatch() throws {
        try withTempDir { dir in
            let owner = DirectoryEventStream(directory: dir.path(percentEncoded: false)) { _ in }
            defer { owner.cancel() }

            let reference = DirectoryEventStream.makeStream(
                owner: owner,
                directories: [],
                exclusionPaths: [],
                debounceDuration: 0.1
            )
            let created = reference != nil

            #expect(created == false)
        }
    }

    @Test
    func payloadEntriesBecomeEventsPerFlagAndEntriesWithoutAPathAreSkipped() {
        let pathKey = kFSEventStreamEventExtendedDataPathKey as String
        let payload = NSArray(array: [
            NSDictionary(dictionary: [pathKey: "/root/one"]),
            NSDictionary(dictionary: ["unrelated": "value"]),
            NSDictionary(dictionary: [pathKey: "/root/two"])
        ])
        let flags: [FSEventStreamEventFlags] = [
            FSEventStreamEventFlags(Int(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified)),
            FSEventStreamEventFlags(Int(kFSEventStreamEventFlagItemRenamed)),
            FSEventStreamEventFlags(Int(kFSEventStreamEventFlagItemRemoved))
        ]

        let events = DirectoryEventStream.events(fromPayload: payload, flags: flags)

        #expect(Set(events.filter { $0.path == "/root/one" }.map(\.eventType)) == [.itemCreated, .itemModified])
        #expect(Set(events.filter { $0.path == "/root/two" }.map(\.eventType)) == [.itemRemoved])
        #expect(events.count == 3)
    }

    @Test
    func aPayloadThatIsNotAListOfDictionariesYieldsNoEvents() {
        let payload = NSArray(array: ["/root/one", "/root/two"])

        let flags: [FSEventStreamEventFlags] = [0, 0]
        let events = DirectoryEventStream.events(fromPayload: payload, flags: flags)

        #expect(events.isEmpty)
    }

    @Test
    func rawFlagsMapToEventTypes() {
        func events(_ flag: Int) -> Set<FSEvent> {
            DirectoryEventStream.events(fromFlags: FSEventStreamEventFlags(flag))
        }

        #expect(events(Int(kFSEventStreamEventFlagNone)) == [.changeInDirectory])
        #expect(events(Int(kFSEventStreamEventFlagRootChanged)) == [.rootChanged])
        #expect(events(Int(kFSEventStreamEventFlagItemChangeOwner)) == [.itemChangedOwner])
        #expect(events(Int(kFSEventStreamEventFlagItemCreated)) == [.itemCreated])
        #expect(events(Int(kFSEventStreamEventFlagItemCloned)) == [.itemCloned])
        #expect(events(Int(kFSEventStreamEventFlagItemModified)) == [.itemModified])
        #expect(events(Int(kFSEventStreamEventFlagItemRemoved)) == [.itemRemoved])
        #expect(events(Int(kFSEventStreamEventFlagItemRenamed)) == [.itemRenamed])
        #expect(
            events(Int(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified))
                == [.itemCreated, .itemModified]
        )
        #expect(events(Int(kFSEventStreamEventFlagItemIsFile)).isEmpty)
    }
}
