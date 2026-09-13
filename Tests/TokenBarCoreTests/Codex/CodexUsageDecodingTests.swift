import Foundation
import Testing
@testable import TokenBarCore

let codexUsageFixture = #"{"plan_type":"plus","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":54,"limit_window_seconds":18000,"reset_after_seconds":11325,"reset_at":1789313353},"secondary_window":{"used_percent":8.5,"limit_window_seconds":604800,"reset_at":1789811371}},"credits":{"has_credits":false,"balance":"0"},"rate_limit_reset_credits":{"available_count":2,"applicable_available_count":0},"unknown":{"future":true}}"#

@Test func codexUsageDecoding() throws {
    let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(codexUsageFixture.utf8))
    #expect(response.plan_type == "plus")
    #expect(response.rate_limit?.primary_window?.used_percent == 54)
    #expect(response.rate_limit?.secondary_window?.used_percent == 8.5)
    #expect(response.credits?.has_credits == false)
    #expect(response.credits?.balance == "0")
    #expect(response.rate_limit_reset_credits?.available_count == 2)
    #expect(response.rate_limit?.primary_window?.usageWindow?.resetsAt == Date(timeIntervalSince1970: 1789313353))
}

@Test(arguments: ["{}", #"{"rate_limit":null,"credits":null}"#, #"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#, #"{"rate_limit":{"primary_window":{}}}"#])
func codexMissingWindows(json: String) throws {
    let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    #expect(response.rate_limit?.primary_window?.usageWindow == nil)
    #expect(response.rate_limit?.secondary_window?.usageWindow == nil)
}

@Test(arguments: zip([18000, 604800, 10800, 172800, 5400, 45], ["5h", "week", "3h", "2d", "90m", "45s"]))
func codexWindowLabels(seconds: Int, expected: String) {
    #expect(CodexUsageResponse.Window.label(seconds: seconds) == expected)
}

@Test(arguments: ["{}", #"{"rate_limit_reset_credits":null}"#, #"{"rate_limit_reset_credits":{}}"#])
func codexMissingResetCredits(json: String) throws {
    let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    #expect(response.rate_limit_reset_credits?.available_count == nil)
}
