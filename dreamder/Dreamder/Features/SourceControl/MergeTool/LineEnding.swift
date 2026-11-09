import Foundation

nonisolated enum LineEnding: String, Sendable, Equatable {
    case lineFeed = "\n"
    case crlf = "\r\n"
    case carriageReturn = "\r"

    private static let lineFeedByte: UInt8 = 10
    private static let carriageReturnByte: UInt8 = 13

    static func dominant(in text: String) -> LineEnding? {
        var lineFeedCount = 0
        var crlfCount = 0
        var carriageReturnCount = 0
        var previous: UInt8 = 0
        for byte in text.utf8 {
            if byte == lineFeedByte {
                if previous == carriageReturnByte {
                    crlfCount += 1
                    carriageReturnCount -= 1
                } else {
                    lineFeedCount += 1
                }
            } else if byte == carriageReturnByte {
                carriageReturnCount += 1
            }
            previous = byte
        }
        let candidates: [(ending: LineEnding, occurrences: Int)] = [
            (.lineFeed, lineFeedCount),
            (.crlf, crlfCount),
            (.carriageReturn, carriageReturnCount)
        ]
        guard let best = candidates.max(by: { $0.occurrences < $1.occurrences }), best.occurrences > 0 else {
            return nil
        }
        return best.ending
    }

    static func endsWithLineBreak(_ text: String) -> Bool {
        let last = text.utf8.last
        return last == lineFeedByte || last == carriageReturnByte
    }

    func converting(_ text: String) -> String {
        let normalized = TextDiff.normalizingLineBreaks(in: text)
        return (normalized as NSString).replacingOccurrences(of: "\n", with: rawValue)
    }
}
