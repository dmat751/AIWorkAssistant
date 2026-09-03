import XCTest
@testable import AIWorkAssistant

final class CursorNotifyInstallerTests: XCTestCase {
    private func mergeHooks(existingData: Data?) throws -> [String: Any] {
        let data = try CursorNotifyInstaller.mergedHooksJSON(
            existingData: existingData,
            stopHookCommand: CursorNotifyInstaller.stopHookCommand
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func repoHooksDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cursor-hooks", isDirectory: true)
    }

    private func copyBundledHooks(to hooksRoot: URL) throws {
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        for script in ["notify-ntfy.sh", "on-stop.sh", "notify.env.example"] {
            try FileManager.default.copyItem(
                at: repoHooksDirectory().appendingPathComponent(script),
                to: hooksRoot.appendingPathComponent(script)
            )
        }
    }

    func testMergeCreatesStopHookWhenMissing() throws {
        let json = try mergeHooks(existingData: nil)
        let hooks = json["hooks"] as? [String: Any]
        let stopHooks = hooks?["stop"] as? [[String: Any]]

        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(stopHooks?.count, 1)
        XCTAssertEqual(stopHooks?.first?["command"] as? String, "./hooks/on-stop.sh")
        XCTAssertEqual(stopHooks?.first?["matcher"] as? String, "Stop")
        XCTAssertNil(hooks?["beforeShellExecution"])
        XCTAssertNil(hooks?["beforeMCPExecution"])
    }

    func testInstallCopiesHookScriptsAndSkipsPermissionHooks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWorkAssistantInstallerTests-\(UUID().uuidString)", isDirectory: true)
        let hooksRoot = root.appendingPathComponent("CursorHooks", isDirectory: true)
        let cursorRoot = root.appendingPathComponent(".cursor", isDirectory: true)
        try copyBundledHooks(to: hooksRoot)

        let installer = CursorNotifyInstaller(
            fileManager: .default,
            resourceDirectory: hooksRoot,
            cursorDirectory: cursorRoot
        )

        try installer.install(sendTestNotification: false)

        for script in ["notify-ntfy.sh", "on-stop.sh"] {
            let installedHook = cursorRoot.appendingPathComponent("hooks/\(script)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: installedHook.path))

            let attributes = try FileManager.default.attributesOfItem(atPath: installedHook.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
            XCTAssertEqual(permissions, 0o755)
        }

        for stale in CursorNotifyInstaller.staleHookScripts {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: cursorRoot.appendingPathComponent("hooks/\(stale)").path
                )
            )
        }

        let hooksJSONData = try Data(contentsOf: cursorRoot.appendingPathComponent("hooks.json"))
        let json = try JSONSerialization.jsonObject(with: hooksJSONData) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        XCTAssertEqual(
            (hooks?["stop"] as? [[String: Any]])?.first?["command"] as? String,
            "./hooks/on-stop.sh"
        )
        XCTAssertNil(hooks?["beforeShellExecution"])
        XCTAssertNil(hooks?["beforeMCPExecution"])
    }

