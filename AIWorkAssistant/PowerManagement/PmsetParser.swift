import Foundation

struct PmsetProfileSettings {
    let sleepMinutes: Int?
    let tcpKeepAlive: Bool?
}

enum PmsetParser {
    static func parseSleepDisabled(from pmsetGOutput: String) -> Bool {
        for line in pmsetGOutput.split(separator: "\n") {
            let parts = line
                .trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            if parts[0] == "SleepDisabled", parts[1] == "1" {
                return true
            }
        }
        return false
    }

    static func parseCustomProfiles(from output: String) -> (ac: PmsetProfileSettings, battery: PmsetProfileSettings) {
        var section = ""
        var acSleep: Int?
        var batterySleep: Int?
        var acTcpKeepAlive: Int?
        var batteryTcpKeepAlive: Int?

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "AC Power:" {
                section = "ac"
                continue
            }
            if trimmed == "Battery Power:" {
                section = "battery"
                continue
            }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let value = Int(parts.last!) else { continue }
            let key = parts.dropLast().joined(separator: " ")

            switch key {
            case "sleep":
                if section == "ac" { acSleep = value }
                if section == "battery" { batterySleep = value }
            case "tcpkeepalive":
                if section == "ac" { acTcpKeepAlive = value }
                if section == "battery" { batteryTcpKeepAlive = value }
            default:
                break
            }
        }

        let ac = PmsetProfileSettings(
            sleepMinutes: acSleep,
            tcpKeepAlive: acTcpKeepAlive.map { $0 != 0 }
        )
        let battery = PmsetProfileSettings(
            sleepMinutes: batterySleep,
            tcpKeepAlive: batteryTcpKeepAlive.map { $0 != 0 }
        )
        return (ac, battery)
    }

    static func parseActiveSleepMinutes(from pmsetGOutput: String) -> Int? {
        for line in pmsetGOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[0] == "sleep", let value = Int(parts[1]) else { continue }
            return value
        }
        return nil
    }
}
