import Foundation
import Testing
@testable import TokenBarCore

let claudeUsageFixture = Data(#"""
{
  "five_hour": {"utilization": 5.5, "resets_at": "2026-09-13T16:10:00.944794+00:00"},
  "seven_day": {"utilization": 12, "resets_at": "2026-09-18T20:00:00.944817+00:00"},
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "extra_usage": {"is_enabled": true, "utilization": 0.212, "used_credits": 21.0, "monthly_limit": 9900, "currency": "USD", "decimal_places": 2},
  "limits": [{"kind": "session", "group": "session", "percent": 5.5, "severity": "normal", "resets_at": "2026-09-13T16:10:00.944794+00:00", "is_active": true}],
  "unknown": {"experimental": true}
}
"""#.utf8)

@Test func claudeUsageDecodesFractionalDatesAndOptionalFields() throws {
    let usage = try ClaudeUsageResponse.decode(from: claudeUsageFixture)
    let date = try #require(usage.fiveHour?.resetsAt)
    #expect(abs(date.timeIntervalSince1970 - 1789315800.944794) < 0.001)
    #expect(usage.fiveHour?.utilization == 5.5)
    #expect(usage.sevenDay?.utilization == 12)
    #expect(usage.sevenDayOpus == nil)
    #expect(usage.sevenDaySonnet == nil)
    #expect(usage.limits?.first?.kind == "session")
    #expect(usage.limits?.first?.group == "session")
    #expect(usage.limits?.first?.percent == 5.5)
    #expect(usage.limits?.first?.severity == "normal")
    #expect(usage.limits?.first?.isActive == true)
    #expect(usage.limits?.first?.resetsAt == date)
    #expect(usage.extraUsage?.utilization == 0.212)
    #expect(usage.extraUsage?.usedCredits == 21)
    #expect(usage.extraUsage?.monthlyLimit == 9900)
    #expect(usage.extraUsage?.currency == "USD")
}

@Test func claudeUsageNullAndMissingWindows() throws {
    for json in ["{}", #"{"five_hour":null,"seven_day":null,"limits":null,"extra_usage":null,"unknown":42}"#] {
        let usage = try ClaudeUsageResponse.decode(from: Data(json.utf8))
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay == nil)
        #expect(usage.extraUsage == nil)
        #expect(usage.limits == nil)
    }
}

@Test func claudeUsageDatesWithoutFractionsAndWithOffsets() throws {
    let usage = try ClaudeUsageResponse.decode(from: Data(#"{"five_hour":{"utilization":0,"resets_at":"2026-09-13T18:10:00+02:00"},"seven_day":{"utilization":0,"resets_at":null}}"#.utf8))
    #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1789315800))
    #expect(usage.sevenDay?.resetsAt == nil)
}

@Test func claudeUsageRejectsInvalidDates() {
    #expect(throws: (any Error).self) {
        try ClaudeUsageResponse.decode(from: Data(#"{"five_hour":{"utilization":0,"resets_at":"invalid"}}"#.utf8))
    }
}
