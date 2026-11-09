import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class InterleavingScenario {
    private enum Phase {
        case unopened
        case opening
        case open
    }

    struct Attempt {
        let connection: ScriptedServerConnection
        let gate: GatedOpenConnection
        let server: LanguageServer<SyncTestDocument>
    }

    let editor = SyncEditorHarness()
    private(set) var attempts: [Attempt] = []
    private let mode: DocumentSyncMode
    private var generator: SeededRandomNumberGenerator
    private var phase = Phase.unopened
    private var opening: Task<Void, any Error>?
    private var flushes: [Task<Void, Never>] = []

    init(seed: UInt64, mode: DocumentSyncMode) {
        self.mode = mode
        generator = SeededRandomNumberGenerator(seed: seed)
    }

    func run(steps: Int) async throws {
        for _ in 0..<steps {
            try await step()
        }
        if phase == .unopened {
            try await beginOpen()
        }
        try await finishOpen()
        await drainFlushes()
        await editor.coordinator.flushPendingChanges()
    }

    private func step() async throws {
        let choice = Int.random(in: 0..<4, using: &generator)
        switch (phase, choice) {
        case (.unopened, 2), (.unopened, 3):
            try await beginOpen()
        case (.opening, 2), (.open, 2):
            let coordinator = editor.coordinator
            flushes.append(Task { await coordinator.flushPendingChanges() })
        case (.opening, 3):
            try await finishOpen()
        case (.open, 3):
            await drainFlushes()
            try await beginOpen()
        default:
            typeRandomEdit()
        }
    }

    private func beginOpen() async throws {
        let connection = ScriptedServerConnection(capabilities: mode.capabilities)
        let gate = GatedOpenConnection(inner: connection)
        let server = try await SyncTestServer.makeServer(connection: gate, capabilities: mode.capabilities)
        attempts.append(Attempt(connection: connection, gate: gate, server: server))
        let document = editor.document
        opening = Task { try await server.openDocument(document) }
        phase = .opening
        var started = gate.started.makeAsyncIterator()
        _ = await started.next()
    }

    private func finishOpen() async throws {
        guard let pending = opening, let attempt = attempts.last else { return }
        attempt.gate.release()
        try await pending.value
        opening = nil
        phase = .open
    }

    private func drainFlushes() async {
        for flush in flushes {
            await flush.value
        }
        flushes.removeAll()
    }

    private func typeRandomEdit() {
        let current = editor.text as NSString
        let offset = Int.random(in: 0..<current.length, using: &generator)
        let canDelete = current.length > 4 && current.character(at: offset) != 10
        let wantsDelete = Bool.random(using: &generator)
        if canDelete && wantsDelete {
            editor.replace(NSRange(location: offset, length: 1), with: "")
        } else {
            let letter = Character(UnicodeScalar(UInt8(97 + Int.random(in: 0..<26, using: &generator))))
            editor.insert(String(letter), at: offset)
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct LanguageServerSyncInterleavingTests {
    @Test(arguments: DocumentSyncMode.allCases)
    func anyInterleavingOfOpenReopenAndEditsLeavesTheServerWithTheEditorText(mode: DocumentSyncMode) async throws {
        for seed in UInt64(1)...UInt64(40) {
            let scenario = InterleavingScenario(seed: seed, mode: mode)

            try await scenario.run(steps: 16)

            for attempt in scenario.attempts {
                let replay = DocumentSyncReplay(attempt.connection.notifications)
                #expect(replay.changedBeforeOpen == false, "seed \(seed)")
                #expect(replay.versions.first == 0, "seed \(seed)")
                #expect(replay.versionsIncrease, "seed \(seed)")
            }
            let last = try #require(scenario.attempts.last)
            let finalReplay = DocumentSyncReplay(last.connection.notifications)
            #expect(finalReplay.text == scenario.editor.text, "seed \(seed)")
            #expect(last.server.openFiles.documentVersion(for: syncTestDocumentURI) == finalReplay.versions.last)
        }
    }
}
