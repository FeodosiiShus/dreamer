import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

enum SignatureHelpTestError: Error {
    case failed
}

final class SignatureHelpServerConnection: ServerConnection, Sendable {
    private struct State {
        var params: [SignatureHelpRequestParams] = []
        var didChangesAtRequest: [Int] = []
        var queued: [SignatureHelp?] = []
        var fallback: SignatureHelp?
        var failing = false
        var isHeld = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    let inner: ScriptedServerConnection
    private let state = Mutex(State())

    init(capabilities: ServerCapabilities) {
        inner = ScriptedServerConnection(capabilities: capabilities)
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    var receivedParams: [SignatureHelpRequestParams] {
        state.withLock { $0.params }
    }

    var didChangesAtRequest: [Int] {
        state.withLock { $0.didChangesAtRequest }
    }

    func answer(with help: SignatureHelp?) {
        state.withLock { $0.fallback = help }
    }

    func enqueue(_ answers: [SignatureHelp?]) {
        state.withLock { $0.queued.append(contentsOf: answers) }
    }

    func failRequests(_ failing: Bool) {
        state.withLock { $0.failing = failing }
    }

    func hold() {
        state.withLock { $0.isHeld = true }
    }

    func release() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isHeld = false
            let pending = state.waiters
            state.waiters = []
            return pending
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        guard case let .custom(method, params, _) = request, method == SignatureHelpProtocol.method else {
            return try await inner.sendRequest(request)
        }
        let decoded = try JSONDecoder().decode(SignatureHelpRequestParams.self, from: JSONEncoder().encode(params))
        let changes = inner.notificationCount(.textDocumentDidChange)
        let outcome = state.withLock { state -> (failing: Bool, answer: SignatureHelp?) in
            state.params.append(decoded)
            state.didChangesAtRequest.append(changes)
            let answer = state.queued.isEmpty ? state.fallback : state.queued.removeFirst()
            return (state.failing, answer)
        }
        await waitWhileHeld()
        if outcome.failing {
            throw SignatureHelpTestError.failed
        }
        let data = try outcome.answer.map { try JSONEncoder().encode($0) } ?? Data("null".utf8)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func waitWhileHeld() async {
        await withCheckedContinuation { continuation in
            let resumesNow = state.withLock { state -> Bool in
                if state.isHeld {
                    state.waiters.append(continuation)
                    return false
                }
                return true
            }
            if resumesNow {
                continuation.resume()
            }
        }
    }
}

enum SignatureHelpFixtures {
    static func capabilities(provider: SignatureHelpOptions?) -> ServerCapabilities {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(
            TextDocumentSyncOptions(openClose: true, change: .incremental, willSave: false, willSaveWaitUntil: false, save: nil)
        )
        capabilities.signatureHelpProvider = provider
        return capabilities
    }

    static func signature(
        _ parameters: String...,
        name: String = "function",
        activeParameter: UInt? = nil,
        documentation: String? = nil
    ) -> SignatureInformation {
        SignatureInformation(
            label: "\(name)(\(parameters.joined(separator: ", ")))",
            documentation: documentation.map { TwoTypeOption<String, MarkupContent>.optionA($0) },
            parameters: parameters.map { ParameterInformation(label: .optionA($0)) },
            activeParameter: activeParameter
        )
    }

    static func help(
        _ signatures: [SignatureInformation],
        activeSignature: Int? = nil,
        activeParameter: Int? = nil
    ) -> SignatureHelp {
        SignatureHelp(signatures: signatures, activeSignature: activeSignature, activeParameter: activeParameter)
    }

    static func twoOverloads(activeSignature: Int? = 0, activeParameter: Int? = 0) -> SignatureHelp {
        help(
            [signature("a: Int", "b: String"), signature("a: Int", "b: String", "c: Bool")],
            activeSignature: activeSignature,
            activeParameter: activeParameter
        )
    }

    static func oneOverload(activeParameter: Int? = 0) -> SignatureHelp {
        help([signature("a: Int", "b: String")], activeSignature: 0, activeParameter: activeParameter)
    }
}

@MainActor
struct SignatureHelpEditorHarness {
    let fixture: HostedSourceEditorFixture
    let hosted: HostedSourceEditor
    let controller: TextViewController
    let textView: TextView
    let coordinator: SignatureHelpCoordinator
    let connection: SignatureHelpServerConnection
    let server: LanguageServer<CodeFileDocument>
    let directory: URL

    static func open(
        in directory: URL,
        contents: String,
        provider: SignatureHelpOptions? = SignatureHelpOptions(),
        refreshDelay: Duration = .milliseconds(5),
        visibleFrame: SignatureHelpPopup.VisibleFrameProvider? = nil,
        useServiceLookup: Bool = false,
        useDefaultProviders: Bool = false,
        isCompletionWindowVisible: @escaping SignatureHelpCoordinator.CompletionVisibility = SignatureHelpCoordinator.isSuggestionWindowVisible
    ) async throws -> Self {
        let fixture = try HostedSourceEditorFixture.make(in: directory, contents: contents)
        let capabilities = SignatureHelpFixtures.capabilities(provider: provider)
        let connection = SignatureHelpServerConnection(capabilities: capabilities)
        let server = LanguageServer<CodeFileDocument>(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LanguageServer<CodeFileDocument>.getInitParams(workspacePath: directory.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: directory,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        try await server.openDocument(fixture.document)
        var clientProvider: SignatureHelpCoordinator.ClientProvider?
        if !useServiceLookup {
            clientProvider = { server }
        }
        let coordinator: SignatureHelpCoordinator
        if useDefaultProviders {
            coordinator = SignatureHelpCoordinator(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document,
                clientProvider: clientProvider,
                refreshDelay: refreshDelay
            )
        } else {
            coordinator = SignatureHelpCoordinator(
                editorInstance: fixture.editorInstance,
                codeFile: fixture.document,
                clientProvider: clientProvider,
                refreshDelay: refreshDelay,
                visibleFrameProvider: visibleFrame ?? { _ in nil },
                isCompletionWindowVisible: isCompletionWindowVisible
            )
        }
        let hosted = fixture.host(coordinators: [coordinator], size: NSSize(width: 900, height: 600))
        try await hosted.waitForSettledGeometry()
        let controller = try #require(hosted.controller)
        let textView = try #require(controller.textView)
        hosted.window.makeFirstResponder(textView)
        return Self(
            fixture: fixture,
            hosted: hosted,
            controller: controller,
            textView: textView,
            coordinator: coordinator,
            connection: connection,
            server: server,
            directory: directory
        )
    }

    var childPanels: [SignatureHelpPanel] {
        (hosted.window.childWindows ?? []).compactMap { $0 as? SignatureHelpPanel }
    }

    var caret: Int {
        textView.selectionManager.textSelections.first?.range.location ?? -1
    }

    var text: String {
        textView.string
    }

    func moveCaret(to offset: Int) {
        controller.setCursorPositions([CursorPosition(range: NSRange(location: offset, length: 0))])
    }

    func type(_ string: String) {
        textView.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func close() {
        coordinator.destroy()
        hosted.close()
    }

    func keyEvent(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow? = nil) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: (window ?? hosted.window).windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    func caretAnchor(_ offset: Int) throws -> NSRect {
        try #require(EditorCaretGeometry.screenRect(ofOffset: offset, in: textView))
    }

    func requests(settling: Duration = .milliseconds(120)) async throws -> [SignatureHelpRequestParams] {
        try await Task.sleep(for: settling)
        return connection.receivedParams
    }
}
