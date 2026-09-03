import XCTest
@testable import AIWorkAssistant

@MainActor
final class CursorApprovalMonitorTests: XCTestCase {
    func testSendsPushForMCPApprovalImmediately() async {
        let sender = MockNtfySender()
        let monitor = CursorApprovalMonitor(
            ntfyClient: sender,
            pollInterval: 60,
            pendingDelay: 1.5
        )

        let line = """
        shouldBlockMcp: needsApproval (not in allowlist) toolName="cursor_dialog", providerIdentifier="cursor-app-control"
        """
        monitor.handle(line: line)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sender.sent.count, 1)
        XCTAssertEqual(sender.sent.first?.title, "Cursor: approve")
    }

    func testDoesNotPushWhenShellApprovalAutoResolvesInSameBatch() async {
        let sender = MockNtfySender()
        let monitor = CursorApprovalMonitor(
            ntfyClient: sender,
            pollInterval: 60,
            pendingDelay: 1.5
        )

        let requesting = """
        {"message":"Shell permissions: requesting shell approval","metadata":{"toolCallId":"tool_5a1254fc","requestedPolicyType":"insecure_none","commandCount":"2"}}
        """
        let blocked = """
        {"message":"Shell stream: approval gate blocked command","metadata":{"toolCallId":"tool_5a1254fc","blockReasonType":"userRejected"}}
        """
        monitor.handle(lines: [requesting, blocked])

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sender.sent.count, 0)
    }

    func testSendsPushAfterPendingShellDelayExpires() async {
        let sender = MockNtfySender()
        let monitor = CursorApprovalMonitor(
            ntfyClient: sender,
            pollInterval: 60,
            pendingDelay: 0.05
        )

        let line = """
        {"message":"Shell permissions: requesting shell approval","metadata":{"toolCallId":"tool_123","hookForcesPrompt":"false","requestedPolicyType":"insecure_none","commandCount":"1"}}
        """
        monitor.handle(line: line)
        monitor.flushExpiredPending(now: Date().addingTimeInterval(0.1))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sender.sent.count, 1)
        XCTAssertEqual(sender.sent.first?.title, "Cursor: approve")
    }

    func testDoesNotPushAgainForReplayedToolCallId() async {
        let sender = MockNtfySender()
        let monitor = CursorApprovalMonitor(
            ntfyClient: sender,
            pollInterval: 60,
            pendingDelay: 0.05
        )

        let requesting = """
        {"message":"Shell permissions: requesting shell approval","metadata":{"toolCallId":"tool_replay","requestedPolicyType":"insecure_none","commandCount":"1"}}
        """
        let blocked = """
        {"message":"Shell stream: approval gate blocked command","metadata":{"toolCallId":"tool_replay","blockReasonType":"userRejected"}}
        """
        monitor.handle(lines: [requesting, blocked])
        monitor.handle(line: requesting)
        monitor.flushExpiredPending(now: Date().addingTimeInterval(0.1))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sender.sent.count, 0)
    }

    func testDoesNotPushWhenAutoApprovedShellIsImmediatelyAllowed() async {
        let sender = MockNtfySender()
        let monitor = CursorApprovalMonitor(
            ntfyClient: sender,
            pollInterval: 60,
            pendingDelay: 1.5
        )

        let autoApproved = """
        {"message":"Shell permissions: auto-approved shell command","metadata":{"toolCallId":"tool_expo","allCommandsPreapproved":"true","allCommandsAllowlisted":"false","mergedPolicyType":"workspace_readwrite"}}
        """
        let allowed = """
        {"message":"Shell stream: approval gate allowed command","metadata":{"toolCallId":"tool_expo"}}
        """
        monitor.handle(lines: [autoApproved, allowed])

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sender.sent.count, 0)
    }

    func testPollReadsNewApprovalLinesFromLogFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWorkAssistantApprovalMonitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("Cursor Structured Logs.test.log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let tailer = CursorApprovalLogTailer(fileManager: .default, logsRoot: root)
        let sender = MockNtfySender()
        let monitor = CursorApprovalMonitor(
            tailer: tailer,
            ntfyClient: sender,
            pollInterval: 60,
            pendingDelay: 0.05
        )

        monitor.start()
        let approvalLine = "{\"message\":\"Shell permissions: requesting shell approval\",\"metadata\":{\"toolCallId\":\"tool_poll\",\"hookForcesPrompt\":\"false\"}}\n"
        try approvalLine.append(to: fileURL)

        monitor.poll()
        monitor.flushExpiredPending(now: Date().addingTimeInterval(0.1))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sender.sent.count, 1)
        monitor.stop()
    }
}

private final class MockNtfySender: CursorNtfySending {
    struct SentMessage {
        let title: String
        let body: String
    }

    private(set) var sent: [SentMessage] = []

    func sendApprovalPush(title: String, body: String) async throws {
        sent.append(SentMessage(title: title, body: body))
    }
}

private extension String {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = self.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }
}
