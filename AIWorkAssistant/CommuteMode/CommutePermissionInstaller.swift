import AppKit
import Foundation

enum CommutePermissionInstallError: LocalizedError {
    case missingBundleResource
    case cancelled
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource:
            return "Missing bundled commute permission installer script."
        case .cancelled:
            return "Permission installation was cancelled."
        case .scriptFailed(let message):
            return message
        }
    }
}

struct NSAppleScriptPrivilegedRunner: PrivilegedScriptRunner {
    func runPrivilegedShellScript(_ shellCommand: String) throws -> String {
        let source =
            "do shell script \"\(AppleScriptShellEscaping.escapeForAppleScriptShell(shellCommand))\" with administrator privileges"
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        guard let result = script?.executeAndReturnError(&errorInfo) else {
            if let errorInfo {
                let number = errorInfo[NSAppleScript.errorNumber] as? Int
                if number == -128 {
                    throw CommutePermissionInstallError.cancelled
                }
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                throw CommutePermissionInstallError.scriptFailed(message)
            }
            throw CommutePermissionInstallError.scriptFailed("AppleScript execution failed.")
        }

        return result.stringValue ?? ""
    }
}

struct CommutePermissionInstaller {
    static let bundledResourceDirectory = "CommuteScripts"
    static let installScriptName = "install-commute-permission.sh"
    static let uninstallScriptName = "uninstall-commute-permission.sh"

    private let bundle: Bundle
    private let runner: PrivilegedScriptRunner

    init(
        bundle: Bundle = .main,
        runner: PrivilegedScriptRunner = NSAppleScriptPrivilegedRunner()
    ) {
        self.bundle = bundle
        self.runner = runner
    }

    func install(username: String) throws {
        let scriptURL = try bundledScriptURL(named: Self.installScriptName)
        let shellCommand = Self.installShellCommand(
            username: username,
            scriptPath: scriptURL.path
        )
        _ = try runner.runPrivilegedShellScript(shellCommand)
    }

    func uninstall() throws {
        let scriptURL = try bundledScriptURL(named: Self.uninstallScriptName)
        _ = try runner.runPrivilegedShellScript(Self.uninstallShellCommand(scriptPath: scriptURL.path))
    }

    static func installShellCommand(username: String, scriptPath: String) -> String {
        let escapedUser = AppleScriptShellEscaping.escapeForSingleQuotedShell(username)
        let escapedPath = AppleScriptShellEscaping.escapeForSingleQuotedShell(scriptPath)
        return "export SUDO_USER=\(escapedUser); /bin/bash \(escapedPath)"
    }

    static func uninstallShellCommand(scriptPath: String) -> String {
        let escapedPath = AppleScriptShellEscaping.escapeForSingleQuotedShell(scriptPath)
        return "/bin/bash \(escapedPath)"
    }

    private func bundledScriptURL(named scriptName: String) throws -> URL {
        let resourceName = (scriptName as NSString).deletingPathExtension
        let fileExtension = (scriptName as NSString).pathExtension

        if let url = bundle.url(
            forResource: resourceName,
            withExtension: fileExtension.isEmpty ? nil : fileExtension,
            subdirectory: Self.bundledResourceDirectory
        ) {
            return url
        }

        throw CommutePermissionInstallError.missingBundleResource
    }
}
