import AppKit
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
@testable import Dreamder

final class GatedOpenConnection: ServerConnection, Sendable {
    let inner: ScriptedServerConnection
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let releases: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init(inner: ScriptedServerConnection) {
        self.inner = inner
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
        (releases, releaseContinuation) = AsyncStream<Void>.makeStream()
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    func release() {
        releaseContinuation.yield()
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        if notif.method == .textDocumentDidOpen {
            startedContinuation.yield()
            var iterator = releases.makeAsyncIterator()
            _ = await iterator.next()
        }
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        try await inner.sendRequest(request)
    }
}

struct DocumentSyncReplay {
    private(set) var text: String?
    private(set) var versions: [Int] = []
    private(set) var changedBeforeOpen = false

    init(_ notifications: [ClientNotification]) {
        for notification in notifications {
            switch notification {
            case let .textDocumentDidOpen(params):
                text = params.textDocument.text
                versions.append(Int(params.textDocument.version))
            case let .textDocumentDidChange(params):
                guard var current = text else {
                    changedBeforeOpen = true
                    continue
                }
                for change in params.contentChanges {
                    current = Self.apply(change, to: current)
                }
                text = current
                versions.append(params.textDocument.version ?? -1)
            default:
                continue
            }
        }
    }

    var versionsIncrease: Bool {
        zip(versions, versions.dropFirst()).allSatisfy { $0 < $1 }
    }

    private static func apply(_ change: TextDocumentContentChangeEvent, to text: String) -> String {
        guard let range = change.range else { return change.text }
        let storage = NSMutableString(string: text)
        let start = offset(of: range.start, in: storage)
        let end = offset(of: range.end, in: storage)
        storage.replaceCharacters(in: NSRange(location: start, length: max(end - start, 0)), with: change.text)
        return storage as String
    }

    private static func offset(of position: Position, in text: NSString) -> Int {
        var lineStart = 0
        for _ in 0..<Int(position.line) {
            let newline = text.range(
                of: "\n",
                range: NSRange(location: lineStart, length: text.length - lineStart)
            )
            if newline.location == NSNotFound {
                return text.length
            }
            lineStart = newline.location + 1
        }
        return min(lineStart + Int(position.character), text.length)
    }
}

@MainActor
final class SyncEditorHarness {
    typealias Coordinator = LSPContentCoordinator<SyncTestDocument>

    let document: SyncTestDocument
    let coordinator: Coordinator
    let textView: TextView

    init(text: String = "hello\nworld", batchInterval: Duration = .seconds(60)) {
        document = SyncTestDocument(text: text)
        coordinator = Coordinator(batchInterval: batchInterval)
        document.languageServerObjects.textCoordinator = coordinator
        textView = TextView(string: text)
        textView.delegate = coordinator
    }

    var text: String {
        textView.textStorage.string
    }

    func replace(_ range: NSRange, with string: String) {
        textView.replaceCharacters(in: range, with: string)
        document.content?.replaceCharacters(in: range, with: string)
    }

    func insert(_ string: String, at offset: Int) {
        replace(NSRange(location: offset, length: 0), with: string)
    }
}

enum DocumentSyncMode: CaseIterable, Sendable {
    case incremental
    case full

    var capabilities: ServerCapabilities {
        switch self {
        case .incremental:
            ScriptedServerConnection.incrementalCapabilities()
        case .full:
            ScriptedServerConnection.fullCapabilities()
        }
    }
}
