import Foundation

struct UsageEvent: Equatable {
    let timestamp: TimeInterval
    let model: String
    let costCents: Int
    let tokenCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
}

struct DailyUsage: Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let totalCostCents: Int
    let totalTokens: Int
    let eventCount: Int
    let updatedAt: Date
}

enum CursorUsageError: LocalizedError {
    case stateDatabaseNotFound
    case accessTokenNotFound
    case invalidToken(String)
    case apiError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .stateDatabaseNotFound:
            return "Cursor state database not found. Make sure Cursor is installed and you are logged in."
        case .accessTokenNotFound:
            return "Cursor access token not found. Make sure you are logged into Cursor."
        case .invalidToken(let message):
            return message
        case .apiError(let statusCode):
            return "Cursor API returned \(statusCode)."
        case .invalidResponse:
            return "Cursor API returned an invalid response."
        }
    }
}
