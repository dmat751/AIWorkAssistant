import XCTest
@testable import DesktopNumber

final class MockPowerManagementClient: PowerManagementClient {
    var sleepDisabled = false
    var passwordlessAccess = true
    var officeStatus = OfficePowerStatus.evaluate(isOnACPower: true, acSleepMinutes: 0)
    var setSleepDisabledCalls: [Bool] = []
    var enableOfficePowerModeCalls = 0
    var enableOfficePowerModeError: Error?

    func isSleepDisabled() throws -> Bool {
        sleepDisabled
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        setSleepDisabledCalls.append(disabled)
        sleepDisabled = disabled
    }

    func officePowerStatus() throws -> OfficePowerStatus {
        officeStatus
    }

    func enableOfficePowerMode() throws {
        enableOfficePowerModeCalls += 1
        if let enableOfficePowerModeError {
            throw enableOfficePowerModeError
        }
        officeStatus = OfficePowerStatus.evaluate(isOnACPower: true, acSleepMinutes: 0)
    }

    func hasPasswordlessPmsetAccess() -> Bool {
        passwordlessAccess
    }
}

final class MockPowerSourceReader: PowerSourceReader {
    var batteryPercentValue: Int? = 80
    var onBattery = false

    func batteryPercent() -> Int? {
        batteryPercentValue
    }

    func isOnBatteryPower() -> Bool {
        onBattery
    }
}

final class MockThermalStateReader: ThermalStateReader {
    var state: ProcessInfo.ThermalState = .nominal

    func currentThermalState() -> ProcessInfo.ThermalState {
        state
    }
}

final class CommuteModeLeaseTests: XCTestCase {
    func testLeaseRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberTests-\(UUID().uuidString)", isDirectory: true)
        let leaseURL = directory.appendingPathComponent("commute-mode.json")
        let store = CommuteModeStateStore(customLeaseURL: leaseURL)

        let lease = CommuteModeLease.makeNew(
            ownerPID: 99,
            failsafePID: 100,
            enabledAt: Date(timeIntervalSince1970: 1_000),
            deadline: Date(timeIntervalSince1970: 2_000),
            baselineSleepDisabled: false,
            appVersion: "1.0"
        )

        try store.saveLease(lease)
        let loaded = store.loadLease()

        XCTAssertEqual(loaded, lease)
        try store.clearLease()
        try FileManager.default.removeItem(at: directory)
    }
}
