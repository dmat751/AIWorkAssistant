import XCTest
@testable import AIWorkAssistant

final class CommuteFailsafePolicyTests: XCTestCase {
    func testTimerExpiryTriggersStop() {
        let policy = CommuteFailsafePolicy(batteryThresholdPercent: 20, pollIntervalSeconds: 5)
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(-1)
        let ownerPID = ProcessInfo.processInfo.processIdentifier

        let reason = policy.shouldStop(
            ownerPID: ownerPID,
            deadline: deadline,
            now: now,
            isOnBattery: false,
            batteryPercent: 80,
            thermalState: .nominal
        )

        XCTAssertEqual(reason, .timerExpired)
    }

    func testBatteryThresholdTriggersStopOnBattery() {
        let policy = CommuteFailsafePolicy(batteryThresholdPercent: 20, pollIntervalSeconds: 5)
        let now = Date()
        let ownerPID = ProcessInfo.processInfo.processIdentifier

        let reason = policy.shouldStop(
            ownerPID: ownerPID,
            deadline: now.addingTimeInterval(3600),
            now: now,
            isOnBattery: true,
            batteryPercent: 15,
            thermalState: .nominal
        )

        XCTAssertEqual(reason, .batteryLow)
    }

    func testThermalSeriousTriggersStop() {
        let policy = CommuteFailsafePolicy(batteryThresholdPercent: 20, pollIntervalSeconds: 5)
        let now = Date()
        let ownerPID = ProcessInfo.processInfo.processIdentifier

        let reason = policy.shouldStop(
            ownerPID: ownerPID,
            deadline: now.addingTimeInterval(3600),
            now: now,
            isOnBattery: false,
            batteryPercent: 80,
            thermalState: .serious
        )

        XCTAssertEqual(reason, .thermalPressure)
    }
}
