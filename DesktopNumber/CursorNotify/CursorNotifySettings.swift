import Foundation

struct CursorNotifyEnvFile {
    static let enabledKey = "NTFY_ENABLED"
    static let approveEnabledKey = "NTFY_APPROVE_ENABLED"
    static let topicKey = "NTFY_TOPIC"

    let lines: [String]

    init(contents: String) {
        lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    func value(for key: String) -> String? {
        let prefix = "\(key)="
        for line in lines {
            guard !line.hasPrefix("#"), line.hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    var isEnabled: Bool {
        Self.isTruthy(value(for: Self.enabledKey), defaultValue: false)
    }

    var isApproveEnabled: Bool {
        Self.isTruthy(value(for: Self.approveEnabledKey), defaultValue: false)
    }

    var topic: String? {
        value(for: Self.topicKey)
    }

    private static func isTruthy(_ raw: String?, defaultValue: Bool) -> Bool {
        guard let raw else { return defaultValue }
        switch raw.lowercased() {
        case "0", "false", "no", "off":
            return false
        default:
            return true
        }
    }

    func settingEnabled(_ enabled: Bool) -> String {
        settingKey(Self.enabledKey, enabled: enabled)
    }

    func settingApproveEnabled(_ enabled: Bool) -> String {
        settingKey(Self.approveEnabledKey, enabled: enabled)
    }

    private func settingKey(_ key: String, enabled: Bool) -> String {
        let newValue = enabled ? "1" : "0"
        var updated = false
        var output: [String] = []

        for line in lines {
            if !line.hasPrefix("#"), line.hasPrefix("\(key)=") {
                output.append("\(key)=\(newValue)")
                updated = true
            } else {
                output.append(line)
            }
        }

        if !updated {
            if !output.isEmpty, output.last?.isEmpty == false {
                output.append("")
            }
            output.append("\(key)=\(newValue)")
        }

        while output.last == "" {
            output.removeLast()
        }

        return output.joined(separator: "\n") + "\n"
    }

    func settingTopic(_ topic: String) -> String {
        var updated = false
        var output: [String] = []

        for line in lines {
            if !line.hasPrefix("#"), line.hasPrefix("\(Self.topicKey)=") {
                output.append("\(Self.topicKey)=\(topic)")
                updated = true
            } else {
                output.append(line)
            }
        }

        if !updated {
            if !output.isEmpty, output.last?.isEmpty == false {
                output.append("")
            }
            output.append("\(Self.topicKey)=\(topic)")
        }

        while output.last == "" {
            output.removeLast()
        }

        return output.joined(separator: "\n") + "\n"
    }
}

@MainActor
final class CursorNotifySettings: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var needsMigration = false
    @Published private(set) var isEnabled = false
    @Published private(set) var isApproveEnabled = false
    @Published private(set) var topic: String?
    @Published private(set) var isUpdating = false
    @Published private(set) var installError: String?
    @Published private(set) var migrationStatus: String?
    @Published private(set) var isSendingTestPush = false
    @Published private(set) var testPushStatus: String?
    @Published private(set) var setupStatus: String?

    static let placeholderTopic = CursorNotifyConstants.placeholderTopic

    let approvalMonitor: CursorApprovalMonitor

    private let fileManager: FileManager
    private let bundle: Bundle
    private let resourceDirectory: URL?
    private let cursorDirectory: URL
    private let hooksDirectory: URL
    private let envFileURL: URL

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        resourceDirectory: URL? = nil,
        hooksDirectory: URL? = nil,
        envFileURL: URL? = nil,
        cursorDirectory: URL? = nil,
        approvalMonitor: CursorApprovalMonitor? = nil,
        autoMigrate: Bool = true,
        startMonitor: Bool = true
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
        self.envFileURL = envFileURL ?? self.hooksDirectory.appendingPathComponent("notify.env")
        self.approvalMonitor = approvalMonitor ?? CursorApprovalMonitor(envFileURL: self.envFileURL)
        refresh()
        if autoMigrate {
            migrateIfNeeded()
        }
        if startMonitor, isApproveEnabled {
            self.approvalMonitor.start()
        }
    }

    func refresh() {
        let installer = makeInstaller()
        let status = installer.installationStatus()
        let hasStopHook = fileManager.fileExists(
            atPath: hooksDirectory.appendingPathComponent("on-stop.sh").path
        )
        isInstalled = hasStopHook
        needsMigration = status.needsMigration

        guard let contents = try? String(contentsOf: envFileURL, encoding: .utf8) else {
            isEnabled = hasStopHook
            isApproveEnabled = false
            topic = nil
            return
        }

        let env = CursorNotifyEnvFile(contents: contents)
        isEnabled = env.isEnabled
        isApproveEnabled = env.isApproveEnabled
        topic = env.topic
    }

    func migrateIfNeeded() {
        let installer = makeInstaller()
        let status = installer.installationStatus()
        guard status.needsMigration else {
            migrationStatus = nil
            return
        }

        do {
            try installer.migrateIfNeeded()
            migrationStatus = "Updated Cursor push hooks."
            refresh()
        } catch {
            migrationStatus = error.localizedDescription
            refresh()
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }

        isUpdating = true
        installError = nil
        defer { isUpdating = false }

        let installer = makeInstaller()
        let keepApproveActive = isApproveEnabled

        do {
            if enabled {
                try installer.installStopHook()
                try writeEnvFile { $0.settingEnabled(true) }
                isEnabled = true
            } else {
                try installer.uninstallStopHook()
                try writeEnvFile { $0.settingEnabled(false) }
                isEnabled = false
                if !keepApproveActive {
                    try installer.uninstall()
                    approvalMonitor.stop()
                }
            }
            refresh()
        } catch {
            installError = error.localizedDescription
            refresh()
        }
    }

    func setApproveEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }

