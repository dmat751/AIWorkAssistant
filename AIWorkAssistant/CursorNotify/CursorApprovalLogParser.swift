import CommonCrypto
import Foundation

enum CursorApprovalEventKind: Equatable {
    case shell
    case mcp
}

struct CursorApprovalEvent: Equatable {
    let kind: CursorApprovalEventKind
    let dedupeKey: String
    let title: String
    let body: String
}

enum CursorApprovalLogEntry: Equatable {
    case push(CursorApprovalEvent)
    case pendingShell(CursorApprovalEvent)
    case resolveShell(toolCallId: String)
}

enum CursorApprovalLogParser {
    static func parse(line: String) -> CursorApprovalLogEntry? {
        if let toolCallId = parseShellGateResolutionToolCallId(line: line) {
            return .resolveShell(toolCallId: toolCallId)
        }
        if let event = parseStructuredShellApproval(line: line) {
            return .pendingShell(event)
        }
        if let event = parseShellRunConfirmation(line: line) {
            return .pendingShell(event)
        }
        if let event = parseMCPAllowlistApproval(line: line) {
            return .push(event)
        }
        return nil
    }

    private static func parseShellGateResolutionToolCallId(line: String) -> String? {
        guard line.contains("Shell stream: approval gate blocked command")
            || line.contains("Shell stream: approval gate allowed command") else {
            return nil
        }
        guard let toolCallId = metadataValue(in: line, key: "toolCallId"), !toolCallId.isEmpty else {
            return nil
        }
        return toolCallId
    }

    private static func parseStructuredShellApproval(line: String) -> CursorApprovalEvent? {
        guard line.contains("Shell permissions: requesting shell approval") else {
            return nil
        }

        let toolCallId = metadataValue(in: line, key: "toolCallId")
        let dedupeKey = toolCallId.map { "shell:\($0)" } ?? fingerprint(for: line)

        let policyType = metadataValue(in: line, key: "requestedPolicyType") ?? "shell"
        let commandCount = metadataValue(in: line, key: "commandCount")
        var details = "Shell approval needed (\(policyType))"
        if let commandCount {
            details += ", \(commandCount) command(s)"
        }

        return CursorApprovalEvent(
            kind: .shell,
            dedupeKey: dedupeKey,
            title: "Cursor: approve",
            body: details
        )
    }

    private static func parseShellRunConfirmation(line: String) -> CursorApprovalEvent? {
        guard line.contains("Shell permissions: auto-approved shell command") else {
            return nil
        }
        guard metadataValue(in: line, key: "allCommandsPreapproved") == "true" else {
            return nil
        }
        guard metadataValue(in: line, key: "allCommandsAllowlisted") == "false" else {
            return nil
        }

        let toolCallId = metadataValue(in: line, key: "toolCallId")
        let dedupeKey = toolCallId.map { "shell:run:\($0)" } ?? fingerprint(for: line)
        let policyType = metadataValue(in: line, key: "mergedPolicyType")
            ?? metadataValue(in: line, key: "autoApprovalPolicyType")
            ?? "shell"

        return CursorApprovalEvent(
            kind: .shell,
            dedupeKey: dedupeKey,
            title: "Cursor: approve",
            body: "Shell run waiting for confirmation (\(policyType))"
        )
    }

    private static func parseMCPAllowlistApproval(line: String) -> CursorApprovalEvent? {
        guard line.contains("shouldBlockMcp: needsApproval") else {
            return nil
        }

        let toolName = quotedValue(in: line, key: "toolName") ?? "unknown tool"
        let provider = quotedValue(in: line, key: "providerIdentifier") ?? "unknown provider"
        let dedupeKey = "mcp:\(provider):\(toolName):\(fingerprint(for: line))"

        return CursorApprovalEvent(
            kind: .mcp,
            dedupeKey: dedupeKey,
            title: "Cursor: approve",
            body: "MCP approval needed: \(toolName) (\(provider))"
        )
    }

    private static func metadataValue(in line: String, key: String) -> String? {
        let pattern = #""\#(key)":"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange])
    }

    private static func quotedValue(in line: String, key: String) -> String? {
        let pattern = #"\#(key)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange])
    }

    private static func fingerprint(for line: String) -> String {
        let digest = SHA256Digest.hash(data: Data(line.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum SHA256Digest {
    static func hash(data: Data) -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash
    }
}
