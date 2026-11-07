import Foundation

nonisolated struct ProcessLineSplitter: Sendable {
    private var pending: [UInt8] = []

    init() {}

    mutating func append(_ data: Data) -> [String] {
        var lines: [String] = []
        for byte in data {
            if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                if !pending.isEmpty {
                    lines.append(String(decoding: pending, as: UTF8.self))
                    pending.removeAll(keepingCapacity: true)
                }
            } else {
                pending.append(byte)
            }
        }
        return lines
    }

    mutating func finish() -> String? {
        defer { pending.removeAll() }
        guard !pending.isEmpty else { return nil }
        return String(decoding: pending, as: UTF8.self)
    }
}
