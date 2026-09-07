import Foundation

enum CommuteStopReason: String, Codable, Equatable {
    case user
    case userQuit
    case timerExpired
    case batteryLow
    case thermalPressure
    case ownerProcessEnded
    case failsafeTriggered
    case reconciliation
    case helperLost
    case permissionMissing
    case externalOverride
}

enum CommuteModePhase: Equatable {
    case inactive
    case enabling
    case active
    case stopping
    case failed
    case externalOverride
}

struct CommuteModeLease: Codable, Equatable {
    var isActive: Bool
    var ownerPID: Int32
    var failsafePID: Int32?
    var enabledAt: Date
    var deadline: Date
    var baselineSleepDisabled: Bool
    var appVersion: String
    var lastStopReason: CommuteStopReason?
    var lastStopAt: Date?

    static func makeNew(
        ownerPID: Int32,
        failsafePID: Int32?,
        enabledAt: Date,
        deadline: Date,
        baselineSleepDisabled: Bool,
        appVersion: String
    ) -> CommuteModeLease {
        CommuteModeLease(
            isActive: true,
            ownerPID: ownerPID,
            failsafePID: failsafePID,
            enabledAt: enabledAt,
            deadline: deadline,
            baselineSleepDisabled: baselineSleepDisabled,
            appVersion: appVersion,
            lastStopReason: nil,
            lastStopAt: nil
        )
    }
}

struct CommuteModeStateStore {
    static let directoryName = "AIWorkAssistant"
    static let leaseFileName = "commute-mode.json"

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let customLeaseURL: URL?

    init(customLeaseURL: URL? = nil) {
        self.customLeaseURL = customLeaseURL
    }

    func leaseURL() -> URL {
        if let customLeaseURL {
            return customLeaseURL
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(Self.leaseFileName)
    }

    func loadLease() -> CommuteModeLease? {
        let url = leaseURL()
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(CommuteModeLease.self, from: data)
    }

    func saveLease(_ lease: CommuteModeLease) throws {
        let url = leaseURL()
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(lease)
        try data.write(to: url, options: .atomic)
    }

    func clearLease() throws {
        let url = leaseURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

enum CommuteFailsafePaths {
    static func failsafeExecutableURL(bundle: Bundle = .main) -> URL? {
        let macOSURL = bundle.bundleURL
            .appendingPathComponent("Contents/MacOS/CommuteFailsafe")
        if FileManager.default.isExecutableFile(atPath: macOSURL.path) {
            return macOSURL
        }

        let resourcesURL = bundle.bundleURL
            .appendingPathComponent("Contents/Resources/CommuteFailsafe")
        if FileManager.default.isExecutableFile(atPath: resourcesURL.path) {
            return resourcesURL
        }

        return nil
    }
}

enum ProcessLiveness {
    static func isProcessRunning(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}
