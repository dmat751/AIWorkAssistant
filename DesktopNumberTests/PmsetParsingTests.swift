import XCTest
@testable import DesktopNumber

final class PmsetParsingTests: XCTestCase {
    func testParseSleepDisabled() {
        let output = """
        SleepDisabled\t1
        sleep                0
        """
        XCTAssertTrue(PmsetParser.parseSleepDisabled(from: output))
    }

    func testParseSleepDisabledWithDoubleTabAlignment() {
        let output = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         sleep                0
        """
        XCTAssertTrue(PmsetParser.parseSleepDisabled(from: output))
    }

    func testParseSleepDisabledReturnsFalseForZero() {
        let output = " SleepDisabled\t\t0\n"
        XCTAssertFalse(PmsetParser.parseSleepDisabled(from: output))
    }

    func testParseCustomProfiles() {
        let output = """
        AC Power:
         sleep                0
         tcpkeepalive         1
        Battery Power:
         sleep                1
         tcpkeepalive         0
        """
        let profiles = PmsetParser.parseCustomProfiles(from: output)
        XCTAssertEqual(profiles.ac.sleepMinutes, 0)
        XCTAssertEqual(profiles.ac.tcpKeepAlive, true)
        XCTAssertEqual(profiles.battery.sleepMinutes, 1)
        XCTAssertEqual(profiles.battery.tcpKeepAlive, false)
    }

    func testOfficeReadyOnACWithSleepZero() {
        let status = OfficePowerStatus.evaluate(isOnACPower: true, acSleepMinutes: 0)
        XCTAssertTrue(status.preventSleepWhenDisplayOff)
        XCTAssertTrue(status.isOfficeReady)
    }

    func testOfficeNotReadyOnBatteryEvenWithSleepZero() {
        let status = OfficePowerStatus.evaluate(isOnACPower: false, acSleepMinutes: 0)
        XCTAssertFalse(status.isOfficeReady)
    }

    func testEnableOfficeModeShellCommand() {
        XCTAssertEqual(
            PmsetPowerManagementClient.enableOfficeModeShellCommand(),
            "/usr/bin/pmset -c sleep 0"
        )
    }

    func testEnableOfficePowerModeThrowsWhenVerificationFails() throws {
        let customOutput = """
        AC Power:
         sleep                1
        Battery Power:
         sleep                1
        """

        let executor = MockCommandExecutor(
            responses: [
                MockCommandResponse(executablePath: "/usr/bin/pmset", arguments: ["-g", "custom"], stdout: customOutput)
            ]
        )
        let runner = MockPrivilegedScriptRunner()
        let client = PmsetPowerManagementClient(
            commandExecutor: executor,
            powerStatusMonitor: PowerStatusMonitor(powerSourceReader: MockPowerSourceReader()),
            privilegedRunner: runner
        )

        XCTAssertThrowsError(try client.enableOfficePowerMode()) { error in
            guard case PowerManagementError.officeModeVerificationFailed = error else {
                return XCTFail("Expected officeModeVerificationFailed, got \(error)")
            }
        }
        XCTAssertEqual(runner.lastCommand, "/usr/bin/pmset -c sleep 0")
    }

    func testEnableOfficePowerModeSucceedsWhenSleepZero() throws {
        let customOutput = """
        AC Power:
         sleep                0
        Battery Power:
         sleep                1
        """

        let executor = MockCommandExecutor(
            responses: [
                MockCommandResponse(executablePath: "/usr/bin/pmset", arguments: ["-g", "custom"], stdout: customOutput)
            ]
        )
        let runner = MockPrivilegedScriptRunner()
        let client = PmsetPowerManagementClient(
            commandExecutor: executor,
            powerStatusMonitor: PowerStatusMonitor(powerSourceReader: MockPowerSourceReader()),
            privilegedRunner: runner
        )

        XCTAssertNoThrow(try client.enableOfficePowerMode())
        let status = try client.officePowerStatus()
        XCTAssertTrue(status.preventSleepWhenDisplayOff)
        XCTAssertTrue(status.isOfficeReady)
    }
}

private struct MockCommandResponse {
    let executablePath: String
    let arguments: [String]
    let stdout: String
    let stderr: String
    let exitCode: Int32

    init(
        executablePath: String,
        arguments: [String],
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32 = 0
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

private final class MockCommandExecutor: CommandExecutor {
    private let responses: [MockCommandResponse]

    init(responses: [MockCommandResponse]) {
        self.responses = responses
    }

    func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        if let match = responses.first(where: {
            $0.executablePath == executablePath && $0.arguments == arguments
        }) {
            return CommandResult(exitCode: match.exitCode, stdout: match.stdout, stderr: match.stderr)
        }

        return CommandResult(exitCode: 1, stdout: "", stderr: "No mock response for \(executablePath) \(arguments)")
    }
}

private final class MockPrivilegedScriptRunner: PrivilegedScriptRunner {
    private(set) var lastCommand: String?

    func runPrivilegedShellScript(_ shellCommand: String) throws -> String {
        lastCommand = shellCommand
        return ""
    }
}
