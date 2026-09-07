import Foundation

enum CursorNotifyInstallError: LocalizedError {
    case missingBundleResource(String)
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource(let name):
            return "Missing bundled hook resource: \(name)."
        case .fileOperationFailed(let message):
            return message
        }
    }
}

struct CursorNotifyInstallationStatus: Equatable {
    let missingScripts: [String]
    let missingHookEntries: [String]
    let staleHookScripts: [String]
    let staleHookEntries: [String]
    let envNeedsMigration: Bool

    var isFullyInstalled: Bool {
        missingScripts.isEmpty && missingHookEntries.isEmpty
    }

    var needsMigration: Bool {
        !missingScripts.isEmpty
            || !missingHookEntries.isEmpty
            || !staleHookScripts.isEmpty
            || !staleHookEntries.isEmpty
            || envNeedsMigration
    }
}

struct CursorNotifyInstaller {
    static let stopHookCommand = "./hooks/on-stop.sh"
    static let bundledResourceDirectory = "CursorHooks"
    static let requiredHookScripts = [
        "notify-ntfy.sh",
        "on-stop.sh",
    ]
    static let staleHookScripts = [
        "approval-notify.sh",
        "on-before-shell.sh",
        "on-before-mcp.sh",
    ]
    static let staleHookCommands = [
        "./hooks/on-before-shell.sh",
        "./hooks/on-before-mcp.sh",
    ]
    static let permissionHookEvents = [
        "beforeShellExecution",
        "beforeMCPExecution",
    ]

