import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var spaceObserver: SpaceObserver
    @ObservedObject var usageObserver: CursorUsageObserver
    @ObservedObject var commuteController: CommuteModeController
    @ObservedObject var notifySettings: CursorNotifySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if spaceObserver.totalSpaces > 1 {
                Text("Desktop \(spaceObserver.currentSpaceIndex) of \(spaceObserver.totalSpaces)")
            } else {
                Text("Desktop \(spaceObserver.currentSpaceIndex)")
            }

            Divider()

            if let costCents = usageObserver.todayCostCents {
                Text("Today's Cursor cost: \(UsageFormatting.formatDollars(cents: costCents))")
            } else if usageObserver.isLoading {
                Text("Today's Cursor cost: Loading...")
            } else {
                Text("Today's Cursor cost: --")
            }

            if let tokens = usageObserver.todayTokens {
                Text("Tokens today: \(UsageFormatting.formatTokens(tokens))")
            }

            if let lastUpdated = usageObserver.lastUpdated {
                Text("Updated \(UsageFormatting.formatRelativeTime(lastUpdated))")
            }

            if let errorMessage = usageObserver.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(usageObserver.isLoading ? "Refreshing..." : "Refresh Cursor Usage") {
                usageObserver.refresh()
            }
            .disabled(usageObserver.isLoading)

            Divider()

            Text("Cursor Agent Push")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Push when agent finishes",
                isOn: Binding(
                    get: { notifySettings.isEnabled },
                    set: { enabled in
                        Task {
                            await notifySettings.setEnabled(enabled)
                        }
                    }
                )
            )
            .disabled(notifySettings.isUpdating)

            Toggle(
                "Push when approve needed",
                isOn: Binding(
                    get: { notifySettings.isApproveEnabled },
                    set: { enabled in
                        Task {
                            await notifySettings.setApproveEnabled(enabled)
                        }
                    }
                )
            )
            .disabled(notifySettings.isUpdating)

            Text("ntfy topic")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField(
                "your-topic-name",
                text: Binding(
                    get: { notifySettings.topic ?? "" },
                    set: { notifySettings.setTopic($0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            Button(notifySettings.isSendingTestPush ? "Sending..." : "Send Test Push") {
                Task {
                    await notifySettings.sendTestPush()
                }
            }
            .disabled(notifySettings.isSendingTestPush)

            if let testPushStatus = notifySettings.testPushStatus {
                Text(testPushStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if notifySettings.needsMigration {
                Text("Push hooks were updated automatically. Restart Cursor once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let migrationStatus = notifySettings.migrationStatus {
                Text(migrationStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let approvalError = notifySettings.approvalMonitor.lastError {
                Text(approvalError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Finish pushes use Cursor stop hooks. Approve pushes use AI Work Assistant log monitoring.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let installError = notifySettings.installError {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Office / Power")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let officeStatus = commuteController.officeStatus {
                StatusIndicator(
                    title: "Office mode",
                    status: officeStatus.isOfficeReady ? "Ready" : "Needs attention",
                    color: officeStatus.isOfficeReady ? .green : .orange
                )
                Text("On AC power: \(officeStatus.isOnACPower ? "Yes" : "No")")
                Text(
                    "Prevent sleep when display off: \(officeStatus.preventSleepWhenDisplayOff ? "ON" : "OFF")"
                )
                Text("Office lock-screen safe: \(officeStatus.isOfficeReady ? "Yes" : "No")")

                if !officeStatus.preventSleepWhenDisplayOff {
                    if !officeStatus.isOnACPower {
                        Text("Plug in the power adapter.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button(
                        commuteController.isEnablingOfficeMode ? "Enabling..." : "Enable Office Mode"
                    ) {
                        Task { @MainActor in
                            await commuteController.enableOfficeMode()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(commuteController.isEnablingOfficeMode)

                    Text("Sets pmset -c sleep 0. Asks for your admin password.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                StatusIndicator(title: "Office mode", status: "Unavailable", color: .secondary)
            }

            if let officeErrorMessage = commuteController.officeErrorMessage {
                Text(officeErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Refresh Power Status") {
                commuteController.refreshOfficeStatus()
            }

            Divider()

            Text("Commute Mode (closed lid)")
                .font(.caption)
                .foregroundStyle(.secondary)

            commuteStatusIndicator

            Text("Keeps the Mac awake with lid closed. Risk: heat and battery drain.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if commuteController.isActive {
                Button("Stop Commute Mode") {
                    commuteController.stop(reason: .user)
                }
                if let remaining = commuteController.remainingSeconds {
                    Text("Time left: \(UsageFormatting.formatDuration(seconds: remaining))")
                }
            } else {
                HStack {
                    Button("Start Commute Mode (90 min)") {
                        commuteController.enable()
                    }
                    .disabled(!commuteController.hasPasswordlessAccess || commuteController.phase == .enabling)

                    if !commuteController.hasPasswordlessAccess {
                        Button(commuteController.isInstallingPermissions ? "Installing..." : "Grant Access") {
                            Task {
                                await commuteController.installPermissions()
                            }
                        }
                        .disabled(commuteController.isInstallingPermissions)
                    }
                }

                if !commuteController.hasPasswordlessAccess {
                    Text("Requires administrator password once.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let batteryPercent = commuteController.batteryPercent {
                Text("Battery: \(batteryPercent)%")
            }

            Text("Thermal: \(UsageFormatting.formatThermalState(commuteController.thermalState))")

            if let lastStopReason = commuteController.lastStopReason {
                Text(UsageFormatting.formatCommuteStopReason(lastStopReason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = commuteController.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            DisclosureGroup("Setup") {
                Text("Office power settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let officeStatus = commuteController.officeStatus {
                    if officeStatus.isOfficeReady {
                        StatusIndicator(title: "Office power settings", status: "Ready", color: .green)
                    } else if !officeStatus.isOnACPower {
                        StatusIndicator(title: "Office power settings", status: "Plug in power", color: .orange)
                        Text("Plug in the power adapter, then enable office settings.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        StatusIndicator(title: "Office power settings", status: "Needs setup", color: .orange)
                        Button(
                            commuteController.isEnablingOfficeMode ? "Enabling..." : "Enable Office Mode"
                        ) {
                            Task { @MainActor in
                                await commuteController.enableOfficeMode()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(commuteController.isEnablingOfficeMode)

                        Text("Sets pmset -c sleep 0. Asks for your admin password.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    StatusIndicator(title: "Office power settings", status: "Unavailable", color: .secondary)
                }

                if let officeErrorMessage = commuteController.officeErrorMessage {
                    Text(officeErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Commute sudo access")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if commuteController.hasPasswordlessAccess {
                    StatusIndicator(title: "Commute sudo access", status: "Installed", color: .green)
                    Button(
                        commuteController.isRemovingPermissions ? "Removing..." : "Remove Access"
                    ) {
                        Task { @MainActor in
                            await commuteController.removePermissions()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(commuteController.isRemovingPermissions || commuteController.isActive)
                } else {
                    StatusIndicator(title: "Commute sudo access", status: "Not installed", color: .orange)
                    Button(
                        commuteController.isInstallingPermissions ? "Installing..." : "Grant Access"
                    ) {
                        Task { @MainActor in
                            await commuteController.installPermissions()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(commuteController.isInstallingPermissions)
                }

                Text("Requires administrator password once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Cursor push hooks")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if notifySettings.isInstalled {
                    StatusIndicator(title: "Cursor push hooks", status: "Installed", color: .green)
                    Button(notifySettings.isUpdating ? "Uninstalling..." : "Uninstall Hooks") {
                        Task { @MainActor in
                            await notifySettings.uninstallHooks()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(notifySettings.isUpdating)
                } else {
                    StatusIndicator(title: "Cursor push hooks", status: "Not installed", color: .orange)
                    Button(notifySettings.isUpdating ? "Installing..." : "Install Hooks") {
                        Task { @MainActor in
                            await notifySettings.installHooks()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(notifySettings.isUpdating)
                }

                if let setupStatus = notifySettings.setupStatus {
                    Text(setupStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let installError = notifySettings.installError {
                    Text(installError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Quit") {
                commuteController.stop(reason: .userQuit)
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder
    private var commuteStatusIndicator: some View {
        if commuteController.isActive {
            StatusIndicator(title: "Commute mode", status: "Active", color: .green)
        } else if commuteController.hasPasswordlessAccess {
            StatusIndicator(title: "Commute mode", status: "Ready", color: .green)
        } else {
            StatusIndicator(title: "Commute mode", status: "Setup required", color: .orange)
        }
    }
}

private struct StatusIndicator: View {
    let title: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text("\(title): \(status)")
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}
