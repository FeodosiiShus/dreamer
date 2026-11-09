import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LSPContentCoordinatorTests {
    typealias Coordinator = LSPContentCoordinator<SyncTestDocument>

    private let uri = syncTestDocumentURI

    private func edit(_ coordinator: Coordinator, _ text: String, at column: Int = 0) {
        coordinator.recordEdit(uri: uri, range: SyncTestServer.range(0, column, column), string: text)
    }

    @Test
    func recordEditInvalidatesTheServerCacheImmediatelyAndKeepsTheEditPending() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let hoverKey = CacheKey(uri: uri, requestType: "hover")
        let otherKey = CacheKey(uri: "file:///tmp/sync/other.swift", requestType: "hover")
        harness.server.lspCache.set(key: hoverKey, value: ["cached"])
        harness.server.lspCache.set(key: otherKey, value: ["other"])

        edit(coordinator, "a")

        #expect(harness.server.lspCache.get(key: hoverKey, as: [String].self) == nil)
        #expect(harness.server.lspCache.get(key: otherKey, as: [String].self) == ["other"])
        #expect(coordinator.hasPendingChanges)
        #expect(harness.didChanges.isEmpty)
    }

    @Test
    func editsAreBatchedUntilFlushedAndSentAsOneDidChange() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator

        edit(coordinator, "a", at: 0)
        edit(coordinator, "b", at: 1)
        edit(coordinator, "c", at: 2)
        #expect(harness.didChanges.isEmpty)

        await coordinator.flushPendingChanges()

        let changes = try #require(harness.didChanges.first)
        #expect(harness.didChanges.count == 1)
        #expect(changes.textDocument.version == 1)
        #expect(changes.contentChanges.map(\.text) == ["a", "b", "c"])
        #expect(changes.contentChanges.map(\.range) == [
            SyncTestServer.range(0, 0, 0),
            SyncTestServer.range(0, 1, 1),
            SyncTestServer.range(0, 2, 2)
        ])
        #expect(coordinator.hasPendingChanges == false)
    }

    @Test
    func theBatchTimerSendsEveryEditInOneDidChangeAndRearmsForLaterEdits() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .milliseconds(30))
        let coordinator = document.languageServerObjects.textCoordinator

        edit(coordinator, "a", at: 0)
        edit(coordinator, "b", at: 1)
        try await eventually { harness.didChanges.count == 1 }

        #expect(harness.didChanges.first?.contentChanges.map(\.text) == ["a", "b"])
        #expect(coordinator.hasPendingChanges == false)

        edit(coordinator, "c", at: 2)
        try await eventually { harness.didChanges.count == 2 }

        #expect(harness.didChanges.last?.contentChanges.map(\.text) == ["c"])
        #expect(harness.didChanges.map(\.textDocument.version) == [1, 2])
    }

    @Test
    func flushingWithNothingPendingSendsNothing() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))

        await document.languageServerObjects.textCoordinator.flushPendingChanges()

        #expect(harness.didChanges.isEmpty)
    }

    @Test
    func flushesAreOrderedBehindInFlightSendsAndAwaitThem() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let gate = GatedChangeConnection(inner: scripted)
        let server = try await SyncTestServer.makeServer(connection: gate, capabilities: capabilities)
        let document = SyncTestDocument()
        let coordinator = Coordinator(batchInterval: .seconds(60))
        document.languageServerObjects.textCoordinator = coordinator
        try await server.openDocument(document)

        edit(coordinator, "a")
        let first = Task { await coordinator.flushPendingChanges() }
        var started = gate.started.makeAsyncIterator()
        _ = await started.next()
        #expect(scripted.notificationCount(.textDocumentDidChange) == 0)

        edit(coordinator, "b")
        let second = Task { await coordinator.flushPendingChanges() }
        let idle = Task { () -> Int in
            await coordinator.flushPendingChanges()
            return scripted.notificationCount(.textDocumentDidChange)
        }
        gate.release()
        gate.release()
        await first.value
        await second.value
        let changesSeenByIdleFlush = await idle.value

        #expect(changesSeenByIdleFlush == 2)
        let changes = scripted.notifications.compactMap { notification -> DidChangeTextDocumentParams? in
            if case let .textDocumentDidChange(params) = notification {
                return params
            }
            return nil
        }
        #expect(changes.map(\.textDocument.version) == [1, 2])
        #expect(changes.map { $0.contentChanges.map(\.text) } == [["a"], ["b"]])
        #expect(server.openFiles.documentVersion(for: uri) == 2)
        withExtendedLifetime(document) {}
    }

    @Test
    func aRequestShortlyAfterAnEditSeesTheDidChangeFirstAndCancelsTheTimer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .milliseconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        try harness.connection.script(.textDocumentDefinition, SyncTestServer.location(uri: uri, line: 0))

        edit(coordinator, "x")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await harness.server.requestGoToDefinition(for: uri, position: Position(line: 0, character: 0))

        let log = harness.connection.log
        let changeIndex = try #require(log.firstIndex(of: "textDocument/didChange"))
        let definitionIndex = try #require(log.firstIndex(of: "textDocument/definition"))
        #expect(changeIndex < definitionIndex)
        #expect(coordinator.hasPendingChanges == false)

        try await Task.sleep(for: .milliseconds(150))

        #expect(harness.didChanges.count == 1)
    }

    @Test
    func discardingDropsPendingEditsAndCancelsTheTimer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .milliseconds(30))
        let coordinator = document.languageServerObjects.textCoordinator

        edit(coordinator, "a")
        coordinator.discardPendingChanges()
        try await Task.sleep(for: .milliseconds(120))
        await coordinator.flushPendingChanges()

        #expect(coordinator.hasPendingChanges == false)
        #expect(harness.didChanges.isEmpty)
    }

    @Test
    func destroyDropsPendingEditsAndCancelsTheTimer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .milliseconds(30))
        let coordinator = document.languageServerObjects.textCoordinator

        edit(coordinator, "a")
        coordinator.destroy()
        try await Task.sleep(for: .milliseconds(120))

        #expect(coordinator.hasPendingChanges == false)
        #expect(harness.didChanges.isEmpty)
    }

    @Test
    func preparingTheCoordinatorForAControllerCancelsTheArmedTimerButKeepsTheEdits() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        let theme = try #require(ThemeModel.shared.selectedTheme ?? ThemeModel.shared.themes.first)
        let coordinator = Coordinator(documentURI: uri, languageServer: harness.server, batchInterval: .milliseconds(30))
        edit(coordinator, "a")

        let controller = TextViewController(
            string: "x",
            language: .swift,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme.editor.editorTheme,
                    font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    wrapLines: false
                )
            ),
            cursorPositions: [],
            highlightProviders: [],
            coordinators: [coordinator]
        )
        try await Task.sleep(for: .milliseconds(120))

        #expect(harness.didChanges.isEmpty)
        #expect(coordinator.hasPendingChanges)

        await coordinator.flushPendingChanges()

        #expect(harness.didChanges.count == 1)
        withExtendedLifetime(controller) {}
    }

    @Test
    func textViewEditsAreRecordedWithTheirLSPRangesAndSentOnFlush() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "hello world\nsecond", batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let textView = TextView(string: "hello world\nsecond")
        textView.delegate = coordinator
        let key = CacheKey(uri: uri, requestType: "hover")
        harness.server.lspCache.set(key: key, value: ["cached"])

        textView.replaceCharacters(in: NSRange(location: 5, length: 0), with: ",")
        textView.replaceCharacters(in: NSRange(location: 14, length: 3), with: "")

        #expect(coordinator.hasPendingChanges)
        #expect(harness.server.lspCache.get(key: key, as: [String].self) == nil)

        await coordinator.flushPendingChanges()

        let contentChanges = try #require(harness.didChanges.first?.contentChanges)
        #expect(contentChanges.map(\.text) == [",", ""])
        #expect(contentChanges.map(\.range) == [SyncTestServer.range(0, 5, 5), SyncTestServer.range(1, 1, 4)])
    }

    @Test
    func replacementsWithoutAPrecedingWillReplaceOrWithoutAURIAreIgnored() async throws {
        let harness = try await SyncTestServer.make()
        let textView = TextView(string: "hello world")

        let withURI = Coordinator(documentURI: uri, languageServer: harness.server, batchInterval: .seconds(60))
        withURI.textView(textView, didReplaceContentsIn: NSRange(location: 0, length: 0), with: "a")
        withURI.textView(textView, willReplaceContentsIn: NSRange(location: 500, length: 1), with: "")
        withURI.textView(textView, didReplaceContentsIn: NSRange(location: 500, length: 1), with: "")
        #expect(withURI.hasPendingChanges == false)

        let withoutURI = Coordinator(languageServer: harness.server, batchInterval: .seconds(60))
        withoutURI.textView(textView, willReplaceContentsIn: NSRange(location: 0, length: 0), with: "a")
        withoutURI.textView(textView, didReplaceContentsIn: NSRange(location: 0, length: 0), with: "a")
        #expect(withoutURI.hasPendingChanges == false)
        #expect(harness.didChanges.isEmpty)
    }

    private func makeController(_ coordinator: Coordinator) throws -> TextViewController {
        let theme = try #require(ThemeModel.shared.selectedTheme ?? ThemeModel.shared.themes.first)
        return TextViewController(
            string: "hello world",
            language: .swift,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme.editor.editorTheme,
                    font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    wrapLines: false
                )
            ),
            cursorPositions: [],
            highlightProviders: [],
            coordinators: [coordinator]
        )
    }

    private func applyBehindTheDelegatesBack(_ textView: TextView, replacing range: NSRange, with string: String) {
        NotificationCenter.default.post(name: TextView.textWillChangeNotification, object: textView)
        textView.textStorage.replaceCharacters(in: range, with: string)
        NotificationCenter.default.post(name: TextView.textDidChangeNotification, object: textView)
    }

    @Test
    func editsAppliedWithoutTheDelegateAreSentAsAFullDocumentChange() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "hello world", batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let controller = try makeController(coordinator)
        let textView = try #require(controller.textView)
        let key = CacheKey(uri: uri, requestType: "hover")
        harness.server.lspCache.set(key: key, value: ["cached"])

        applyBehindTheDelegatesBack(textView, replacing: NSRange(location: 0, length: 0), with: "}")

        #expect(coordinator.hasPendingChanges)
        #expect(harness.server.lspCache.get(key: key, as: [String].self) == nil)

        await coordinator.flushPendingChanges()

        let change = try #require(harness.didChanges.first?.contentChanges.first)
        #expect(harness.didChanges.count == 1)
        #expect(change.range == nil)
        #expect(change.text == "hello world")
        withExtendedLifetime(controller) {}
    }

    @Test
    func aNestedChangeIsReconciledOnceItsOutermostChangeEnds() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "hello world", batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let controller = try makeController(coordinator)
        let textView = try #require(controller.textView)

        NotificationCenter.default.post(name: TextView.textWillChangeNotification, object: textView)
        NotificationCenter.default.post(name: TextView.textWillChangeNotification, object: textView)
        textView.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "}")
        NotificationCenter.default.post(name: TextView.textDidChangeNotification, object: textView)
        #expect(!coordinator.hasPendingChanges)
        NotificationCenter.default.post(name: TextView.textDidChangeNotification, object: textView)

        #expect(coordinator.hasPendingChanges)
        withExtendedLifetime(controller) {}
    }

    @Test
    func editsThroughTheDelegateAreNeverReplacedByAFullDocumentChange() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "hello world", batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let controller = try makeController(coordinator)
        let textView = try #require(controller.textView)
        textView.delegate = coordinator

        textView.replaceCharacters(in: NSRange(location: 5, length: 0), with: ",")
        await coordinator.flushPendingChanges()

        let changes = try #require(harness.didChanges.first?.contentChanges)
        #expect(harness.didChanges.count == 1)
        #expect(changes.map(\.text) == [","])
        #expect(changes.first?.range == SyncTestServer.range(0, 5, 5))
        withExtendedLifetime(controller) {}
    }

    @Test
    func destroyingTheCoordinatorStopsObservingTheTextView() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "hello world", batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let controller = try makeController(coordinator)
        let textView = try #require(controller.textView)

        coordinator.destroy()
        applyBehindTheDelegatesBack(textView, replacing: NSRange(location: 0, length: 0), with: "}")

        #expect(!coordinator.hasPendingChanges)
        withExtendedLifetime(controller) {}
    }

    @Test
    func aCoordinatorWithoutAServerStillDrainsItsBatch() async {
        let coordinator = Coordinator(batchInterval: .seconds(60))

        edit(coordinator, "a")
        #expect(coordinator.hasPendingChanges)
        await coordinator.flushPendingChanges()

        #expect(coordinator.hasPendingChanges == false)
    }

    @Test
    func setUpBindsTheServerAndTheDocumentURI() async throws {
        let harness = try await SyncTestServer.make()
        let coordinator = Coordinator()
        let document = SyncTestDocument()

        coordinator.setUp(server: harness.server, document: document)

        #expect(coordinator.languageServer === harness.server)
        #expect(coordinator.documentURI == uri)
    }
}