        isUpdating = true
        installError = nil
        defer { isUpdating = false }

        let installer = makeInstaller()
        let keepFinishActive = isEnabled

        do {
            if enabled {
                try installer.ensureNotifyEnv()
                try writeEnvFile { $0.settingApproveEnabled(true) }
                isApproveEnabled = true
                approvalMonitor.start()
            } else {
                try writeEnvFile { $0.settingApproveEnabled(false) }
                isApproveEnabled = false
                approvalMonitor.stop()
                if !keepFinishActive {
                    try installer.uninstall()
                }
            }
            refresh()
        } catch {
            installError = error.localizedDescription
            refresh()
        }
    }

    func setTopic(_ topic: String) {
        do {
            try writeEnvFile { env in
                if env.lines.isEmpty {
                    return """
                    NTFY_TOPIC=\(topic)
                    NTFY_ENABLED=\(isEnabled ? "1" : "0")
                    NTFY_APPROVE_ENABLED=\(isApproveEnabled ? "1" : "0")

                    """
                }
                return env.settingTopic(topic)
            }
            self.topic = topic
            refresh()
        } catch {
            installError = error.localizedDescription
            refresh()
        }
    }

    func sendTestPush() async {
        guard !isSendingTestPush else { return }

        guard let topic,
              !topic.isEmpty,
              topic != Self.placeholderTopic,
              let url = URL(string: "https://ntfy.sh/\(topic)") else {
            testPushStatus = "Set an ntfy topic first."
            return
        }

        isSendingTestPush = true
        testPushStatus = nil

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = "DesktopNumber: test push".data(using: .utf8)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                testPushStatus = "Test push failed with status \(http.statusCode)."
            } else {
                testPushStatus = "Test push sent."
            }
        } catch {
            testPushStatus = error.localizedDescription
        }

        isSendingTestPush = false
    }

    func installHooks() async {
        guard !isUpdating else { return }

        isUpdating = true
        installError = nil
        setupStatus = nil
        defer { isUpdating = false }

        let installer = makeInstaller()

        do {
            try installer.install(sendTestNotification: false)
            refresh()
            setupStatus = "Cursor push hooks installed."
        } catch {
            installError = error.localizedDescription
            setupStatus = nil
            refresh()
        }
    }

    func uninstallHooks() async {
        guard !isUpdating else { return }

        isUpdating = true
        installError = nil
        setupStatus = nil
        defer { isUpdating = false }

        let installer = makeInstaller()

        do {
            try installer.uninstall()
            try writeEnvFile { env in
                CursorNotifyEnvFile(contents: env.settingEnabled(false)).settingApproveEnabled(false)
            }
            approvalMonitor.stop()
            refresh()
            setupStatus = "Cursor push hooks uninstalled."
        } catch {
            installError = error.localizedDescription
            setupStatus = nil
            refresh()
        }
    }

    private func makeInstaller() -> CursorNotifyInstaller {
        CursorNotifyInstaller(
            fileManager: fileManager,
            bundle: bundle,
            resourceDirectory: resourceDirectory,
            cursorDirectory: cursorDirectory,
            hooksDirectory: hooksDirectory,
            envFileURL: envFileURL
        )
    }

    private func writeEnvFile(transform: (CursorNotifyEnvFile) -> String) throws {
        let existing = (try? String(contentsOf: envFileURL, encoding: .utf8)) ?? ""
        let contents = transform(CursorNotifyEnvFile(contents: existing))
        try fileManager.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        try contents.write(to: envFileURL, atomically: true, encoding: .utf8)
        if !fileManager.fileExists(atPath: envFileURL.path) {
            return
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envFileURL.path)
    }
}
