import Foundation

nonisolated enum GitLogRelativeDate {
    static func string(for date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 45 {
            return "just now"
        }
        let minutes = max(seconds / 60, 1)
        if minutes < 60 {
            return unit(minutes, "minute")
        }
        let hours = minutes / 60
        if hours < 24 {
            return unit(hours, "hour")
        }
        let days = hours / 24
        if days < 30 {
            return unit(days, "day")
        }
        let months = days / 30
        if months < 12 {
            return unit(months, "month")
        }
        return unit(months / 12, "year")
    }

    private static func unit(_ count: Int, _ name: String) -> String {
        "\(count) \(name)\(count == 1 ? "" : "s") ago"
    }
}
