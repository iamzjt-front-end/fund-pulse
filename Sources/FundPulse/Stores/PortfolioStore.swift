import Foundation
import Observation

@Observable
@MainActor
final class PortfolioStore {
    var snapshot: PortfolioSnapshot = .empty {
        didSet { snapshotRevision &+= 1 }
    }
    private(set) var snapshotRevision: UInt64 = 0
    @ObservationIgnored private let presentationCache = PortfolioPresentationCache()

    func listPresentation(filter: FundListFilter, sort: FundSortMode) -> PortfolioListPresentation {
        presentationCache.value(snapshot: snapshot, revision: snapshotRevision, filter: filter, sort: sort)
    }
    var loadState: LoadState = .loading
    var isRefreshingQuotes = false
    var quoteRefreshWarning: String?
    var lastSuccessfulQuoteRefresh: Date?
    private(set) var dataDirectory: URL
    let quoteService: FundQuoteService
    let exchangeQuoteService: ExchangeFundQuoteService
    let nowProvider: () -> Date
    let repository: any PortfolioRepository
    let accountKind: PortfolioAccountKind
    let performanceStore: PortfolioPerformanceStore
    var persistedSnapshot: PortfolioSnapshot?
    var prefetchedQuotes: [String: FundQuote]?
    var refreshTask: Task<Void, Never>?
    var refreshRequestGeneration = 0
    var quoteRefreshDeferralCount = 0
    var hasDeferredQuoteRefresh = false
    var isImporting = false

    enum LoadState: Equatable {
        case loading
        case loaded
        case missingPlainData(hasLegacyStore: Bool)
        case failed(String)
    }

    init(
        dataDirectory: URL = AppDataPaths.sharedDataDirectory,
        quoteService: FundQuoteService = FundQuoteService(),
        exchangeQuoteService: ExchangeFundQuoteService = ExchangeFundQuoteService(),
        performanceStore: PortfolioPerformanceStore? = nil,
        accountKind: PortfolioAccountKind = .offExchange,
        now: @escaping () -> Date = { .now }
    ) {
        self.dataDirectory = dataDirectory
        self.quoteService = quoteService
        self.exchangeQuoteService = exchangeQuoteService
        self.nowProvider = now
        self.repository = JSONPortfolioRepository(dataDirectory: dataDirectory)
        self.accountKind = accountKind
        self.performanceStore = performanceStore ?? PortfolioPerformanceStore(dataDirectory: dataDirectory)
    }

    init(
        repository: any PortfolioRepository,
        quoteService: FundQuoteService = FundQuoteService(),
        exchangeQuoteService: ExchangeFundQuoteService = ExchangeFundQuoteService(),
        performanceStore: PortfolioPerformanceStore? = nil,
        accountKind: PortfolioAccountKind = .offExchange,
        now: @escaping () -> Date = { .now }
    ) {
        self.dataDirectory = repository.dataDirectory
        self.quoteService = quoteService
        self.exchangeQuoteService = exchangeQuoteService
        self.nowProvider = now
        self.repository = repository
        self.accountKind = accountKind
        self.performanceStore = performanceStore ?? PortfolioPerformanceStore(dataDirectory: repository.dataDirectory)
    }

    var dataFileURL: URL {
        repository.dataFileURL
    }

