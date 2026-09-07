import Combine
import Foundation

@MainActor
final class CursorUsageObserver: ObservableObject {
    @Published private(set) var todayCostCents: Int?
    @Published private(set) var todayTokens: Int?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let client: CursorUsageClient
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    init(client: CursorUsageClient = CursorUsageClient(), refreshInterval: TimeInterval = 300) {
        self.client = client
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    private func performRefresh() async {
        isLoading = true

        do {
            let usage = try await client.fetchTodayUsage()
            guard !Task.isCancelled else { return }

            todayCostCents = usage.totalCostCents
            todayTokens = usage.totalTokens
            lastUpdated = usage.updatedAt
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