    private let fileManager: FileManager
    private let bundle: Bundle
    private let resourceDirectory: URL?
    private let cursorDirectory: URL
    private let hooksDirectory: URL
    private let hooksJSONURL: URL
    private let envFileURL: URL

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        resourceDirectory: URL? = nil,
        cursorDirectory: URL? = nil,
        hooksDirectory: URL? = nil,
        envFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.resourceDirectory = resourceDirectory
        let home = fileManager.homeDirectoryForCurrentUser
        let defaultCursorDirectory = home.appendingPathComponent(".cursor", isDirectory: true)
        if let hooksDirectory {
            self.hooksDirectory = hooksDirectory
            self.cursorDirectory = cursorDirectory ?? hooksDirectory.deletingLastPathComponent()
        } else {
            self.cursorDirectory = cursorDirectory ?? defaultCursorDirectory
            self.hooksDirectory = self.cursorDirectory.appendingPathComponent("hooks", isDirectory: true)
        }
        hooksJSONURL = self.cursorDirectory.appendingPathComponent("hooks.json")
        self.envFileURL = envFileURL ?? self.hooksDirectory.appendingPathComponent("notify.env")
    }

    func install(sendTestNotification: Bool = true) throws {
        try installStopHook(sendTestNotification: sendTestNotification)
    }

    func installStopHook(sendTestNotification: Bool = false) throws {
        try fileManager.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)

        try installBundledScript(named: "notify-ntfy", destinationName: "notify-ntfy.sh")
        try installBundledScript(named: "on-stop", destinationName: "on-stop.sh")
        try removeStaleHookScripts()
        try ensureNotifyEnv()

        try mergeHooksIntoHooksJSON(includeStopHook: true)
        if sendTestNotification {
            try sendTestNotificationIfPossible()
        }
    }

    func ensureNotifyEnv() throws {
        guard !fileManager.fileExists(atPath: envFileURL.path) else {
            try migrateEnvFileIfNeeded()
            return
        }

        let exampleURL = try bundledResourceURL(name: "notify.env.example")
        try copyReplacingItem(at: exampleURL, to: envFileURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envFileURL.path)
    }

    func uninstallStopHook() throws {
        let stopScript = hooksDirectory.appendingPathComponent("on-stop.sh")
        if fileManager.fileExists(atPath: stopScript.path) {
            try fileManager.removeItem(at: stopScript)
        }

        guard fileManager.fileExists(atPath: hooksJSONURL.path) else { return }

        let merged = try Self.mergedHooksJSON(
            existingData: try Data(contentsOf: hooksJSONURL),
            stopHookCommand: Self.stopHookCommand,
            includeStopHook: false
        )
        try merged.write(to: hooksJSONURL, options: .atomic)
    }

    func uninstall() throws {
        for script in Self.requiredHookScripts + Self.staleHookScripts {
            let url = hooksDirectory.appendingPathComponent(script)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        if fileManager.fileExists(atPath: hooksJSONURL.path) {
            let merged = try Self.mergedHooksJSON(
                existingData: try Data(contentsOf: hooksJSONURL),
                stopHookCommand: Self.stopHookCommand,
                includeStopHook: false
            )
            try merged.write(to: hooksJSONURL, options: .atomic)
        }
    }

    func installationStatus() -> CursorNotifyInstallationStatus {
        let missingScripts = Self.requiredHookScripts.filter { script in
            !fileManager.fileExists(atPath: hooksDirectory.appendingPathComponent(script).path)
        }
        let staleScripts = Self.staleHookScripts.filter { script in
            fileManager.fileExists(atPath: hooksDirectory.appendingPathComponent(script).path)
        }
        let hooksData = try? Data(contentsOf: hooksJSONURL)

        return CursorNotifyInstallationStatus(
            missingScripts: missingScripts,
            missingHookEntries: Self.hooksJSONStatus(data: hooksData),
            staleHookScripts: staleScripts,
            staleHookEntries: Self.staleHookEntries(in: hooksData),
            envNeedsMigration: envFileNeedsMigration()
        )
    }

    func migrateIfNeeded(sendTestNotification: Bool = false) throws {
        let status = installationStatus()
        guard status.needsMigration else { return }

        try fileManager.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)

        for script in status.missingScripts {
            let resourceName = (script as NSString).deletingPathExtension
            try installBundledScript(named: resourceName, destinationName: script)
        }

        try removeStaleHookScripts()

        if !status.missingHookEntries.isEmpty || !status.staleHookEntries.isEmpty {
            try mergeHooksIntoHooksJSON()
        }

        if status.envNeedsMigration {
            try migrateEnvFileIfNeeded()
        }

        if sendTestNotification {
            try sendTestNotificationIfPossible()
        }
    }

    private func migrateEnvFileIfNeeded() throws {
        guard let contents = try? String(contentsOf: envFileURL, encoding: .utf8) else { return }
        let env = CursorNotifyEnvFile(contents: contents)
        guard env.value(for: CursorNotifyEnvFile.approveEnabledKey) == nil else { return }

        let updated = env.settingApproveEnabled(env.isApproveEnabled)
        try updated.write(to: envFileURL, atomically: true, encoding: .utf8)
    }

    private func envFileNeedsMigration() -> Bool {
        guard let contents = try? String(contentsOf: envFileURL, encoding: .utf8) else {
            return false
        }
        let env = CursorNotifyEnvFile(contents: contents)
        return env.value(for: CursorNotifyEnvFile.approveEnabledKey) == nil
    }

    static func hooksJSONStatus(data: Data?) -> [String] {
        guard let data,
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = parsed["hooks"] as? [String: Any] else {
            return ["stop"]
        }

        if hookEntries(hooks["stop"]).contains(where: { $0["command"] as? String == stopHookCommand }) {
            return []
        }
        return ["stop"]
    }

    static func staleHookEntries(in data: Data?) -> [String] {
        guard let data,
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = parsed["hooks"] as? [String: Any] else {
            return []
        }

        return permissionHookEvents.filter { event in
            hookEntries(hooks[event]).contains { entry in
                guard let command = entry["command"] as? String else { return false }
                return staleHookCommands.contains(command)
            }
        }
    }

    private static func hookEntries(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private func installBundledScript(named resourceName: String, destinationName: String) throws {
        let sourceURL = try bundledResourceURL(name: "\(resourceName).sh")
        let destinationURL = hooksDirectory.appendingPathComponent(destinationName)
        try copyReplacingItem(at: sourceURL, to: destinationURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
    }

    private func removeStaleHookScripts() throws {
        for script in Self.staleHookScripts {
            let url = hooksDirectory.appendingPathComponent(script)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func bundledResourceURL(name: String) throws -> URL {
        if let resourceDirectory {
            let url = resourceDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
            throw CursorNotifyInstallError.missingBundleResource(name)
        }

        let fileName = (name as NSString).deletingPathExtension
        let fileExtension = (name as NSString).pathExtension
        let resourceExtension = fileExtension.isEmpty ? nil : fileExtension

        if let url = bundle.url(
            forResource: fileName,
            withExtension: resourceExtension,
            subdirectory: Self.bundledResourceDirectory
        ) {
            return url
        }

        if let url = bundle.url(forResource: fileName, withExtension: resourceExtension) {
            return url
        }

        throw CursorNotifyInstallError.missingBundleResource(name)
    }

    private func copyReplacingItem(at sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func mergeHooksIntoHooksJSON(includeStopHook: Bool = true) throws {
        if fileManager.fileExists(atPath: hooksJSONURL.path) {
            let backupURL = hooksJSONURL.deletingPathExtension()
                .appendingPathExtension("bak.\(Self.timestampBackupSuffix())")
            try fileManager.copyItem(at: hooksJSONURL, to: backupURL)
        }

        let merged = try Self.mergedHooksJSON(
            existingData: try? Data(contentsOf: hooksJSONURL),
            stopHookCommand: Self.stopHookCommand,
            includeStopHook: includeStopHook
        )
        try merged.write(to: hooksJSONURL, options: .atomic)
    }

    static func mergedHooksJSON(
        existingData: Data?,
        stopHookCommand: String,
        includeStopHook: Bool = true
    ) throws -> Data {
        var root: [String: Any]
        if let existingData,
           let parsed = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            root = parsed
        } else {
            root = [:]
        }

        if root["version"] == nil {
            root["version"] = 1
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        if includeStopHook {
            hooks["stop"] = Self.mergedHookEntries(
                existing: hooks["stop"] as? [[String: Any]] ?? [],
                command: stopHookCommand,
                matcher: "Stop"
            )
        } else {
            let filtered = hookEntries(hooks["stop"]).filter { entry in
                entry["command"] as? String != stopHookCommand
            }
            if filtered.isEmpty {
                hooks.removeValue(forKey: "stop")
            } else {
                hooks["stop"] = filtered
            }
        }

        for event in permissionHookEvents {
            let filtered = hookEntries(hooks[event]).filter { entry in
                guard let command = entry["command"] as? String else { return true }
                return !staleHookCommands.contains(command)
            }
            if filtered.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = filtered
            }
        }

        root["hooks"] = hooks

        guard JSONSerialization.isValidJSONObject(root) else {
            throw CursorNotifyInstallError.fileOperationFailed("Generated hooks.json is invalid.")
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        if let string = String(data: data, encoding: .utf8) {
            return (string + "\n").data(using: .utf8) ?? data
        }
        return data
    }

    private static func mergedHookEntries(
        existing: [[String: Any]],
        command: String,
        matcher: String? = nil
    ) -> [[String: Any]] {
        var entries = existing
        let alreadyInstalled = entries.contains { hook in
            hook["command"] as? String == command
        }

        guard !alreadyInstalled else { return entries }

        var entry: [String: Any] = ["command": command]
        if let matcher {
            entry["matcher"] = matcher
        }
        entries.append(entry)
        return entries
    }

    private func sendTestNotificationIfPossible() throws {
        guard let contents = try? String(contentsOf: envFileURL, encoding: .utf8) else { return }
        guard let topic = CursorNotifyEnvFile(contents: contents).topic,
              !topic.isEmpty,
              topic != "your-topic-name",
              let url = URL(string: "https://ntfy.sh/\(topic)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "AI Work Assistant: Cursor notify hooks installed".data(using: .utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var requestError: Error?
        URLSession.shared.dataTask(with: request) { _, response, error in
            requestError = error
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                requestError = CursorNotifyInstallError.fileOperationFailed(
                    "Test notification failed with status \(http.statusCode)."
                )
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let requestError {
            throw requestError
        }
    }

    private static func timestampBackupSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }
}
