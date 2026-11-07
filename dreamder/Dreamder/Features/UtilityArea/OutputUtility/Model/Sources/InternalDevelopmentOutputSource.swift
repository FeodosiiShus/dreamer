//
//  InternalDevelopmentOutputSource.swift
//  Dreamder
//
//  Created by Khan Winter on 7/18/25.
//

import Foundation

class InternalDevelopmentOutputSource: UtilityAreaOutputSource {
    static let shared = InternalDevelopmentOutputSource()

    nonisolated struct Message: UtilityAreaOutputMessage, Sendable {
        var id: UUID = UUID()

        var message: String
        var date: Date = Date()
        var subsystem: String?
        var category: String?
        var level: UtilityAreaLogLevel
    }

    nonisolated let id: UUID = UUID()
    private var logs: [Message] = []
    private(set) var streamContinuation: AsyncStream<Message>.Continuation
    private var stream: AsyncStream<Message>

    init() {
        (stream, streamContinuation) = AsyncStream<Message>.makeStream()
    }

    func pushLog(_ log: Message) {
        logs.append(log)
        streamContinuation.yield(log)
    }

    func cachedMessages() -> [Message] {
        logs
    }

    func streamMessages() -> AsyncStream<Message> {
        stream
    }
}
