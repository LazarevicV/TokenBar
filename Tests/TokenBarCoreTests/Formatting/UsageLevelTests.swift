import Testing
@testable import TokenBarCore

@Suite struct UsageLevelTests {
    @Test func thresholds() {
        #expect(UsageLevel(percent: 0) == .normal)
        #expect(UsageLevel(percent: 69.9) == .normal)
        #expect(UsageLevel(percent: 70) == .warning)
        #expect(UsageLevel(percent: 89.9) == .warning)
        #expect(UsageLevel(percent: 90) == .critical)
        #expect(UsageLevel(percent: 100) == .critical)
        #expect(UsageLevel(percent: 250) == .critical)
        #expect(UsageLevel(percent: -5) == .normal)
        #expect(UsageLevel(percent: .nan) == .normal)
    }

    @Test func filledSegmentsRoundsAndClamps() {
        #expect(filledSegments(percent: 0) == 0)
        #expect(filledSegments(percent: 4.9) == 0)
        #expect(filledSegments(percent: 5) == 1)
        #expect(filledSegments(percent: 68) == 7)
        #expect(filledSegments(percent: 41) == 4)
        #expect(filledSegments(percent: 94) == 9)
        #expect(filledSegments(percent: 100) == 10)
        #expect(filledSegments(percent: 140) == 10)
        #expect(filledSegments(percent: -20) == 0)
        #expect(filledSegments(percent: .nan) == 0)
        #expect(filledSegments(percent: .infinity) == 0)
    }

    @Test func filledSegmentsCustomTotal() {
        #expect(filledSegments(percent: 50, total: 4) == 2)
        #expect(filledSegments(percent: 100, total: 20) == 20)
        #expect(filledSegments(percent: 50, total: 0) == 0)
    }
}
