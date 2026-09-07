import Foundation

struct CursorUsageEventsResponse: Decodable {
    let usageEventsDisplay: [CursorUsageEventDisplay]?
    let usageEvents: [CursorUsageEventDisplay]?
    let hasMore: Bool?
    let totalPages: Int?
}

struct CursorUsageEventDisplay: Decodable {
    let timestamp: CursorTimestamp?
    let model: String?
    let modelName: String?
    let usageBasedCosts: CursorFlexibleNumber?
    let chargedCents: CursorFlexibleNumber?
    let tokenUsage: CursorTokenUsage?
}

struct CursorTokenUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let totalCents: CursorFlexibleNumber?
    let chargedCents: CursorFlexibleNumber?
}

enum CursorTimestamp: Decodable {
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        throw DecodingError.typeMismatch(
            CursorTimestamp.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported timestamp type")
        )
    }
}

enum CursorFlexibleNumber: Decodable {
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        throw DecodingError.typeMismatch(
            CursorFlexibleNumber.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported flexible number type")
        )
    }
}

struct CursorUsageStartResponse: Decodable {
    let startOfMonth: String?
}

final class CursorUsageClient {
    private let apiBaseURL = URL(string: "https://cursor.com/api")!
    private let session: URLSession
    private let pageSize: Int
    private let maxPages: Int

    init(session: URLSession = .shared, pageSize: Int = 100, maxPages: Int = 20) {
        self.session = session
        self.pageSize = min(max(pageSize, 25), 500)
        self.maxPages = maxPages
    }

    func fetchTodayUsage(now: Date = Date(), calendar: Calendar = .current) async throws -> DailyUsage {
        let token = try CursorAuthReader.readAccessToken()
        let userId = try CursorAuthReader.extractUserId(from: token)

        let startOfToday = calendar.startOfDay(for: now)
        let billingStart = try await fetchBillingPeriodStart(token: token, userId: userId, now: now)

        let events = try await fetchUsageEvents(
            token: token,
            userId: userId,
            startTime: billingStart,
            endTime: now
        )

        let todayStart = startOfToday.timeIntervalSince1970 * 1000
        let todayEvents = events.filter { $0.timestamp >= todayStart }

        return DailyUsage(
            startTime: startOfToday.timeIntervalSince1970,
            endTime: now.timeIntervalSince1970,
            totalCostCents: todayEvents.reduce(0) { $0 + $1.costCents },
            totalTokens: todayEvents.reduce(0) { $0 + $1.tokenCount },
            eventCount: todayEvents.count,
            updatedAt: now
        )
    }

    private func fetchBillingPeriodStart(token: String, userId: String, now: Date) async throws -> Date {
        do {
            let response: CursorUsageStartResponse = try await get(
                path: "/usage",
                token: token,
                userId: userId
            )

            if let startOfMonth = response.startOfMonth,
               let date = ISO8601DateFormatter().date(from: startOfMonth)
                ?? parseFlexibleDate(startOfMonth) {
                return date
            }
        } catch {
            // Fall back to the first day of the current month.
        }

        let components = Calendar.current.dateComponents([.year, .month], from: now)
        return Calendar.current.date(from: components) ?? now
    }

    private func fetchUsageEvents(
        token: String,
        userId: String,
        startTime: Date,
        endTime: Date
    ) async throws -> [UsageEvent] {
        var events: [UsageEvent] = []
        let startMillis = Int64(startTime.timeIntervalSince1970 * 1000)
        let endMillis = Int64(endTime.timeIntervalSince1970 * 1000)

        for page in 1...maxPages {
            let response: CursorUsageEventsResponse = try await post(
                path: "/dashboard/get-filtered-usage-events",
                token: token,
                userId: userId,
                body: [
                    "teamId": 0,
                    "startDate": String(startMillis),
                    "endDate": String(endMillis),
                    "page": page,
                    "pageSize": pageSize,
                ]
            )

            let rawEvents = response.usageEventsDisplay ?? response.usageEvents ?? []
            events.append(contentsOf: rawEvents.compactMap(UsageEventParser.makeUsageEvent(from:)))

            let hasMore = response.hasMore == true
                || (response.totalPages.map { page < $0 } ?? false)
            if !hasMore && rawEvents.count < pageSize {
                break
            }
        }

        return events.sorted { $0.timestamp > $1.timestamp }
    }

