import Foundation

nonisolated struct GitBlameLine: Equatable {
    static let uncommittedHash = "0000000000000000000000000000000000000000"

    let line: Int
    let commitHash: String
    let author: String
    let authorDate: Date
    let summary: String

    var isUncommitted: Bool {
        commitHash == Self.uncommittedHash
    }

    var shortHash: String {
        String(commitHash.prefix(8))
    }
}

nonisolated enum GitBlameParser {
    nonisolated private struct Metadata {
        var author = ""
        var date = Date(timeIntervalSince1970: 0)
        var summary = ""
    }

    static func parse(_ output: String) -> [GitBlameLine] {
        var metadata: [String: Metadata] = [:]
        var currentHash: String?
        var currentLine = 0
        var lines: [GitBlameLine] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            var text = String(rawLine)
            if text.hasSuffix("\r") {
                text.removeLast()
            }
            guard !text.isEmpty else { continue }

            if text.hasPrefix("\t") {
                guard let hash = currentHash else { continue }
                let info = metadata[hash] ?? Metadata()
                lines.append(
                    GitBlameLine(
                        line: currentLine,
                        commitHash: hash,
                        author: info.author,
                        authorDate: info.date,
                        summary: info.summary
                    )
                )
                currentLine += 1
                continue
            }

            if let header = header(in: text) {
                currentHash = header.hash
                currentLine = header.line
                if metadata[header.hash] == nil {
                    metadata[header.hash] = Metadata()
                }
                continue
            }

            guard let hash = currentHash, let field = field(in: text) else { continue }
            switch field.key {
            case "author":
                metadata[hash]?.author = field.value
            case "author-time":
                if let seconds = TimeInterval(field.value) {
                    metadata[hash]?.date = Date(timeIntervalSince1970: seconds)
                }
            case "summary":
                metadata[hash]?.summary = field.value
            default:
                continue
            }
        }

        return lines.sorted { $0.line < $1.line }
    }

    private static func header(in text: String) -> (hash: String, line: Int)? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 4,
              parts[0].count == 40,
              parts[0].allSatisfy(\.isHexDigit),
              !parts[2].isEmpty,
              parts[2].allSatisfy(\.isNumber),
              let line = Int(parts[2]) else {
            return nil
        }
        return (String(parts[0]), line)
    }

    private static func field(in text: String) -> (key: String, value: String)? {
        guard let separator = text.firstIndex(of: " ") else { return nil }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }
}

nonisolated enum GitBlameRelativeDate {
    static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func string(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = GitBlameRelativeDate.posixLocale
    ) -> String {
        let interval = now.timeIntervalSince(date)
        guard interval >= 60 else { return "just now" }

        if calendar.isDate(date, inSameDayAs: now) {
            let minutes = Int(interval / 60)
            guard minutes >= 60 else { return unit(minutes, "minute") + " ago" }
            return unit(minutes / 60, "hour") + " ago"
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days <= 1 {
            return "yesterday"
        }
        if days < 7 {
            return "\(days) days ago"
        }
        return absoluteString(for: date, now: now, calendar: calendar, locale: locale)
    }

    static func absoluteString(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = GitBlameRelativeDate.posixLocale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let isSameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = isSameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private static func unit(_ value: Int, _ name: String) -> String {
        value == 1 ? "1 \(name)" : "\(value) \(name)s"
    }
}
