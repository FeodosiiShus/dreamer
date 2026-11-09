import Foundation
import Testing
@testable import Dreamder

actor FindGate {
    private var remainingHolds: Int
    private(set) var arrivals = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(holds: Int = Int.max) {
        remainingHolds = holds
    }

    func wait() async {
        arrivals += 1
        guard !isOpen, remainingHolds > 0 else { return }
        remainingHolds -= 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

actor FindCallCounter {
    private(set) var value = 0

    func record() {
        value += 1
    }
}

@MainActor
enum FindStateSupport {
    typealias State = WorkspaceDocument.SearchState

    static func write(_ text: String, _ path: String, in directory: URL) throws {
        try writeData(Data(text.utf8), path, in: directory)
    }

    static func writeData(_ data: Data, _ path: String, in directory: URL) throws {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func read(_ path: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appending(path: path), encoding: .utf8)
    }

    static func prepare(in directory: URL) async throws -> (WorkspaceDocument, State) {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let state = try #require(workspace.searchState)
        try await eventually { state.indexStatus == .done }
        return (workspace, state)
    }

    static func replaceSession(
        files: [String: String],
        query: String,
        replacement: String,
        regex: Bool = false,
        preserveCase: Bool = false,
        in directory: URL
    ) async throws -> (WorkspaceDocument, State) {
        for (path, text) in files {
            try write(text, path, in: directory)
        }
        let (workspace, state) = try await prepare(in: directory)
        state.setReplaceMode(true)
        if regex {
            state.isRegularExpression = true
        }
        state.findModel.isPreserveCase = preserveCase
        state.replaceText = replacement
        try await settle()
        await state.search(query)
        return (workspace, state)
    }

    static func settle() async throws {
        try await Task.sleep(for: .milliseconds(80))
    }

    static func hold(_ fileName: String, with gate: FindGate, in state: State) {
        state.fileEvaluationOverride = { @Sendable url in
            if url.lastPathComponent == fileName {
                await gate.wait()
            }
            return nil
        }
    }

    static func relativePaths(of state: State, in directory: URL) -> [String] {
        state.searchResult
            .map { $0.file.url.path.replacingOccurrences(of: directory.path + "/", with: "") }
            .sorted()
    }

    static func result(_ name: String, in state: State) -> SearchResultModel? {
        state.searchResult.first { $0.file.name == name }
    }

    static func matches(_ name: String, in state: State) -> [SearchResultMatchModel] {
        result(name, in: state)?.lineMatches ?? []
    }
}