    func testMergeDoesNotDuplicateStopHook() throws {
        let existing = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/on-stop.sh", "matcher": "Stop" }
            ]
          }
        }
        """.data(using: .utf8)

        let json = try mergeHooks(existingData: existing)
        let hooks = json["hooks"] as? [String: Any]

        XCTAssertEqual((hooks?["stop"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(hooks?["beforeShellExecution"])
        XCTAssertNil(hooks?["beforeMCPExecution"])
    }

    func testMergeRemovesStalePermissionHooksAndKeepsOtherEntries() throws {
        let existing = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/on-stop.sh", "matcher": "Stop" }
            ],
            "beforeShellExecution": [
              { "command": "./hooks/on-before-shell.sh" },
              { "command": "./hooks/my-policy.sh" }
            ],
            "beforeMCPExecution": [
              { "command": "./hooks/on-before-mcp.sh" }
            ]
          }
        }
        """.data(using: .utf8)

        let json = try mergeHooks(existingData: existing)
        let hooks = json["hooks"] as? [String: Any]
        let shellHooks = try XCTUnwrap(hooks?["beforeShellExecution"] as? [[String: Any]])

        XCTAssertEqual(shellHooks.count, 1)
        XCTAssertEqual(shellHooks.first?["command"] as? String, "./hooks/my-policy.sh")
        XCTAssertNil(hooks?["beforeMCPExecution"])
    }

    func testHooksJSONStatusTreatsStopOnlyInstallAsComplete() throws {
        let stopOnly = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/on-stop.sh", "matcher": "Stop" }
            ]
          }
        }
        """.data(using: .utf8)

        XCTAssertEqual(CursorNotifyInstaller.hooksJSONStatus(data: stopOnly), [])
        XCTAssertEqual(CursorNotifyInstaller.staleHookEntries(in: stopOnly), [])
    }

    func testStaleHookEntriesDetectsLegacyAllowHooks() throws {
        let legacy = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/on-stop.sh", "matcher": "Stop" }
            ],
            "beforeShellExecution": [
              { "command": "./hooks/on-before-shell.sh" }
            ],
            "beforeMCPExecution": [
              { "command": "./hooks/on-before-mcp.sh" }
            ]
          }
        }
        """.data(using: .utf8)

        XCTAssertEqual(
            CursorNotifyInstaller.staleHookEntries(in: legacy),
            ["beforeShellExecution", "beforeMCPExecution"]
        )
    }

    func testMigrateIfNeededRemovesStaleApprovalHooks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWorkAssistantInstallerTests-\(UUID().uuidString)", isDirectory: true)
        let hooksRoot = root.appendingPathComponent("CursorHooks", isDirectory: true)
        let cursorRoot = root.appendingPathComponent(".cursor", isDirectory: true)
        try copyBundledHooks(to: hooksRoot)
        try FileManager.default.createDirectory(
            at: cursorRoot.appendingPathComponent("hooks"),
            withIntermediateDirectories: true
        )

        let hooksJSON = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/on-stop.sh", "matcher": "Stop" }
            ],
            "beforeShellExecution": [
              { "command": "./hooks/on-before-shell.sh" }
            ],
            "beforeMCPExecution": [
              { "command": "./hooks/on-before-mcp.sh" }
            ]
          }
        }
        """
        try hooksJSON.write(
            to: cursorRoot.appendingPathComponent("hooks.json"),
            atomically: true,
            encoding: .utf8
        )
        try "NTFY_TOPIC=Cursor-test\nNTFY_ENABLED=1\nNTFY_APPROVE_ENABLED=1\n".write(
            to: cursorRoot.appendingPathComponent("hooks/notify.env"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/bash\n".write(
            to: cursorRoot.appendingPathComponent("hooks/on-stop.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/bash\necho '{\"permission\": \"allow\"}'\n".write(
            to: cursorRoot.appendingPathComponent("hooks/on-before-shell.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/bash\necho '{\"permission\": \"allow\"}'\n".write(
            to: cursorRoot.appendingPathComponent("hooks/on-before-mcp.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/bash\n".write(
            to: cursorRoot.appendingPathComponent("hooks/approval-notify.sh"),
            atomically: true,
            encoding: .utf8
        )

        let installer = CursorNotifyInstaller(
            fileManager: .default,
            resourceDirectory: hooksRoot,
            cursorDirectory: cursorRoot
        )

        let before = installer.installationStatus()
        XCTAssertTrue(before.needsMigration)
        XCTAssertEqual(before.staleHookEntries, ["beforeShellExecution", "beforeMCPExecution"])
        XCTAssertEqual(
            Set(before.staleHookScripts),
            Set(CursorNotifyInstaller.staleHookScripts)
        )

        try installer.migrateIfNeeded()

        let after = installer.installationStatus()
        XCTAssertFalse(after.needsMigration)
        XCTAssertEqual(after.staleHookEntries, [])
        XCTAssertEqual(after.staleHookScripts, [])

        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: cursorRoot.appendingPathComponent("hooks.json"))
        ) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        XCTAssertNil(hooks?["beforeShellExecution"])
        XCTAssertNil(hooks?["beforeMCPExecution"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cursorRoot.appendingPathComponent("hooks/on-before-shell.sh").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cursorRoot.appendingPathComponent("hooks/on-before-mcp.sh").path
            )
        )
    }
}
