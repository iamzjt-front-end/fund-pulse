import Foundation
import Observation

@Observable
@MainActor
final class PortfolioStore {
    private(set) var snapshot: PortfolioSnapshot = .empty
    private(set) var loadState: LoadState = .loading
    private(set) var isRefreshingQuotes = false
    private(set) var dataDirectory: URL
    private let quoteService: FundQuoteService
    private let nowProvider: () -> Date
    private let repository: any PortfolioRepository
    let performanceStore: PortfolioPerformanceStore
    private var persistedSnapshot: PortfolioSnapshot?
    private var refreshTask: Task<Void, Never>?
    private var refreshRequestGeneration = 0
    private var quoteRefreshDeferralCount = 0
    private var hasDeferredQuoteRefresh = false

    enum LoadState: Equatable {
        case loading
        case loaded
        case missingPlainData(hasLegacyStore: Bool)
        case failed(String)
    }

    init(
        dataDirectory: URL = AppDataPaths.sharedDataDirectory,
        quoteService: FundQuoteService = FundQuoteService(),
        performanceStore: PortfolioPerformanceStore? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        self.dataDirectory = dataDirectory
        self.quoteService = quoteService
        self.nowProvider = now
        self.repository = JSONPortfolioRepository(dataDirectory: dataDirectory)
        self.performanceStore = performanceStore ?? PortfolioPerformanceStore(dataDirectory: dataDirectory)
    }

    init(
        repository: any PortfolioRepository,
        quoteService: FundQuoteService = FundQuoteService(),
        performanceStore: PortfolioPerformanceStore? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        self.dataDirectory = repository.dataDirectory
        self.quoteService = quoteService
        self.nowProvider = now
        self.repository = repository
        self.performanceStore = performanceStore ?? PortfolioPerformanceStore(dataDirectory: repository.dataDirectory)
    }

    var dataFileURL: URL {
        repository.dataFileURL
    }

    func load() {
        loadState = .loading
        performanceStore.load()

        do {
            if let loadedSnapshot = try repository.load() {
                snapshot = loadedSnapshot
                persistedSnapshot = loadedSnapshot
                loadState = .loaded
                return
            }

            snapshot = .empty
            persistedSnapshot = nil
            loadState = .missingPlainData(hasLegacyStore: AppDataPaths.hasLegacyStore(in: dataDirectory))
        } catch {
            snapshot = .empty
            persistedSnapshot = nil
            loadState = .failed(error.localizedDescription)
        }
    }

    func exportPortfolio(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var backup = snapshot
        backup.portfolioPerformanceHistory = try performanceStore.snapshotForExport()
        let data = try encoder.encode(backup)
        try data.write(to: url, options: .atomic)
    }

    func importPortfolio(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var importedSnapshot = try decoder.decode(PortfolioSnapshot.self, from: data)
        let importedPerformance = importedSnapshot.portfolioPerformanceHistory ?? .empty
        importedSnapshot.portfolioPerformanceHistory = nil

        let previousSnapshot = snapshot
        let previousPerformance = performanceStore.snapshot
        let previousPerformanceWasUnreadable = performanceStore.hasUnreadablePersistedData
        do {
            try save(importedSnapshot)
            try performanceStore.replace(importedPerformance)
            snapshot = importedSnapshot
            loadState = .loaded
        } catch {
            try? save(previousSnapshot)
            if !previousPerformanceWasUnreadable {
                try? performanceStore.replace(previousPerformance)
            }
            snapshot = previousSnapshot
            throw error
        }
    }

    func clearAllHoldings() throws {
        let previousSnapshot = snapshot
        let clearedSnapshot = PortfolioSnapshot(
            updateTime: nowProvider(),
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [],
            migration: nil
        )
        try save(clearedSnapshot)

        guard performanceStore.clear() else {
            try? save(previousSnapshot)
            throw PortfolioStoreError.performanceHistoryWriteFailed(
                performanceStore.lastError ?? "未知错误"
            )
        }
        snapshot = clearedSnapshot
        loadState = .loaded
    }

    func refreshQuotes() async {
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
        if case .loading = loadState {
            load()
        }
        if case .missingPlainData = loadState {
            return
        }
        if case .failed = loadState {
            return
        }

        let codes = snapshot.funds.map(\.code)
        guard !codes.isEmpty else {
            resetEmptyPortfolioAggregates(updateTime: nowProvider())
            loadState = .loaded
            try? save(snapshot)
            return
        }

        do {
            let quotes = await quoteService.fetchQuotes(codes: codes)
            repairAmountModeSharePrecisionFromTradeRecords()
            await processPendingTrades(quotes: quotes)
            await processPendingConversions(quotes: quotes)
            await processPendingPositions(quotes: quotes)
            let now = nowProvider()
            let calculatedSnapshot = PortfolioCalculator.applyingQuotes(to: snapshot, quotes: quotes, now: now)
            snapshot = FundIntradayRateHistoryRecorder.applyingQuotes(
                to: calculatedSnapshot,
                quotes: quotes,
                now: now
            )
            syncInitialTradeRecordsFromFunds()
            try save(snapshot)
            recordPortfolioPerformanceIfPossible(quotes: quotes, now: now)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func upsertFund(_ draft: FundPositionDraft, replacing existingCode: String? = nil) async throws {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw PortfolioStoreError.invalidCode
        }

        let existingFund = snapshot.funds.first { $0.code == (existingCode ?? code) }
        let isCreatingFund = existingFund == nil && existingCode == nil
        let quote = try? await quoteService.fetchQuote(code: code)
        let requestedAcceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.positionDate,
            timeType: draft.positionTimeType
        )
        let acceptedDate = resolvedInitialAcceptedDate(
            draft: draft,
            quote: quote,
            requestedAcceptedDate: requestedAcceptedDate,
            isCreatingFund: isCreatingFund
        )
        var persistedDraft = draft
        if isCreatingFund && !draft.requiresTradeConfirmation {
            persistedDraft.positionDate = acceptedDate
            persistedDraft.positionTimeType = .before15
        }
        let canConfirmInitialPosition = existingFund != nil
            || !draft.requiresTradeConfirmation
            || shouldConfirmPendingTrade(acceptedDate: acceptedDate)
        let fetchedConfirmedNetValue = await quoteService.fetchConfirmedNetValue(
            code: code,
            acceptedDate: acceptedDate,
            latestQuote: quote
        )
        let confirmedNetValue = canConfirmInitialPosition
            ? resolvedInitialConfirmedNetValue(
                fetchedConfirmedNetValue,
                draft: draft,
                quote: quote,
                isCreatingFund: isCreatingFund
            )
            : nil
        let fund = try makeFundPosition(
            from: persistedDraft,
            existingFund: existingFund,
            quote: quote,
            confirmedNetValue: confirmedNetValue,
            isEditingExistingFund: existingFund != nil
        )
        var funds = snapshot.funds.filter { $0.code != (existingCode ?? code) && $0.code != code }

        if let existingCode,
           let index = snapshot.funds.firstIndex(where: { $0.code == existingCode }) {
            let insertionIndex = min(index, funds.count)
            funds.insert(fund, at: insertionIndex)
        } else {
            funds.insert(fund, at: 0)
        }

        snapshot.funds = funds
        if isCreatingFund {
            appendInitialTradeRecord(
                draft: persistedDraft,
                fund: fund,
                acceptedDate: acceptedDate,
                confirmedNetValue: confirmedNetValue
            )
        } else {
            resetTradeHistoryForEditedFund(codes: Set([existingCode ?? code, code]))
            appendInitialTradeRecord(
                draft: persistedDraft,
                fund: fund,
                acceptedDate: acceptedDate,
                confirmedNetValue: confirmedNetValue
            )
        }
        try save(snapshot)
        await refreshQuotes()
    }

    func lookupFundName(code: String) async -> String? {
        await quoteService.lookupFundName(code: code)
    }

    func fetchLatestQuote(code: String) async -> FundQuote? {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        return try? await quoteService.fetchQuote(code: code)
    }

    func fetchTradeReferenceNetValue(
        code: String,
        tradeDate: String,
        timeType: PositionTimeType
    ) async -> (date: String, value: Double)? {
        let acceptedDate = TradingCalendar.acceptedTradeDate(positionDate: tradeDate, timeType: timeType)
        return await quoteService.fetchSmartNetValue(code: code, startDate: acceptedDate)
    }

    func applyAmountPositionSyncUpdates(_ updates: [FundAmountPositionSyncUpdate]) async throws {
        guard !updates.isEmpty else { return }

        for update in updates {
            let code = update.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { throw PortfolioStoreError.invalidCode }
            guard let index = snapshot.funds.firstIndex(where: { $0.code == code }) else {
                throw PortfolioStoreError.fundNotFound
            }

            var fund = snapshot.funds[index]
            guard fund.status == .holding else { continue }

            let amount = roundedMoney(update.amount)
            let holdingIncome = roundedMoney(update.holdingIncome ?? fund.holdingIncome ?? fund.confirmedHoldingIncome ?? 0)
            let principal = roundedMoney(amount - holdingIncome)
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            guard principal > 0 else { throw PortfolioStoreError.invalidCost }

            let quote = try await quoteService.fetchQuote(code: code)
            guard let netValue = quoteNetValue(quote) else {
                throw PortfolioStoreError.missingNetValue
            }
            let lot = try amountSyncLot(
                code: code,
                amount: amount,
                principal: principal,
                netValue: netValue,
                fund: fund
            )
            let holdingRate = principal > 0 ? holdingIncome / principal * 100 : nil
            let baselineDate = update.syncedAt ?? nowProvider()
            let tradeDate = DateOnlyFormatter.string(from: baselineDate)
            let syncedPendingBuyAmount = roundedMoney(max(update.syncedPendingBuyAmount ?? 0, 0))

            fund.name = quote.name.isEmpty ? fund.name : quote.name
            fund.dateText = dateText(for: quote, fallback: fund.dateText)
            fund.todayRate = quote.growthRate
            fund.isUpdated = quoteIsUpdated(quote)
            fund.status = .holding
            fund.isIncomeActive = true
            fund.positionMode = .amount
            fund.currentAmount = amount
            fund.holdingIncome = holdingIncome
            fund.holdingRate = holdingRate
            fund.confirmedHoldingIncome = holdingIncome
            fund.confirmedHoldingRate = holdingRate
            fund.migratedPrincipal = principal
            fund.lots = [lot]
            fund.migratedShares = lot.shares
            fund.migratedCost = lot.cost
            fund.pendingAmount = nil
            fund.pendingProfit = nil
            fund.syncedPendingBuyAmount = syncedPendingBuyAmount > 0 ? syncedPendingBuyAmount : nil
            fund.syncedPendingBuyDate = syncedPendingBuyAmount > 0 ? tradeDate : nil

            snapshot.funds[index] = fund

            var records = snapshot.tradeRecords ?? []
            records.append(FundTradeRecord(
                id: UUID().uuidString,
                kind: .newFund,
                status: .confirmed,
                code: code,
                name: fund.name,
                mode: .amount,
                amount: amount,
                shares: nil,
                confirmedShares: lot.shares,
                price: netValue,
                profit: holdingIncome,
                tradeDate: tradeDate,
                tradeTimeType: .before15,
                acceptedDate: tradeDate,
                createdAt: baselineDate,
                confirmedAt: baselineDate,
                failureReason: nil,
                syncSource: .jdFinance,
                syncKey: JDFinanceSyncFingerprint.positionBaseline(code: code, syncedAt: baselineDate),
                externalStatus: .externalConfirmed,
                externalStatusText: "京东持仓对账基线",
                waitsForExternalConfirmation: false,
                isReconciliationBaseline: true
            ))
            snapshot.tradeRecords = records
        }

        try save(snapshot)
        await refreshQuotes()
    }

