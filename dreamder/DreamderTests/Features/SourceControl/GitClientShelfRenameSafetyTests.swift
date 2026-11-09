import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated final class StashSimulator: Sendable {
    struct Entry: Equatable, Sendable {
        let hash: String
        let subject: String
    }

    private let entries: Mutex<[Entry]>
    private let storeCalls = Mutex(0)
    private let failingStoreCalls: Set<Int>
    private let removesPreviousCopyAfterStore: Bool

    init(entries: [Entry], failingStoreCalls: Set<Int> = [], removesPreviousCopyAfterStore: Bool = false) {
        self.entries = Mutex(entries)
        self.failingStoreCalls = failingStoreCalls
        self.removesPreviousCopyAfterStore = removesPreviousCopyAfterStore
    }

    var current: [Entry] {
        entries.withLock { $0 }
    }

    func handle(_ invocation: ProcessInvocation) -> ProcessOutput {
        let arguments = ScmFakeGit.arguments(invocation)
        guard arguments.first == "stash", let action = arguments.dropFirst().first else { return ScmFakeGit.ok() }
        switch action {
        case "list":
            return ScmFakeGit.ok(listing())
        case "store":
            return store(message: arguments.dropFirst(3).first ?? "", hash: arguments.last ?? "")
        case "drop":
            return drop(reference: arguments.last ?? "")
        default:
            return ScmFakeGit.ok()
        }
    }

    private func listing() -> String {
        entries.withLock { entries in
            entries.enumerated()
                .map { "\($1.hash)\u{1f}\(1000 + $0)\u{1f}\($1.subject)" }
                .joined(separator: "\n")
        }
    }

    private func store(message: String, hash: String) -> ProcessOutput {
        let call = storeCalls.withLock { count -> Int in
            count += 1
            return count
        }
        guard !failingStoreCalls.contains(call) else { return ScmFakeGit.failure("fatal: could not store") }
        entries.withLock { entries in
            if entries.first?.hash != hash {
                entries.insert(Entry(hash: hash, subject: message), at: 0)
            }
            if removesPreviousCopyAfterStore {
                entries.removeAll { $0.hash == hash && $0.subject != message }
            }
        }
        return ScmFakeGit.ok()
    }

    private func drop(reference: String) -> ProcessOutput {
        let index = Int(reference.dropFirst("stash@{".count).dropLast()) ?? -1
        let removed = entries.withLock { entries -> Bool in
            guard entries.indices.contains(index) else { return false }
            entries.remove(at: index)
            return true
        }
        return removed ? ScmFakeGit.ok() : ScmFakeGit.failure("error: \(reference) is not a valid reference")
    }
}

@Suite
struct GitClientShelfRenameSafetyTests {
    private typealias Entry = StashSimulator.Entry

    private static let listArguments = ["stash", "list", "--format=%H%x1f%ct%x1f%gs"]
    private static let other = Entry(hash: "1111", subject: "On main: keep me")

    private static func shelf(_ name: String) -> Entry {
        Entry(hash: "2222", subject: "On main: " + GitShelf.marker + name)
    }

    private static func client(_ simulator: StashSimulator) -> (client: GitClient, fake: FakeProcessRunner) {
        ScmFakeGit.client { simulator.handle($0) }
    }

    private static func storeArguments(_ entry: Entry) -> [String] {
        ["stash", "store", "--message", entry.subject, entry.hash]
    }

