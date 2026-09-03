import Foundation

final class CommuteFailsafeRunner {
    private var failsafeProcess: Process?

    func start(leasePath: String, ownerPID: Int32, deadline: Date, bundle: Bundle = .main) throws -> Int32 {
        guard let executableURL = CommuteFailsafePaths.failsafeExecutableURL(bundle: bundle) else {
            throw PowerManagementError.commandFailed("CommuteFailsafe executable not found in app bundle.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--lease-path", leasePath,
            "--owner-pid", String(ownerPID),
            "--deadline", ISO8601DateFormatter().string(from: deadline),
            "--battery-threshold", "20",
        ]

        try process.run()
        failsafeProcess = process
        return process.processIdentifier
    }

    func stop() {
        guard let process = failsafeProcess, process.isRunning else {
            failsafeProcess = nil
            return
        }
        process.terminate()
        process.waitUntilExit()
        failsafeProcess = nil
    }

    func isRunning() -> Bool {
        failsafeProcess?.isRunning ?? false
    }
}
