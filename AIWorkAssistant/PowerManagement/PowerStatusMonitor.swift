import Foundation
import IOKit.ps

protocol PowerSourceReader {
    func batteryPercent() -> Int?
    func isOnBatteryPower() -> Bool
}

protocol ThermalStateReader {
    func currentThermalState() -> ProcessInfo.ThermalState
}

struct SystemPowerSourceReader: PowerSourceReader {
    private func readPowerSourceState() -> (percent: Int?, onBattery: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sourceList.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return (nil, false)
        }

        var percent: Int?
        if let current = info[kIOPSCurrentCapacityKey] as? Int,
           let max = info[kIOPSMaxCapacityKey] as? Int,
           max > 0 {
            percent = Int((Double(current) / Double(max)) * 100.0)
        }

        let onBattery = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        return (percent, onBattery)
    }

    func batteryPercent() -> Int? {
        readPowerSourceState().percent
    }

    func isOnBatteryPower() -> Bool {
        readPowerSourceState().onBattery
    }
}

struct SystemThermalStateReader: ThermalStateReader {
    func currentThermalState() -> ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
}

final class PowerStatusMonitor {
    private let powerSourceReader: PowerSourceReader
    private let thermalStateReader: ThermalStateReader

    init(
        powerSourceReader: PowerSourceReader = SystemPowerSourceReader(),
        thermalStateReader: ThermalStateReader = SystemThermalStateReader()
    ) {
        self.powerSourceReader = powerSourceReader
        self.thermalStateReader = thermalStateReader
    }

    func batteryPercent() -> Int? {
        powerSourceReader.batteryPercent()
    }

    func isOnBatteryPower() -> Bool {
        powerSourceReader.isOnBatteryPower()
    }

    func isOnACPower() -> Bool {
        !powerSourceReader.isOnBatteryPower()
    }

    func currentThermalState() -> ProcessInfo.ThermalState {
        thermalStateReader.currentThermalState()
    }

    func isThermallyUnsafeForCommute() -> Bool {
        let state = currentThermalState()
        return state == .serious || state == .critical
    }
}