    private func endpointURL(for path: String) -> URL {
        var url = apiBaseURL
        for component in path.split(separator: "/") where !component.isEmpty {
            url.appendPathComponent(String(component))
        }
        return url
    }

    private func get<T: Decodable>(
        path: String,
        token: String,
        userId: String
    ) async throws -> T {
        var request = URLRequest(url: endpointURL(for: path))
        request.httpMethod = "GET"
        applyCommonHeaders(to: &request, token: token, userId: userId)
        return try await perform(request)
    }

    private func post<T: Decodable>(
        path: String,
        token: String,
        userId: String,
        body: [String: Any]
    ) async throws -> T {
        var request = URLRequest(url: endpointURL(for: path))
        request.httpMethod = "POST"
        applyCommonHeaders(to: &request, token: token, userId: userId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func applyCommonHeaders(to request: inout URLRequest, token: String, userId: String) {
        let cookieValue = CursorAuthReader.buildCookieValue(userId: userId, token: token)
        request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CursorUsageError.apiError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CursorUsageError.invalidResponse
        }
    }

    private func parseFlexibleDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.date(from: value)
    }
}

enum UsageEventParser {
    static func makeUsageEvent(from event: CursorUsageEventDisplay) -> UsageEvent? {
        guard let timestamp = parseTimestamp(event.timestamp) else {
            return nil
        }

        let inputTokens = event.tokenUsage?.inputTokens ?? 0
        let outputTokens = event.tokenUsage?.outputTokens ?? 0
        let cacheReadTokens = event.tokenUsage?.cacheReadTokens ?? 0
        let cacheWriteTokens = event.tokenUsage?.cacheWriteTokens ?? 0

        return UsageEvent(
            timestamp: timestamp,
            model: event.modelName ?? event.model ?? "Unknown model",
            costCents: costCents(for: event),
            tokenCount: inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens
        )
    }

    static func parseTimestamp(_ value: CursorTimestamp?) -> TimeInterval? {
        guard let value else { return nil }

        switch value {
        case .number(let number):
            return number
        case .string(let string):
            if let numeric = Double(string) {
                return numeric
            }
            if let parsed = Date.parseISO8601(string) {
                return parsed.timeIntervalSince1970 * 1000
            }
            return nil
        }
    }

    static func costCents(for event: CursorUsageEventDisplay) -> Int {
        if let totalCents = centsValue(event.tokenUsage?.totalCents) {
            return totalCents
        }
        if let chargedCents = centsValue(event.tokenUsage?.chargedCents) {
            return chargedCents
        }
        if let chargedCents = centsValue(event.chargedCents) {
            return chargedCents
        }
        return parseUsageBasedCostCents(event.usageBasedCosts)
    }

    static func centsValue(_ value: CursorFlexibleNumber?) -> Int? {
        guard let value else { return nil }

        switch value {
        case .number(let number):
            return Int(number.rounded())
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "-", let numeric = Double(trimmed) else {
                return nil
            }
            return Int(numeric.rounded())
        }
    }

    static func parseUsageBasedCostCents(_ value: CursorFlexibleNumber?) -> Int {
        guard let value else { return 0 }

        switch value {
        case .number(let number):
            return Int((number * 100).rounded())
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "-" {
                return 0
            }

            let cleaned = trimmed
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "¢", with: "")

            guard let numeric = Double(cleaned) else {
                return 0
            }

            return trimmed.contains("¢") ? Int(numeric.rounded()) : Int((numeric * 100).rounded())
        }
    }

    static func filterTodayEvents(_ events: [UsageEvent], now: Date = Date(), calendar: Calendar = .current) -> [UsageEvent] {
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970 * 1000
        return events.filter { $0.timestamp >= startOfToday }
    }
}

private extension Date {
    static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
