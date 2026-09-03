import XCTest
@testable import AIWorkAssistant

final class CommutePermissionInstallerTests: XCTestCase {
    func testEscapeForAppleScriptShellEscapesQuotesAndBackslashes() {
        let input = #"path\"with"quotes"#
        let escaped = AppleScriptShellEscaping.escapeForAppleScriptShell(input)
        XCTAssertEqual(escaped, #"path\\\"with\"quotes"#)
    }

    func testEscapeForSingleQuotedShellEscapesEmbeddedQuotes() {
        let input = "O'Brien's Mac"
        let escaped = AppleScriptShellEscaping.escapeForSingleQuotedShell(input)
        XCTAssertEqual(escaped, "'O'\\''Brien'\\''s Mac'")
    }

    func testInstallShellCommandIncludesSudoUserAndScriptPath() {
        let command = CommutePermissionInstaller.installShellCommand(
            username: "testuser",
            scriptPath: "/Applications/AIWorkAssistant.app/Contents/Resources/CommuteScripts/install-commute-permission.sh"
        )

        XCTAssertTrue(command.hasPrefix("export SUDO_USER='testuser'; /bin/bash "))
        XCTAssertTrue(command.contains("install-commute-permission.sh"))
    }

    func testInstallShellCommandEscapesSpacesInPath() {
        let command = CommutePermissionInstaller.installShellCommand(
            username: "test user",
            scriptPath: "/My Apps/AIWorkAssistant.app/Contents/Resources/CommuteScripts/install-commute-permission.sh"
        )

        XCTAssertTrue(command.contains("export SUDO_USER='test user'"))
        XCTAssertTrue(command.contains("'/My Apps/AIWorkAssistant.app/Contents/Resources/CommuteScripts/install-commute-permission.sh'"))
    }

    func testInstallInvokesPrivilegedRunnerWithShellCommand() throws {
        let runner = MockPrivilegedScriptRunner()
        let resourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommutePermissionInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: resourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resourceDirectory) }

        let scriptURL = resourceDirectory.appendingPathComponent("install-commute-permission.sh")
        try "#!/bin/bash\necho ok\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let command = CommutePermissionInstaller.installShellCommand(
            username: "alice",
            scriptPath: scriptURL.path
        )
        try runner.runPrivilegedShellScript(command)

        XCTAssertEqual(runner.lastCommand, command)
    }

    func testUninstallShellCommandEscapesSpacesInPath() {
        let command = CommutePermissionInstaller.uninstallShellCommand(
            scriptPath: "/My Apps/AIWorkAssistant.app/Contents/Resources/CommuteScripts/uninstall-commute-permission.sh"
        )

        XCTAssertEqual(
            command,
            "/bin/bash '/My Apps/AIWorkAssistant.app/Contents/Resources/CommuteScripts/uninstall-commute-permission.sh'"
        )
    }
}

private final class MockPrivilegedScriptRunner: PrivilegedScriptRunner {
    private(set) var lastCommand: String?

    func runPrivilegedShellScript(_ shellCommand: String) throws -> String {
        lastCommand = shellCommand
        return ""
    }
}
