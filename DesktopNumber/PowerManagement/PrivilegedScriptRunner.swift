import Foundation

protocol PrivilegedScriptRunner {
    func runPrivilegedShellScript(_ shellCommand: String) throws -> String
}

struct UnavailablePrivilegedScriptRunner: PrivilegedScriptRunner {
    func runPrivilegedShellScript(_ shellCommand: String) throws -> String {
        throw PowerManagementError.commandFailed("Privileged execution is not available.")
    }
}

enum AppleScriptShellEscaping {
    static func escapeForAppleScriptShell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func escapeForSingleQuotedShell(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
