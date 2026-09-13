import Foundation
import Testing
@testable import TokenBarCore

@Suite struct UsageLevelTests {
    @Test func thresholds() {
        #expect(UsageLevel(remaining: 100) == .normal)
        #expect(UsageLevel(remaining: 30.1) == .normal)
        #expect(UsageLevel(remaining: 30) == .warning)
        #expect(UsageLevel(remaining: 10) == .warning)
        #expect(UsageLevel(remaining: 9.9) == .critical)
        #expect(UsageLevel(remaining: 0) == .critical)
        #expect(UsageLevel(remaining: -5) == .critical)
        #expect(UsageLevel(remaining: 250) == .normal)
        #expect(UsageLevel(remaining: .nan) == .normal)
    }

    @Test func remainingIsClampedInverseOfPercent() {
        func window(_ percent: Double) -> UsageWindow {
            UsageWindow(percent: percent, resetsAt: Date(), label: "5h")
        }
        #expect(window(0).remaining == 100)
        #expect(window(79).remaining == 21)
        #expect(window(100).remaining == 0)
        #expect(window(140).remaining == 0)
        #expect(window(-20).remaining == 100)
        #expect(window(.nan).remaining == 0)
    }

    @Test func filledSegmentsRoundsAndClamps() {
        #expect(filledSegments(remaining: 0) == 0)
        #expect(filledSegments(remaining: 4.9) == 0)
        #expect(filledSegments(remaining: 5) == 1)
        #expect(filledSegments(remaining: 68) == 7)
        #expect(filledSegments(remaining: 41) == 4)
        #expect(filledSegments(remaining: 94) == 9)
        #expect(filledSegments(remaining: 100) == 10)
        #expect(filledSegments(remaining: 140) == 10)
        #expect(filledSegments(remaining: -20) == 0)
        #expect(filledSegments(remaining: .nan) == 0)
        #expect(filledSegments(remaining: .infinity) == 0)
    }

    @Test func filledSegmentsCustomTotal() {
        #expect(filledSegments(remaining: 50, total: 4) == 2)
        #expect(filledSegments(remaining: 100, total: 20) == 20)
        #expect(filledSegments(remaining: 50, total: 0) == 0)
    }
}