    func adjustFundPosition(_ draft: FundTradeDraft, syncMetadata: FundTradeSyncMetadata? = nil) async throws {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw PortfolioStoreError.invalidCode
        }
        guard let index = snapshot.funds.firstIndex(where: { $0.code == code }) else {
            throw PortfolioStoreError.fundNotFound
        }
        guard draft.action != .buy || draft.mode == .amount else {
            throw PortfolioStoreError.buyTradeRequiresAmount
        }
        guard draft.action != .sell || draft.mode == .share else {
            throw PortfolioStoreError.sellTradeRequiresShare
        }

        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.tradeDate,
            timeType: draft.tradeTimeType
        )
        appendPendingTrade(draft, fund: snapshot.funds[index], acceptedDate: acceptedDate, syncMetadata: syncMetadata)
        try save(snapshot)
        await refreshQuotes()
    }

    func importTradeIfNeeded(_ draft: FundTradeDraft, syncMetadata: FundTradeSyncMetadata? = nil) async throws {
        if hasImportedTrade(matching: draft) {
            if let syncMetadata {
                markImportedTrade(matching: draft, syncMetadata: syncMetadata)
                try save(snapshot)
            }
            return
        }
        try await adjustFundPosition(draft, syncMetadata: syncMetadata)
    }

    func markImportedTradeIfPresent(
        _ draft: FundTradeDraft,
        syncMetadata: FundTradeSyncMetadata
    ) throws {
        guard hasImportedTrade(matching: draft) else {
            return
        }
        markImportedTrade(matching: draft, syncMetadata: syncMetadata)
        try save(snapshot)
    }

    func convertFundPosition(_ draft: FundConversionDraft, syncMetadata: FundTradeSyncMetadata? = nil) async throws {
        let normalizedDraft = try normalizedConversionDraft(draft)
        guard let fromIndex = snapshot.funds.firstIndex(where: { $0.code == normalizedDraft.fromCode }) else {
            throw PortfolioStoreError.fundNotFound
        }
        guard availableShares(for: snapshot.funds[fromIndex]) + PortfolioPrecision.shareAvailabilityTolerance >= normalizedDraft.shares else {
            throw PortfolioStoreError.insufficientShares
        }

        ensureConversionTargetFund(for: normalizedDraft)
        let fromFund = snapshot.funds.first { $0.code == normalizedDraft.fromCode } ?? snapshot.funds[fromIndex]
        let toFund = snapshot.funds.first { $0.code == normalizedDraft.toCode }
        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: normalizedDraft.tradeDate,
            timeType: normalizedDraft.tradeTimeType
        )
        appendPendingConversion(
            normalizedDraft,
            fromFund: fromFund,
            toFund: toFund,
            acceptedDate: acceptedDate,
            conversionID: UUID().uuidString,
            outRecordID: UUID().uuidString,
            inRecordID: UUID().uuidString,
            syncMetadata: syncMetadata
        )
        try save(snapshot)
        await refreshQuotes()
    }

    func importConversionIfNeeded(_ draft: FundConversionDraft, syncMetadata: FundTradeSyncMetadata? = nil) async throws {
        let normalizedDraft = try normalizedConversionDraft(draft)
        if hasImportedConversion(matching: normalizedDraft) {
            if let syncMetadata {
                markImportedConversion(matching: normalizedDraft, syncMetadata: syncMetadata)
                try save(snapshot)
            }
            return
        }
        try await convertFundPosition(normalizedDraft, syncMetadata: syncMetadata)
    }

    var needsJDFinanceTradeOrderReconciliation: Bool {
        let recordsNeedReconciliation = (snapshot.tradeRecords ?? []).contains { record in
            record.syncSource == .jdFinance
                && ((record.waitsForExternalConfirmation ?? false)
                    || record.externalStatus == .waitingExternalConfirmation)
        }
        let pendingTradesNeedReconciliation = (snapshot.pendingTrades ?? []).contains { pendingTrade in
            pendingTrade.syncSource == .jdFinance
                && ((pendingTrade.waitsForExternalConfirmation ?? false)
                    || pendingTrade.externalStatus == .waitingExternalConfirmation)
        }
        let pendingConversionsNeedReconciliation = (snapshot.pendingConversions ?? []).contains { pendingConversion in
            pendingConversion.syncSource == .jdFinance
                && ((pendingConversion.waitsForExternalConfirmation ?? false)
                    || pendingConversion.externalStatus == .waitingExternalConfirmation)
        }
        return recordsNeedReconciliation || pendingTradesNeedReconciliation || pendingConversionsNeedReconciliation
    }

    func jdFinanceTradeOrderStartDate(now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let defaultStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let stateStart = snapshot.jdFinanceSyncState.map { state in
            let anchor = state.lastCompleteTradeOrderSyncAt ?? state.baselineEstablishedAt
            return calendar.date(byAdding: .day, value: -2, to: anchor) ?? anchor
        }
        var candidateDates = [stateStart ?? defaultStart]

        if let trackedPendingStartDate = snapshot.jdFinanceSyncState?.trackedPendingStartDate,
           let date = DateOnlyFormatter.parse(trackedPendingStartDate)
        {
            candidateDates.append(date)
        }

        candidateDates.append(contentsOf: (snapshot.tradeRecords ?? []).compactMap { record in
            guard record.syncSource == .jdFinance,
                  (record.waitsForExternalConfirmation ?? false)
                    || record.externalStatus == .waitingExternalConfirmation
            else {
                return nil
            }
            return DateOnlyFormatter.parse(record.tradeDate)
        })
        candidateDates.append(contentsOf: (snapshot.pendingTrades ?? []).compactMap { pendingTrade in
            guard pendingTrade.syncSource == .jdFinance,
                  (pendingTrade.waitsForExternalConfirmation ?? false)
                    || pendingTrade.externalStatus == .waitingExternalConfirmation
            else {
                return nil
            }
            return DateOnlyFormatter.parse(pendingTrade.tradeDate)
        })
        candidateDates.append(contentsOf: (snapshot.pendingConversions ?? []).compactMap { pendingConversion in
            guard pendingConversion.syncSource == .jdFinance,
                  (pendingConversion.waitsForExternalConfirmation ?? false)
                    || pendingConversion.externalStatus == .waitingExternalConfirmation
            else {
                return nil
            }
            return DateOnlyFormatter.parse(pendingConversion.tradeDate)
        })

        return DateOnlyFormatter.string(from: candidateDates.min() ?? defaultStart)
    }

    func applyJDFinanceAccountTotal(_ amount: Double?, syncedAt: Date) throws {
        try applyJDFinanceSyncMetadata(
            accountTotal: amount,
            confirmations: [],
            syncedAt: syncedAt
        )
    }

    func applyJDFinanceSyncMetadata(
        accountTotal: Double?,
        confirmations: [JDFinanceAutomaticConfirmation],
        syncedAt: Date,
        syncState: JDFinanceSyncState? = nil,
        syncedPendingBuyAmounts: [String: Double?] = [:],
        syncedTodayIncomes: [String: Double?] = [:]
    ) throws {
        guard accountTotal.map({ $0 >= 0 }) == true
                || !confirmations.isEmpty
                || syncState != nil
                || !syncedPendingBuyAmounts.isEmpty
                || !syncedTodayIncomes.isEmpty
        else {
            return
        }

        var updatedSnapshot = snapshot
        if let accountTotal, accountTotal >= 0 {
            let roundedAmount = roundedMoney(accountTotal)
            updatedSnapshot.syncedAccountTotal = PortfolioSyncedAccountTotal(
                source: .jdFinance,
                amount: roundedAmount,
                syncedAt: syncedAt
            )
        }

        let syncedPendingBuyDate = DateOnlyFormatter.string(from: syncedAt)
        for (code, rawAmount) in syncedPendingBuyAmounts {
            guard let index = updatedSnapshot.funds.firstIndex(where: { $0.code == code }),
                  updatedSnapshot.funds[index].status == .holding
            else {
                continue
            }
            let amount = roundedMoney(max(rawAmount ?? 0, 0))
            updatedSnapshot.funds[index].syncedPendingBuyAmount = amount > 0 ? amount : nil
            updatedSnapshot.funds[index].syncedPendingBuyDate = amount > 0 ? syncedPendingBuyDate : nil
        }

        let syncedTodayIncomeDate = DateOnlyFormatter.string(from: syncedAt)
        for (code, rawIncome) in syncedTodayIncomes {
            guard let index = updatedSnapshot.funds.firstIndex(where: { $0.code == code }),
                  updatedSnapshot.funds[index].status == .holding
            else {
                continue
            }
            let income = rawIncome.flatMap { $0.isFinite ? roundedMoney($0) : nil }
            updatedSnapshot.funds[index].syncedTodayIncome = income
            updatedSnapshot.funds[index].syncedTodayIncomeDate = income == nil ? nil : syncedTodayIncomeDate
        }

        for confirmation in confirmations {
            let recordIDs = Set(confirmation.recordIDs)
            var matchedRecordIDs = Set<String>()
            if var records = updatedSnapshot.tradeRecords {
                for index in records.indices where recordIDs.contains(records[index].id) {
                    records[index].syncSource = .jdFinance
                    records[index].syncKey = confirmation.syncKey ?? records[index].syncKey
                    records[index].externalStatus = .externalConfirmed
                    records[index].externalStatusText = confirmation.statusText ?? records[index].externalStatusText
                    records[index].waitsForExternalConfirmation = false
                    matchedRecordIDs.insert(records[index].id)
                }
                updatedSnapshot.tradeRecords = records
            }
            guard matchedRecordIDs == recordIDs else {
                throw PortfolioStoreError.tradeRecordNotFound
            }

            if var pendingTrades = updatedSnapshot.pendingTrades {
                for index in pendingTrades.indices
                where pendingTrades[index].recordID.map(recordIDs.contains) == true
                    || recordIDs.contains(pendingTrades[index].id)
                {
                    pendingTrades[index].syncSource = .jdFinance
                    pendingTrades[index].syncKey = confirmation.syncKey ?? pendingTrades[index].syncKey
                    pendingTrades[index].externalStatus = .externalConfirmed
                    pendingTrades[index].externalStatusText = confirmation.statusText ?? pendingTrades[index].externalStatusText
                    pendingTrades[index].waitsForExternalConfirmation = false
                }
                updatedSnapshot.pendingTrades = pendingTrades
            }
            if var pendingConversions = updatedSnapshot.pendingConversions {
                for index in pendingConversions.indices
                where confirmation.id == pendingConversions[index].id
                    || pendingConversions[index].outRecordID.map(recordIDs.contains) == true
                    || pendingConversions[index].inRecordID.map(recordIDs.contains) == true
                {
                    pendingConversions[index].syncSource = .jdFinance
                    pendingConversions[index].syncKey = confirmation.syncKey ?? pendingConversions[index].syncKey
                    pendingConversions[index].externalStatus = .externalConfirmed
                    pendingConversions[index].externalStatusText = confirmation.statusText ?? pendingConversions[index].externalStatusText
                    pendingConversions[index].waitsForExternalConfirmation = false
                }
                updatedSnapshot.pendingConversions = pendingConversions
            }
        }

        confirmPendingNewFundsCoveredByJDFinanceBaselines(
            in: &updatedSnapshot,
            syncedAt: syncedAt
        )

        if let syncState {
            updatedSnapshot.jdFinanceSyncState = syncState
        }

        try save(updatedSnapshot)
        snapshot = updatedSnapshot
        loadState = .loaded
    }

    private func confirmPendingNewFundsCoveredByJDFinanceBaselines(
        in snapshot: inout PortfolioSnapshot,
        syncedAt: Date
    ) {
        guard var records = snapshot.tradeRecords, !records.isEmpty else { return }
        let baselines = records.filter { record in
            record.kind == .newFund
                && record.status == .confirmed
                && record.syncSource == .jdFinance
                && record.isReconciliationBaseline == true
        }
        guard !baselines.isEmpty else { return }

        var coveredRecordIDs = Set<String>()
        for index in records.indices {
            guard records[index].kind == .newFund,
                  records[index].status == .pending,
                  records[index].syncSource == .jdFinance,
                  let baseline = baselines.first(where: { baseline in
                      baseline.code == records[index].code
                          && baseline.acceptedDate >= records[index].acceptedDate
                          && baseline.createdAt >= records[index].createdAt
                  })
            else {
                continue
            }

            records[index].status = .confirmed
            records[index].confirmedAt = records[index].confirmedAt ?? baseline.confirmedAt ?? syncedAt
            records[index].externalStatus = .externalConfirmed
            records[index].externalStatusText = "已包含在京东持仓对账基线"
            records[index].waitsForExternalConfirmation = false
            coveredRecordIDs.insert(records[index].id)
        }

        guard !coveredRecordIDs.isEmpty else { return }
        snapshot.tradeRecords = records
        snapshot.pendingTrades?.removeAll { pendingTrade in
            pendingTrade.recordID.map(coveredRecordIDs.contains) == true
                || coveredRecordIDs.contains(pendingTrade.id)
        }
        if snapshot.pendingTrades?.isEmpty == true {
            snapshot.pendingTrades = nil
        }
        snapshot.pendingCount = (snapshot.pendingTrades?.count ?? 0)
            + (snapshot.pendingConversions?.count ?? 0)
    }

    func markJDFinanceOrderRepresented(_ orderKey: String, dismissed: Bool) throws {
        let normalizedKey = orderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty,
              var state = snapshot.jdFinanceSyncState
        else {
            throw PortfolioStoreError.invalidJDFinanceSyncState
        }

        if dismissed {
            if !state.dismissedOrderKeys.contains(normalizedKey) {
                state.dismissedOrderKeys.append(normalizedKey)
            }
        } else if !state.representedOrderKeys.contains(normalizedKey) {
            state.representedOrderKeys.append(normalizedKey)
        }
        state.representedOrderKeys.sort()
        state.dismissedOrderKeys.sort()
        snapshot.jdFinanceSyncState = state
        try save(snapshot)
    }

    func resetJDFinanceSyncState() throws {
        guard snapshot.jdFinanceSyncState != nil else { return }
        snapshot.jdFinanceSyncState = nil
        try save(snapshot)
    }

    func applyJDFinanceFullClearance(
        _ holding: JDFinanceMissingLocalHolding,
        syncedAt: Date
    ) throws {
        guard let order = holding.finalOutflowOrder,
              holding.canClear,
              let fundIndex = snapshot.funds.firstIndex(where: { $0.code == holding.code })
        else {
            throw PortfolioStoreError.invalidPosition
        }

        let fund = snapshot.funds[fundIndex]
        let lots = effectiveLots(for: fund)
        let totalShares = roundedStoredShares(lots.reduce(0) { $0 + $1.shares })
        let totalPrincipal = roundedMoney(lots.reduce(0) { $0 + lotPrincipal($1) })
        guard totalShares > 0, totalPrincipal > 0 else {
            throw PortfolioStoreError.invalidPosition
        }

        let holdingIncome = fund.holdingIncome ?? fund.confirmedHoldingIncome ?? 0
        let currentAmount = roundedMoney(fund.currentAmount ?? (totalPrincipal + holdingIncome))
        let baselineAmount = currentAmount > 0 ? currentAmount : totalPrincipal
        let baselineProfit = roundedMoney(baselineAmount - totalPrincipal)
        let tradeDate = DateOnlyFormatter.string(from: syncedAt)
        let orderKey = order.stableOrderKey
            ?? JDFinanceSyncFingerprint.tradeOrderRecord(order, fallbackCode: holding.code)
        var records = snapshot.tradeRecords ?? []
        records.append(FundTradeRecord(
            id: UUID().uuidString,
            kind: .newFund,
            status: .confirmed,
            code: holding.code,
            name: fund.name,
            mode: .amount,
            amount: baselineAmount,
            shares: nil,
            confirmedShares: totalShares,
            price: baselineAmount / totalShares,
            profit: baselineProfit,
            tradeDate: tradeDate,
            tradeTimeType: .before15,
            acceptedDate: tradeDate,
            createdAt: syncedAt,
            confirmedAt: syncedAt,
            failureReason: nil,
            syncSource: .jdFinance,
            syncKey: JDFinanceSyncFingerprint.positionBaseline(code: holding.code, syncedAt: syncedAt),
            externalStatus: .externalConfirmed,
            externalStatusText: "清仓前持仓对账基线",
            waitsForExternalConfirmation: false,
            isReconciliationBaseline: true
        ))
        records.append(FundTradeRecord(
            id: UUID().uuidString,
            kind: .sell,
            status: .confirmed,
            code: holding.code,
            name: fund.name,
            mode: .share,
            amount: order.amount,
            shares: totalShares,
            confirmedShares: totalShares,
            price: order.amount.map { $0 / totalShares },
            tradeDate: order.tradeDate ?? tradeDate,
            tradeTimeType: order.tradeTimeType ?? .before15,
            acceptedDate: order.tradeDate ?? tradeDate,
            createdAt: syncedAt.addingTimeInterval(0.001),
            confirmedAt: syncedAt,
            failureReason: nil,
            syncSource: .jdFinance,
            syncKey: orderKey,
            externalStatus: .externalConfirmed,
            externalStatusText: order.statusText ?? "京东清仓流水已确认",
            waitsForExternalConfirmation: false
        ))
        snapshot.tradeRecords = records
        try rebuildFundPositionFromTradeRecords(code: holding.code)
        if let updatedIndex = snapshot.funds.firstIndex(where: { $0.code == holding.code }) {
            snapshot.funds[updatedIndex].status = .watch
            snapshot.funds[updatedIndex].isIncomeActive = false
            snapshot.funds[updatedIndex].currentAmount = 0
            snapshot.funds[updatedIndex].holdingIncome = 0
            snapshot.funds[updatedIndex].holdingRate = nil
            snapshot.funds[updatedIndex].confirmedHoldingIncome = 0
            snapshot.funds[updatedIndex].confirmedHoldingRate = nil
            snapshot.funds[updatedIndex].pendingAmount = nil
            snapshot.funds[updatedIndex].pendingProfit = nil
        }
        try save(snapshot)
    }

    func performJDFinanceAtomicMutation(
        _ mutation: @MainActor (PortfolioStore) async throws -> Void
    ) async throws {
        await beginDeferringQuoteRefresh()
        do {
            let baseSnapshot = snapshot
            let stagingPerformanceDirectory = FileManager.default.temporaryDirectory
                .appending(
                    path: "fund-pulse-jd-staging-performance-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
            defer {
                try? FileManager.default.removeItem(at: stagingPerformanceDirectory)
            }
            let stagingPerformanceStore = PortfolioPerformanceStore(
                dataDirectory: stagingPerformanceDirectory
            )
            try stagingPerformanceStore.replace(performanceStore.snapshot)
            let stagingRepository = StagedPortfolioRepository(
                dataDirectory: dataDirectory,
                snapshot: baseSnapshot
            )
            let stagingStore = PortfolioStore(
                repository: stagingRepository,
                quoteService: quoteService,
                performanceStore: stagingPerformanceStore,
                now: nowProvider
            )
            stagingStore.load()

            try await mutation(stagingStore)

            guard snapshot == baseSnapshot else {
                throw PortfolioStoreError.concurrentModification
            }
            let stagedSnapshot = stagingStore.snapshot
            try save(stagedSnapshot)
            snapshot = stagedSnapshot
            loadState = .loaded
        } catch {
            await endDeferringQuoteRefresh()
            throw error
        }
        await endDeferringQuoteRefresh()
    }

    private func beginDeferringQuoteRefresh() async {
        quoteRefreshDeferralCount += 1
        if let refreshTask {
            await refreshTask.value
        }
    }

    private func endDeferringQuoteRefresh() async {
        quoteRefreshDeferralCount = max(0, quoteRefreshDeferralCount - 1)
        guard quoteRefreshDeferralCount == 0, hasDeferredQuoteRefresh else { return }

        hasDeferredQuoteRefresh = false
        await refreshQuotes()
    }

    func applyJDFinanceReconciliation(_ notice: JDFinanceReconciliationNotice) async throws {
        guard notice.isOverwritable else {
            throw PortfolioStoreError.invalidPosition
        }

        switch notice.kind {
        case .trade(let recordID, _):
            try overwriteJDFinanceTradeRecord(recordID: recordID, values: notice.values)
        case .conversion(let conversionID, _, _):
            try overwriteJDFinanceConversionRecords(conversionID: conversionID, values: notice.values)
        }

        try save(snapshot)
        await refreshQuotes()
    }

    func editConversion(id: String, with draft: FundConversionDraft) async throws {
        let conversionID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversionID.isEmpty else {
            throw PortfolioStoreError.tradeRecordNotFound
        }
        let normalizedDraft = try normalizedConversionDraft(draft)
        guard let fromIndex = snapshot.funds.firstIndex(where: { $0.code == normalizedDraft.fromCode }) else {
            throw PortfolioStoreError.fundNotFound
        }
        ensureConversionTargetFund(for: normalizedDraft)

        var records = snapshot.tradeRecords ?? []
        let linkedRecords = records.filter { $0.conversionID == conversionID }
        guard !linkedRecords.isEmpty else {
            throw PortfolioStoreError.tradeRecordNotFound
        }

        let fromFund = snapshot.funds.first { $0.code == normalizedDraft.fromCode } ?? snapshot.funds[fromIndex]
        let toFund = snapshot.funds.first { $0.code == normalizedDraft.toCode }
        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: normalizedDraft.tradeDate,
            timeType: normalizedDraft.tradeTimeType
        )
        let outRecordID = linkedRecords.first { $0.kind == .conversionOut }?.id ?? UUID().uuidString
        let inRecordID = linkedRecords.first { $0.kind == .conversionIn }?.id ?? UUID().uuidString

        records.removeAll { $0.conversionID == conversionID }
        records.append(
            pendingConversionOutRecord(
                id: outRecordID,
                conversionID: conversionID,
                draft: normalizedDraft,
                fromFund: fromFund,
                toFund: toFund,
                acceptedDate: acceptedDate,
                createdAt: linkedRecords.map(\.createdAt).min() ?? .now
            )
        )
        records.append(
            pendingConversionInRecord(
                id: inRecordID,
                conversionID: conversionID,
                draft: normalizedDraft,
                fromFund: fromFund,
                toFund: toFund,
                acceptedDate: acceptedDate,
                createdAt: linkedRecords.map(\.createdAt).min() ?? .now
            )
        )
        snapshot.tradeRecords = records
        upsertPendingConversion(
            id: conversionID,
            outRecordID: outRecordID,
            inRecordID: inRecordID,
            draft: normalizedDraft,
            acceptedDate: acceptedDate,
            createdAt: linkedRecords.map(\.createdAt).min() ?? .now,
            failureReason: nil
        )

        let affectedCodes = Set(linkedRecords.map(\.code) + [normalizedDraft.fromCode, normalizedDraft.toCode])
        for code in affectedCodes {
            try rebuildFundPositionFromTradeRecords(code: code)
        }
        try save(snapshot)
        await refreshQuotes()
    }

    func deleteFund(code rawCode: String) async throws {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw PortfolioStoreError.invalidCode
        }

        snapshot.funds.removeAll { $0.code == code }

        var removedRecordIDs = Set<String>()
        var removedConversionIDs = Set<String>()
        var affectedCodes = Set<String>()
        if var records = snapshot.tradeRecords {
            let directlyRemovedRecords = records.filter {
                $0.code == code || $0.linkedCode == code
            }
            removedRecordIDs = Set(directlyRemovedRecords.map(\.id))
            removedConversionIDs = Set(directlyRemovedRecords.compactMap(\.conversionID))

            let removedRecords = records.filter {
                $0.code == code
                    || $0.linkedCode == code
                    || $0.conversionID.map(removedConversionIDs.contains) == true
            }
            removedRecordIDs.formUnion(removedRecords.map(\.id))
            removedConversionIDs.formUnion(removedRecords.compactMap(\.conversionID))
            affectedCodes = Set(
                removedRecords.flatMap { record in
                    [record.code, record.linkedCode].compactMap { $0 }
                }
            )
            affectedCodes.remove(code)

            records.removeAll {
                $0.code == code
                    || $0.linkedCode == code
                    || $0.conversionID.map(removedConversionIDs.contains) == true
            }
            snapshot.tradeRecords = records.isEmpty ? nil : records
        }

        snapshot.pendingTrades?.removeAll {
            $0.code == code || $0.recordID.map(removedRecordIDs.contains) == true
        }
        if snapshot.pendingTrades?.isEmpty == true {
            snapshot.pendingTrades = nil
        }
        snapshot.pendingConversions?.removeAll {
            $0.fromCode == code || $0.toCode == code || removedConversionIDs.contains($0.id)
        }
        if snapshot.pendingConversions?.isEmpty == true {
            snapshot.pendingConversions = nil
        }

        for affectedCode in affectedCodes where snapshot.funds.contains(where: { $0.code == affectedCode }) {
            rebuildPendingTradesFromRecords(for: affectedCode)
            try rebuildFundPositionFromTradeRecords(code: affectedCode)
        }

        resetEmptyPortfolioAggregates(updateTime: nowProvider())
        try save(snapshot)
        await refreshQuotes()
    }

    func editTradeRecord(id: String, with draft: FundTradeDraft) async throws {
        guard var records = snapshot.tradeRecords,
              let index = records.firstIndex(where: { $0.id == id })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }
        let code = records[index].code
        let originalKind = records[index].kind
        guard originalKind == .newFund || draft.action != .buy || draft.mode == .amount else {
            throw PortfolioStoreError.buyTradeRequiresAmount
        }
        guard originalKind == .newFund || draft.action != .sell || draft.mode == .share else {
            throw PortfolioStoreError.sellTradeRequiresShare
        }
        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.tradeDate,
            timeType: draft.tradeTimeType
        )
        let latestQuote: FundQuote?
        let confirmedNetValue: Double?
        if originalKind == .newFund {
            latestQuote = try? await quoteService.fetchQuote(code: code)
            confirmedNetValue = await quoteService.fetchConfirmedNetValue(
                code: code,
                acceptedDate: acceptedDate,
                latestQuote: latestQuote
            )
        } else {
            latestQuote = nil
            confirmedNetValue = nil
        }
        let fundName = snapshot.funds.first { $0.code == code }?.name ?? records[index].name
        records[index].kind = originalKind == .newFund ? .newFund : tradeKind(for: draft.action)
        records[index].status = originalKind == .newFund && confirmedNetValue != nil ? .confirmed : .pending
        records[index].name = fundName
        records[index].mode = draft.mode
        records[index].amount = draft.amount
        records[index].shares = draft.shares
        if originalKind == .newFund, let confirmedNetValue {
            let existingFund = snapshot.funds.first { $0.code == code }
            records[index].confirmedShares = confirmedInitialShares(
                mode: draft.mode,
                amount: draft.amount,
                shares: draft.shares,
                price: confirmedNetValue
            )
            records[index].price = confirmedInitialPrice(
                mode: draft.mode,
                amount: draft.amount,
                confirmedShares: records[index].confirmedShares,
                existingFund: existingFund,
                confirmedNetValue: confirmedNetValue
            )
        } else {
            records[index].confirmedShares = nil
            records[index].price = nil
        }
        records[index].buyFeeRate = draft.buyFeeRate
        records[index].sellFeeMode = draft.sellFeeMode
        records[index].sellFeeValue = draft.sellFeeValue
        records[index].tradeDate = draft.tradeDate
        records[index].tradeTimeType = draft.tradeTimeType
        records[index].acceptedDate = acceptedDate
        records[index].confirmedAt = records[index].status == .confirmed ? .now : nil
        records[index].failureReason = nil
        snapshot.tradeRecords = records
        rebuildPendingTradesFromRecords(for: code)
        try rebuildFundPositionFromTradeRecords(code: code)
        if originalKind == .newFund,
           records[index].status == .pending,
           let records = snapshot.tradeRecords {
            restorePendingInitialPosition(for: code, records: records)
        }
        try save(snapshot)
        await refreshQuotes()
    }

    func deleteTradeRecord(id: String) async throws {
        guard var records = snapshot.tradeRecords,
              let index = records.firstIndex(where: { $0.id == id })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }

        let record = records[index]
        let fundSnapshots = Dictionary(uniqueKeysWithValues: snapshot.funds.map { ($0.code, $0) })
        let removedRecords: [FundTradeRecord]
        let affectedCodes: Set<String>
        if let conversionID = record.conversionID {
            let linkedRecords = records.filter { $0.conversionID == conversionID }
            removedRecords = linkedRecords
            affectedCodes = Set(linkedRecords.flatMap { [$0.code, $0.linkedCode].compactMap { $0 } })
            records.removeAll { $0.conversionID == conversionID }
            snapshot.pendingConversions?.removeAll { $0.id == conversionID }
            if snapshot.pendingConversions?.isEmpty == true {
                snapshot.pendingConversions = nil
            }
        } else {
            removedRecords = [record]
            affectedCodes = [record.code]
            records.remove(at: index)
        }
        snapshot.tradeRecords = records.isEmpty ? nil : records
        snapshot.pendingTrades?.removeAll { $0.recordID == id }
        for code in affectedCodes {
            rebuildPendingTradesFromRecords(for: code)
            let removedRecordsForCode = removedRecords.filter { $0.code == code }
            if !removedRecordsForCode.isEmpty && removedRecordsForCode.allSatisfy({ $0.status == .pending }) {
                try handlePendingOnlyTradeRecordDeletion(
                    code: code,
                    remainingRecords: records,
                    removedRecords: removedRecordsForCode,
                    fundBeforeDeletion: fundSnapshots[code]
                )
            } else if shouldRestoreLegacyFundAfterDeletingTrade(
                code: code,
                remainingRecords: records,
                removedRecords: removedRecords,
                fundBeforeDeletion: fundSnapshots[code]
            ) {
                try restoreLegacyFundAfterDeletingTrade(
                    code: code,
                    removedRecords: removedRecords,
                    fundBeforeDeletion: fundSnapshots[code]
                )
            } else {
                try rebuildFundPositionFromTradeRecords(code: code)
            }
        }
        try save(snapshot)
        await refreshQuotes()
    }

    private func handlePendingOnlyTradeRecordDeletion(
        code: String,
        remainingRecords: [FundTradeRecord],
        removedRecords: [FundTradeRecord],
        fundBeforeDeletion: FundPosition?
    ) throws {
        if shouldRemoveFundAfterDeletingPendingOnlyRecord(
            code: code,
            remainingRecords: remainingRecords,
            removedRecords: removedRecords,
            fundBeforeDeletion: fundBeforeDeletion
        ) {
            snapshot.funds.removeAll { $0.code == code }
            return
        }

        if remainingRecords.contains(where: { $0.code == code && $0.status == .confirmed }) {
            try rebuildFundPositionFromTradeRecords(code: code)
        } else if let fundBeforeDeletion,
                  let index = snapshot.funds.firstIndex(where: { $0.code == code }) {
            snapshot.funds[index] = fundBeforeDeletion
        } else {
            try rebuildFundPositionFromTradeRecords(code: code)
        }
    }

    private func shouldRemoveFundAfterDeletingPendingOnlyRecord(
        code: String,
        remainingRecords: [FundTradeRecord],
        removedRecords: [FundTradeRecord],
        fundBeforeDeletion: FundPosition?
    ) -> Bool {
        guard let fundBeforeDeletion,
              !remainingRecords.contains(where: { $0.code == code })
        else {
            return false
        }

        if removedRecords.contains(where: { $0.kind == .newFund }) {
            return true
        }

        return removedRecords.contains(where: { $0.kind == .conversionIn })
            && isEmptyPendingPlaceholder(fundBeforeDeletion)
    }

    private func isEmptyPendingPlaceholder(_ fund: FundPosition) -> Bool {
        let shares = fund.migratedShares ?? 0
        let principal = fund.migratedPrincipal ?? 0
        let currentAmount = fund.currentAmount ?? 0
        let pendingAmount = fund.pendingAmount ?? 0
        return fund.status.isPendingDisplay
            && effectiveLots(for: fund).isEmpty
            && shares <= 0.0001
            && principal <= 0.0001
            && currentAmount <= 0.0001
            && pendingAmount <= 0.0001
    }

    private func makeFundPosition(
        from draft: FundPositionDraft,
        existingFund: FundPosition?,
        quote: FundQuote?,
        confirmedNetValue: Double?,
        isEditingExistingFund: Bool
    ) throws -> FundPosition {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.positionDate,
            timeType: draft.positionTimeType
        )
        let incomeStartDate = acceptedDate
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = !name.isEmpty ? name : quote?.name ?? existingFund?.name ?? code

        let position: (shares: Double, cost: Double, principal: Double)?
        let status: FundHoldingStatus
        let pendingAmount: Double?
        let pendingProfit: Double?
        let manualCurrentAmount: Double?
        let manualHoldingIncome: Double?
        let manualHoldingRate: Double?
        let manualPrincipal: Double?

        switch draft.positionMode {
        case .amount:
            let netValue = isEditingExistingFund
                ? (quoteNetValue(quote) ?? confirmedNetValue)
                : confirmedNetValue
            if let netValue {
                position = try resolvedPosition(draft: draft, netValue: netValue)
                status = .holding
                pendingAmount = nil
                pendingProfit = nil
                manualCurrentAmount = nil
                manualHoldingIncome = nil
                manualHoldingRate = nil
                manualPrincipal = nil
            } else {
                let amount = draft.positionAmount ?? 0
                guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
                let principal = amount - draft.positionProfit
                guard principal > 0 else { throw PortfolioStoreError.invalidCost }
                position = nil
                status = draft.requiresTradeConfirmation ? .pending : .holding
                pendingAmount = amount
                pendingProfit = draft.positionProfit == 0 ? nil : draft.positionProfit
                manualCurrentAmount = status == .holding ? amount : nil
                manualHoldingIncome = status == .holding ? draft.positionProfit : nil
                manualHoldingRate = status == .holding ? draft.positionProfit / principal * 100 : nil
                manualPrincipal = status == .holding ? principal : nil
            }
        case .share:
            position = try resolvedPosition(draft: draft, netValue: draft.cost)
            status = .holding
            pendingAmount = nil
            pendingProfit = nil
            manualCurrentAmount = nil
            manualHoldingIncome = nil
            manualHoldingRate = nil
            manualPrincipal = nil
        }

        let lots: [FundPositionLot]? = position.map {
            [
                FundPositionLot(
                    id: UUID().uuidString,
                    shares: $0.shares,
                    cost: $0.cost,
                    principal: $0.principal,
                    incomeStartDate: incomeStartDate,
                    positionDate: draft.positionDate,
                    positionTimeType: draft.positionTimeType
                )
            ]
        }
        let resolvedDateText = confirmedNetValue != nil
            ? Self.confirmedDateText(acceptedDate)
            : (quote.map { dateText(for: $0, fallback: existingFund?.dateText ?? "--") } ?? existingFund?.dateText ?? "--")

        return FundPosition(
            code: code,
            name: resolvedName,
            dateText: resolvedDateText,
            todayIncome: existingFund?.todayIncome ?? 0,
            todayRate: quote?.growthRate ?? existingFund?.todayRate ?? 0,
            holdingIncome: manualHoldingIncome,
            holdingRate: manualHoldingRate ?? existingFund?.holdingRate,
            confirmedHoldingIncome: manualHoldingIncome,
            confirmedHoldingRate: manualHoldingRate,
            currentAmount: manualCurrentAmount,
            status: status,
            isUpdated: quote.map(quoteIsUpdated) ?? existingFund?.isUpdated ?? false,
            isIncomeActive: status == .holding,
            migratedShares: position?.shares ?? 0,
            migratedCost: position?.cost,
            migratedPrincipal: position?.principal ?? manualPrincipal ?? 0,
            incomeStartDate: incomeStartDate,
            positionMode: draft.positionMode,
            positionDate: draft.positionDate,
            positionTimeType: draft.positionTimeType,
            pendingAmount: pendingAmount,
            pendingProfit: pendingProfit,
            zdfRange: nil,
            jzNotice: nil,
            memo: draft.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.memo,
            lots: lots,
            intradayRateDate: existingFund?.intradayRateDate,
            intradayRateHistory: existingFund?.intradayRateHistory
        )
    }

    @discardableResult
    private func applyBuy(_ draft: FundTradeDraft, price: Double, to fund: inout FundPosition) throws -> Double {
        let shares: Double
        let lotCost: Double
        switch draft.mode {
        case .amount:
            let amount = draft.amount ?? 0
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            let netAmount = buyNetAmount(totalAmount: amount, feeRate: draft.buyFeeRate)
            shares = roundedStoredShares(netAmount / price)
            guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
            lotCost = roundedCost(amount / shares)
        case .share:
            shares = roundedDisplayedShares(draft.shares ?? 0)
            lotCost = roundedCost(price)
        }
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
        guard lotCost > 0 else { throw PortfolioStoreError.invalidCost }

        let lot = FundPositionLot(
            id: UUID().uuidString,
            shares: shares,
            cost: lotCost,
            principal: draft.mode == .amount ? draft.amount : nil,
            incomeStartDate: TradingCalendar.acceptedTradeDate(
                positionDate: draft.tradeDate,
                timeType: draft.tradeTimeType
            ),
            positionDate: draft.tradeDate,
            positionTimeType: draft.tradeTimeType
        )
        var lots = effectiveLots(for: fund)
        lots.append(lot)
        fund.lots = lots
        fund.positionMode = draft.mode
        fund.positionDate = draft.tradeDate
        fund.positionTimeType = draft.tradeTimeType
        return shares
    }

    private func processPendingTrades(quotes: [String: FundQuote]) async {
        repairPendingTradeIndexFromRecords()
        guard let pendingTrades = snapshot.pendingTrades, !pendingTrades.isEmpty else {
            return
        }

        var remaining: [FundPendingTrade] = []
        for pendingTrade in pendingTrades {
            let draft = pendingTrade.draft
            guard let index = snapshot.funds.firstIndex(where: { $0.code == draft.code }) else {
                remaining.append(pendingTrade)
                continue
            }

            let acceptedDate = TradingCalendar.acceptedTradeDate(
                positionDate: draft.tradeDate,
                timeType: draft.tradeTimeType
            )
            guard shouldConfirmPendingTrade(acceptedDate: acceptedDate) else {
                remaining.append(pendingTrade)
                continue
            }
            // 京东的“支付成功/确认中”只应阻止当日提前入账；进入受理日的
            // 次日后，基金份额确认以本地确认净值为准，不能被旧的外部等待标记永久卡住。
            guard let confirmedNetValue = await quoteService.fetchConfirmedNetValue(
                code: draft.code,
                acceptedDate: acceptedDate,
                latestQuote: quotes[draft.code]
            )
            else {
                remaining.append(pendingTrade)
                continue
            }

            var fund = snapshot.funds[index]
            do {
                let confirmedShares: Double
                switch draft.action {
                case .buy:
                    confirmedShares = try applyBuy(draft, price: confirmedNetValue, to: &fund)
                case .sell:
                    confirmedShares = try applySell(draft, price: confirmedNetValue, from: &fund)
                }
                syncAggregateFields(for: &fund)
                confirmPendingTradeRecord(
                    pendingTrade,
                    draft: draft,
                    fund: fund,
                    acceptedDate: acceptedDate,
                    price: confirmedNetValue,
                    confirmedShares: confirmedShares
                )
                snapshot.funds[index] = fund
            } catch {
                remaining.append(pendingTrade)
            }
        }

        snapshot.pendingTrades = remaining.isEmpty ? nil : remaining
    }

    private func processPendingConversions(quotes: [String: FundQuote]) async {
        guard let pendingConversions = snapshot.pendingConversions, !pendingConversions.isEmpty else {
            return
        }

        var remaining: [FundPendingConversion] = []
        for pendingConversion in pendingConversions {
            let draft = pendingConversion.draft
            // 转换与加仓、减仓、新增持仓共用同一确认门禁：必须先跨过受理日，
            // 再由双方正式净值共同决定是否可以确认。同步状态仅保留为订单元数据。
            guard shouldConfirmPendingTrade(acceptedDate: pendingConversion.acceptedDate) else {
                remaining.append(pendingConversion)
                continue
            }
            guard let fromPrice = await quoteService.fetchConfirmedNetValue(
                code: draft.fromCode,
                acceptedDate: pendingConversion.acceptedDate,
                latestQuote: quotes[draft.fromCode]
            ),
                  let toPrice = await quoteService.fetchConfirmedNetValue(
                    code: draft.toCode,
                    acceptedDate: pendingConversion.acceptedDate,
                    latestQuote: quotes[draft.toCode]
                  )
            else {
                remaining.append(pendingConversion)
                continue
            }
            ensureConversionTargetFund(for: draft)
            guard let fromIndex = snapshot.funds.firstIndex(where: { $0.code == draft.fromCode }) else {
                continue
            }
            guard let toIndex = snapshot.funds.firstIndex(where: { $0.code == draft.toCode }) else {
                remaining.append(pendingConversion)
                continue
            }

            var fromFund = snapshot.funds[fromIndex]
            var toFund = snapshot.funds[toIndex]
            let resolvedAmounts = pendingConversionResolvedAmounts(
                draft: draft,
                fromPrice: fromPrice,
                toPrice: toPrice
            )
            updatePendingConversionRecordsWithResolvedValues(
                pendingConversion,
                draft: draft,
                fromFund: fromFund,
                toFund: toFund,
                fromPrice: fromPrice,
                toPrice: toPrice,
                grossAmount: resolvedAmounts.grossAmount,
                transferAmount: resolvedAmounts.transferAmount,
                sellFee: resolvedAmounts.sellFee,
                buyFee: resolvedAmounts.buyFee,
                confirmedOutShares: resolvedAmounts.confirmedOutShares,
                confirmedInShares: resolvedAmounts.confirmedInShares
            )
            do {
                let outDraft = FundTradeDraft(
                    action: .sell,
                    code: draft.fromCode,
                    mode: .share,
                    amount: nil,
                    shares: draft.shares,
                    tradeDate: draft.tradeDate,
                    tradeTimeType: draft.tradeTimeType,
                    sellFeeMode: draft.sellFeeMode,
                    sellFeeValue: draft.sellFeeValue
                )
                let confirmedOutShares = try applySell(outDraft, price: fromPrice, from: &fromFund)
                let executedAmounts = pendingConversionResolvedAmounts(
                    draft: draft,
                    fromPrice: fromPrice,
                    toPrice: toPrice,
                    confirmedOutShares: confirmedOutShares
                )
                let inDraft = FundTradeDraft(
                    action: .buy,
                    code: draft.toCode,
                    mode: .amount,
                    amount: executedAmounts.transferAmount,
                    shares: nil,
                    tradeDate: draft.tradeDate,
                    tradeTimeType: draft.tradeTimeType,
                    buyFeeRate: draft.buyFeeRate
                )
                let confirmedInShares = try applyBuy(inDraft, price: toPrice, to: &toFund)

                syncAggregateFields(for: &fromFund)
                syncAggregateFields(for: &toFund)
                confirmPendingConversionRecords(
                    pendingConversion,
                    draft: draft,
                    fromFund: fromFund,
                    toFund: toFund,
                    fromPrice: fromPrice,
                    toPrice: toPrice,
                    grossAmount: executedAmounts.grossAmount,
                    transferAmount: executedAmounts.transferAmount,
                    sellFee: executedAmounts.sellFee,
                    buyFee: executedAmounts.buyFee,
                    confirmedOutShares: confirmedOutShares,
                    confirmedInShares: confirmedInShares
                )
                snapshot.funds[fromIndex] = fromFund
                if let refreshedToIndex = snapshot.funds.firstIndex(where: { $0.code == draft.toCode }) {
                    snapshot.funds[refreshedToIndex] = toFund
                }
            } catch PortfolioStoreError.insufficientShares {
                var failed = pendingConversion
                failed.failureReason = "可转换份额不足"
                markPendingConversion(pendingConversion.id, failureReason: failed.failureReason)
                remaining.append(failed)
            } catch {
                var failed = pendingConversion
                failed.failureReason = error.localizedDescription
                markPendingConversion(pendingConversion.id, failureReason: failed.failureReason)
                remaining.append(failed)
            }
        }

        snapshot.pendingConversions = remaining.isEmpty ? nil : remaining
    }

    private func pendingConversionResolvedAmounts(
        draft: FundConversionDraft,
        fromPrice: Double,
        toPrice: Double,
        confirmedOutShares: Double? = nil
    ) -> (
        confirmedOutShares: Double,
        grossAmount: Double,
        sellFee: Double,
        transferAmount: Double,
        buyFee: Double,
        confirmedInShares: Double
    ) {
        let outShares = confirmedOutShares ?? roundedDisplayedShares(draft.shares)
        let grossAmount = roundedMoney(outShares * fromPrice)
        let sellFee = roundedMoney(conversionFeeAmount(grossAmount: grossAmount, mode: draft.sellFeeMode, value: draft.sellFeeValue))
        let transferAmount = roundedMoney(max(grossAmount - sellFee, 0))
        let buyNetAmount = buyNetAmount(totalAmount: transferAmount, feeRate: draft.buyFeeRate)
        let buyFee = roundedMoney(transferAmount - buyNetAmount)
        let confirmedInShares = toPrice > 0 ? roundedStoredShares(buyNetAmount / toPrice) : 0
        return (outShares, grossAmount, sellFee, transferAmount, buyFee, confirmedInShares)
    }

    private func updatePendingConversionRecordsWithResolvedValues(
        _ pendingConversion: FundPendingConversion,
        draft: FundConversionDraft,
        fromFund: FundPosition,
        toFund: FundPosition,
        fromPrice: Double,
        toPrice: Double,
        grossAmount: Double,
        transferAmount: Double,
        sellFee: Double,
        buyFee: Double,
        confirmedOutShares: Double,
        confirmedInShares: Double
    ) {
        let acceptedDate = pendingConversion.acceptedDate
        let conversionID = pendingConversion.id

        _ = updateTradeRecord(
            id: pendingConversion.outRecordID,
            matching: { record in
                record.conversionID == conversionID && record.kind == .conversionOut
            },
            update: { record in
                record.status = .pending
                record.name = fromFund.name
                record.mode = .share
                record.amount = grossAmount
                record.shares = draft.shares
                record.confirmedShares = confirmedOutShares
                record.price = fromPrice
                record.sellFeeMode = draft.sellFeeMode
                record.sellFeeValue = draft.sellFeeValue
                record.feeAmount = sellFee
                record.tradeDate = draft.tradeDate
                record.tradeTimeType = draft.tradeTimeType
                record.acceptedDate = acceptedDate
                record.failureReason = nil
                record.linkedCode = draft.toCode
                record.linkedName = toFund.name
            }
        )

        _ = updateTradeRecord(
            id: pendingConversion.inRecordID,
            matching: { record in
                record.conversionID == conversionID && record.kind == .conversionIn
            },
            update: { record in
                record.status = .pending
                record.name = toFund.name
                record.mode = .amount
                record.amount = transferAmount
                record.shares = nil
                record.confirmedShares = confirmedInShares
                record.price = toPrice
                record.buyFeeRate = draft.buyFeeRate
                record.feeAmount = buyFee
                record.tradeDate = draft.tradeDate
                record.tradeTimeType = draft.tradeTimeType
                record.acceptedDate = acceptedDate
                record.failureReason = nil
                record.linkedCode = draft.fromCode
                record.linkedName = fromFund.name
            }
        )
    }

    private func shouldConfirmPendingTrade(acceptedDate: String) -> Bool {
        guard DateOnlyFormatter.parse(acceptedDate) != nil else {
            return false
        }
        return acceptedDate < DateOnlyFormatter.string(from: nowProvider())
    }

    private func resolvedInitialAcceptedDate(
        draft: FundPositionDraft,
        quote: FundQuote?,
        requestedAcceptedDate: String,
        isCreatingFund: Bool
    ) -> String {
        guard isCreatingFund,
              !draft.requiresTradeConfirmation,
              let netValueDate = quote?.netValueDate,
              !netValueDate.isEmpty
        else {
            return requestedAcceptedDate
        }
        return netValueDate
    }

    private func resolvedInitialConfirmedNetValue(
        _ fetchedNetValue: Double?,
        draft: FundPositionDraft,
        quote: FundQuote?,
        isCreatingFund: Bool
    ) -> Double? {
        if let fetchedNetValue, fetchedNetValue > 0 {
            return fetchedNetValue
        }
        guard isCreatingFund,
              !draft.requiresTradeConfirmation,
              let quote,
              !quote.netValueDate.isEmpty,
              quote.netValue > 0
        else {
            return nil
        }
        return quote.netValue
    }

    private func normalizePrematureInitialConfirmations() {
        guard var records = snapshot.tradeRecords, !records.isEmpty else {
            return
        }

        let fundsByCode = Dictionary(uniqueKeysWithValues: snapshot.funds.map { ($0.code, $0) })
        var affectedCodes = Set<String>()
        for index in records.indices {
            guard records[index].kind == .newFund,
                  records[index].status == .confirmed,
                  records[index].mode == .amount,
                  !isJDFinanceSyncedManualHolding(fundsByCode[records[index].code]),
                  !isManualAmountHolding(fundsByCode[records[index].code]),
                  !shouldConfirmPendingTrade(acceptedDate: records[index].acceptedDate)
            else {
                continue
            }

            records[index].status = .pending
            records[index].confirmedShares = nil
            records[index].price = nil
            records[index].confirmedAt = nil
            records[index].failureReason = nil
            affectedCodes.insert(records[index].code)
        }

        guard !affectedCodes.isEmpty else {
            return
        }

        snapshot.tradeRecords = records
        for code in affectedCodes {
            restorePendingInitialPosition(for: code, records: records)
        }
    }

    private func restorePendingInitialPosition(for code: String, records: [FundTradeRecord]) {
        guard let index = snapshot.funds.firstIndex(where: { $0.code == code }),
              let record = records
                .filter({ $0.code == code && $0.kind == .newFund && $0.status == .pending })
                .sorted(by: { $0.createdAt < $1.createdAt })
                .last
        else {
            return
        }

        var fund = snapshot.funds[index]
        fund.status = .pending
        fund.lots = []
        fund.migratedShares = 0
        fund.migratedCost = nil
        fund.migratedPrincipal = 0
        fund.isIncomeActive = false
        fund.currentAmount = 0
        fund.holdingIncome = 0
        fund.holdingRate = nil
        fund.confirmedHoldingIncome = nil
        fund.confirmedHoldingRate = nil
        fund.pendingAmount = record.amount
        fund.pendingProfit = nil
        fund.positionMode = record.mode
        fund.positionDate = record.tradeDate
        fund.positionTimeType = record.tradeTimeType
        fund.incomeStartDate = record.acceptedDate
        snapshot.funds[index] = fund
    }

    private func isJDFinanceSyncedManualHolding(_ fund: FundPosition?) -> Bool {
        guard let fund,
              fund.positionMode == .amount,
              (fund.pendingAmount ?? 0) > 0,
              fund.memo?.contains("京东金融同步") == true
        else {
            return false
        }
        return true
    }

    private func isManualAmountHolding(_ fund: FundPosition?) -> Bool {
        guard let fund,
              fund.status == .holding,
              fund.positionMode == .amount,
              (fund.pendingAmount ?? 0) > 0
        else {
            return false
        }
        return true
    }

    private func processPendingPositions(quotes: [String: FundQuote]) async {
        for index in snapshot.funds.indices {
            var fund = snapshot.funds[index]
            guard fund.status.isPendingDisplay else {
                continue
            }

            let pendingRecord = pendingInitialTradeRecord(for: fund.code)
            let positionDate = pendingRecord?.tradeDate ?? fund.positionDate ?? DateOnlyFormatter.string(from: .now)
            let positionTimeType = pendingRecord?.tradeTimeType ?? fund.positionTimeType ?? .before15
            let positionMode = pendingRecord?.mode ?? fund.positionMode ?? .amount

            // 无论手工录入还是外部同步，新增基金都只走受理日与正式净值门禁。
            let acceptedDate = TradingCalendar.acceptedTradeDate(
                positionDate: positionDate,
                timeType: positionTimeType
            )
            guard shouldConfirmPendingTrade(acceptedDate: acceptedDate) else {
                continue
            }
            guard let confirmedNetValue = await quoteService.fetchConfirmedNetValue(
                code: fund.code,
                acceptedDate: acceptedDate,
                latestQuote: quotes[fund.code]
            )
            else {
                continue
            }

            do {
                switch positionMode {
                case .amount:
                    guard let amount = pendingRecord?.amount ?? fund.pendingAmount, amount > 0 else {
                        continue
                    }
                    try confirmPendingAmountPosition(
                        amount: amount,
                        profit: fund.pendingProfit ?? 0,
                        price: confirmedNetValue,
                        acceptedDate: acceptedDate,
                        positionDate: positionDate,
                        positionTimeType: positionTimeType,
                        fund: &fund
                    )
                case .share:
                    guard let shares = pendingRecord?.shares ?? pendingRecord?.confirmedShares, shares > 0 else {
                        continue
                    }
                    try confirmPendingSharePosition(
                        shares: shares,
                        price: confirmedNetValue,
                        acceptedDate: acceptedDate,
                        positionDate: positionDate,
                        positionTimeType: positionTimeType,
                        fund: &fund
                    )
                }
                syncAggregateFields(for: &fund)
                confirmInitialTradeRecord(
                    fund: fund,
                    acceptedDate: acceptedDate,
                    price: confirmedNetValue
                )
                snapshot.funds[index] = fund
            } catch {
                continue
            }
        }
    }

    private func pendingInitialTradeRecord(for code: String) -> FundTradeRecord? {
        (snapshot.tradeRecords ?? [])
            .filter { $0.code == code && $0.kind == .newFund && $0.status == .pending }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }

    private func normalizedConversionDraft(_ draft: FundConversionDraft) throws -> FundConversionDraft {
        let fromCode = draft.fromCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let toCode = draft.toCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fromCode.isEmpty, !toCode.isEmpty else {
            throw PortfolioStoreError.invalidCode
        }
        guard fromCode != toCode else {
            throw PortfolioStoreError.invalidConversionTarget
        }
        let shares = roundedDisplayedShares(draft.shares)
        guard shares > 0 else {
            throw PortfolioStoreError.invalidPosition
        }
        return FundConversionDraft(
            fromCode: fromCode,
            toCode: toCode,
            toName: draft.toName?.trimmingCharacters(in: .whitespacesAndNewlines),
            shares: shares,
            tradeDate: draft.tradeDate,
            tradeTimeType: draft.tradeTimeType,
            sellFeeMode: draft.sellFeeMode,
            sellFeeValue: max(draft.sellFeeValue, 0),
            buyFeeRate: max(draft.buyFeeRate, 0)
        )
    }

    private func ensureConversionTargetFund(for draft: FundConversionDraft) {
        guard !snapshot.funds.contains(where: { $0.code == draft.toCode }) else {
            return
        }

        let name = draft.toName?.isEmpty == false ? draft.toName! : draft.toCode
        snapshot.funds.insert(
            FundPosition(
                code: draft.toCode,
                name: name,
                dateText: "--",
                todayIncome: 0,
                todayRate: 0,
                holdingRate: nil,
                status: .pending,
                isUpdated: false,
                isIncomeActive: false,
                migratedShares: 0,
                migratedCost: 0,
                migratedPrincipal: 0,
                positionMode: .amount,
                positionDate: draft.tradeDate,
                positionTimeType: draft.tradeTimeType,
                lots: []
            ),
            at: 0
        )
    }

    private func availableShares(for fund: FundPosition) -> Double {
        effectiveLots(for: fund).reduce(0) { $0 + $1.shares }
    }

    private func appendPendingConversion(
        _ draft: FundConversionDraft,
        fromFund: FundPosition,
        toFund: FundPosition?,
        acceptedDate: String,
        conversionID: String,
        outRecordID: String,
        inRecordID: String,
        syncMetadata: FundTradeSyncMetadata? = nil
    ) {
        let createdAt = Date.now
        let targetFund = toFund ?? snapshot.funds.first { $0.code == draft.toCode }
        var pendingConversions = snapshot.pendingConversions ?? []
        pendingConversions.append(
            FundPendingConversion(
                id: conversionID,
                outRecordID: outRecordID,
                inRecordID: inRecordID,
                fromCode: draft.fromCode,
                toCode: draft.toCode,
                toName: targetFund?.name ?? draft.toName,
                shares: draft.shares,
                tradeDate: draft.tradeDate,
                tradeTimeType: draft.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: createdAt,
                sellFeeMode: draft.sellFeeMode,
                sellFeeValue: draft.sellFeeValue,
                buyFeeRate: draft.buyFeeRate,
                syncSource: syncMetadata?.source,
                syncKey: syncMetadata?.syncKey,
                externalStatus: syncMetadata?.externalStatus,
                externalStatusText: syncMetadata?.externalStatusText,
                waitsForExternalConfirmation: syncMetadata?.waitsForExternalConfirmation
            )
        )
        snapshot.pendingConversions = pendingConversions
        appendTradeRecord(
            pendingConversionOutRecord(
                id: outRecordID,
                conversionID: conversionID,
                draft: draft,
                fromFund: fromFund,
                toFund: targetFund,
                acceptedDate: acceptedDate,
                createdAt: createdAt,
                syncMetadata: syncMetadata
            )
        )
        appendTradeRecord(
            pendingConversionInRecord(
                id: inRecordID,
                conversionID: conversionID,
                draft: draft,
                fromFund: fromFund,
                toFund: targetFund,
                acceptedDate: acceptedDate,
                createdAt: createdAt,
                syncMetadata: syncMetadata
            )
        )
    }

    private func upsertPendingConversion(
        id: String,
        outRecordID: String?,
        inRecordID: String?,
        draft: FundConversionDraft,
        acceptedDate: String,
        createdAt: Date,
        failureReason: String?
    ) {
        var pendingConversions = (snapshot.pendingConversions ?? []).filter { $0.id != id }
        pendingConversions.append(
            FundPendingConversion(
                id: id,
                outRecordID: outRecordID,
                inRecordID: inRecordID,
                fromCode: draft.fromCode,
                toCode: draft.toCode,
                toName: draft.toName,
                shares: draft.shares,
                tradeDate: draft.tradeDate,
                tradeTimeType: draft.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: createdAt,
                sellFeeMode: draft.sellFeeMode,
                sellFeeValue: draft.sellFeeValue,
                buyFeeRate: draft.buyFeeRate,
                failureReason: failureReason
            )
        )
        snapshot.pendingConversions = pendingConversions
    }

    private func pendingConversionOutRecord(
        id: String,
        conversionID: String,
        draft: FundConversionDraft,
        fromFund: FundPosition,
        toFund: FundPosition?,
        acceptedDate: String,
        createdAt: Date,
        syncMetadata: FundTradeSyncMetadata? = nil
    ) -> FundTradeRecord {
        FundTradeRecord(
            id: id,
            kind: .conversionOut,
            status: .pending,
            code: draft.fromCode,
            name: fromFund.name,
            mode: .share,
            amount: nil,
            shares: draft.shares,
            confirmedShares: nil,
            price: nil,
            tradeDate: draft.tradeDate,
            tradeTimeType: draft.tradeTimeType,
            acceptedDate: acceptedDate,
            createdAt: createdAt,
            confirmedAt: nil,
            failureReason: nil,
            sellFeeMode: draft.sellFeeMode,
            sellFeeValue: draft.sellFeeValue,
            conversionID: conversionID,
            linkedCode: draft.toCode,
            linkedName: toFund?.name ?? draft.toName,
            syncSource: syncMetadata?.source,
            syncKey: syncMetadata?.syncKey,
            externalStatus: syncMetadata?.externalStatus,
            externalStatusText: syncMetadata?.externalStatusText,
            waitsForExternalConfirmation: syncMetadata?.waitsForExternalConfirmation
        )
    }

    private func pendingConversionInRecord(
        id: String,
        conversionID: String,
        draft: FundConversionDraft,
        fromFund: FundPosition,
        toFund: FundPosition?,
        acceptedDate: String,
        createdAt: Date,
        syncMetadata: FundTradeSyncMetadata? = nil
    ) -> FundTradeRecord {
        FundTradeRecord(
            id: id,
            kind: .conversionIn,
            status: .pending,
            code: draft.toCode,
            name: toFund?.name ?? draft.toName ?? draft.toCode,
            mode: .amount,
            amount: nil,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: draft.tradeDate,
            tradeTimeType: draft.tradeTimeType,
            acceptedDate: acceptedDate,
            createdAt: createdAt,
            confirmedAt: nil,
            failureReason: nil,
            buyFeeRate: draft.buyFeeRate,
            conversionID: conversionID,
            linkedCode: draft.fromCode,
            linkedName: fromFund.name,
            syncSource: syncMetadata?.source,
            syncKey: syncMetadata?.syncKey,
            externalStatus: syncMetadata?.externalStatus,
            externalStatusText: syncMetadata?.externalStatusText,
            waitsForExternalConfirmation: syncMetadata?.waitsForExternalConfirmation
        )
    }

    private func appendPendingTrade(
        _ draft: FundTradeDraft,
        fund: FundPosition,
        acceptedDate: String,
        syncMetadata: FundTradeSyncMetadata? = nil
    ) {
        let record = tradeRecord(
            kind: tradeKind(for: draft.action),
            status: .pending,
            code: draft.code,
            name: fund.name,
            mode: draft.mode,
            amount: draft.amount,
            shares: draft.shares,
            confirmedShares: nil,
            price: nil,
            buyFeeRate: draft.buyFeeRate,
            sellFeeMode: draft.sellFeeMode,
            sellFeeValue: draft.sellFeeValue,
            tradeDate: draft.tradeDate,
            tradeTimeType: draft.tradeTimeType,
            acceptedDate: acceptedDate,
            createdAt: .now,
            confirmedAt: nil,
            syncMetadata: syncMetadata
        )
        var pendingTrades = snapshot.pendingTrades ?? []
        pendingTrades.append(
            FundPendingTrade(
                id: UUID().uuidString,
                recordID: record.id,
                action: draft.action,
                code: draft.code,
                mode: draft.mode,
                amount: draft.amount,
                shares: draft.shares,
                tradeDate: draft.tradeDate,
                tradeTimeType: draft.tradeTimeType,
                createdAt: .now,
                buyFeeRate: draft.buyFeeRate,
                sellFeeMode: draft.sellFeeMode,
                sellFeeValue: draft.sellFeeValue,
                syncSource: syncMetadata?.source,
                syncKey: syncMetadata?.syncKey,
                externalStatus: syncMetadata?.externalStatus,
                externalStatusText: syncMetadata?.externalStatusText,
                waitsForExternalConfirmation: syncMetadata?.waitsForExternalConfirmation
            )
        )
        snapshot.pendingTrades = pendingTrades
        appendTradeRecord(record)
    }

    private func confirmPendingAmountPosition(
        amount: Double,
        profit: Double,
        price: Double,
        acceptedDate: String,
        positionDate: String,
        positionTimeType: PositionTimeType,
        fund: inout FundPosition
    ) throws {
        guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
        guard price > 0 else { throw PortfolioStoreError.missingNetValue }
        let principal = amount - profit
        guard principal > 0 else { throw PortfolioStoreError.invalidCost }
        let shares = roundedStoredShares(amount / price)
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
        let cost = roundedCost(principal / shares)
        guard cost > 0 else { throw PortfolioStoreError.invalidCost }

        let incomeStartDate = acceptedDate
        let lot = FundPositionLot(
            id: UUID().uuidString,
            shares: shares,
            cost: cost,
            principal: principal,
            incomeStartDate: incomeStartDate,
            positionDate: positionDate,
            positionTimeType: positionTimeType
        )
        fund.lots = [lot]
        fund.incomeStartDate = incomeStartDate
        fund.dateText = Self.confirmedDateText(acceptedDate)
        fund.positionMode = .amount
        fund.positionDate = positionDate
        fund.positionTimeType = positionTimeType
        fund.pendingAmount = nil
        fund.pendingProfit = nil
    }

    private func confirmPendingSharePosition(
        shares: Double,
        price: Double,
        acceptedDate: String,
        positionDate: String,
        positionTimeType: PositionTimeType,
        fund: inout FundPosition
    ) throws {
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
        guard price > 0 else { throw PortfolioStoreError.missingNetValue }
        let lot = FundPositionLot(
            id: UUID().uuidString,
            shares: roundedDisplayedShares(shares),
            cost: roundedCost(price),
            incomeStartDate: acceptedDate,
            positionDate: positionDate,
            positionTimeType: positionTimeType
        )
        fund.lots = [lot]
        fund.incomeStartDate = acceptedDate
        fund.dateText = Self.confirmedDateText(acceptedDate)
        fund.positionMode = .share
        fund.positionDate = positionDate
        fund.positionTimeType = positionTimeType
        fund.pendingAmount = nil
        fund.pendingProfit = nil
    }

    @discardableResult
    private func applySell(_ draft: FundTradeDraft, price: Double, from fund: inout FundPosition) throws -> Double {
        let sellShares: Double
        switch draft.mode {
        case .amount:
            let amount = draft.amount ?? 0
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            sellShares = roundedStoredShares(amount / price)
        case .share:
            sellShares = roundedDisplayedShares(draft.shares ?? 0)
        }
        guard sellShares > 0 else { throw PortfolioStoreError.invalidPosition }

        var remainingToSell = sellShares
        var lots = effectiveLots(for: fund)
            .sorted { lhs, rhs in
                if lhs.incomeStartDate == rhs.incomeStartDate {
                    return lhs.positionDate < rhs.positionDate
                }
                return lhs.incomeStartDate < rhs.incomeStartDate
            }
        let availableShares = lots.reduce(0) { $0 + $1.shares }
        guard sellShares <= availableShares + PortfolioPrecision.shareAvailabilityTolerance else {
            throw PortfolioStoreError.insufficientShares
        }

        for index in lots.indices {
            guard remainingToSell > 0 else { break }
            let originalShares = lots[index].shares
            let deducted = min(originalShares, remainingToSell)
            let remainingShares = roundedStoredShares(originalShares - deducted)
            lots[index].shares = remainingShares
            if let principal = lots[index].principal {
                lots[index].principal = remainingPrincipal(
                    originalPrincipal: principal,
                    originalShares: originalShares,
                    remainingShares: remainingShares
                )
            }
            remainingToSell = roundedStoredShares(remainingToSell - deducted)
        }
        fund.lots = lots.filter { $0.shares > 0 }
        fund.positionDate = draft.tradeDate
        fund.positionTimeType = draft.tradeTimeType
        return sellShares
    }

    private func effectiveLots(for fund: FundPosition) -> [FundPositionLot] {
        if let lots = fund.lots {
            return lots
        }
        guard let shares = fund.migratedShares,
              let cost = fund.migratedCost,
              shares > 0,
              cost > 0
        else {
            return []
        }
        return [
            FundPositionLot(
                id: "\(fund.code)-legacy",
                shares: shares,
                cost: cost,
                incomeStartDate: fund.incomeStartDate ?? "",
                positionDate: fund.positionDate ?? "",
                positionTimeType: fund.positionTimeType ?? .before15
            )
        ]
    }

    private func syncAggregateFields(for fund: inout FundPosition) {
        let lots = effectiveLots(for: fund)
        let totalShares = roundedStoredShares(lots.reduce(0) { $0 + $1.shares })
        let totalCost = lots.reduce(0) { $0 + lotPrincipal($1) }
        fund.migratedShares = totalShares
        fund.migratedCost = totalShares > 0 ? roundedCost(totalCost / totalShares) : 0
        fund.migratedPrincipal = totalCost
        fund.status = totalShares > 0 ? .holding : .pending
        if totalShares > 0 {
            fund.pendingAmount = nil
            fund.pendingProfit = nil
        } else {
            // 整仓卖出或转换后立即清除旧金额，避免本次刷新仍被误计为待确认。
            fund.currentAmount = 0
        }
    }

    private func rebuildPendingTradesFromRecords(for code: String) {
        let existing = (snapshot.pendingTrades ?? []).filter { $0.code != code }
        let rebuilt = (snapshot.tradeRecords ?? [])
            .filter { $0.code == code && $0.status == .pending && ($0.kind == .buy || $0.kind == .sell) }
            .map { record in
                FundPendingTrade(
                    id: "pending-\(record.id)",
                    recordID: record.id,
                    action: record.kind == .sell ? .sell : .buy,
                    code: record.code,
                    mode: record.mode,
                    amount: record.amount,
                    shares: record.shares,
                    tradeDate: record.tradeDate,
                    tradeTimeType: record.tradeTimeType,
                    createdAt: record.createdAt,
                    buyFeeRate: record.buyFeeRate,
                    sellFeeMode: record.sellFeeMode,
                    sellFeeValue: record.sellFeeValue,
                    syncSource: record.syncSource,
                    syncKey: record.syncKey,
                    externalStatus: record.externalStatus,
                    externalStatusText: record.externalStatusText,
                    waitsForExternalConfirmation: record.waitsForExternalConfirmation
                )
            }
        let next = existing + rebuilt
        snapshot.pendingTrades = next.isEmpty ? nil : next
    }

    private func repairPendingTradeIndexFromRecords() {
        let recordCodes = Set((snapshot.tradeRecords ?? []).compactMap { record -> String? in
            guard record.status == .pending,
                  record.kind == .buy || record.kind == .sell
            else {
                return nil
            }
            return record.code
        })
        let indexedCodes = Set((snapshot.pendingTrades ?? []).map(\.code))

        for code in recordCodes.union(indexedCodes).sorted() {
            rebuildPendingTradesFromRecords(for: code)
        }
        snapshot.pendingCount = (snapshot.pendingTrades?.count ?? 0)
            + (snapshot.pendingConversions?.count ?? 0)
    }

    private func rebuildFundPositionFromTradeRecords(code: String) throws {
        guard let index = snapshot.funds.firstIndex(where: { $0.code == code }) else {
            return
        }

        var fund = snapshot.funds[index]
        let records = (snapshot.tradeRecords ?? [])
            .filter { $0.code == code && $0.status == .confirmed }
            .sorted { lhs, rhs in
                if lhs.acceptedDate != rhs.acceptedDate {
                    return lhs.acceptedDate < rhs.acceptedDate
                }
                return lhs.createdAt < rhs.createdAt
            }
        guard !records.isEmpty else {
            fund.lots = []
            fund.pendingAmount = nil
            fund.pendingProfit = nil
            syncAggregateFields(for: &fund)
            snapshot.funds[index] = fund
            return
        }

        var lots: [FundPositionLot] = []
        var didRebuildPosition = false
        for record in records {
            switch record.kind {
            case .newFund:
                lots = []
                didRebuildPosition = true
                fund.positionMode = record.mode
                fund.positionDate = record.tradeDate
                fund.positionTimeType = record.tradeTimeType
                fund.incomeStartDate = record.acceptedDate
                fund.dateText = Self.confirmedDateText(record.acceptedDate)
                if let lot = lot(from: record) {
                    lots = [lot]
                }
            case .buy, .conversionIn:
                guard let lot = lot(from: record) else { continue }
                lots.append(lot)
                didRebuildPosition = true
                fund.positionMode = record.mode
                fund.positionDate = record.tradeDate
                fund.positionTimeType = record.tradeTimeType
            case .sell, .conversionOut:
                guard didRebuildPosition else { continue }
                let sellShares = try confirmedShares(for: record)
                lots = try lotsAfterSelling(shares: sellShares, from: lots)
                fund.positionDate = record.tradeDate
                fund.positionTimeType = record.tradeTimeType
            }
        }

        fund.lots = lots
        syncAggregateFields(for: &fund)
        snapshot.funds[index] = fund
    }

    private func resetEmptyPortfolioAggregates(updateTime: Date) {
        guard snapshot.funds.isEmpty else { return }
        snapshot.updateTime = updateTime
        snapshot.totalAmount = 0
        snapshot.holdingIncome = 0
        snapshot.holdingIncomeRate = 0
        snapshot.todayIncome = 0
        snapshot.todayIncomeRate = 0
        snapshot.pendingCount = (snapshot.pendingTrades?.count ?? 0) + (snapshot.pendingConversions?.count ?? 0)
        snapshot.syncedAccountTotal = nil
    }

    private func shouldRestoreLegacyFundAfterDeletingTrade(
        code: String,
        remainingRecords: [FundTradeRecord],
        removedRecords: [FundTradeRecord],
        fundBeforeDeletion: FundPosition?
    ) -> Bool {
        guard let fundBeforeDeletion,
              removedRecords.contains(where: { $0.code == code && $0.status == .confirmed })
        else {
            return false
        }

        let remainingConfirmedRecords = remainingRecords.filter { $0.code == code && $0.status == .confirmed }
        if remainingConfirmedRecords.contains(where: { $0.kind == .newFund }) {
            return false
        }

        return !effectiveLots(for: fundBeforeDeletion).isEmpty || (fundBeforeDeletion.migratedShares ?? 0) > 0
    }

    private func restoreLegacyFundAfterDeletingTrade(
        code: String,
        removedRecords: [FundTradeRecord],
        fundBeforeDeletion: FundPosition?
    ) throws {
        guard let index = snapshot.funds.firstIndex(where: { $0.code == code }),
              var fund = fundBeforeDeletion
        else {
            return
        }

        var lots = effectiveLots(for: fund)
        let recordsToUndo = removedRecords
            .filter { $0.code == code && $0.status == .confirmed }
            .sorted { lhs, rhs in
                if lhs.acceptedDate != rhs.acceptedDate {
                    return lhs.acceptedDate > rhs.acceptedDate
                }
                return lhs.createdAt > rhs.createdAt
            }

        for record in recordsToUndo {
            switch record.kind {
            case .newFund, .buy, .conversionIn:
                let shares = try confirmedShares(for: record)
                lots = try lotsAfterRemovingRecentlyAdded(shares: shares, from: lots)
            case .sell, .conversionOut:
                if let lot = restoredLegacyLot(from: record, fund: fund) {
                    lots.append(lot)
                }
            }
        }

        fund.lots = lots
        syncAggregateFields(for: &fund)
        snapshot.funds[index] = fund
    }

    private func lotsAfterRemovingRecentlyAdded(
        shares sharesToRemove: Double,
        from sourceLots: [FundPositionLot]
    ) throws -> [FundPositionLot] {
        var lots = sourceLots
        var remainingShares = roundedStoredShares(sharesToRemove)

        while remainingShares > 0.0001, !lots.isEmpty {
            let index = lots.count - 1
            let lotShares = roundedStoredShares(lots[index].shares)
            if lotShares <= remainingShares + 0.0001 {
                remainingShares = roundedStoredShares(remainingShares - lotShares)
                lots.removeLast()
            } else {
                let nextShares = roundedStoredShares(lotShares - remainingShares)
                lots[index].shares = nextShares
                if let principal = lots[index].principal {
                    lots[index].principal = remainingPrincipal(
                        originalPrincipal: principal,
                        originalShares: lotShares,
                        remainingShares: nextShares
                    )
                }
                remainingShares = 0
            }
        }

        guard remainingShares <= 0.0001 else {
            throw PortfolioStoreError.insufficientShares
        }
        return lots
    }

    private func restoredLegacyLot(from record: FundTradeRecord, fund: FundPosition) -> FundPositionLot? {
        guard let shares = try? confirmedShares(for: record),
              shares > 0
        else {
            return nil
        }

        let cost: Double
        if let migratedCost = fund.migratedCost, migratedCost > 0 {
            cost = migratedCost
        } else if let amount = record.amount, amount > 0 {
            cost = roundedCost(amount / shares)
        } else if let price = record.price, price > 0 {
            cost = price
        } else {
            return nil
        }

        return FundPositionLot(
            id: "restored-\(record.id)",
            shares: shares,
            cost: roundedCost(cost),
            incomeStartDate: fund.incomeStartDate ?? record.acceptedDate,
            positionDate: record.tradeDate,
            positionTimeType: record.tradeTimeType
        )
    }

    private func lot(from record: FundTradeRecord) -> FundPositionLot? {
        guard let shares = try? confirmedShares(for: record),
              shares > 0
        else {
            return nil
        }

        let cost: Double
        if record.kind == .newFund,
           record.mode == .amount,
           let amount = record.amount,
           amount > 0 {
            let principal = amount - (record.profit ?? 0)
            guard principal > 0 else { return nil }
            cost = roundedCost(principal / shares)
        } else if (record.kind == .buy || record.kind == .conversionIn),
                  record.mode == .amount,
                  let amount = record.amount,
                  amount > 0,
                  shares > 0 {
            cost = roundedCost(amount / shares)
        } else if let price = record.price, price > 0 {
            cost = price
        } else if let amount = record.amount, amount > 0 {
            cost = roundedCost(amount / shares)
        } else {
            return nil
        }

        return FundPositionLot(
            id: record.id,
            shares: roundedStoredShares(shares),
            cost: roundedCost(cost),
            principal: lotPrincipal(from: record, shares: shares, cost: cost),
            incomeStartDate: record.acceptedDate,
            positionDate: record.tradeDate,
            positionTimeType: record.tradeTimeType
        )
    }

    private func confirmedShares(for record: FundTradeRecord) throws -> Double {
        if let amountModeShares = amountModeConfirmedShares(for: record) {
            return amountModeShares
        }
        if let shares = record.confirmedShares ?? record.shares, shares > 0 {
            return roundedStoredShares(shares)
        }
        if let amount = record.amount,
           let price = record.price,
           amount > 0,
           price > 0 {
            return roundedStoredShares(amount / price)
        }
        throw PortfolioStoreError.invalidPosition
    }

    private func amountModeConfirmedShares(for record: FundTradeRecord) -> Double? {
        guard record.status == .confirmed,
              record.mode == .amount,
              let amount = record.amount,
              let price = record.price,
              amount > 0,
              price > 0
        else {
            return nil
        }

        switch record.kind {
        case .newFund, .sell:
            return roundedStoredShares(amount / price)
        case .buy, .conversionIn:
            let netAmount = buyNetAmount(totalAmount: amount, feeRate: record.buyFeeRate)
            return roundedStoredShares(netAmount / price)
        case .conversionOut:
            return nil
        }
    }

    private func repairAmountModeSharePrecisionFromTradeRecords() {
        guard var records = snapshot.tradeRecords, !records.isEmpty else {
            return
        }

        var changedCodes = Set<String>()
        var didChange = false
        for index in records.indices {
            guard let shares = amountModeConfirmedShares(for: records[index]) else {
                continue
            }

            if abs((records[index].confirmedShares ?? 0) - shares) > 0.000001 {
                records[index].confirmedShares = shares
                didChange = true
            }
            if records[index].kind == .newFund || records[index].kind == .buy || records[index].kind == .conversionIn,
               records[index].shares != nil {
                records[index].shares = nil
                didChange = true
            }
            changedCodes.insert(records[index].code)
        }

        guard didChange else { return }
        snapshot.tradeRecords = records
        for code in changedCodes {
            try? rebuildFundPositionFromTradeRecords(code: code)
        }
    }

    private func lotsAfterSelling(shares sellShares: Double, from sourceLots: [FundPositionLot]) throws -> [FundPositionLot] {
        guard sellShares > 0 else { throw PortfolioStoreError.invalidPosition }
        var remainingToSell = sellShares
        var lots = sourceLots.sorted { lhs, rhs in
            if lhs.incomeStartDate == rhs.incomeStartDate {
                return lhs.positionDate < rhs.positionDate
            }
            return lhs.incomeStartDate < rhs.incomeStartDate
        }
        let availableShares = lots.reduce(0) { $0 + $1.shares }
        guard sellShares <= availableShares + PortfolioPrecision.shareAvailabilityTolerance else {
            throw PortfolioStoreError.insufficientShares
        }

        for index in lots.indices {
            guard remainingToSell > 0 else { break }
            let originalShares = lots[index].shares
            let deducted = min(originalShares, remainingToSell)
            let remainingShares = roundedStoredShares(originalShares - deducted)
            lots[index].shares = remainingShares
            if let principal = lots[index].principal {
                lots[index].principal = remainingPrincipal(
                    originalPrincipal: principal,
                    originalShares: originalShares,
                    remainingShares: remainingShares
                )
            }
            remainingToSell = roundedStoredShares(remainingToSell - deducted)
        }
        return lots.filter { $0.shares > 0 }
    }

    private func appendInitialTradeRecord(
        draft: FundPositionDraft,
        fund: FundPosition,
        acceptedDate: String,
        confirmedNetValue: Double?
    ) {
        let status: FundTradeRecordStatus = fund.status.isPendingDisplay ? .pending : .confirmed
        let confirmedShares: Double? = {
            guard status == .confirmed,
                  let shares = fund.migratedShares,
                  shares > 0
            else {
                return nil
            }
            return shares
        }()
        let amount = draft.positionAmount ?? confirmedShares.flatMap { shares in
            (fund.migratedCost ?? confirmedNetValue).map { roundedMoney(shares * $0) }
        }
        let price = initialRecordPrice(
            mode: draft.positionMode,
            status: status,
            amount: amount,
            confirmedShares: confirmedShares,
            fund: fund,
            confirmedNetValue: confirmedNetValue
        )
        let record = tradeRecord(
            kind: .newFund,
            status: status,
            code: fund.code,
            name: fund.name,
            mode: draft.positionMode,
            amount: amount,
            shares: draft.shares,
            confirmedShares: confirmedShares,
            price: price,
            profit: draft.positionMode == .amount ? draft.positionProfit : nil,
            tradeDate: draft.positionDate,
            tradeTimeType: draft.positionTimeType,
            acceptedDate: acceptedDate,
            createdAt: .now,
            confirmedAt: status == .confirmed ? .now : nil
        )
        appendTradeRecord(record)
    }

    private func initialRecordPrice(
        mode: PositionMode,
        status: FundTradeRecordStatus,
        amount: Double?,
        confirmedShares: Double?,
        fund: FundPosition,
        confirmedNetValue: Double?
    ) -> Double? {
        guard status == .confirmed else { return nil }
        switch mode {
        case .amount:
            if let amount, let confirmedShares, amount > 0, confirmedShares > 0 {
                return roundedCost(amount / confirmedShares)
            }
            return confirmedNetValue
        case .share:
            return fund.migratedCost ?? confirmedNetValue
        }
    }

    private func confirmedInitialShares(
        mode: PositionMode,
        amount: Double?,
        shares: Double?,
        price: Double
    ) -> Double? {
        guard price > 0 else { return nil }
        switch mode {
        case .amount:
            guard let amount, amount > 0 else { return nil }
            return roundedStoredShares(amount / price)
        case .share:
            guard let shares, shares > 0 else { return nil }
            return roundedDisplayedShares(shares)
        }
    }

    private func confirmedInitialPrice(
        mode: PositionMode,
        amount: Double?,
        confirmedShares: Double?,
        existingFund: FundPosition?,
        confirmedNetValue: Double
    ) -> Double? {
        switch mode {
        case .amount:
            if let amount, let confirmedShares, amount > 0, confirmedShares > 0 {
                return roundedCost(amount / confirmedShares)
            }
            return confirmedNetValue
        case .share:
            return existingFund?.migratedCost ?? confirmedNetValue
        }
    }

    private func appendConfirmedTradeRecord(
        draft: FundTradeDraft,
        fund: FundPosition,
        acceptedDate: String,
        price: Double,
        confirmedShares: Double
    ) {
        appendTradeRecord(
            tradeRecord(
                kind: tradeKind(for: draft.action),
                status: .confirmed,
                code: fund.code,
                name: fund.name,
                mode: draft.mode,
                amount: draft.amount,
                shares: draft.shares,
                confirmedShares: confirmedShares,
                price: price,
                buyFeeRate: draft.buyFeeRate,
                sellFeeMode: draft.sellFeeMode,
                sellFeeValue: draft.sellFeeValue,
                tradeDate: draft.tradeDate,
                tradeTimeType: draft.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: .now,
                confirmedAt: .now
            )
        )
    }

    private func confirmPendingTradeRecord(
        _ pendingTrade: FundPendingTrade,
        draft: FundTradeDraft,
        fund: FundPosition,
        acceptedDate: String,
        price: Double,
        confirmedShares: Double
    ) {
        let kind = tradeKind(for: draft.action)
        let recordID = pendingTrade.recordID
        if updateTradeRecord(
            id: recordID,
            matching: { record in
                record.status == .pending
                    && record.kind == kind
                    && record.code == draft.code
                    && record.tradeDate == draft.tradeDate
                    && record.acceptedDate == acceptedDate
            },
            update: { record in
                record.status = .confirmed
                record.name = fund.name
                record.price = price
                record.confirmedShares = confirmedShares
                record.buyFeeRate = draft.buyFeeRate
                record.sellFeeMode = draft.sellFeeMode
                record.sellFeeValue = draft.sellFeeValue
                record.confirmedAt = .now
                record.externalStatus = .externalConfirmed
                record.waitsForExternalConfirmation = false
            }
        ) {
            return
        }

        if updateTradeRecord(
            id: nil,
            matching: { record in
                tradeRecordMatches(record, draft: draft, code: draft.code)
            },
            update: { record in
                record.status = .confirmed
                record.name = fund.name
                record.price = record.price ?? price
                record.confirmedShares = record.confirmedShares ?? confirmedShares
                record.buyFeeRate = draft.buyFeeRate
                record.sellFeeMode = draft.sellFeeMode
                record.sellFeeValue = draft.sellFeeValue
                record.confirmedAt = record.confirmedAt ?? .now
                record.externalStatus = .externalConfirmed
                record.waitsForExternalConfirmation = false
                if let syncMetadata = syncMetadata(from: pendingTrade) {
                    record.syncSource = syncMetadata.source
                    record.syncKey = syncMetadata.syncKey ?? record.syncKey
                }
            }
        ) {
            return
        }

        appendTradeRecord(
            tradeRecord(
                kind: kind,
                status: .confirmed,
                code: fund.code,
                name: fund.name,
                mode: draft.mode,
                amount: draft.amount,
                shares: draft.shares,
                confirmedShares: confirmedShares,
                price: price,
                buyFeeRate: draft.buyFeeRate,
                sellFeeMode: draft.sellFeeMode,
                sellFeeValue: draft.sellFeeValue,
                tradeDate: draft.tradeDate,
                tradeTimeType: draft.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: pendingTrade.createdAt,
                confirmedAt: .now,
                syncMetadata: syncMetadata(from: pendingTrade)
            )
        )
    }

    private func confirmPendingConversionRecords(
        _ pendingConversion: FundPendingConversion,
        draft: FundConversionDraft,
        fromFund: FundPosition,
        toFund: FundPosition,
        fromPrice: Double,
        toPrice: Double,
        grossAmount: Double,
        transferAmount: Double,
        sellFee: Double,
        buyFee: Double,
        confirmedOutShares: Double,
        confirmedInShares: Double
    ) {
        let createdAt = pendingConversion.createdAt
        let acceptedDate = pendingConversion.acceptedDate
        let conversionID = pendingConversion.id

        if !updateTradeRecord(
            id: pendingConversion.outRecordID,
            matching: { record in
                record.conversionID == conversionID && record.kind == .conversionOut
            },
            update: { record in
                record.status = .confirmed
                record.name = fromFund.name
                record.mode = .share
                record.amount = grossAmount
                record.shares = draft.shares
                record.confirmedShares = confirmedOutShares
                record.price = fromPrice
                record.sellFeeMode = draft.sellFeeMode
                record.sellFeeValue = draft.sellFeeValue
                record.feeAmount = sellFee
                record.tradeDate = draft.tradeDate
                record.tradeTimeType = draft.tradeTimeType
                record.acceptedDate = acceptedDate
                record.confirmedAt = .now
                record.failureReason = nil
                record.linkedCode = draft.toCode
                record.linkedName = toFund.name
                if record.syncSource == .jdFinance {
                    record.externalStatus = .externalConfirmed
                    record.waitsForExternalConfirmation = false
                }
            }
        ) {
            appendTradeRecord(
                FundTradeRecord(
                    id: pendingConversion.outRecordID ?? UUID().uuidString,
                    kind: .conversionOut,
                    status: .confirmed,
                    code: draft.fromCode,
                    name: fromFund.name,
                    mode: .share,
                    amount: grossAmount,
                    shares: draft.shares,
                    confirmedShares: confirmedOutShares,
                    price: fromPrice,
                    tradeDate: draft.tradeDate,
                    tradeTimeType: draft.tradeTimeType,
                    acceptedDate: acceptedDate,
                    createdAt: createdAt,
                    confirmedAt: .now,
                    failureReason: nil,
                    sellFeeMode: draft.sellFeeMode,
                    sellFeeValue: draft.sellFeeValue,
                    conversionID: conversionID,
                    linkedCode: draft.toCode,
                    linkedName: toFund.name,
                    feeAmount: sellFee,
                    syncSource: pendingConversion.syncSource,
                    syncKey: pendingConversion.syncKey,
                    externalStatus: pendingConversion.syncSource == .jdFinance
                        ? .externalConfirmed
                        : pendingConversion.externalStatus,
                    externalStatusText: pendingConversion.externalStatusText,
                    waitsForExternalConfirmation: pendingConversion.syncSource == .jdFinance
                        ? false
                        : pendingConversion.waitsForExternalConfirmation
                )
            )
        }

        if !updateTradeRecord(
            id: pendingConversion.inRecordID,
            matching: { record in
                record.conversionID == conversionID && record.kind == .conversionIn
            },
            update: { record in
                record.status = .confirmed
                record.name = toFund.name
                record.mode = .amount
                record.amount = transferAmount
                record.shares = nil
                record.confirmedShares = confirmedInShares
                record.price = toPrice
                record.buyFeeRate = draft.buyFeeRate
                record.feeAmount = buyFee
                record.tradeDate = draft.tradeDate
                record.tradeTimeType = draft.tradeTimeType
                record.acceptedDate = acceptedDate
                record.confirmedAt = .now
                record.failureReason = nil
                record.linkedCode = draft.fromCode
                record.linkedName = fromFund.name
                if record.syncSource == .jdFinance {
                    record.externalStatus = .externalConfirmed
                    record.waitsForExternalConfirmation = false
                }
            }
        ) {
            appendTradeRecord(
                FundTradeRecord(
                    id: pendingConversion.inRecordID ?? UUID().uuidString,
                    kind: .conversionIn,
                    status: .confirmed,
                    code: draft.toCode,
                    name: toFund.name,
                    mode: .amount,
                    amount: transferAmount,
                    shares: nil,
                    confirmedShares: confirmedInShares,
                    price: toPrice,
                    tradeDate: draft.tradeDate,
                    tradeTimeType: draft.tradeTimeType,
                    acceptedDate: acceptedDate,
                    createdAt: createdAt,
                    confirmedAt: .now,
                    failureReason: nil,
                    buyFeeRate: draft.buyFeeRate,
                    conversionID: conversionID,
                    linkedCode: draft.fromCode,
                    linkedName: fromFund.name,
                    feeAmount: buyFee,
                    syncSource: pendingConversion.syncSource,
                    syncKey: pendingConversion.syncKey,
                    externalStatus: pendingConversion.syncSource == .jdFinance
                        ? .externalConfirmed
                        : pendingConversion.externalStatus,
                    externalStatusText: pendingConversion.externalStatusText,
                    waitsForExternalConfirmation: pendingConversion.syncSource == .jdFinance
                        ? false
                        : pendingConversion.waitsForExternalConfirmation
                )
            )
        }
    }

    private func markPendingConversion(_ conversionID: String, failureReason: String?) {
        guard var records = snapshot.tradeRecords, !records.isEmpty else {
            return
        }
        for index in records.indices where records[index].conversionID == conversionID {
            records[index].status = .pending
            records[index].failureReason = failureReason
        }
        snapshot.tradeRecords = records
    }

    private func confirmInitialTradeRecord(
        fund: FundPosition,
        acceptedDate: String,
        price: Double
    ) {
        let totalShares = fund.migratedShares ?? effectiveLots(for: fund).reduce(0) { $0 + $1.shares }
        let amount = roundedMoney(totalShares * price)
        let tradeDate = fund.positionDate ?? acceptedDate
        let timeType = fund.positionTimeType ?? .before15
        if updateTradeRecord(
            id: nil,
            matching: { record in
                record.status == .pending
                    && record.kind == .newFund
                    && record.code == fund.code
                    && record.acceptedDate == acceptedDate
            },
            update: { record in
                record.status = .confirmed
                record.name = fund.name
                record.amount = record.amount ?? amount
                record.price = price
                record.confirmedShares = totalShares
                record.confirmedAt = .now
                if record.syncSource == .jdFinance {
                    record.externalStatus = .externalConfirmed
                    record.waitsForExternalConfirmation = false
                }
            }
        ) {
            return
        }

        appendTradeRecord(
            tradeRecord(
                kind: .newFund,
                status: .confirmed,
                code: fund.code,
                name: fund.name,
                mode: fund.positionMode ?? .amount,
                amount: amount,
                shares: nil,
                confirmedShares: totalShares,
                price: price,
                tradeDate: tradeDate,
                tradeTimeType: timeType,
                acceptedDate: acceptedDate,
                createdAt: .now,
                confirmedAt: .now
            )
        )
    }

    private func tradeRecord(
        kind: FundTradeKind,
        status: FundTradeRecordStatus,
        code: String,
        name: String,
        mode: PositionMode,
        amount: Double?,
        shares: Double?,
        confirmedShares: Double?,
        price: Double?,
        profit: Double? = nil,
        buyFeeRate: Double? = nil,
        sellFeeMode: TradeFeeMode? = nil,
        sellFeeValue: Double? = nil,
        tradeDate: String,
        tradeTimeType: PositionTimeType,
        acceptedDate: String,
        createdAt: Date,
        confirmedAt: Date?,
        syncMetadata: FundTradeSyncMetadata? = nil
    ) -> FundTradeRecord {
        FundTradeRecord(
            id: UUID().uuidString,
            kind: kind,
            status: status,
            code: code,
            name: name,
            mode: mode,
            amount: amount,
            shares: shares,
            confirmedShares: confirmedShares,
            price: price,
            profit: profit,
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType,
            acceptedDate: acceptedDate,
            createdAt: createdAt,
            confirmedAt: confirmedAt,
            failureReason: nil,
            buyFeeRate: buyFeeRate,
            sellFeeMode: sellFeeMode,
            sellFeeValue: sellFeeValue,
            syncSource: syncMetadata?.source,
            syncKey: syncMetadata?.syncKey,
            externalStatus: syncMetadata?.externalStatus,
            externalStatusText: syncMetadata?.externalStatusText,
            waitsForExternalConfirmation: syncMetadata?.waitsForExternalConfirmation
        )
    }

    private func appendTradeRecord(_ record: FundTradeRecord) {
        var records = snapshot.tradeRecords ?? []
        records.append(record)
        snapshot.tradeRecords = records
    }

    private func hasImportedTrade(matching draft: FundTradeDraft) -> Bool {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return false }

        if (snapshot.pendingTrades ?? []).contains(where: { pendingTradeMatches($0, draft: draft, code: code) }) {
            return true
        }

        return (snapshot.tradeRecords ?? []).contains { tradeRecordMatches($0, draft: draft, code: code) }
    }

    private func markImportedTrade(
        matching draft: FundTradeDraft,
        syncMetadata: FundTradeSyncMetadata
    ) {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        if var pendingTrades = snapshot.pendingTrades {
            for index in pendingTrades.indices where pendingTradeMatches(pendingTrades[index], draft: draft, code: code) {
                apply(syncMetadata, to: &pendingTrades[index])
            }
            snapshot.pendingTrades = pendingTrades
        }

        if var records = snapshot.tradeRecords {
            for index in records.indices where tradeRecordMatches(records[index], draft: draft, code: code) {
                apply(syncMetadata, to: &records[index])
            }
            snapshot.tradeRecords = records
        }
    }

    private func pendingTradeMatches(_ pendingTrade: FundPendingTrade, draft: FundTradeDraft, code: String) -> Bool {
        guard pendingTrade.code == code,
              pendingTrade.action == draft.action,
              pendingTrade.tradeDate == draft.tradeDate,
              pendingTrade.tradeTimeType == draft.tradeTimeType
        else {
            return false
        }

        switch draft.action {
        case .buy:
            return moneyMatches(pendingTrade.amount, draft.amount)
        case .sell:
            return sharesMatch(pendingTrade.shares, draft.shares)
        }
    }

    private func tradeRecordMatches(_ record: FundTradeRecord, draft: FundTradeDraft, code: String) -> Bool {
        guard record.code == code,
              record.tradeDate == draft.tradeDate,
              record.tradeTimeType == draft.tradeTimeType
        else {
            return false
        }

        switch draft.action {
        case .buy:
            guard record.kind == .newFund || record.kind == .buy else { return false }
            return moneyMatches(record.amount, draft.amount)
        case .sell:
            guard record.kind == .sell else { return false }
            return sharesMatch(record.shares ?? record.confirmedShares, draft.shares)
        }
    }

    private func overwriteJDFinanceTradeRecord(
        recordID: String,
        values: JDFinanceReconciliationValues
    ) throws {
        guard var records = snapshot.tradeRecords,
              let index = records.firstIndex(where: { $0.id == recordID })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }

        let code = records[index].code
        let amount = values.amount ?? records[index].amount
        let shares = values.shares ?? records[index].confirmedShares ?? records[index].shares
        records[index].status = .confirmed
        records[index].amount = amount
        switch records[index].kind {
        case .newFund, .buy, .conversionIn:
            records[index].shares = nil
        case .sell, .conversionOut:
            records[index].shares = shares
        }
        records[index].confirmedShares = shares
        records[index].price = reconciliationPrice(
            amount: amount,
            shares: shares,
            fallback: values.price ?? records[index].price
        )
        records[index].confirmedAt = records[index].confirmedAt ?? .now
        records[index].failureReason = nil
        markRecordAsJDFinanceConfirmed(&records[index], values: values)
        snapshot.tradeRecords = records
        snapshot.pendingTrades?.removeAll { $0.recordID == recordID || $0.id == recordID }
        if snapshot.pendingTrades?.isEmpty == true {
            snapshot.pendingTrades = nil
        }
        try rebuildFundPositionFromTradeRecords(code: code)
    }

    private func overwriteJDFinanceConversionRecords(
        conversionID: String,
        values: JDFinanceReconciliationValues
    ) throws {
        guard var records = snapshot.tradeRecords else {
            throw PortfolioStoreError.tradeRecordNotFound
        }
        guard let outIndex = records.firstIndex(where: { $0.conversionID == conversionID && $0.kind == .conversionOut }),
              let inIndex = records.firstIndex(where: { $0.conversionID == conversionID && $0.kind == .conversionIn })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }

        let affectedCodes = Set([records[outIndex].code, records[inIndex].code])
        let outAmount = values.amount ?? records[outIndex].amount
        let outShares = values.shares ?? records[outIndex].confirmedShares ?? records[outIndex].shares
        records[outIndex].status = .confirmed
        records[outIndex].amount = outAmount
        records[outIndex].shares = outShares
        records[outIndex].confirmedShares = outShares
        records[outIndex].price = reconciliationPrice(
            amount: outAmount,
            shares: outShares,
            fallback: values.price ?? records[outIndex].price
        )
        records[outIndex].confirmedAt = records[outIndex].confirmedAt ?? .now
        records[outIndex].failureReason = nil
        markRecordAsJDFinanceConfirmed(&records[outIndex], values: values)

        let inAmount = values.inAmount ?? records[inIndex].amount
        let inShares = values.inShares ?? records[inIndex].confirmedShares ?? records[inIndex].shares
        records[inIndex].status = .confirmed
        records[inIndex].amount = inAmount
        records[inIndex].shares = nil
        records[inIndex].confirmedShares = inShares
        records[inIndex].price = reconciliationPrice(
            amount: inAmount,
            shares: inShares,
            fallback: values.inPrice ?? records[inIndex].price
        )
        records[inIndex].confirmedAt = records[inIndex].confirmedAt ?? .now
        records[inIndex].failureReason = nil
        markRecordAsJDFinanceConfirmed(&records[inIndex], values: values)

        snapshot.tradeRecords = records
        snapshot.pendingConversions?.removeAll { $0.id == conversionID }
        if snapshot.pendingConversions?.isEmpty == true {
            snapshot.pendingConversions = nil
        }
        for code in affectedCodes {
            try rebuildFundPositionFromTradeRecords(code: code)
        }
    }

    private func reconciliationPrice(amount: Double?, shares: Double?, fallback: Double?) -> Double? {
        guard let amount, let shares, amount > 0, shares > 0 else {
            return fallback
        }
        return roundedStoredShares(amount / shares)
    }

    private func markRecordAsJDFinanceConfirmed(
        _ record: inout FundTradeRecord,
        values: JDFinanceReconciliationValues
    ) {
        record.syncSource = .jdFinance
        record.syncKey = values.syncKey ?? record.syncKey
        record.externalStatus = .externalConfirmed
        record.externalStatusText = values.statusText ?? record.externalStatusText
        record.waitsForExternalConfirmation = false
    }

    private func hasImportedConversion(matching draft: FundConversionDraft) -> Bool {
        if (snapshot.pendingConversions ?? []).contains(where: { pendingConversionMatches($0, draft: draft) }) {
            return true
        }

        return (snapshot.tradeRecords ?? []).contains { record in
            record.kind == .conversionOut
                && record.code == draft.fromCode
                && record.linkedCode == draft.toCode
                && record.tradeDate == draft.tradeDate
                && record.tradeTimeType == draft.tradeTimeType
                && sharesMatch(record.shares ?? record.confirmedShares, draft.shares)
        }
    }

    private func markImportedConversion(
        matching draft: FundConversionDraft,
        syncMetadata: FundTradeSyncMetadata
    ) {
        var conversionIDs = Set<String>()

        if var pendingConversions = snapshot.pendingConversions {
            for index in pendingConversions.indices where pendingConversionMatches(pendingConversions[index], draft: draft) {
                apply(syncMetadata, to: &pendingConversions[index])
                conversionIDs.insert(pendingConversions[index].id)
            }
            snapshot.pendingConversions = pendingConversions
        }

        if var records = snapshot.tradeRecords {
            for index in records.indices {
                let matchesDraft = records[index].kind == .conversionOut
                    && records[index].code == draft.fromCode
                    && records[index].linkedCode == draft.toCode
                    && records[index].tradeDate == draft.tradeDate
                    && records[index].tradeTimeType == draft.tradeTimeType
                    && sharesMatch(records[index].shares ?? records[index].confirmedShares, draft.shares)
                if matchesDraft, let conversionID = records[index].conversionID {
                    conversionIDs.insert(conversionID)
                }
            }

            for index in records.indices where records[index].conversionID.map(conversionIDs.contains) == true {
                apply(syncMetadata, to: &records[index])
            }
            snapshot.tradeRecords = records
        }
    }

    private func apply(_ syncMetadata: FundTradeSyncMetadata, to record: inout FundTradeRecord) {
        record.syncSource = syncMetadata.source
        record.syncKey = syncMetadata.syncKey
        record.externalStatus = syncMetadata.externalStatus
        record.externalStatusText = syncMetadata.externalStatusText
        record.waitsForExternalConfirmation = syncMetadata.waitsForExternalConfirmation
    }

    private func apply(_ syncMetadata: FundTradeSyncMetadata, to pendingTrade: inout FundPendingTrade) {
        pendingTrade.syncSource = syncMetadata.source
        pendingTrade.syncKey = syncMetadata.syncKey
        pendingTrade.externalStatus = syncMetadata.externalStatus
        pendingTrade.externalStatusText = syncMetadata.externalStatusText
        pendingTrade.waitsForExternalConfirmation = syncMetadata.waitsForExternalConfirmation
    }

    private func apply(_ syncMetadata: FundTradeSyncMetadata, to pendingConversion: inout FundPendingConversion) {
        pendingConversion.syncSource = syncMetadata.source
        pendingConversion.syncKey = syncMetadata.syncKey
        pendingConversion.externalStatus = syncMetadata.externalStatus
        pendingConversion.externalStatusText = syncMetadata.externalStatusText
        pendingConversion.waitsForExternalConfirmation = syncMetadata.waitsForExternalConfirmation
    }

    private func syncMetadata(from pendingTrade: FundPendingTrade) -> FundTradeSyncMetadata? {
        guard let source = pendingTrade.syncSource else { return nil }
        return FundTradeSyncMetadata(
            source: source,
            syncKey: pendingTrade.syncKey,
            externalStatus: pendingTrade.externalStatus,
            externalStatusText: pendingTrade.externalStatusText,
            waitsForExternalConfirmation: pendingTrade.waitsForExternalConfirmation
        )
    }

    private func pendingConversionMatches(_ pendingConversion: FundPendingConversion, draft: FundConversionDraft) -> Bool {
        pendingConversion.fromCode == draft.fromCode
            && pendingConversion.toCode == draft.toCode
            && pendingConversion.tradeDate == draft.tradeDate
            && pendingConversion.tradeTimeType == draft.tradeTimeType
            && sharesMatch(pendingConversion.shares, draft.shares)
    }

    private func moneyMatches(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs, let rhs else { return false }
        return roundedMoney(lhs) == roundedMoney(rhs)
    }

    private func sharesMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs, let rhs else { return false }
        return roundedStoredShares(lhs) == roundedStoredShares(rhs)
    }

    private func resetTradeHistoryForEditedFund(codes: Set<String>) {
        let normalizedCodes = Set(codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !normalizedCodes.isEmpty else { return }

        var removedRecordIDs = Set<String>()
        var removedConversionIDs = Set<String>()
        if var records = snapshot.tradeRecords {
            for record in records where normalizedCodes.contains(record.code) || record.linkedCode.map(normalizedCodes.contains) == true {
                removedRecordIDs.insert(record.id)
                if let conversionID = record.conversionID {
                    removedConversionIDs.insert(conversionID)
                }
            }

            records.removeAll { record in
                normalizedCodes.contains(record.code)
                    || record.linkedCode.map(normalizedCodes.contains) == true
                    || record.conversionID.map(removedConversionIDs.contains) == true
            }
            snapshot.tradeRecords = records.isEmpty ? nil : records
        }

        snapshot.pendingTrades?.removeAll { pendingTrade in
            normalizedCodes.contains(pendingTrade.code)
                || pendingTrade.recordID.map(removedRecordIDs.contains) == true
        }
        if snapshot.pendingTrades?.isEmpty == true {
            snapshot.pendingTrades = nil
        }

        snapshot.pendingConversions?.removeAll { pendingConversion in
            normalizedCodes.contains(pendingConversion.fromCode)
                || normalizedCodes.contains(pendingConversion.toCode)
                || removedConversionIDs.contains(pendingConversion.id)
        }
        if snapshot.pendingConversions?.isEmpty == true {
            snapshot.pendingConversions = nil
        }
    }

    private func syncInitialTradeRecordsFromFunds() {
        guard var records = snapshot.tradeRecords, !records.isEmpty else {
            return
        }
        var didChange = false
        let fundsByCode = Dictionary(uniqueKeysWithValues: snapshot.funds.map { ($0.code, $0) })
        for index in records.indices {
            guard records[index].kind == .newFund,
                  records[index].status == .confirmed,
                  records[index].mode == .amount,
                  let fund = fundsByCode[records[index].code],
                  let amount = records[index].amount,
                  amount > 0,
                  let shares = fund.migratedShares,
                  shares > 0
            else {
                continue
            }

            if records[index].confirmedShares == nil {
                records[index].confirmedShares = shares
                didChange = true
            }
            if records[index].price == nil {
                records[index].price = roundedCost(amount / shares)
                didChange = true
            }
            if records[index].profit == nil,
               let principal = fund.migratedPrincipal {
                records[index].profit = roundedMoney(amount - principal)
                didChange = true
            }
        }
        if didChange {
            snapshot.tradeRecords = records
        }
    }

    private func updateTradeRecord(
        id: String?,
        matching: (FundTradeRecord) -> Bool,
        update: (inout FundTradeRecord) -> Void
    ) -> Bool {
        var records = snapshot.tradeRecords ?? []
        let index: Int?
        if let id, let matchedIndex = records.firstIndex(where: { $0.id == id }) {
            index = matchedIndex
        } else {
            index = records.firstIndex(where: matching)
        }
        guard let index else { return false }
        update(&records[index])
        snapshot.tradeRecords = records
        return true
    }

    private func tradeKind(for action: FundTradeAction) -> FundTradeKind {
        switch action {
        case .buy:
            .buy
        case .sell:
            .sell
        }
    }

    private func resolvedPosition(draft: FundPositionDraft, netValue: Double?) throws -> (shares: Double, cost: Double, principal: Double) {
        switch draft.positionMode {
        case .share:
            let shares = roundedDisplayedShares(draft.shares ?? 0)
            guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
            let cost = roundedCost(draft.cost ?? netValue ?? 0)
            guard cost > 0 else { throw PortfolioStoreError.missingNetValue }
            return (shares, cost, shares * cost)

        case .amount:
            let amount = draft.positionAmount ?? 0
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            guard let netValue, netValue > 0 else { throw PortfolioStoreError.missingNetValue }
            let shares = roundedStoredShares(amount / netValue)
            guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
            let principal = amount - draft.positionProfit
            guard principal > 0 else { throw PortfolioStoreError.invalidCost }
            let cost = roundedCost(principal / shares)
            guard cost > 0 else { throw PortfolioStoreError.invalidCost }
            return (shares, cost, principal)
        }
    }

    private func amountSyncLot(
        code: String,
        amount: Double,
        principal: Double,
        netValue: Double,
        fund: FundPosition
    ) throws -> FundPositionLot {
        guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
        guard principal > 0 else { throw PortfolioStoreError.invalidCost }
        guard netValue > 0 else { throw PortfolioStoreError.missingNetValue }

        let shares = roundedStoredShares(amount / netValue)
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
        let cost = roundedCost(principal / shares)
        guard cost > 0 else { throw PortfolioStoreError.invalidCost }

        return FundPositionLot(
            id: "\(code)-jd-finance-sync",
            shares: shares,
            cost: cost,
            principal: principal,
            incomeStartDate: fund.incomeStartDate ?? fund.positionDate ?? DateOnlyFormatter.string(from: nowProvider()),
            positionDate: fund.positionDate ?? DateOnlyFormatter.string(from: nowProvider()),
            positionTimeType: fund.positionTimeType ?? .before15
        )
    }

    private func lotPrincipal(_ lot: FundPositionLot) -> Double {
        lot.principal ?? (lot.shares * lot.cost)
    }

    private func lotPrincipal(from record: FundTradeRecord, shares: Double, cost: Double) -> Double {
        if record.kind == .newFund,
           record.mode == .amount,
           let amount = record.amount {
            return amount - (record.profit ?? 0)
        }
        if (record.kind == .buy || record.kind == .conversionIn),
           record.mode == .amount,
           let amount = record.amount {
            return amount
        }
        return shares * cost
    }

    private func remainingPrincipal(
        originalPrincipal: Double,
        originalShares: Double,
        remainingShares: Double
    ) -> Double {
        guard remainingShares > 0, originalShares > 0 else { return 0 }
        return originalPrincipal * remainingShares / originalShares
    }

    private func quoteNetValue(_ quote: FundQuote?) -> Double? {
        guard let quote else { return nil }
        if quote.netValue > 0 { return quote.netValue }
        if quote.estimatedNetValue > 0 { return quote.estimatedNetValue }
        return nil
    }

    private func buyNetAmount(totalAmount: Double, feeRate: Double?) -> Double {
        let normalizedFeeRate = max(feeRate ?? 0, 0)
        return totalAmount / (1 + normalizedFeeRate / 100)
    }

    private func conversionFeeAmount(grossAmount: Double, mode: TradeFeeMode, value: Double) -> Double {
        let normalizedValue = max(value, 0)
        switch mode {
        case .rate:
            return grossAmount * normalizedValue / 100
        case .amount:
            return min(grossAmount, normalizedValue)
        }
    }

    private func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    private func roundedStoredShares(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.storedSharePlaces)
    }

    private func roundedDisplayedShares(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.displayedSharePlaces)
    }

    private func roundedCost(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.costPlaces)
    }

    private func roundedMoney(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.moneyPlaces)
    }

    private func dateText(for quote: FundQuote, fallback: String) -> String {
        if quote.estimateTime.count >= 16 {
            return String(quote.estimateTime.dropFirst(5).prefix(11))
        }
        if quote.netValueDate.count >= 10 {
            return String(quote.netValueDate.dropFirst(5)) + " 15:00"
        }
        return fallback
    }

    private static func confirmedDateText(_ date: String) -> String {
        guard date.count >= 10 else {
            return date.isEmpty ? "--" : date
        }
        return String(date.dropFirst(5).prefix(5)) + " 15:00"
    }

    private func quoteIsUpdated(_ quote: FundQuote) -> Bool {
        guard let date = DateOnlyFormatter.parse(quote.netValueDate) else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    private func save(_ snapshot: PortfolioSnapshot) throws {
        do {
            try repository.save(snapshot)
            persistedSnapshot = snapshot
        } catch {
            if let persistedSnapshot {
                self.snapshot = persistedSnapshot
            }
            throw error
        }
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

enum PortfolioStoreError: LocalizedError, Equatable {
    case invalidCode
    case invalidPosition
    case invalidCost
    case missingNetValue
    case fundNotFound
    case pendingNetValue
    case insufficientShares
    case tradeRecordNotFound
    case buyTradeRequiresAmount
    case sellTradeRequiresShare
    case invalidConversionTarget
    case concurrentModification
    case jdFinanceAccountUnidentified
    case jdFinanceAccountMismatch
    case invalidJDFinanceSyncState
    case performanceHistoryWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            "请输入基金代码"
        case .invalidPosition:
            "请输入大于 0 的持仓金额或份额"
        case .invalidCost:
            "成本价计算失败，请检查持仓金额和收益"
        case .missingNetValue:
            "无法获取基金净值，请改用按份额并填写成本价"
        case .fundNotFound:
            "未找到这只基金"
        case .pendingNetValue:
            "所选交易日的净值尚未更新，暂时不能确认这笔操作"
        case .insufficientShares:
            "可卖出份额不足"
        case .tradeRecordNotFound:
            "未找到这条交易记录"
        case .buyTradeRequiresAmount:
            "加仓只能按金额录入"
        case .sellTradeRequiresShare:
            "减仓只能按份额录入"
        case .invalidConversionTarget:
            "转换目标基金不能与当前基金相同"
        case .concurrentModification:
            "持仓已在后台更新，请重新同步后再试"
        case .jdFinanceAccountUnidentified:
            "无法确认当前京东账号，请重新登录后再同步"
        case .jdFinanceAccountMismatch:
            "当前京东账号与已有京东同步数据来源不一致，请切回原账号或清除旧账号的同步数据"
        case .invalidJDFinanceSyncState:
            "京东同步基线尚未建立，请先重新同步"
        case .performanceHistoryWriteFailed(let reason):
            "组合收益历史写入失败：\(reason)"
        }
    }
}

enum AppDataPaths {
    static var sharedDataDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/fund-pulse", directoryHint: .isDirectory)
    }

    static func hasLegacyStore(in directory: URL) -> Bool {
        ["config.json", "state.json", "cache.json"].contains { fileName in
            FileManager.default.fileExists(atPath: directory.appending(path: fileName).path)
        }
    }
}
