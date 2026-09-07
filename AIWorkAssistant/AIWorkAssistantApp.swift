import SwiftUI

@main
struct AIWorkAssistantApp: App {
    @StateObject private var spaceObserver = SpaceObserver()
    @StateObject private var usageObserver = CursorUsageObserver()
    @StateObject private var commuteController = CommuteModeController()
    @StateObject private var notifySettings = CursorNotifySettings()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                spaceObserver: spaceObserver,
                usageObserver: usageObserver,
                commuteController: commuteController,
                notifySettings: notifySettings
            )
        } label: {
            Text(menuBarLabel)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: String {
        let desktopLabel: String
        if spaceObserver.totalSpaces > 1 {
            desktopLabel = "\(spaceObserver.currentSpaceIndex)/\(spaceObserver.totalSpaces)"
        } else {
            desktopLabel = "\(spaceObserver.currentSpaceIndex)"
        }

        var label = desktopLabel

        if let costCents = usageObserver.todayCostCents {
            label += " · \(UsageFormatting.formatDollars(cents: costCents))"
        }

        if commuteController.isActive {
            label += " ☕"
        }

        return label
    }
}
