import XCTest
@testable import AIWorkAssistant

final class CursorAuthReaderTests: XCTestCase {
    func testExtractUserIdFromPrefixedToken() throws {
        let userId = try CursorAuthReader.extractUserId(from: "user_abc123::jwt-part")
        XCTAssertEqual(userId, "user_abc123")
    }

    func testExtractUserIdFromJWT() throws {
        let payload = #"{"sub":"auth0|user_xyz789"}"#
        let encodedPayload = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let token = "header.\(encodedPayload).signature"
        let userId = try CursorAuthReader.extractUserId(from: token)
        XCTAssertEqual(userId, "user_xyz789")
    }

    func testBuildCookieValueEncodesSeparator() {
        let cookie = CursorAuthReader.buildCookieValue(
            userId: "user_abc123",
            token: "user_abc123::jwt-part"
        )
        XCTAssertEqual(cookie, "user_abc123%3A%3Ajwt-part")
    }
}
