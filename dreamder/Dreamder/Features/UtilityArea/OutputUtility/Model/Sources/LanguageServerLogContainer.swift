//
//  LanguageServerLogContainer.swift
//  Dreamder
//
//  Created by Khan Winter on 7/18/25.
//

import OSLog
import LanguageServerProtocol

class LanguageServerLogContainer: UtilityAreaOutputSource {
    nonisolated struct LanguageServerMessage: UtilityAreaOutputMessage, Sendable {
        let log: LogMessageParams
        var id: UUID = UUID()

        var message: String {
            log.message
        }

        var level: UtilityAreaLogLevel {
            switch log.type {
            case .error:
                    .error
            case .warning:
                    .warning
            case .info:
                    .info
            case .log:
                    .debug
            }
        }

        var date: Date = Date()
        var subsystem: String?
        var category: String?
    }

    nonisolated let id: String

    private var streamContinuation: AsyncStream<LanguageServerMessage>.Continuation
    private var stream: AsyncStream<LanguageServerMessage>
    private(set) var logs: [LanguageServerMessage] = []

    init(languageID: String) {
        id = languageID
        (stream, streamContinuation) = AsyncStream<LanguageServerMessage>.makeStream(
            bufferingPolicy: .bufferingNewest(0)
        )
    }

    func appendLog(_ log: LogMessageParams) {
        let message = LanguageServerMessage(log: log)
        logs.append(message)
        streamContinuation.yield(message)
    }

    func cachedMessages() -> [LanguageServerMessage] {
        logs
    }

    func streamMessages() -> AsyncStream<LanguageServerMessage> {
        stream
    }
}
