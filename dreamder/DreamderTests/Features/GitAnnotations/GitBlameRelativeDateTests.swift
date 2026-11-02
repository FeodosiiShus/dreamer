import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitBlameRelativeDateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private var now: Date {
        Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func string(secondsAgo: TimeInterval) -> String {
        GitBlameRelativeDate.string(for: now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar)
    }

    @Test
    func showsJustNowForRecentCommits() {
        #expect(string(secondsAgo: 0) == "just now")
        #expect(string(secondsAgo: 59) == "just now")
    }

    @Test
    func showsMinutesAndHours() {
        #expect(string(secondsAgo: 60) == "1 minute ago")
        #expect(string(secondsAgo: 300) == "5 minutes ago")
        #expect(string(secondsAgo: 3600) == "1 hour ago")
        #expect(string(secondsAgo: 3 * 3600) == "3 hours ago")
    }

    @Test
    func showsYesterdayForThePreviousDay() {
        #expect(string(secondsAgo: 24 * 3600) == "yesterday")
        #expect(string(secondsAgo: 40 * 3600) == "yesterday")
    }

    @Test
    func showsDaysWithinTheLastWeek() {
        #expect(string(secondsAgo: 3 * 86_400) == "3 days ago")
        #expect(string(secondsAgo: 6 * 86_400) == "6 days ago")
    }

    @Test
    func showsMonthAndDayForOlderCommits() {
        #expect(string(secondsAgo: 20 * 86_400) == "Oct 25")
        #expect(string(secondsAgo: 60 * 86_400) == "Sep 15")
    }

    @Test
    func showsTheYearForCommitsFromAnotherYear() {
        #expect(string(secondsAgo: 400 * 86_400) == "Oct 10, 2022")
    }

    @Test
    func treatsFutureDatesAsJustNow() {
        let future = GitBlameRelativeDate.string(
            for: now.addingTimeInterval(600),
            now: now,
            calendar: calendar
        )
        #expect(future == "just now")
    }

    @Test
    func formatsAbsoluteDates() {
        let sameYear = GitBlameRelativeDate.absoluteString(for: now, now: now, calendar: calendar)
        #expect(sameYear == "Nov 14")

        let otherYear = GitBlameRelativeDate.absoluteString(
            for: now.addingTimeInterval(-400 * 86_400),
            now: now,
            calendar: calendar
        )
        #expect(otherYear == "Oct 10, 2022")
    }
}
