import Foundation
import Observation

@Observable
@MainActor
final class PortfolioStore {
    private(set) var snapshot: PortfolioSnapshot = .empty
    private(set) var loadState: LoadState = .loading
    private(set) var dataDirectory: URL
    private let quoteService: FundQuoteService
    private let nowProvider: () -> Date

    enum LoadState: Equatable {
        case loading
        case loaded
        case missingPlainData(hasLegacyStore: Bool)
        case failed(String)
    }

    init(
        dataDirectory: URL = AppDataPaths.sharedDataDirectory,
        quoteService: FundQuoteService = FundQuoteService(),
        now: @escaping () -> Date = { .now }
    ) {
        self.dataDirectory = dataDirectory
        self.quoteService = quoteService
        self.nowProvider = now
    }

    var dataFileURL: URL {
        dataDirectory.appending(path: "portfolio.json")
    }

    func load() {
        loadState = .loading

        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            let url = dataFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                snapshot = try decoder.decode(PortfolioSnapshot.self, from: data)
                loadState = .loaded
                return
            }

            snapshot = .sample
            loadState = .missingPlainData(hasLegacyStore: AppDataPaths.hasLegacyStore(in: dataDirectory))
        } catch {
            snapshot = .sample
            loadState = .failed(error.localizedDescription)
        }
    }

    func writeSamplePortfolioIfNeeded() throws {
        let url = dataDirectory.appending(path: "portfolio.json")
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }

        try save(PortfolioSnapshot.sample)
        load()
    }

    func exportPortfolio(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    func importPortfolio(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importedSnapshot = try decoder.decode(PortfolioSnapshot.self, from: data)
        try save(importedSnapshot)
        snapshot = importedSnapshot
        loadState = .loaded
    }

    func refreshQuotes() async {
        if case .loading = loadState {
            load()
        }

        let codes = snapshot.funds.map(\.code)
        guard !codes.isEmpty else {
            snapshot.updateTime = .now
            loadState = .loaded
            try? save(snapshot)
            return
        }

        do {
            let quotes = await fetchQuotes(codes: codes, source: .fundBabyAuto)
            normalizePrematureInitialConfirmations()
            await processPendingTrades(quotes: quotes)
            await processPendingPositions(quotes: quotes)
            snapshot = PortfolioCalculator.applyingQuotes(to: snapshot, quotes: quotes, now: nowProvider())
            try save(snapshot)
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
        let quote = try? await quoteService.fetchQuote(code: code, source: .fundBabyAuto)
        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.positionDate,
            timeType: draft.positionTimeType
        )
        let canConfirmInitialPosition = existingFund != nil || shouldConfirmPendingTrade(acceptedDate: acceptedDate)
        let fetchedConfirmedNetValue = await quoteService.fetchConfirmedNetValue(
            code: code,
            acceptedDate: acceptedDate,
            latestQuote: quote
        )
        let confirmedNetValue = canConfirmInitialPosition ? fetchedConfirmedNetValue : nil
        let fund = try makeFundPosition(
            from: draft,
            existingFund: existingFund,
            quote: quote,
            confirmedNetValue: confirmedNetValue,
            isEditingExistingFund: existingFund != nil
        )
        let isCreatingFund = existingFund == nil && existingCode == nil
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
                draft: draft,
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
        return try? await quoteService.fetchQuote(code: code, source: .fundBabyAuto)
    }

    func adjustFundPosition(_ draft: FundTradeDraft) async throws {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw PortfolioStoreError.invalidCode
        }
        guard let index = snapshot.funds.firstIndex(where: { $0.code == code }) else {
            throw PortfolioStoreError.fundNotFound
        }

        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.tradeDate,
            timeType: draft.tradeTimeType
        )
        appendPendingTrade(draft, fund: snapshot.funds[index], acceptedDate: acceptedDate)
        try save(snapshot)
        await refreshQuotes()
    }

    func deleteFund(code: String) async throws {
        snapshot.funds.removeAll { $0.code == code }
        snapshot.pendingTrades?.removeAll { $0.code == code }
        if snapshot.pendingTrades?.isEmpty == true {
            snapshot.pendingTrades = nil
        }
        snapshot.tradeRecords?.removeAll { $0.code == code }
        if snapshot.tradeRecords?.isEmpty == true {
            snapshot.tradeRecords = nil
        }
        try save(snapshot)
        await refreshQuotes()
    }

    func editTradeRecord(id: String, with draft: FundTradeDraft) async throws {
        guard var records = snapshot.tradeRecords,
              let index = records.firstIndex(where: { $0.id == id })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }
        guard records[index].kind != .newFund else {
            throw PortfolioStoreError.unsupportedTradeRecordEdit
        }

        let code = records[index].code
        let acceptedDate = TradingCalendar.acceptedTradeDate(
            positionDate: draft.tradeDate,
            timeType: draft.tradeTimeType
        )
        let fundName = snapshot.funds.first { $0.code == code }?.name ?? records[index].name
        records[index].kind = tradeKind(for: draft.action)
        records[index].status = .pending
        records[index].name = fundName
        records[index].mode = draft.mode
        records[index].amount = draft.amount
        records[index].shares = draft.shares
        records[index].confirmedShares = nil
        records[index].price = nil
        records[index].tradeDate = draft.tradeDate
        records[index].tradeTimeType = draft.tradeTimeType
        records[index].acceptedDate = acceptedDate
        records[index].confirmedAt = nil
        records[index].failureReason = nil
        snapshot.tradeRecords = records
        rebuildPendingTradesFromRecords(for: code)
        try rebuildFundPositionFromTradeRecords(code: code)
        try save(snapshot)
        await refreshQuotes()
    }

    func deleteTradeRecord(id: String) async throws {
        guard var records = snapshot.tradeRecords,
              let index = records.firstIndex(where: { $0.id == id })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }

        let code = records[index].code
        records.remove(at: index)
        snapshot.tradeRecords = records.isEmpty ? nil : records
        snapshot.pendingTrades?.removeAll { $0.recordID == id }
        rebuildPendingTradesFromRecords(for: code)
        try rebuildFundPositionFromTradeRecords(code: code)
        try save(snapshot)
        await refreshQuotes()
    }

    private func fetchQuotes(codes: [String], source: QuoteSource) async -> [String: FundQuote] {
        await withTaskGroup(of: (String, FundQuote?).self) { group in
            for code in codes {
                group.addTask { [quoteService] in
                    do {
                        return (code, try await quoteService.fetchQuote(code: code, source: source))
                    } catch {
                        return (code, nil)
                    }
                }
            }

            var quotes: [String: FundQuote] = [:]
            for await (code, quote) in group {
                if let quote {
                    quotes[code] = quote
                }
            }
            return quotes
        }
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

        let position: (shares: Double, cost: Double)?
        let status: FundHoldingStatus
        let pendingAmount: Double?
        let pendingProfit: Double?

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
            } else {
                let amount = draft.positionAmount ?? 0
                guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
                let principal = amount - draft.positionProfit
                guard principal > 0 else { throw PortfolioStoreError.invalidCost }
                position = nil
                status = .pending
                pendingAmount = amount
                pendingProfit = draft.positionProfit == 0 ? nil : draft.positionProfit
            }
        case .share:
            position = try resolvedPosition(draft: draft, netValue: confirmedNetValue ?? draft.cost)
            status = .holding
            pendingAmount = nil
            pendingProfit = nil
        }

        let lots: [FundPositionLot]? = position.map {
            [
                FundPositionLot(
                    id: UUID().uuidString,
                    shares: $0.shares,
                    cost: $0.cost,
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
            holdingRate: existingFund?.holdingRate,
            status: status,
            isUpdated: quote.map(quoteIsUpdated) ?? existingFund?.isUpdated ?? false,
            migratedShares: position?.shares ?? 0,
            migratedCost: position?.cost,
            migratedPrincipal: position.map { $0.shares * $0.cost } ?? 0,
            incomeStartDate: incomeStartDate,
            positionMode: draft.positionMode,
            positionDate: draft.positionDate,
            positionTimeType: draft.positionTimeType,
            pendingAmount: pendingAmount,
            pendingProfit: pendingProfit,
            zdfRange: draft.zdfRange,
            jzNotice: draft.jzNotice,
            memo: draft.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.memo,
            lots: lots
        )
    }

    @discardableResult
    private func applyBuy(_ draft: FundTradeDraft, price: Double, to fund: inout FundPosition) throws -> Double {
        let shares: Double
        switch draft.mode {
        case .amount:
            let amount = draft.amount ?? 0
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            shares = rounded(amount / price, places: 2)
        case .share:
            shares = rounded(draft.shares ?? 0, places: 2)
        }
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }

        let lot = FundPositionLot(
            id: UUID().uuidString,
            shares: shares,
            cost: rounded(price, places: 4),
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
        guard let pendingTrades = snapshot.pendingTrades, !pendingTrades.isEmpty else {
            return
        }

        var remaining: [FundPendingTrade] = []
        for pendingTrade in pendingTrades {
            let draft = pendingTrade.draft
            guard let index = snapshot.funds.firstIndex(where: { $0.code == draft.code }) else {
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

    private func shouldConfirmPendingTrade(acceptedDate: String) -> Bool {
        guard DateOnlyFormatter.parse(acceptedDate) != nil else {
            return false
        }
        return acceptedDate < DateOnlyFormatter.string(from: nowProvider())
    }

    private func normalizePrematureInitialConfirmations() {
        guard var records = snapshot.tradeRecords, !records.isEmpty else {
            return
        }

        var affectedCodes = Set<String>()
        for index in records.indices {
            guard records[index].kind == .newFund,
                  records[index].status == .confirmed,
                  records[index].mode == .amount,
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

    private func processPendingPositions(quotes: [String: FundQuote]) async {
        for index in snapshot.funds.indices {
            var fund = snapshot.funds[index]
            guard fund.status.isPendingDisplay,
                  fund.positionMode == .amount,
                  let amount = fund.pendingAmount,
                  amount > 0
            else {
                continue
            }

            let positionDate = fund.positionDate ?? DateOnlyFormatter.string(from: .now)
            let positionTimeType = fund.positionTimeType ?? .before15
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
                try confirmPendingAmountPosition(
                    amount: amount,
                    profit: fund.pendingProfit ?? 0,
                    price: confirmedNetValue,
                    acceptedDate: acceptedDate,
                    positionDate: positionDate,
                    positionTimeType: positionTimeType,
                    fund: &fund
                )
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

    private func appendPendingTrade(
        _ draft: FundTradeDraft,
        fund: FundPosition,
        acceptedDate: String
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
            tradeDate: draft.tradeDate,
            tradeTimeType: draft.tradeTimeType,
            acceptedDate: acceptedDate,
            createdAt: .now,
            confirmedAt: nil
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
                createdAt: .now
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
        let shares = rounded(amount / price, places: 2)
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
        let cost = rounded(principal / shares, places: 4)
        guard cost > 0 else { throw PortfolioStoreError.invalidCost }

        let incomeStartDate = acceptedDate
        let lot = FundPositionLot(
            id: UUID().uuidString,
            shares: shares,
            cost: cost,
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

    @discardableResult
    private func applySell(_ draft: FundTradeDraft, price: Double, from fund: inout FundPosition) throws -> Double {
        let sellShares: Double
        switch draft.mode {
        case .amount:
            let amount = draft.amount ?? 0
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            sellShares = rounded(amount / price, places: 2)
        case .share:
            sellShares = rounded(draft.shares ?? 0, places: 2)
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
        guard sellShares <= availableShares + 0.0001 else {
            throw PortfolioStoreError.insufficientShares
        }

        for index in lots.indices {
            guard remainingToSell > 0 else { break }
            let deducted = min(lots[index].shares, remainingToSell)
            lots[index].shares = rounded(lots[index].shares - deducted, places: 2)
            remainingToSell = rounded(remainingToSell - deducted, places: 2)
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
        let totalShares = rounded(lots.reduce(0) { $0 + $1.shares }, places: 2)
        let totalCost = lots.reduce(0) { $0 + $1.shares * $1.cost }
        fund.migratedShares = totalShares
        fund.migratedCost = totalShares > 0 ? rounded(totalCost / totalShares, places: 4) : 0
        fund.migratedPrincipal = totalCost
        fund.status = totalShares > 0 ? .holding : .pending
        if totalShares > 0 {
            fund.pendingAmount = nil
            fund.pendingProfit = nil
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
                    createdAt: record.createdAt
                )
            }
        let next = existing + rebuilt
        snapshot.pendingTrades = next.isEmpty ? nil : next
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
            syncAggregateFields(for: &fund)
            snapshot.funds[index] = fund
            return
        }

        var lots: [FundPositionLot] = []
        var didRebuildPosition = false
        for record in records {
            switch record.kind {
            case .newFund:
                if let lot = lot(from: record) {
                    lots = [lot]
                    didRebuildPosition = true
                    fund.positionMode = record.mode
                    fund.positionDate = record.tradeDate
                    fund.positionTimeType = record.tradeTimeType
                    fund.incomeStartDate = record.acceptedDate
                    fund.dateText = Self.confirmedDateText(record.acceptedDate)
                }
            case .buy:
                guard let lot = lot(from: record) else { continue }
                lots.append(lot)
                didRebuildPosition = true
                fund.positionMode = record.mode
                fund.positionDate = record.tradeDate
                fund.positionTimeType = record.tradeTimeType
            case .sell:
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

    private func lot(from record: FundTradeRecord) -> FundPositionLot? {
        guard let shares = record.confirmedShares ?? record.shares,
              shares > 0
        else {
            return nil
        }

        let cost: Double
        if let price = record.price, price > 0 {
            cost = price
        } else if let amount = record.amount, amount > 0 {
            cost = rounded(amount / shares, places: 4)
        } else {
            return nil
        }

        return FundPositionLot(
            id: record.id,
            shares: rounded(shares, places: 2),
            cost: rounded(cost, places: 4),
            incomeStartDate: record.acceptedDate,
            positionDate: record.tradeDate,
            positionTimeType: record.tradeTimeType
        )
    }

    private func confirmedShares(for record: FundTradeRecord) throws -> Double {
        if let shares = record.confirmedShares ?? record.shares, shares > 0 {
            return rounded(shares, places: 2)
        }
        if let amount = record.amount,
           let price = record.price,
           amount > 0,
           price > 0 {
            return rounded(amount / price, places: 2)
        }
        throw PortfolioStoreError.invalidPosition
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
        guard sellShares <= availableShares + 0.0001 else {
            throw PortfolioStoreError.insufficientShares
        }

        for index in lots.indices {
            guard remainingToSell > 0 else { break }
            let deducted = min(lots[index].shares, remainingToSell)
            lots[index].shares = rounded(lots[index].shares - deducted, places: 2)
            remainingToSell = rounded(remainingToSell - deducted, places: 2)
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
        let confirmedShares = status == .confirmed ? fund.migratedShares : nil
        let price = status == .confirmed ? (confirmedNetValue ?? fund.migratedCost) : nil
        let amount = draft.positionAmount ?? confirmedShares.flatMap { shares in
            price.map { rounded(shares * $0, places: 2) }
        }
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
            tradeDate: draft.positionDate,
            tradeTimeType: draft.positionTimeType,
            acceptedDate: acceptedDate,
            createdAt: .now,
            confirmedAt: status == .confirmed ? .now : nil
        )
        appendTradeRecord(record)
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
                record.confirmedAt = .now
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
                tradeDate: draft.tradeDate,
                tradeTimeType: draft.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: pendingTrade.createdAt,
                confirmedAt: .now
            )
        )
    }

    private func confirmInitialTradeRecord(
        fund: FundPosition,
        acceptedDate: String,
        price: Double
    ) {
        let totalShares = fund.migratedShares ?? effectiveLots(for: fund).reduce(0) { $0 + $1.shares }
        let amount = rounded(totalShares * price, places: 2)
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
        tradeDate: String,
        tradeTimeType: PositionTimeType,
        acceptedDate: String,
        createdAt: Date,
        confirmedAt: Date?
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
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType,
            acceptedDate: acceptedDate,
            createdAt: createdAt,
            confirmedAt: confirmedAt,
            failureReason: nil
        )
    }

    private func appendTradeRecord(_ record: FundTradeRecord) {
        var records = snapshot.tradeRecords ?? []
        records.append(record)
        snapshot.tradeRecords = records
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

    private func resolvedPosition(draft: FundPositionDraft, netValue: Double?) throws -> (shares: Double, cost: Double) {
        switch draft.positionMode {
        case .share:
            let shares = rounded(draft.shares ?? 0, places: 2)
            guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
            let cost = rounded(draft.cost ?? netValue ?? 0, places: 4)
            guard cost > 0 else { throw PortfolioStoreError.missingNetValue }
            return (shares, cost)

        case .amount:
            let amount = draft.positionAmount ?? 0
            guard amount > 0 else { throw PortfolioStoreError.invalidPosition }
            guard let netValue, netValue > 0 else { throw PortfolioStoreError.missingNetValue }
            let shares = rounded(amount / netValue, places: 2)
            guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
            let principal = amount - draft.positionProfit
            guard principal > 0 else { throw PortfolioStoreError.invalidCost }
            let cost = rounded(principal / shares, places: 4)
            guard cost > 0 else { throw PortfolioStoreError.invalidCost }
            return (shares, cost)
        }
    }

    private func quoteNetValue(_ quote: FundQuote?) -> Double? {
        guard let quote else { return nil }
        if quote.netValue > 0 { return quote.netValue }
        if quote.estimatedNetValue > 0 { return quote.estimatedNetValue }
        return nil
    }

    private func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
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
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let url = dataFileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

enum PortfolioStoreError: LocalizedError {
    case invalidCode
    case invalidPosition
    case invalidCost
    case missingNetValue
    case fundNotFound
    case pendingNetValue
    case insufficientShares
    case tradeRecordNotFound
    case unsupportedTradeRecordEdit

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
        case .unsupportedTradeRecordEdit:
            "新增基金记录暂不支持编辑，请编辑基金持仓信息"
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
