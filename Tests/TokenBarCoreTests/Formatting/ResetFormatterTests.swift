import Foundation
import Testing
@testable import TokenBarCore

@Suite struct ResetFormatterTests {
    // Monday 2026-09-14 10:00:00 UTC (12:00 in Europe/Belgrade, CEST).
    static let now = Date(timeIntervalSince1970: 1_789_380_000)

    // Typed units: untyped literal sums such as `2 * 86_400 + 13 * 3600 + 30 * 60`
    // time out the type checker on some toolchains. Concrete operands avoid the search.
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3_600
    static let day: TimeInterval = 86_400

    static let utc = TimeZone(identifier: "UTC")!
    static let belgrade = TimeZone(identifier: "Europe/Belgrade")!

    static func formatter(locale: String, timeZone: TimeZone) -> ResetFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ResetFormatter(
            now: { now },
            calendar: calendar,
            locale: Locale(identifier: locale),
            timeZone: timeZone
        )
    }

    @Test func nowIsMonday10UTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let parts = calendar.dateComponents([.weekday, .hour, .minute, .second], from: Self.now)
        #expect(parts.weekday == 2)
        #expect(parts.hour == 10)
        #expect(parts.minute == 0)
        #expect(parts.second == 0)
    }

    @Test func pastAndImminent() {
        let f = Self.formatter(locale: "en_US", timeZone: Self.utc)
        #expect(f.string(for: Self.now.addingTimeInterval(-1)) == "now")
        #expect(f.string(for: Self.now) == "now")
        #expect(f.string(for: Self.now.addingTimeInterval(1)) == "in <1m")
        #expect(f.string(for: Self.now.addingTimeInterval(59)) == "in <1m")
    }

    @Test func underADay() {
        let f = Self.formatter(locale: "en_US", timeZone: Self.utc)
        #expect(f.string(for: Self.now.addingTimeInterval(60)) == "in 1m")
        #expect(f.string(for: Self.now.addingTimeInterval(45 * Self.minute)) == "in 45m")
        #expect(f.string(for: Self.now.addingTimeInterval(2 * Self.hour + 15 * Self.minute)) == "in 2h 15m")
        #expect(f.string(for: Self.now.addingTimeInterval(2 * Self.hour + 15 * Self.minute + 59)) == "in 2h 15m")
        #expect(f.string(for: Self.now.addingTimeInterval(2 * Self.hour)) == "in 2h 0m")
        #expect(f.string(for: Self.now.addingTimeInterval(24 * Self.hour - 1)) == "in 23h 59m")
    }

    @Test func switchesToWeekdayAt24Hours() {
        let gb = Self.formatter(locale: "en_GB", timeZone: Self.utc)
        let us = Self.formatter(locale: "en_US", timeZone: Self.utc)
        let tuesday10 = Self.now.addingTimeInterval(24 * Self.hour)
        #expect(gb.string(for: tuesday10) == "Tue 10:00")
        let usString = us.string(for: tuesday10)
        #expect(usString.hasPrefix("Tue 10:00"))
        #expect(usString.hasSuffix("AM"))
    }

    @Test func weekdayUsesLocalTimeZone() {
        let gbUTC = Self.formatter(locale: "en_GB", timeZone: Self.utc)
        let gbBelgrade = Self.formatter(locale: "en_GB", timeZone: Self.belgrade)
        // Wednesday 14:00 UTC → 16:00 CEST.
        let wednesday14 = Self.now.addingTimeInterval(2 * Self.day + 4 * Self.hour)
        #expect(gbUTC.string(for: wednesday14) == "Wed 14:00")
        #expect(gbBelgrade.string(for: wednesday14) == "Wed 16:00")

        // Wednesday 23:30 UTC is already Thursday in Belgrade.
        let lateWednesday = Self.now.addingTimeInterval(2 * Self.day + 13 * Self.hour + 30 * Self.minute)
        #expect(gbUTC.string(for: lateWednesday) == "Wed 23:30")
        #expect(gbBelgrade.string(for: lateWednesday) == "Thu 01:30")
    }

    @Test func twelveHourLocale() {
        let us = Self.formatter(locale: "en_US", timeZone: Self.utc)
        let wednesday14 = Self.now.addingTimeInterval(2 * Self.day + 4 * Self.hour)
        let s = us.string(for: wednesday14)
        #expect(s.hasPrefix("Wed 2:00"))
        #expect(s.hasSuffix("PM"))
    }

    @Test func moreThanSixDaysAddsDate() {
        let gb = Self.formatter(locale: "en_GB", timeZone: Self.utc)
        let us = Self.formatter(locale: "en_US", timeZone: Self.utc)
        // Exactly 6 days: still weekday form.
        let sixDays = Self.now.addingTimeInterval(6 * Self.day)
        #expect(gb.string(for: sixDays) == "Sun 10:00")
        // Sunday 20 September 2026 14:00 UTC.
        let sep20 = Self.now.addingTimeInterval(6 * Self.day + 4 * Self.hour)
        let gbString = gb.string(for: sep20)
        #expect(gbString.contains("20 Sep"))
        #expect(gbString.contains("14:00"))
        #expect(!gbString.contains("Sun"))
        let usString = us.string(for: sep20)
        #expect(usString.contains("Sep 20"))
        #expect(usString.contains("2:00"))
        #expect(usString.hasSuffix("PM"))
    }

    @Test func relativeAge() {
        let f = Self.formatter(locale: "en_US", timeZone: Self.utc)
        #expect(f.relativeAge(since: Self.now) == "just now")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(5)) == "just now")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(-12)) == "12 s ago")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(-59)) == "59 s ago")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(-60)) == "1 min ago")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(-3 * Self.minute)) == "3 min ago")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(-2 * Self.hour)) == "2 h ago")
        #expect(f.relativeAge(since: Self.now.addingTimeInterval(-3 * Self.day)) == "3 d ago")
    }
}
