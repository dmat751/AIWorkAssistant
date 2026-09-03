import Foundation

struct OfficePowerStatus: Equatable {
    let isOnACPower: Bool
    let acSleepMinutes: Int?
    let preventSleepWhenDisplayOff: Bool
    let isOfficeReady: Bool

    static func evaluate(isOnACPower: Bool, acSleepMinutes: Int?) -> OfficePowerStatus {
        let preventSleep = acSleepMinutes == 0
        let officeReady = isOnACPower && preventSleep
        return OfficePowerStatus(
            isOnACPower: isOnACPower,
            acSleepMinutes: acSleepMinutes,
            preventSleepWhenDisplayOff: preventSleep,
            isOfficeReady: officeReady
        )
    }
}
