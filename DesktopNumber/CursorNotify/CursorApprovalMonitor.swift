import Foundation

struct CursorApprovalLogFileState: Equatable {
    var offset: UInt64
    var partialLine: String
}

final class CursorApprovalLogTailer {
    private let fileManager: FileManager
    private let logsRoot: URL
    private(set) var fileStates: [String: CursorApprovalLogFileState] = [:]

    init(fileManager: FileManager = .default, logsRoot: URL? = nil) {
        self.fileManager = fileManager
        let home = fileManager.homeDirectoryForCurrentUser
        self.logsRoot = logsRoot ?? home
            .appendingPathComponent("Library/Application Support/Cursor/logs", isDirectory: true)
    }

    func discoverLogFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.contains("Structured Logs") || name == "workbench.mcp.allowlist.log" else {
                continue
            }
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    func readNewLines(from fileURL: URL) throws -> [String] {
        let path = fileURL.path
        var state = fileStates[path] ?? CursorApprovalLogFileState(offset: 0, partialLine: "")

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if UInt64(fileSize) < state.offset {
            state.offset = 0
            state.partialLine = ""
        }

        try handle.seek(toOffset: state.offset)
        let data = handle.readDataToEndOfFile()
        state.offset = try handle.offset()

        guard !data.isEmpty else {
            fileStates[path] = state
            return []
        }

        var combined = state.partialLine + (String(data: data, encoding: .utf8) ?? "")
        var lines: [String] = []
        while let newlineIndex = combined.firstIndex(of: "\n") {
            let line = String(combined[..<newlineIndex])
            lines.append(line)
            combined = String(combined[combined.index(after: newlineIndex)...])
        }

        state.partialLine = combined
        fileStates[path] = state
        return lines
    }

    func initializeAtEnd(of fileURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        fileStates[fileURL.path] = CursorApprovalLogFileState(offset: size, partialLine: "")
    }
}

@MainActor
final class CursorApprovalMonitor: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var lastPushAt: Date?

    private struct PendingShellApproval {
        let event: CursorApprovalEvent
        let queuedAt: Date
    }

    private let tailer: CursorApprovalLogTailer
    private let ntfyClient: CursorNtfySending
    private var pollTimer: Timer?
    private var pendingShellApprovals: [String: PendingShellApproval] = [:]
    private var sessionDedupeKeys: Set<String> = []
    private let pollInterval: TimeInterval
    private let pendingDelay: TimeInterval

    init(
        tailer: CursorApprovalLogTailer = CursorApprovalLogTailer(),
        ntfyClient: CursorNtfySending,
        pollInterval: TimeInterval = 2.0,
        pendingDelay: TimeInterval = 1.5
    ) {
        self.tailer = tailer
        self.ntfyClient = ntfyClient
        self.pollInterval = pollInterval
        self.pendingDelay = pendingDelay
    }

    convenience init(envFileURL: URL) {
        self.init(ntfyClient: CursorNtfyClient(envFileURL: envFileURL))
    }

    func start() {
        guard pollTimer == nil else { return }

        for file in tailer.discoverLogFiles() {
            try? tailer.initializeAtEnd(of: file)
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func poll() {
        for file in tailer.discoverLogFiles() {
            if tailer.fileStates[file.path] == nil {
                try? tailer.initializeAtEnd(of: file)
            }

            guard let lines = try? tailer.readNewLines(from: file) else { continue }
            handle(lines: lines)
        }
    }

    func handle(line: String) {
        handle(lines: [line])
    }

    func handle(lines: [String]) {
        for line in lines {
            guard let entry = CursorApprovalLogParser.parse(line: line) else { continue }
            switch entry {
            case .push(let event):
                sendPushIfNeeded(event)
            case .pendingShell(let event):
                queuePendingShell(event)
            case .resolveShell(let toolCallId):
                resolvePendingShell(toolCallId: toolCallId)
            }
        }
        flushExpiredPending()
    }

    func flushExpiredPending(now: Date = Date()) {
        let readyKeys = pendingShellApprovals.compactMap { key, pending -> String? in
            now.timeIntervalSince(pending.queuedAt) >= pendingDelay ? key : nil
        }

        for key in readyKeys {
            guard let pending = pendingShellApprovals.removeValue(forKey: key) else { continue }
            sendPushIfNeeded(pending.event)
        }
    }

    private func queuePendingShell(_ event: CursorApprovalEvent) {
        guard !sessionDedupeKeys.contains(event.dedupeKey) else { return }
        pendingShellApprovals[event.dedupeKey] = PendingShellApproval(event: event, queuedAt: Date())
    }

    private func resolvePendingShell(toolCallId: String) {
        pendingShellApprovals.removeValue(forKey: "shell:\(toolCallId)")
        pendingShellApprovals.removeValue(forKey: "shell:run:\(toolCallId)")
        sessionDedupeKeys.insert("shell:\(toolCallId)")
        sessionDedupeKeys.insert("shell:run:\(toolCallId)")
    }

    private func sendPushIfNeeded(_ event: CursorApprovalEvent) {
        guard !sessionDedupeKeys.contains(event.dedupeKey) else { return }
        sessionDedupeKeys.insert(event.dedupeKey)

        Task {
            do {
                try await ntfyClient.sendApprovalPush(title: event.title, body: event.body)
                lastPushAt = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