    func exchangeShareAvailability(
        for code: String,
        on date: Date? = nil
    ) -> ExchangeShareAvailability {
        guard accountKind == .onExchange,
              let fund = snapshot.funds.first(where: { $0.code == code })
        else {
            return .zero
        }

        return exchangeShareAvailability(
            for: fund,
            on: DateOnlyFormatter.string(from: date ?? nowProvider())
        )
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

    func applyExchangeFirstDayReconciliation(
        date: String,
        reportedHoldingIncome: Double,
        reportedTodayIncome: Double
    ) throws {
        guard accountKind == .onExchange else {
            throw PortfolioStoreError.operationUnavailableForAccount
        }

        let today = DateOnlyFormatter.string(from: nowProvider())
        guard DateOnlyFormatter.parse(date) != nil, date <= today else {
            throw PortfolioStoreError.invalidExchangeReconciliationDate
        }

        let holdingsMarketValue = snapshot.totalAmount
        guard !snapshot.funds.isEmpty,
              holdingsMarketValue.isFinite,
              holdingsMarketValue > 0,
              reportedHoldingIncome.isFinite,
              reportedTodayIncome.isFinite,
              holdingsMarketValue - reportedHoldingIncome > 0
        else {
            throw PortfolioStoreError.invalidExchangeReconciliationValue
        }

        var updatedSnapshot = snapshot
        updatedSnapshot.exchangeAccountReconciliation = ExchangeAccountReconciliation(
            date: date,
            holdingsMarketValue: holdingsMarketValue,
            reportedHoldingIncome: reportedHoldingIncome,
            reportedTodayIncome: reportedTodayIncome
        )
        updatedSnapshot.updateTime = nowProvider()

        if date == today {
            let holdingIncomeBase = holdingsMarketValue - reportedHoldingIncome
            updatedSnapshot.holdingIncome = reportedHoldingIncome
            updatedSnapshot.holdingIncomeRate = reportedHoldingIncome / holdingIncomeBase * 100
            updatedSnapshot.todayIncome = reportedTodayIncome
            updatedSnapshot.todayIncomeRate = reportedTodayIncome / holdingsMarketValue * 100
        }

        try save(updatedSnapshot)
        snapshot = updatedSnapshot
        loadState = .loaded
    }

    func upsertFund(_ draft: FundPositionDraft, replacing existingCode: String? = nil) async throws {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw PortfolioStoreError.invalidCode
        }
        if accountKind == .onExchange {
            try await upsertExchangeFund(draft, replacing: existingCode)
            return
        }

        let baseSnapshot = snapshot
        let existingFund = snapshot.funds.first { $0.code == (existingCode ?? code) }
        let isCreatingFund = existingFund == nil && existingCode == nil
        let quote = try? await quoteService.fetchQuote(code: code)
        let requestedAcceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.positionDate,
            timeType: draft.positionTimeType
        )
        guard !requestedAcceptedDate.isEmpty else { throw PortfolioStoreError.tradingCalendarUnavailable }
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
        guard snapshot == baseSnapshot else { throw PortfolioStoreError.concurrentModification }
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
        switch accountKind {
        case .offExchange:
            return await quoteService.lookupFundName(code: code)
        case .onExchange:
            if let name = await quoteService.lookupFundName(code: code) {
                return name
            }
            return await exchangeQuoteService.lookupFundName(code: code)
        }
    }

    func fetchLatestQuote(code: String) async -> FundQuote? {
        try? await fetchLatestQuoteThrowing(code: code)
    }

    func fetchLatestQuoteThrowing(code: String) async throws -> FundQuote {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw PortfolioStoreError.invalidCode }
        switch accountKind {
        case .offExchange:
            return try await quoteService.fetchQuote(code: code)
        case .onExchange:
            return try await exchangeQuoteService.fetchQuote(code: code)
        }
    }

    func fetchTradeReferenceNetValue(
        code: String,
        tradeDate: String,
        timeType: PositionTimeType
    ) async -> (date: String, value: Double)? {
        if accountKind == .onExchange {
            guard let quote = try? await exchangeQuoteService.fetchQuote(code: code) else { return nil }
            return (quote.netValueDate, quote.netValue)
        }
        let acceptedDate = TradingCalendar.acceptedTradeDate(positionDate: tradeDate, timeType: timeType)
        return await quoteService.fetchSmartNetValue(code: code, startDate: acceptedDate)
    }

    func applyAmountPositionSyncUpdates(
        _ updates: [FundAmountPositionSyncUpdate],
        preservingPendingRecordIDs: Set<String> = []
    ) async throws {
        guard !updates.isEmpty else { return }

        let baseSnapshot = snapshot
        var syncQuotes: [String: FundQuote] = [:]
        for update in updates {
            let code = update.code.trimmingCharacters(in: .whitespacesAndNewlines)
            syncQuotes[code] = try await quoteService.fetchQuote(code: code)
        }
        guard snapshot == baseSnapshot else { throw PortfolioStoreError.concurrentModification }
        do {
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

                guard let quote = syncQuotes[code] else { throw PortfolioStoreError.missingNetValue }
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
                resetTradeHistoryForEditedFund(
                    codes: Set([code]),
                    preservingRecordIDs: preservingPendingRecordIDs
                )

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
        } catch {
            snapshot = baseSnapshot
            throw error
        }
        await refreshQuotes()
    }

    func adjustFundPosition(_ draft: FundTradeDraft, syncMetadata: FundTradeSyncMetadata? = nil) async throws {
        if accountKind == .onExchange {
            guard syncMetadata == nil else {
                throw PortfolioStoreError.operationUnavailableForAccount
            }
            try await recordExchangeTrade(draft)
            return
        }

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
        guard !acceptedDate.isEmpty else { throw PortfolioStoreError.tradingCalendarUnavailable }
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
        guard accountKind == .offExchange else {
            throw PortfolioStoreError.operationUnavailableForAccount
        }
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
        if accountKind == .onExchange {
            try await editExchangeTradeRecord(id: id, with: draft)
            return
        }

        let baseSnapshot = snapshot
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
        guard !acceptedDate.isEmpty else { throw PortfolioStoreError.tradingCalendarUnavailable }
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
        guard snapshot == baseSnapshot else { throw PortfolioStoreError.concurrentModification }
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

    func makeFundPosition(
        from draft: FundPositionDraft,
        existingFund: FundPosition?,
        quote: FundQuote?,
        confirmedNetValue: Double?,
        isEditingExistingFund: Bool,
        acceptedDateOverride: String? = nil
    ) throws -> FundPosition {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedDate = acceptedDateOverride ?? TradingCalendar.acceptedTradeDate(
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

        let lots: [FundPositionLot]? = try position.map {
            let baseLot = FundPositionLot(
                id: UUID().uuidString,
                shares: $0.shares,
                cost: $0.cost,
                principal: $0.principal,
                incomeStartDate: incomeStartDate,
                positionDate: draft.positionDate,
                positionTimeType: draft.positionTimeType
            )
            guard accountKind == .onExchange else { return [baseLot] }
            return try exchangeBaselineLots(from: baseLot, draft: draft)
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
            exchangeTurnaroundRule: accountKind == .onExchange
                ? (draft.exchangeTurnaroundRule ?? existingFund?.resolvedExchangeTurnaroundRule ?? .nextTradingDay)
                : nil,
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
    func applyBuy(_ draft: FundTradeDraft, price: Double, to fund: inout FundPosition) throws -> Double {
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

    private func normalizedConversionDraft(_ draft: FundConversionDraft) throws -> FundConversionDraft {
        guard !TradingCalendar.acceptedTradeDate(positionDate: draft.tradeDate, timeType: draft.tradeTimeType).isEmpty else {
            throw PortfolioStoreError.tradingCalendarUnavailable
        }
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

    func ensureConversionTargetFund(for draft: FundConversionDraft) {
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

    func confirmPendingAmountPosition(
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

    func confirmPendingSharePosition(
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
    func applySell(_ draft: FundTradeDraft, price: Double, from fund: inout FundPosition) throws -> Double {
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

    func resolvedPosition(draft: FundPositionDraft, netValue: Double?) throws -> (shares: Double, cost: Double, principal: Double) {
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

    func lotPrincipal(_ lot: FundPositionLot) -> Double {
        lot.principal ?? (lot.shares * lot.cost)
    }

    func lotPrincipal(from record: FundTradeRecord, shares: Double, cost: Double) -> Double {
        if accountKind == .onExchange,
           record.mode == .share,
           record.kind == .newFund || record.kind == .buy {
            return shares * cost + max(record.feeAmount ?? 0, 0)
        }
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

    func remainingPrincipal(
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

    func buyNetAmount(totalAmount: Double, feeRate: Double?) -> Double {
        let normalizedFeeRate = max(feeRate ?? 0, 0)
        return totalAmount / (1 + normalizedFeeRate / 100)
    }

    func conversionFeeAmount(grossAmount: Double, mode: TradeFeeMode, value: Double) -> Double {
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

    func roundedStoredShares(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.storedSharePlaces)
    }

    func roundedDisplayedShares(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.displayedSharePlaces)
    }

    func roundedCost(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.costPlaces)
    }

    func roundedMoney(_ value: Double) -> Double {
        rounded(value, places: PortfolioPrecision.moneyPlaces)
    }

    func dateText(for quote: FundQuote, fallback: String) -> String {
        if let marketPriceTime = quote.marketPriceTime, marketPriceTime.count >= 16 {
            return String(marketPriceTime.dropFirst(5).prefix(11))
        }
        if quote.estimateTime.count >= 16 {
            return String(quote.estimateTime.dropFirst(5).prefix(11))
        }
        if quote.netValueDate.count >= 10 {
            return String(quote.netValueDate.dropFirst(5)) + " 15:00"
        }
        return fallback
    }

    static func confirmedDateText(_ date: String) -> String {
        guard date.count >= 10 else {
            return date.isEmpty ? "--" : date
        }
        return String(date.dropFirst(5).prefix(5)) + " 15:00"
    }

    private func quoteIsUpdated(_ quote: FundQuote) -> Bool {
        FundQuoteUpdatePolicy.isOfficiallyUpdated(quote, on: nowProvider())
    }


}

enum PortfolioStoreError: LocalizedError, Equatable {
    case invalidCode
    case invalidExchangeCode
    case invalidPosition
    case invalidCost
    case missingNetValue
    case missingExchangeMarketPrice
    case invalidExecutionPrice
    case invalidTradeFee
    case fundNotFound
    case pendingNetValue
    case insufficientShares
    case tradeRecordNotFound
    case buyTradeRequiresAmount
    case sellTradeRequiresShare
    case exchangePositionRequiresShares
    case exchangeTradeRequiresShares
    case invalidExchangeSellableShares
    case invalidExchangeReconciliationDate
    case invalidExchangeReconciliationValue
    case operationUnavailableForAccount
    case invalidConversionTarget
    case concurrentModification
    case jdFinanceAccountUnidentified
    case jdFinanceAccountMismatch
    case invalidJDFinanceSyncState
    case performanceHistoryWriteFailed(String)
    case importRecoveryRequired
    case tradingCalendarUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            "请输入基金代码"
        case .invalidExchangeCode:
            "请输入 6 位场内基金代码"
        case .invalidPosition:
            "请输入大于 0 的持仓金额或份额"
        case .invalidCost:
            "成本价计算失败，请检查持仓金额和收益"
        case .missingNetValue:
            "无法获取基金净值，请改用按份额并填写成本价"
        case .missingExchangeMarketPrice:
            "无法获取最新成交价，暂时不能按金额推算；请重试或改用按份额"
        case .invalidExecutionPrice:
            "请输入大于 0 的实际成交价"
        case .invalidTradeFee:
            "手续费不能为负，也不能超过卖出成交金额"
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
        case .exchangePositionRequiresShares:
            "场内持仓需按份额和平均成本价录入"
        case .exchangeTradeRequiresShares:
            "场内买卖需按实际成交份额录入"
        case .invalidExchangeSellableShares:
            "可卖份额不能为负数或大于持仓份额；T+0 基金必须全部可卖"
        case .invalidExchangeReconciliationDate:
            "对账日期无效，不能晚于今天"
        case .invalidExchangeReconciliationValue:
            "首次录入日对账数据无效，请先确认持仓总市值并检查盈亏金额"
        case .operationUnavailableForAccount:
            "此操作不适用于当前账户类型"
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
        case .tradingCalendarUnavailable:
            "该日期超出交易日历覆盖范围，请更新日历后重试"
        case .importRecoveryRequired:
            "上次导入未完整结束，请重新加载持仓以恢复后再操作"
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