    @Test
    func renamingALowerShelfStoresTheNewEntryBeforeDroppingTheOldOne() async throws {
        let simulator = StashSimulator(entries: [Self.other, Self.shelf("old")])
        let (client, fake) = Self.client(simulator)

        try await client.renameShelf(hash: "2222", to: "new")

        #expect(simulator.current == [Self.shelf("new"), Self.other])
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            Self.listArguments,
            Self.storeArguments(Self.shelf("new")),
            Self.listArguments,
            ["stash", "drop", "stash@{2}"]
        ])
    }

    @Test
    func aFailingStoreLeavesTheOriginalShelfInPlaceAndDropsNothing() async throws {
        let original = [Self.other, Self.shelf("old")]
        let simulator = StashSimulator(entries: original, failingStoreCalls: [1])
        let (client, fake) = Self.client(simulator)

        let error = await shelfThrownError { try await client.renameShelf(hash: "2222", to: "new") }

        let failure = try #require(error as? GitClient.GitClientError)
        #expect(failure.description.contains("could not store"))
        #expect(simulator.current == original)
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            Self.listArguments,
            Self.storeArguments(Self.shelf("new"))
        ])
    }

    @Test
    func renamingTheTopShelfDropsItFirstBecauseStoringTheSameCommitIsANoOp() async throws {
        let simulator = StashSimulator(entries: [Self.shelf("old"), Self.other])
        let (client, fake) = Self.client(simulator)

        try await client.renameShelf(hash: "2222", to: "new")

        #expect(simulator.current == [Self.shelf("new"), Self.other])
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            Self.listArguments,
            ["stash", "drop", "stash@{0}"],
            Self.storeArguments(Self.shelf("new"))
        ])
    }

    @Test
    func aFailingStoreOfTheTopShelfIsRolledBackToTheOriginalMessage() async throws {
        let original = [Self.shelf("old"), Self.other]
        let simulator = StashSimulator(entries: original, failingStoreCalls: [1])
        let (client, fake) = Self.client(simulator)

        let error = await shelfThrownError { try await client.renameShelf(hash: "2222", to: "new") }

        let failure = try #require(error as? GitClient.GitClientError)
        #expect(failure.description.contains("could not store"))
        #expect(simulator.current == original)
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            Self.listArguments,
            ["stash", "drop", "stash@{0}"],
            Self.storeArguments(Self.shelf("new")),
            Self.storeArguments(Self.shelf("old"))
        ])
    }

    @Test
    func theOriginalStoreErrorSurvivesAFailedRollback() async throws {
        let simulator = StashSimulator(entries: [Self.shelf("old"), Self.other], failingStoreCalls: [1, 2])
        let (client, fake) = Self.client(simulator)

        let error = await shelfThrownError { try await client.renameShelf(hash: "2222", to: "new") }

        let failure = try #require(error as? GitClient.GitClientError)
        #expect(failure.description.contains("could not store"))
        #expect(simulator.current == [Self.other])
        #expect(fake.invocations.count == 4)
    }

    @Test
    func aShelfThatVanishesBetweenStoreAndDropReportsNotFoundAndKeepsTheNewEntry() async throws {
        let simulator = StashSimulator(entries: [Self.other, Self.shelf("old")], removesPreviousCopyAfterStore: true)
        let (client, _) = Self.client(simulator)

        let error = await shelfThrownError { try await client.renameShelf(hash: "2222", to: "new") }

        #expect((error as? GitShelfError) == .notFound)
        #expect(simulator.current == [Self.shelf("new"), Self.other])
    }

    @Test
    func aNameThatDoesNotChangeTouchesNothing() async throws {
        let simulator = StashSimulator(entries: [Self.other, Self.shelf("old")])
        let (client, fake) = Self.client(simulator)

        try await client.renameShelf(hash: "2222", to: "  old ")

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [Self.listArguments])
        #expect(simulator.current == [Self.other, Self.shelf("old")])
    }

    @Test
    func renamingTheTopShelfInARealRepositoryKeepsTheCommitAndTheEntriesBelow() async throws {
        try await withTempDir { directory in
            let repo = try await ShelfRepo.make(in: directory)
            let plain = try await repo.plainStash("docs/guide.md", "guide2\n", message: "keep me")
            try repo.fixture.write("a.txt", "a2\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "top")

            try await repo.client.renameShelf(hash: shelf.hash, to: "renamed top")

            #expect(try await repo.stashHashes() == [shelf.hash, plain])
            let subjects = try await repo.stashSubjects()
            #expect(subjects.first == "On main: " + GitShelf.marker + "renamed top")
            #expect(subjects.last?.hasSuffix("keep me") == true)
        }
    }
}
