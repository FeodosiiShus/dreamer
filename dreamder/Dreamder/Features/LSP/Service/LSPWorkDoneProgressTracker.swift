import Foundation
import LanguageServerProtocol
import Synchronization

nonisolated struct LSPWorkDoneProgress: Sendable, Equatable {
    var token: ProgressToken
    var title: String?
    var message: String?
    var percentage: Int?
    var hasBegun: Bool
}

nonisolated enum LSPWorkDoneProgressUpdate: Sendable, Equatable {
    case began
    case reported
    case ended
    case ignored
}

nonisolated final class LSPWorkDoneProgressTracker: Sendable {
    private struct State {
        var progresses: [ProgressToken: LSPWorkDoneProgress] = [:]
        var isShutDown = false
    }

    private let state = Mutex(State())

    init() {}

    @discardableResult
    func create(_ token: ProgressToken) -> Bool {
        state.withLock { state in
            guard !state.isShutDown else { return false }
            if state.progresses[token] == nil {
                state.progresses[token] = LSPWorkDoneProgress(
                    token: token,
                    title: nil,
                    message: nil,
                    percentage: nil,
                    hasBegun: false
                )
            }
            return true
        }
    }

    @discardableResult
    func apply(_ params: ProgressParams) -> LSPWorkDoneProgressUpdate {
        guard case .hash(let value)? = params.value, case .string(let kind)? = value["kind"] else {
            return .ignored
        }
        return state.withLock { state in
            switch kind {
            case "begin":
                guard !state.isShutDown, case .string(let title)? = value["title"] else { return .ignored }
                state.progresses[params.token] = LSPWorkDoneProgress(
                    token: params.token,
                    title: title,
                    message: Self.string(value["message"]),
                    percentage: Self.percentage(value["percentage"]),
                    hasBegun: true
                )
                return .began
            case "report":
                guard var progress = state.progresses[params.token], progress.hasBegun else { return .ignored }
                if let message = Self.string(value["message"]) {
                    progress.message = message
                }
                if let percentage = Self.percentage(value["percentage"]) {
                    progress.percentage = percentage
                }
                state.progresses[params.token] = progress
                return .reported
            case "end":
                return state.progresses.removeValue(forKey: params.token) == nil ? .ignored : .ended
            default:
                return .ignored
            }
        }
    }

    func progress(for token: ProgressToken) -> LSPWorkDoneProgress? {
        state.withLock { $0.progresses[token] }
    }

    var activeProgresses: [LSPWorkDoneProgress] {
        state.withLock { Array($0.progresses.values.filter(\.hasBegun)) }
    }

    var trackedTokenCount: Int {
        state.withLock { $0.progresses.count }
    }

    var isShutDown: Bool {
        state.withLock { $0.isShutDown }
    }

    func shutDown() {
        state.withLock { state in
            state.isShutDown = true
            state.progresses.removeAll()
        }
    }

    private static func string(_ value: LSPAny?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }

    private static func percentage(_ value: LSPAny?) -> Int? {
        guard case .number(let number)? = value, number.isFinite else { return nil }
        return Int(min(max(number, 0), 100))
    }
}
