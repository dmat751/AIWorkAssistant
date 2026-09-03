import Foundation

enum PowerManagementError: LocalizedError {
    case sleepStateVerificationFailed
    case officeModeVerificationFailed
    case passwordlessAccessMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .sleepStateVerificationFailed:
            return "pmset did not apply the expected sleep setting."
        case .officeModeVerificationFailed:
            return "pmset did not apply the expected office power setting."
        case .passwordlessAccessMissing:
            return "Passwordless pmset access is not installed. Run scripts/install-commute-permission.sh."
        case .commandFailed(let message):
            return message
        }
    }
}

protocol PowerManagementClient {
    func isSleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
    func officePowerStatus() throws -> OfficePowerStatus
    func enableOfficePowerMode() throws
    func hasPasswordlessPmsetAccess() -> Bool
}

final class PmsetPowerManagementClient: PowerManagementClient {
    private let commandExecutor: CommandExecutor
    private let powerStatusMonitor: PowerStatusMonitor
    private let privilegedRunner: PrivilegedScriptRunner

    init(
        commandExecutor: CommandExecutor = ProcessCommandExecutor(),
        powerStatusMonitor: PowerStatusMonitor = PowerStatusMonitor(),
        privilegedRunner: PrivilegedScriptRunner = UnavailablePrivilegedScriptRunner()
    ) {
        self.commandExecutor = commandExecutor
        self.powerStatusMonitor = powerStatusMonitor
        self.privilegedRunner = privilegedRunner
    }

    static func enableOfficeModeShellCommand() -> String {
        "/usr/bin/pmset -c sleep 0"
    }

    func isSleepDisabled() throws -> Bool {
        let result = try runPmset(arguments: ["-g"])
        guard result.exitCode == 0 else {
            throw PowerManagementError.commandFailed(result.stderr)
        }
        return PmsetParser.parseSleepDisabled(from: result.stdout)
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        guard hasPasswordlessPmsetAccess() else {
            throw PowerManagementError.passwordlessAccessMissing
        }

        let value = disabled ? "1" : "0"
        let result = try runPrivilegedPmset(arguments: ["-a", "disablesleep", value])
        guard result.exitCode == 0 else {
            throw PowerManagementError.commandFailed(result.stderr)
        }

        let verified = try isSleepDisabled()
        if verified != disabled {
            throw PowerManagementError.sleepStateVerificationFailed
        }
    }

    func officePowerStatus() throws -> OfficePowerStatus {
        let result = try runPmset(arguments: ["-g", "custom"])
        guard result.exitCode == 0 else {
            throw PowerManagementError.commandFailed(result.stderr)
        }

        let profiles = PmsetParser.parseCustomProfiles(from: result.stdout)
        return OfficePowerStatus.evaluate(
            isOnACPower: powerStatusMonitor.isOnACPower(),
            acSleepMinutes: profiles.ac.sleepMinutes
        )
    }

    func enableOfficePowerMode() throws {
        _ = try privilegedRunner.runPrivilegedShellScript(Self.enableOfficeModeShellCommand())

        let status = try officePowerStatus()
        guard status.preventSleepWhenDisplayOff else {
            throw PowerManagementError.officeModeVerificationFailed
        }
    }

    func hasPasswordlessPmsetAccess() -> Bool {
        do {
            let result = try commandExecutor.run(
                executablePath: "/usr/bin/sudo",
                arguments: ["-n", "-l"]
            )
            guard result.exitCode == 0 else { return false }
            return result.stdout.contains("/usr/bin/pmset") && result.stdout.contains("disablesleep")
        } catch {
            return false
        }
    }

    private func runPmset(arguments: [String]) throws -> CommandResult {
        try commandExecutor.run(executablePath: "/usr/bin/pmset", arguments: arguments)
    }

    private func runPrivilegedPmset(arguments: [String]) throws -> CommandResult {
        try commandExecutor.run(
            executablePath: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/pmset"] + arguments
        )
    }
}
