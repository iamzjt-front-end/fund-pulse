import Foundation
import Observation

@Observable
@MainActor
final class MarketIndexStore {
    private(set) var quotes: [MarketIndexID: MarketIndexQuote] = [:]
    private(set) var marketBreadth: MarketBreadth?
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
           now.timeIntervalSince(lastRefreshAt) < minimumRefreshInterval,
           !quotes.isEmpty,
           marketBreadth != nil {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        async let nextQuotesTask = service.fetchQuotes(for: ids)
        async let nextBreadthTask = service.fetchMarketBreadth()
        let (nextQuotes, nextBreadth) = await (nextQuotesTask, nextBreadthTask)
        if !nextQuotes.isEmpty {
            quotes.merge(nextQuotes) { _, new in new }
        }
        if let nextBreadth, nextBreadth.hasData {
            marketBreadth = nextBreadth
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
