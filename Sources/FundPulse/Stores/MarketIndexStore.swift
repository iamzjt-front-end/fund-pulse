import Foundation
import Observation

@Observable
@MainActor
final class MarketIndexStore {
    private(set) var quotes: [MarketIndexID: MarketIndexQuote] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefreshAt: Date?

    private let service: MarketIndexService
    private let minimumRefreshInterval: TimeInterval
    private let nowProvider: () -> Date

    init(
        service: MarketIndexService = MarketIndexService(),
        minimumRefreshInterval: TimeInterval = 20,
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.minimumRefreshInterval = minimumRefreshInterval
        self.nowProvider = now
    }

    func refresh(ids: [MarketIndexID] = MarketIndexID.allCases, force: Bool = false) async {
        guard !isRefreshing else { return }

        let now = nowProvider()
        if !force,
           let lastRefreshAt,
           now.timeIntervalSince(lastRefreshAt) < minimumRefreshInterval {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let nextQuotes = await service.fetchQuotes(for: ids)
        if !nextQuotes.isEmpty {
            quotes.merge(nextQuotes) { _, new in new }
        }
        lastRefreshAt = now
    }

    func orderedQuotes(ids: [MarketIndexID] = MarketIndexID.allCases) -> [MarketIndexQuote] {
        ids.compactMap { quotes[$0] }
    }

    func primaryQuote(defaultID: MarketIndexID) -> MarketIndexQuote? {
        quotes[defaultID]
    }
}
