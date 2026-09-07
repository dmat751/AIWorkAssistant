import XCTest
@testable import AIWorkAssistant

final class UsageFormattingTests: XCTestCase {
    func testFormatDollarsShowsTwoDecimals() {
        XCTAssertEqual(UsageFormatting.formatDollars(cents: 42), "$0.42")
        XCTAssertEqual(UsageFormatting.formatDollars(cents: 0), "$0.00")
    }

    func testFormatDollarsShowsFourDecimalsForSubCentAmounts() {
        XCTAssertEqual(UsageFormatting.formatDollars(cents: 0), "$0.00")
        XCTAssertEqual(UsageFormatting.formatDollars(cents: 1), "$0.01")
    }

    func testFormatTokensUsesCompactUnits() {
        XCTAssertEqual(UsageFormatting.formatTokens(999), "999")
        XCTAssertEqual(UsageFormatting.formatTokens(1_500), "1k")
        XCTAssertEqual(UsageFormatting.formatTokens(128_000), "128k")
        XCTAssertEqual(UsageFormatting.formatTokens(1_500_000), "1.5M")
    }

    func testFormatRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            UsageFormatting.formatRelativeTime(now.addingTimeInterval(-30), now: now),
            "just now"
        )
        XCTAssertEqual(
            UsageFormatting.formatRelativeTime(now.addingTimeInterval(-120), now: now),
            "2m ago"
        )
    }
}
