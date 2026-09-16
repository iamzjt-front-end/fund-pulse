import Foundation

extension PortfolioStore {
    func refreshQuotes(prefetched: [String: FundQuote]? = nil) async {
        if let prefetched { prefetchedQuotes = prefetched }
        guard quoteRefreshDeferralCount == 0 else {
            hasDeferredQuoteRefresh = true
            return
        }

        refreshRequestGeneration &+= 1
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await drainRefreshRequests()
        }
        refreshTask = task
        await task.value
    }

    private func drainRefreshRequests() async {
        isRefreshingQuotes = true
        defer {
            isRefreshingQuotes = false
            refreshTask = nil
        }

        var processedGeneration = 0
        repeat {
            processedGeneration = refreshRequestGeneration
            await performRefreshPass()
        } while processedGeneration != refreshRequestGeneration
    }

    private func performRefreshPass() async {
        if case .loading = loadState { load() }
        // Never overwrite an unreadable/missing portfolio. A later write error,
        // however, is retryable when a successfully loaded snapshot exists.
        guard persistedSnapshot != nil else { return }
        let base = snapshot
        let baseRevision = snapshotRevision
        let codes = base.funds.map(\.code)
        do {
            try ensureAccountsRestoreCompleted()
            let fetched: [String: FundQuote]
            if let prefetched = prefetchedQuotes {
                prefetchedQuotes = nil
                fetched = prefetched
            } else {
                switch accountKind {
                case .offExchange: fetched = await quoteService.fetchQuotes(codes: codes)
                case .onExchange: fetched = await exchangeQuoteService.fetchQuotes(codes: codes)
                }
            }
            // Confirmation runs against an isolated value. Actor reentrancy can
            // change the live ledger at any await; only an unchanged base commits.
            let staged = PortfolioStore(
                repository: StagedPortfolioRepository(dataDirectory: dataDirectory, snapshot: base),
                quoteService: quoteService, exchangeQuoteService: exchangeQuoteService,
                performanceStore: performanceStore, accountKind: accountKind, now: nowProvider
            )
            staged.snapshot = base
            let quotes = base.funds.reduce(into: [String: FundQuote]()) { result, fund in
                result[fund.code] = accountKind == .onExchange
                    ? ExchangeQuoteFreshnessPolicy.acceptedQuote(incoming: fetched[fund.code], for: fund)
                    : OffExchangeQuoteFreshnessPolicy.acceptedQuote(incoming: fetched[fund.code], for: fund)
            }
            if accountKind == .offExchange {
                staged.repairAmountModeSharePrecisionFromTradeRecords()
                await staged.processPendingTrades(quotes: quotes)
                await staged.processPendingConversions(quotes: quotes)
                await staged.processPendingPositions(quotes: quotes)
            }
            guard snapshotRevision == baseRevision else {
                refreshRequestGeneration &+= 1
                return
            }
            let now = nowProvider()
            staged.snapshot = FundIntradayRateHistoryRecorder.applyingQuotes(
                to: PortfolioCalculator.applyingQuotes(to: staged.snapshot, quotes: quotes, now: now, accountKind: accountKind),
                quotes: fetched, now: now
            )
            staged.syncInitialTradeRecordsFromFunds()
            if let jsonRepository = repository as? JSONPortfolioRepository {
                let prepared = try await jsonRepository.prepareRefresh(staged.snapshot, replacing: base)
                defer { prepared.discard() }
                guard snapshotRevision == baseRevision else {
                    refreshRequestGeneration &+= 1
                    return
                }
                guard !FileManager.default.fileExists(atPath: importRollbackURL.path) else {
                    throw PortfolioStoreError.importRecoveryRequired
                }
                try ensureAccountsRestoreCompleted()
                try prepared.commit()
                persistedSnapshot = staged.snapshot
            } else {
                try save(staged.snapshot)
            }
            snapshot = staged.snapshot
            let missing = codes.filter { code in
                guard let quote = fetched[code], quotes[code] == quote else { return true }
                return TradingCalendar.isFundTradingDay(now)
                    && !FundQuoteUpdatePolicy.isOfficiallyUpdated(quote, on: now)
                    && !FundQuoteUpdatePolicy.hasCurrentIntradayEstimate(quote, on: now)
            }
            quoteRefreshWarning = missing.isEmpty ? nil
                : "\(missing.count)/\(codes.count) 只基金行情未更新，保留最近有效数据；当日收益可能不完整。"
            if missing.isEmpty {
                lastSuccessfulQuoteRefresh = now
                recordPortfolioPerformanceIfPossible(quotes: fetched, now: now)
            }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func beginDeferringQuoteRefresh() async {
        quoteRefreshDeferralCount += 1
        if let refreshTask {
            await refreshTask.value
        }
    }

    func endDeferringQuoteRefresh() async {
        quoteRefreshDeferralCount = max(0, quoteRefreshDeferralCount - 1)
        guard quoteRefreshDeferralCount == 0, hasDeferredQuoteRefresh else { return }

        hasDeferredQuoteRefresh = false
        await refreshQuotes()
    }

    private func recordPortfolioPerformanceIfPossible(
        quotes: [String: FundQuote],
        now: Date
    ) {
        guard let allQuotesConfirmed = PortfolioPerformanceRecorder.quoteConfirmationState(
            portfolio: snapshot,
            quotes: quotes,
            now: now
        ) else { return }

        _ = performanceStore.record(
            portfolio: snapshot,
            now: now,
            allQuotesConfirmed: allQuotesConfirmed
        )
    }
}
