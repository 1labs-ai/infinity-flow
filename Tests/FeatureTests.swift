import XCTest
@testable import InfinityFlow

final class FeatureTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: - Bring your own key

    func testEndpointJoining() {
        XCTAssertEqual(CloudPreset.endpoint(base: "https://api.groq.com/openai/v1/", path: "/audio/transcriptions")?.absoluteString,
                       "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(CloudPreset.endpoint(base: " http://localhost:1234/v1 ", path: "/models")?.absoluteString,
                       "http://localhost:1234/v1/models")
        XCTAssertNil(CloudPreset.endpoint(base: "", path: "/models"))
        XCTAssertNil(CloudPreset.endpoint(base: "ftp://example.com", path: "/models"))
    }

    func testCostEstimateAppliesMinimumBilling() {
        let now = date(2026, 10, 14)
        let records = [
            UsageRecord(date: now, duration: 3, provider: "groq"),     // billed as 10 s
            UsageRecord(date: now, duration: 50, provider: "groq"),
            UsageRecord(date: now, duration: 600, provider: "openai"),
            UsageRecord(date: now, duration: 30, provider: nil),
        ]
        XCTAssertEqual(Usage.estimatedCost(records, preset: .groq)!, 60.0 / 3600 * 0.04, accuracy: 1e-9)
        XCTAssertEqual(Usage.estimatedCost(records, preset: .openAI)!, 10 * 0.003, accuracy: 1e-9)
        XCTAssertNil(Usage.estimatedCost(records, preset: .custom))
        XCTAssertEqual(Usage.formatCost(0.004), "under $0.01")
        XCTAssertEqual(Usage.formatCost(1.234), "$1.23")
    }

    func testThisMonthAndPrivacyReceipt() {
        let now = date(2026, 10, 14)
        let records = [
            UsageRecord(date: date(2026, 9, 30), duration: 60, provider: "groq"),
            UsageRecord(date: date(2026, 10, 2), duration: 60, provider: nil),
            UsageRecord(date: date(2026, 10, 3), duration: 120, provider: nil),
        ]
        let month = Usage.thisMonth(records, now: now, calendar: calendar)
        XCTAssertEqual(month.count, 2)
        let summary = PrivacySummary(month)
        XCTAssertEqual(summary.onDeviceCount, 2)
        XCTAssertEqual(summary.onDeviceMinutes, 3, accuracy: 1e-9)
        XCTAssertEqual(summary.headline, "No audio left this Mac.")
        XCTAssertEqual(PrivacySummary(records).headline, "1 of 3 dictations were sent to Groq with your key.")
    }

    // MARK: - Cleanup

    func testLightCleanupRemovesFillersAndRepeats() {
        XCTAssertEqual(LightCleanup.clean("um so I I think we should, uh, ship it on Friday"),
                       "So I think we should, ship it on Friday")
        XCTAssertEqual(LightCleanup.clean("Hmm. the the plan is ready"), "The plan is ready")
        XCTAssertEqual(LightCleanup.clean("I had had enough"), "I had had enough", "intentional doubles stay")
        XCTAssertEqual(LightCleanup.clean("Umbrella and summer are fine"), "Umbrella and summer are fine", "words containing fillers stay")
        XCTAssertEqual(LightCleanup.clean("ship it. then rest"), "Ship it. Then rest")
    }

    func testCleanupGuardProtectsNumbers() {
        let original = "Revenue grew 1.5 percent to 42,000 in Q3"
        XCTAssertTrue(CleanupGuard.isSafe(original: original, cleaned: "Revenue grew 1.5% to 42,000 in Q3."))
        XCTAssertFalse(CleanupGuard.isSafe(original: original, cleaned: "Revenue grew 1% to 42,000 in Q3."), "dropped a number")
        XCTAssertFalse(CleanupGuard.isSafe(original: original, cleaned: "Revenue grew."), "too short")
        XCTAssertFalse(CleanupGuard.isSafe(original: original, cleaned: "  "))
    }

    // MARK: - Recordings

    func testRecordingRetention() {
        let now = date(2026, 10, 14)
        XCTAssertFalse(RecordingRetention.forever.isExpired(date(2020, 1, 1), now: now, calendar: calendar))
        XCTAssertTrue(RecordingRetention.days7.isExpired(date(2026, 10, 1), now: now, calendar: calendar))
        XCTAssertFalse(RecordingRetention.days7.isExpired(date(2026, 10, 10), now: now, calendar: calendar))
        XCTAssertFalse(RecordingRetention.days30.isExpired(date(2026, 9, 20), now: now, calendar: calendar))
    }
}
