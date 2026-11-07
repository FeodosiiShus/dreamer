//
//  ExtensionUtilityAreaOutputSource.swift
//  Dreamder
//
//  Created by Khan Winter on 7/18/25.
//

import OSLog
import LogStream

nonisolated extension LogMessage: @retroactive Identifiable, UtilityAreaOutputMessage {
    public var id: String {
        "\(date.timeIntervalSince1970)" + process + (subsystem ?? "") + (category ?? "")
    }

    var level: UtilityAreaLogLevel {
        switch type {
        case .fault, .error:
                .error
        case .info, .default:
                .info
        case .debug:
                .debug
        default:
                .info
        }
    }
}

struct ExtensionUtilityAreaOutputSource: UtilityAreaOutputSource {
    nonisolated let id: String

    let extensionInfo: ExtensionInfo

    init(extensionInfo: ExtensionInfo) {
        self.extensionInfo = extensionInfo
        self.id = "extension_output" + extensionInfo.id
    }

    func cachedMessages() -> [LogMessage] {
        []
    }

    func streamMessages() -> AsyncStream<LogMessage> {
        LogStream.logs(for: extensionInfo.pid, flags: [.info, .historical, .processOnly])
    }
}
