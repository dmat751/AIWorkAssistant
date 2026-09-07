import Foundation

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandExecutor {
    func run(executablePath: String, arguments: [String]) throws -> CommandResult
}

enum CommandExecutorError: LocalizedError {
    case failedToLaunch(String)
    case nonZeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .failedToLaunch(let path):
            return "Failed to launch \(path)."
        case .nonZeroExit(let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Command failed with exit code \(code)."
            }
            return trimmed
        }
    }
}

struct ProcessCommandExecutor: CommandExecutor {
    func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CommandExecutorError.failedToLaunch(executablePath)
        }

        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
