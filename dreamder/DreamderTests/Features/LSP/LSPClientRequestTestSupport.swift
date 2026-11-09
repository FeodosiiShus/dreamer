import Foundation
import JSONRPC
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

final class LSPTestRecorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

func lspDecode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

func lspTextEdit(_ start: (Int, Int), _ end: (Int, Int), _ text: String) -> TextEdit {
    TextEdit(range: LSPRange(startPair: start, endPair: end), newText: text)
}

func lspRegistrations(_ pairs: [(id: String, method: String)]) -> RegistrationParams {
    RegistrationParams(registrations: pairs.map { Registration(id: $0.id, method: $0.method) })
}

func lspUnregistrations(_ pairs: [(id: String, method: String)]) throws -> UnregistrationParams {
    let items = pairs.map { #"{"id":"\#($0.id)","method":"\#($0.method)"}"# }.joined(separator: ",")
    return try lspDecode(UnregistrationParams.self, #"{"unregistrations":[\#(items)]}"#)
}

struct LSPTestDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LSPClientRequestHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
