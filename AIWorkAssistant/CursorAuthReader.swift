import Foundation
import SQLite3

enum CursorAuthReader {
    private static let accessTokenKey = "cursorAuth/accessToken"

    static func cursorStateDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Cursor/User/globalStorage/state.vscdb")
            .path
    }

    static func readAccessToken() throws -> String {
        let dbPath = cursorStateDatabasePath()
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw CursorUsageError.stateDatabaseNotFound
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw CursorUsageError.accessTokenNotFound
        }
        defer { sqlite3_close(database) }

        let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw CursorUsageError.accessTokenNotFound
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, accessTokenKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawValue = sqlite3_column_text(statement, 0) else {
            throw CursorUsageError.accessTokenNotFound
        }

        let token = String(cString: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw CursorUsageError.accessTokenNotFound
        }

        return token
    }

    static func extractUserId(from token: String) throws -> String {
        let decodedToken = decodeSafely(token)

        if decodedToken.hasPrefix("user_"), let separator = decodedToken.range(of: "::") {
            return String(decodedToken[..<separator.lowerBound])
        }

        let jwt = decodedToken.contains("::")
            ? decodedToken.split(separator: "::", omittingEmptySubsequences: false).last.map(String.init) ?? decodedToken
            : decodedToken

        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else {
            throw CursorUsageError.invalidToken("Cursor access token is not a JWT.")
        }

        let payloadData = try base64URLDecode(String(segments[1]))
        guard let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw CursorUsageError.invalidToken("Could not parse Cursor access token payload.")
        }

        let rawUserId = (payload["sub"] as? String)
            ?? (payload["userId"] as? String)
            ?? (payload["user_id"] as? String)

        guard let rawUserId,
              let match = rawUserId.range(of: #"user_[A-Za-z0-9_-]+"#, options: .regularExpression) else {
            throw CursorUsageError.invalidToken("Could not extract Cursor user id from access token.")
        }

        return String(rawUserId[match])
    }

    static func buildCookieValue(userId: String, token: String) -> String {
        let decodedToken = decodeSafely(token)

        if decodedToken.contains("::") {
            return decodedToken.replacingOccurrences(of: "::", with: "%3A%3A")
        }

        if token.contains("%3A%3A") {
            return token
        }

        return "\(userId)%3A%3A\(decodedToken)"
    }

    private static func decodeSafely(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: normalized) else {
            throw CursorUsageError.invalidToken("Could not decode Cursor access token payload.")
        }

        return data
    }
}
