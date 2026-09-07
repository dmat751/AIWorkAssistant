import Foundation

enum UsageFormatting {
    static func formatDollars(cents: Int) -> String {
        let dollars = Double(cents) / 100.0

        if dollars > 0 && dollars < 0.01 {
            return String(format: "$%.4f", dollars)
        }

        return String(format: "$%.2f", dollars)
    }

    static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
        }

        if tokens >= 1_000 {
            return "\(tokens / 1_000)k"
        }

        return String(tokens)
    }

    static func formatRelativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))

        if seconds < 60 {
            return "just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        return "\(hours)h ago"
    }

    static func formatDuration(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }

    static func formatThermalState(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    static func formatCommuteStopReason(_ reason: CommuteStopReason) -> String {
        switch reason {
        case .user:
            return "Stopped manually"
        case .userQuit:
            return "Stopped on quit"
        case .timerExpired:
            return "Stopped: 90-minute limit reached"
        case .batteryLow:
            return "Stopped: battery below 20%"
        case .thermalPressure:
            return "Stopped: thermal pressure"
        case .ownerProcessEnded:
            return "Stopped: app process ended"
        case .failsafeTriggered:
            return "Stopped by fail-safe"
        case .reconciliation:
            return "Stopped during startup reconciliation"
        case .helperLost:
            return "Stopped: fail-safe helper lost"
        case .permissionMissing:
            return "Stopped: permission missing"
        case .externalOverride:
            return "External sleep override detected"
        }
    }
}
