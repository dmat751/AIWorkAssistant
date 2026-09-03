import XCTest
@testable import AIWorkAssistant

final class CursorUsageParsingTests: XCTestCase {
    func testParsesUsageEventWithTokenUsageCost() throws {
        let json = """
        {
          "timestamp": 1700000000000,
          "modelName": "gpt-4",
          "tokenUsage": {
            "inputTokens": 100,
            "outputTokens": 50,
            "cacheReadTokens": 10,
            "cacheWriteTokens": 5,
            "totalCents": 42
          }
        }
        """

        let event = try JSONDecoder().decode(CursorUsageEventDisplay.self, from: Data(json.utf8))
        let usageEvent = UsageEventParser.makeUsageEvent(from: event)

        XCTAssertEqual(usageEvent?.model, "gpt-4")
        XCTAssertEqual(usageEvent?.costCents, 42)
        XCTAssertEqual(usageEvent?.tokenCount, 165)
    }

    func testParsesFractionalTokenUsageCostFromAPI() throws {
        let json = """
        {
          "timestamp": "1784820123233",
          "model": "composer-2.5",
          "tokenUsage": {
            "inputTokens": 66333,
            "outputTokens": 1847,
            "cacheReadTokens": 153734,
            "totalCents": 6.853079795837402
          },
          "chargedCents": 6.853079795837402
        }
        """

        let event = try JSONDecoder().decode(CursorUsageEventDisplay.self, from: Data(json.utf8))
        let usageEvent = UsageEventParser.makeUsageEvent(from: event)

        XCTAssertEqual(usageEvent?.costCents, 7)
        XCTAssertEqual(usageEvent?.timestamp, 1_784_820_123_233)
    }

    func testParsesUsageBasedCostString() throws {
        let json = """
        {
          "timestamp": "1700000000000",
          "model": "claude-3",
          "usageBasedCosts": "$0.12"
        }
        """

        let event = try JSONDecoder().decode(CursorUsageEventDisplay.self, from: Data(json.utf8))
        let usageEvent = UsageEventParser.makeUsageEvent(from: event)

        XCTAssertEqual(usageEvent?.costCents, 12)
        XCTAssertEqual(usageEvent?.model, "claude-3")
    }

    func testFiltersTodayEventsByLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let startOfDay = calendar.startOfDay(for: now).timeIntervalSince1970 * 1000

        let events = [
            UsageEvent(
                timestamp: startOfDay - 1,
                model: "old",
                costCents: 1,
                tokenCount: 1,
                inputTokens: 1,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheWriteTokens: 0
            ),
            UsageEvent(
                timestamp: startOfDay + 1,
                model: "today",
                costCents: 2,
                tokenCount: 2,
                inputTokens: 2,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheWriteTokens: 0
            ),
        ]

        let todayEvents = UsageEventParser.filterTodayEvents(events, now: now, calendar: calendar)
        XCTAssertEqual(todayEvents.count, 1)
        XCTAssertEqual(todayEvents.first?.model, "today")
    }
}
