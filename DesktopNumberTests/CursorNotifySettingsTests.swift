import XCTest
@testable import DesktopNumber

final class CursorNotifyEnvFileTests: XCTestCase {
    func testMissingEnabledKeyDefaultsToDisabled() {
        let env = CursorNotifyEnvFile(contents: "NTFY_TOPIC=Cursor-test\n")
        XCTAssertFalse(env.isEnabled)
        XCTAssertFalse(env.isApproveEnabled)
        XCTAssertEqual(env.topic, "Cursor-test")
    }

    func testParsesApproveEnabledValues() {
        XCTAssertTrue(CursorNotifyEnvFile(contents: "NTFY_APPROVE_ENABLED=1\n").isApproveEnabled)
        XCTAssertFalse(CursorNotifyEnvFile(contents: "NTFY_APPROVE_ENABLED=0\n").isApproveEnabled)
        XCTAssertFalse(CursorNotifyEnvFile(contents: "NTFY_APPROVE_ENABLED=false\n").isApproveEnabled)
    }

    func testSetApproveEnabledUpdatesExistingLine() {
        let original = """
        NTFY_TOPIC=Cursor-test
        NTFY_APPROVE_ENABLED=1

        """
        let updated = CursorNotifyEnvFile(contents: original).settingApproveEnabled(false)
        XCTAssertTrue(updated.contains("NTFY_APPROVE_ENABLED=0"))
        XCTAssertFalse(updated.contains("NTFY_APPROVE_ENABLED=1"))
    }

    func testParsesEnabledValues() {
        XCTAssertTrue(CursorNotifyEnvFile(contents: "NTFY_ENABLED=1\n").isEnabled)
        XCTAssertFalse(CursorNotifyEnvFile(contents: "NTFY_ENABLED=0\n").isEnabled)
        XCTAssertFalse(CursorNotifyEnvFile(contents: "NTFY_ENABLED=false\n").isEnabled)
        XCTAssertFalse(CursorNotifyEnvFile(contents: "NTFY_ENABLED=off\n").isEnabled)
    }

    func testSetEnabledUpdatesExistingLine() {
        let original = """
        NTFY_TOPIC=Cursor-test
        NTFY_ENABLED=1

        """
        let updated = CursorNotifyEnvFile(contents: original).settingEnabled(false)
        XCTAssertTrue(updated.contains("NTFY_ENABLED=0"))
        XCTAssertTrue(updated.contains("NTFY_TOPIC=Cursor-test"))
        XCTAssertFalse(updated.contains("NTFY_ENABLED=1"))
    }

    func testSetEnabledAppendsWhenMissing() {
        let original = "NTFY_TOPIC=Cursor-test\n"
        let updated = CursorNotifyEnvFile(contents: original).settingEnabled(false)
        XCTAssertTrue(updated.contains("NTFY_ENABLED=0"))
        XCTAssertTrue(updated.contains("NTFY_TOPIC=Cursor-test"))
    }

    func testSetEnabledCanReenable() {
        let original = "NTFY_TOPIC=Cursor-test\nNTFY_ENABLED=0\n"
        let updated = CursorNotifyEnvFile(contents: original).settingEnabled(true)
        XCTAssertTrue(updated.contains("NTFY_ENABLED=1"))
        XCTAssertFalse(updated.contains("NTFY_ENABLED=0"))
    }

    func testSetTopicUpdatesExistingLine() {
        let original = """
        NTFY_TOPIC=old-topic
        NTFY_ENABLED=1

        """
        let updated = CursorNotifyEnvFile(contents: original).settingTopic("new-topic")
        XCTAssertTrue(updated.contains("NTFY_TOPIC=new-topic"))
        XCTAssertFalse(updated.contains("NTFY_TOPIC=old-topic"))
        XCTAssertTrue(updated.contains("NTFY_ENABLED=1"))
    }

    func testSetTopicAppendsWhenMissing() {
        let original = "NTFY_ENABLED=1\n"
        let updated = CursorNotifyEnvFile(contents: original).settingTopic("my-topic")
        XCTAssertTrue(updated.contains("NTFY_TOPIC=my-topic"))
    }
}

@MainActor
final class CursorNotifySettingsTests: XCTestCase {
    private func makeSettings(directory: URL) -> CursorNotifySettings {
        let monitor = CursorApprovalMonitor(
            tailer: CursorApprovalLogTailer(logsRoot: directory),
            ntfyClient: MockSettingsNtfySender(),
            pollInterval: 60
        )
        return CursorNotifySettings(
            fileManager: .default,
            hooksDirectory: directory,
            envFileURL: directory.appendingPathComponent("notify.env"),
            cursorDirectory: directory,
            approvalMonitor: monitor,
            autoMigrate: false,
            startMonitor: false
        )
    }

    func testRefreshReadsInstalledStateAndEnvFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hookURL = directory.appendingPathComponent("on-stop.sh")
        let envURL = directory.appendingPathComponent("notify.env")
        try "# hook".write(to: hookURL, atomically: true, encoding: .utf8)
        try """
        NTFY_TOPIC=Cursor-test
        NTFY_ENABLED=0
        NTFY_APPROVE_ENABLED=0

        """.write(to: envURL, atomically: true, encoding: .utf8)

        let settings = makeSettings(directory: directory)

        XCTAssertTrue(settings.isInstalled)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.isApproveEnabled)
        XCTAssertEqual(settings.topic, "Cursor-test")
    }

    func testRefreshDetectsPartialInstallAsNeedingMigration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        let cursorRoot = root.appendingPathComponent(".cursor", isDirectory: true)
        let hooksDirectory = cursorRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)

        try "# hook".write(
            to: hooksDirectory.appendingPathComponent("on-stop.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "NTFY_TOPIC=Cursor-test\nNTFY_ENABLED=1\n".write(
            to: hooksDirectory.appendingPathComponent("notify.env"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/on-stop.sh", "matcher": "Stop" }
            ]
          }
        }
        """.write(
            to: cursorRoot.appendingPathComponent("hooks.json"),
            atomically: true,
            encoding: .utf8
        )

        let installer = CursorNotifyInstaller(
            fileManager: .default,
            cursorDirectory: cursorRoot
        )
        let status = installer.installationStatus()

        XCTAssertTrue(status.needsMigration)
        XCTAssertEqual(status.missingHookEntries, [])
        XCTAssertTrue(status.envNeedsMigration)
    }

    func testSetApproveEnabledWritesToEnvFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hookURL = directory.appendingPathComponent("on-stop.sh")
        let envURL = directory.appendingPathComponent("notify.env")
        try "# hook".write(to: hookURL, atomically: true, encoding: .utf8)
        try "NTFY_TOPIC=Cursor-test\nNTFY_ENABLED=0\nNTFY_APPROVE_ENABLED=1\n".write(to: envURL, atomically: true, encoding: .utf8)

        let settings = makeSettings(directory: directory)

        await settings.setApproveEnabled(false)

        let env = CursorNotifyEnvFile(contents: try String(contentsOf: envURL, encoding: .utf8))
        XCTAssertFalse(env.isApproveEnabled)
        XCTAssertFalse(settings.isApproveEnabled)
    }

    func testSetEnabledWritesToEnvFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hookURL = directory.appendingPathComponent("on-stop.sh")
        let envURL = directory.appendingPathComponent("notify.env")
        try "# hook".write(to: hookURL, atomically: true, encoding: .utf8)
        try "NTFY_TOPIC=Cursor-test\nNTFY_ENABLED=1\nNTFY_APPROVE_ENABLED=0\n".write(to: envURL, atomically: true, encoding: .utf8)

        let settings = makeSettings(directory: directory)

        await settings.setEnabled(false)

        let env = CursorNotifyEnvFile(contents: try String(contentsOf: envURL, encoding: .utf8))
        XCTAssertFalse(env.isEnabled)
        XCTAssertEqual(env.topic, "Cursor-test")
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookURL.path))
    }

    func testSetEnabledInstallsStopHookWhenEnabled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        let hooksRoot = root.appendingPathComponent("CursorHooks", isDirectory: true)
        let cursorRoot = root.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorRoot, withIntermediateDirectories: true)

        let repoHooks = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cursor-hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        for script in ["notify-ntfy.sh", "on-stop.sh", "notify.env.example"] {
            try FileManager.default.copyItem(
                at: repoHooks.appendingPathComponent(script),
                to: hooksRoot.appendingPathComponent(script)
            )
        }

        let hooksDirectory = cursorRoot.appendingPathComponent("hooks", isDirectory: true)
        let monitor = CursorApprovalMonitor(
            tailer: CursorApprovalLogTailer(logsRoot: root),
            ntfyClient: MockSettingsNtfySender(),
            pollInterval: 60
        )
        let settings = CursorNotifySettings(
            fileManager: .default,
            resourceDirectory: hooksRoot,
            hooksDirectory: hooksDirectory,
            envFileURL: hooksDirectory.appendingPathComponent("notify.env"),
            cursorDirectory: cursorRoot,
            approvalMonitor: monitor,
            autoMigrate: false,
            startMonitor: false
        )

        await settings.setEnabled(true)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: hooksDirectory.appendingPathComponent("on-stop.sh").path
            )
        )
        let hooksJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: cursorRoot.appendingPathComponent("hooks.json"))
        ) as? [String: Any]
        let stopHooks = (hooksJSON?["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(stopHooks?.first?["command"] as? String, "./hooks/on-stop.sh")
    }

    func testSetTopicWritesToEnvFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hookURL = directory.appendingPathComponent("on-stop.sh")
        let envURL = directory.appendingPathComponent("notify.env")
        try "# hook".write(to: hookURL, atomically: true, encoding: .utf8)
        try "NTFY_TOPIC=old-topic\nNTFY_ENABLED=1\n".write(to: envURL, atomically: true, encoding: .utf8)

        let settings = makeSettings(directory: directory)

        settings.setTopic("Cursor-1234")

        let env = CursorNotifyEnvFile(contents: try String(contentsOf: envURL, encoding: .utf8))
        XCTAssertEqual(env.topic, "Cursor-1234")
        XCTAssertEqual(settings.topic, "Cursor-1234")
    }

    func testSendTestPushRequiresTopic() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hookURL = directory.appendingPathComponent("on-stop.sh")
        let envURL = directory.appendingPathComponent("notify.env")
        try? "# hook".write(to: hookURL, atomically: true, encoding: .utf8)
        try? "NTFY_TOPIC=your-topic-name\nNTFY_ENABLED=1\n".write(to: envURL, atomically: true, encoding: .utf8)

        let settings = makeSettings(directory: directory)

        await settings.sendTestPush()

        XCTAssertEqual(settings.testPushStatus, "Set an ntfy topic first.")
    }

    func testInstallHooksCreatesScriptsAndHooksJSON() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        let hooksRoot = root.appendingPathComponent("CursorHooks", isDirectory: true)
        let cursorRoot = root.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorRoot, withIntermediateDirectories: true)

        let repoHooks = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cursor-hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        for script in ["notify-ntfy.sh", "on-stop.sh", "notify.env.example"] {
            try FileManager.default.copyItem(
                at: repoHooks.appendingPathComponent(script),
                to: hooksRoot.appendingPathComponent(script)
            )
        }

        let hooksDirectory = cursorRoot.appendingPathComponent("hooks", isDirectory: true)
        let monitor = CursorApprovalMonitor(
            tailer: CursorApprovalLogTailer(logsRoot: root),
            ntfyClient: MockSettingsNtfySender(),
            pollInterval: 60
        )
        let settings = CursorNotifySettings(
            fileManager: .default,
            resourceDirectory: hooksRoot,
            hooksDirectory: hooksDirectory,
            envFileURL: hooksDirectory.appendingPathComponent("notify.env"),
            cursorDirectory: cursorRoot,
            approvalMonitor: monitor,
            autoMigrate: false,
            startMonitor: false
        )

        await settings.installHooks()

        XCTAssertTrue(settings.isInstalled)
        XCTAssertEqual(settings.setupStatus, "Cursor push hooks installed.")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: hooksDirectory.appendingPathComponent("on-stop.sh").path
            )
        )
        let hooksJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: cursorRoot.appendingPathComponent("hooks.json"))
        ) as? [String: Any]
        let stopHooks = (hooksJSON?["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(stopHooks?.first?["command"] as? String, "./hooks/on-stop.sh")
    }

    func testUninstallHooksRemovesScriptsAndDisablesFlags() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopNumberNotifyTests-\(UUID().uuidString)", isDirectory: true)
        let hooksRoot = root.appendingPathComponent("CursorHooks", isDirectory: true)
        let cursorRoot = root.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorRoot, withIntermediateDirectories: true)

        let repoHooks = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cursor-hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        for script in ["notify-ntfy.sh", "on-stop.sh", "notify.env.example"] {
            try FileManager.default.copyItem(
                at: repoHooks.appendingPathComponent(script),
                to: hooksRoot.appendingPathComponent(script)
            )
        }

        let hooksDirectory = cursorRoot.appendingPathComponent("hooks", isDirectory: true)
        let monitor = CursorApprovalMonitor(
            tailer: CursorApprovalLogTailer(logsRoot: root),
            ntfyClient: MockSettingsNtfySender(),
            pollInterval: 60
        )
        let settings = CursorNotifySettings(
            fileManager: .default,
            resourceDirectory: hooksRoot,
            hooksDirectory: hooksDirectory,
            envFileURL: hooksDirectory.appendingPathComponent("notify.env"),
            cursorDirectory: cursorRoot,
            approvalMonitor: monitor,
            autoMigrate: false,
            startMonitor: false
        )

        await settings.installHooks()
        await settings.uninstallHooks()

        XCTAssertFalse(settings.isInstalled)
        XCTAssertEqual(settings.setupStatus, "Cursor push hooks uninstalled.")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: hooksDirectory.appendingPathComponent("on-stop.sh").path
            )
        )
        let env = CursorNotifyEnvFile(
            contents: try String(
                contentsOf: hooksDirectory.appendingPathComponent("notify.env"),
                encoding: .utf8
            )
        )
        XCTAssertFalse(env.isEnabled)
        XCTAssertFalse(env.isApproveEnabled)
    }
}

private final class MockSettingsNtfySender: CursorNtfySending {
    func sendApprovalPush(title: String, body: String) async throws {}
}
