import Foundation

struct CommuteFailsafePolicy {
    let batteryThresholdPercent: Int
    let pollIntervalSeconds: TimeInterval

    func shouldStop(
        ownerPID: Int32,
        deadline: Date,
        now: Date,
        isOnBattery: Bool,
        batteryPercent: Int?,
        thermalState: ProcessInfo.ThermalState
    ) -> CommuteStopReason? {
        if !ProcessLiveness.isProcessRunning(pid: ownerPID) {
            return .ownerProcessEnded
        }
        if now >= deadline {
            return .timerExpired
        }
        if isOnBattery,
           let batteryPercent,
           batteryPercent <= batteryThresholdPercent {
            return .batteryLow
        }
        if thermalState == .serious || thermalState == .critical {
            return .thermalPressure
        }
        return nil
    }
}
