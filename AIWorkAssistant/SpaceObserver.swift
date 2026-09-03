import AppKit
import Combine

struct SpaceInfo {
    let managedSpaceID: Int
    let uuid: String
}

final class SpaceObserver: ObservableObject {

    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var totalSpaces: Int = 1

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?

    init() {
        refresh()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    func refresh() {
        let conn = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] else { return }

        var chosen: [String: Any]?
        for display in raw {
            if chosen == nil { chosen = display }
            if let current = display["Current Space"] as? [String: Any],
               let type = current["type"] as? Int, type == 0 {
                chosen = display
                break
            }
        }
        guard let chosen else { return }

        var spaces: [SpaceInfo] = []
        if let rawSpaces = chosen["Spaces"] as? [[String: Any]] {
            for space in rawSpaces {
                let type = space["type"] as? Int ?? 0
                guard type == 0 else { continue }
                if let id = space["ManagedSpaceID"] as? Int,
                   let uuid = space["uuid"] as? String {
                    spaces.append(SpaceInfo(managedSpaceID: id, uuid: uuid))
                }
            }
        }

        let spaceUUIDs = Set(spaces.map(\.uuid))
        let visualOrder = Self.readVisualOrder(matchingSpaceUUIDs: spaceUUIDs)
        if !visualOrder.isEmpty {
            spaces.sort {
                let a = visualOrder[$0.uuid] ?? Int.max
                let b = visualOrder[$1.uuid] ?? Int.max
                return a < b
            }
        }

        let currentID = (chosen["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int

        totalSpaces = max(1, spaces.count)

        if let id = currentID,
           let idx = spaces.firstIndex(where: { $0.managedSpaceID == id }) {
            currentSpaceIndex = idx + 1
        } else {
            currentSpaceIndex = 1
        }
    }

    private static func readVisualOrder(matchingSpaceUUIDs uuids: Set<String>) -> [String: Int] {
        let path = ("~/Library/Preferences/com.apple.spaces.plist" as NSString).expandingTildeInPath
        guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any],
              let config = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let mgmt = config["Management Data"] as? [String: Any],
              let monitors = mgmt["Monitors"] as? [[String: Any]] else { return [:] }

        var bestMonitorSpaces: [[String: Any]]?
        var bestOverlap = 0
        for monitor in monitors {
            guard let monitorSpaces = monitor["Spaces"] as? [[String: Any]] else { continue }
            let monitorUUIDs = Set(monitorSpaces.compactMap { $0["uuid"] as? String })
            let overlap = monitorUUIDs.intersection(uuids).count
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestMonitorSpaces = monitorSpaces
            }
        }

        guard let visualSpaces = bestMonitorSpaces else { return [:] }

        var positions: [String: Int] = [:]
        var visualIndex = 0
        for space in visualSpaces {
            let type = space["type"] as? Int ?? 0
            guard type == 0 else { continue }
            if let uuid = space["uuid"] as? String {
                positions[uuid] = visualIndex
                visualIndex += 1
            }
        }
        return positions
    }
}
