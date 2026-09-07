import AppKit
import Combine
import Foundation

@MainActor
final class CommuteModeController: ObservableObject {
    static let defaultDuration: TimeInterval = 90 * 60
    static let batteryThresholdPercent = 20

    @Published private(set) var phase: CommuteModePhase = .inactive
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var officeStatus: OfficePowerStatus?
    @Published private(set) var lastStopReason: CommuteStopReason?
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasPasswordlessAccess = false
    @Published private(set) var isInstallingPermissions = false
    @Published private(set) var isRemovingPermissions = false
    @Published private(set) var isEnablingOfficeMode = false
    @Published private(set) var officeErrorMessage: String?

    private let powerClient: PowerManagementClient
    private let powerMonitor: PowerStatusMonitor
    private let stateStore: CommuteModeStateStore
    private let failsafeRunner: CommuteFailsafeRunner
    private let permissionInstaller: CommutePermissionInstaller
    private let bundle: Bundle

    private var statusTimer: Timer?
    private var failsafeWatchTimer: Timer?

    init(
        powerClient: PowerManagementClient = PmsetPowerManagementClient(
            privilegedRunner: NSAppleScriptPrivilegedRunner()
        ),
        powerMonitor: PowerStatusMonitor = PowerStatusMonitor(),
        stateStore: CommuteModeStateStore = CommuteModeStateStore(),
        failsafeRunner: CommuteFailsafeRunner = CommuteFailsafeRunner(),
        permissionInstaller: CommutePermissionInstaller = CommutePermissionInstaller(),
        bundle: Bundle = .main
    ) {
        self.powerClient = powerClient
        self.powerMonitor = powerMonitor
        self.stateStore = stateStore
        self.failsafeRunner = failsafeRunner
        self.permissionInstaller = permissionInstaller
        self.bundle = bundle

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop(reason: .userQuit)
            }
        }

        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleThermalChange()
            }
        }

        Task { @MainActor in
            reconcileOnLaunch()
            refreshOfficeStatus()
            refreshPermissionStatus()
            startStatusTimer()
        }
    }

    deinit {
        statusTimer?.invalidate()
        failsafeWatchTimer?.invalidate()
    }

    var isActive: Bool {
        phase == .active
    }

    func refreshOfficeStatus() {
        do {
            officeStatus = try powerClient.officePowerStatus()
            errorMessage = nil
        } catch {
            officeStatus = nil
        }
        refreshLiveStatus()
    }

    func refreshPermissionStatus() {
        hasPasswordlessAccess = powerClient.hasPasswordlessPmsetAccess()
    }

    func installPermissions() async {
        guard !isInstallingPermissions else { return }

        isInstallingPermissions = true
        errorMessage = nil

        let username = NSUserName()
        let installer = permissionInstaller

        do {
            try await Task.detached {
                try installer.install(username: username)
            }.value

            refreshPermissionStatus()
            if !hasPasswordlessAccess {
                errorMessage = "Installed, but sudo access was not detected. Try restarting the app."
            }
        } catch {
            errorMessage = error.localizedDescription
            refreshPermissionStatus()
        }

        isInstallingPermissions = false
    }

    func removePermissions() async {
        guard !isRemovingPermissions else { return }
        guard hasPasswordlessAccess else { return }

        if isActive {
            errorMessage = "Stop commute mode before removing sudo access."
            return
        }

        isRemovingPermissions = true
        errorMessage = nil

        let installer = permissionInstaller

        do {
            try await Task.detached {
                try installer.uninstall()
            }.value

            refreshPermissionStatus()
            if hasPasswordlessAccess {
                errorMessage = "Removed, but sudo access was still detected. Try restarting the app."
            }
        } catch {
            errorMessage = error.localizedDescription
            refreshPermissionStatus()
        }

        isRemovingPermissions = false
    }

    func enableOfficeMode() async {
        guard !isEnablingOfficeMode else { return }

        isEnablingOfficeMode = true
        officeErrorMessage = nil

        let client = powerClient

        do {
            try await Task.detached {
                try client.enableOfficePowerMode()
            }.value

            refreshOfficeStatus()
        } catch let error as CommutePermissionInstallError {
            if case .cancelled = error {
                refreshOfficeStatus()
            } else {
                officeErrorMessage = error.localizedDescription
                refreshOfficeStatus()
            }
        } catch {
            officeErrorMessage = error.localizedDescription
            refreshOfficeStatus()
        }

        isEnablingOfficeMode = false
    }

    func enable() {
        guard phase == .inactive || phase == .failed else { return }
        errorMessage = nil
        lastStopReason = nil
        phase = .enabling

        refreshPermissionStatus()
        guard hasPasswordlessAccess else {
            phase = .failed
            errorMessage = PowerManagementError.passwordlessAccessMissing.localizedDescription
            return
        }

        do {
            let baselineDisabled = try powerClient.isSleepDisabled()
            if baselineDisabled {
                phase = .externalOverride
                errorMessage = "Sleep is already disabled by another tool. Commute mode was not started."
                return
            }

            let now = Date()
            let deadline = now.addingTimeInterval(Self.defaultDuration)
            let ownerPID = ProcessInfo.processInfo.processIdentifier

            var lease = CommuteModeLease.makeNew(
                ownerPID: ownerPID,
                failsafePID: nil,
                enabledAt: now,
                deadline: deadline,
                baselineSleepDisabled: baselineDisabled,
                appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            )
            try stateStore.saveLease(lease)

            let failsafePID = try failsafeRunner.start(
                leasePath: stateStore.leaseURL().path,
                ownerPID: ownerPID,
                deadline: deadline,
                bundle: bundle
            )
            lease.failsafePID = failsafePID
            try stateStore.saveLease(lease)

            try powerClient.setSleepDisabled(true)

            phase = .active
            remainingSeconds = Int(deadline.timeIntervalSince(now))
            startFailsafeWatch()
            refreshLiveStatus()
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            failsafeRunner.stop()
            try? stateStore.clearLease()
            try? powerClient.setSleepDisabled(false)
        }
    }

    func stop(reason: CommuteStopReason = .user) {
        guard phase == .active || phase == .enabling || phase == .externalOverride else { return }
        phase = .stopping
        performStop(reason: reason)
    }

    private func performStop(reason: CommuteStopReason) {
        failsafeWatchTimer?.invalidate()
        failsafeWatchTimer = nil
        failsafeRunner.stop()

        do {
            if powerClient.hasPasswordlessPmsetAccess() {
                try powerClient.setSleepDisabled(false)
            } else if let lease = stateStore.loadLease(), lease.isActive {
                errorMessage = PowerManagementError.passwordlessAccessMissing.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if let lease = stateStore.loadLease() {
            var updatedLease = lease
            updatedLease.isActive = false
            updatedLease.lastStopReason = reason
            updatedLease.lastStopAt = Date()
            try? stateStore.saveLease(updatedLease)
        }

        try? stateStore.clearLease()

        lastStopReason = reason
        remainingSeconds = nil
        phase = .inactive
        refreshLiveStatus()
    }

    private func reconcileOnLaunch() {
        refreshPermissionStatus()

        guard let lease = stateStore.loadLease() else {
            if (try? powerClient.isSleepDisabled()) == true {
                phase = .externalOverride
                errorMessage = "Sleep is disabled externally. Commute mode did not own this setting."
            }
            return
        }

        let sleepDisabled = (try? powerClient.isSleepDisabled()) ?? false
        let ownerAlive = ProcessLiveness.isProcessRunning(pid: lease.ownerPID)
        let failsafeAlive = lease.failsafePID.map { ProcessLiveness.isProcessRunning(pid: $0) } ?? false

        if lease.isActive {
            if !ownerAlive || !sleepDisabled {
                performStop(reason: .reconciliation)
            } else if !failsafeAlive {
                performStop(reason: .helperLost)
            } else {
                phase = .active
                remainingSeconds = max(0, Int(lease.deadline.timeIntervalSinceNow))
                startFailsafeWatch()
            }
        } else if let reason = lease.lastStopReason {
            lastStopReason = reason
        }
    }

    private func startStatusTimer() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func startFailsafeWatch() {
        failsafeWatchTimer?.invalidate()
        failsafeWatchTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkFailsafeProcess()
            }
        }
    }

    private func tick() {
        refreshOfficeStatus()
        refreshPermissionStatus()

        guard phase == .active else { return }

        refreshLiveStatus()

        if let lease = stateStore.loadLease() {
            remainingSeconds = max(0, Int(lease.deadline.timeIntervalSinceNow))
            if lease.deadline <= Date() {
                performStop(reason: .timerExpired)
                return
            }
        }

        if powerMonitor.isOnBatteryPower(),
           let percent = powerMonitor.batteryPercent(),
           percent <= Self.batteryThresholdPercent {
            performStop(reason: .batteryLow)
            return
        }

        if powerMonitor.isThermallyUnsafeForCommute() {
            performStop(reason: .thermalPressure)
        }
    }

    private func checkFailsafeProcess() {
        guard phase == .active else { return }

        if !failsafeRunner.isRunning() {
            if let lease = stateStore.loadLease(),
               let failsafePID = lease.failsafePID,
               !ProcessLiveness.isProcessRunning(pid: failsafePID) {
                performStop(reason: .helperLost)
            }
        }

        if let lease = stateStore.loadLease(),
           lease.lastStopReason != nil,
           !lease.isActive {
            lastStopReason = lease.lastStopReason
            phase = .inactive
            remainingSeconds = nil
            refreshLiveStatus()
        }
    }

    private func handleThermalChange() {
        thermalState = powerMonitor.currentThermalState()
        guard phase == .active, powerMonitor.isThermallyUnsafeForCommute() else { return }
        performStop(reason: .thermalPressure)
    }

    private func refreshLiveStatus() {
        batteryPercent = powerMonitor.batteryPercent()
        thermalState = powerMonitor.currentThermalState()
    }
}
