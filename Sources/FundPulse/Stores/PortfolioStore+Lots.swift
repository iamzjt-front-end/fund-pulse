import Foundation

extension PortfolioStore {
    func availableShares(for fund: FundPosition) -> Double {
        effectiveLots(for: fund).reduce(0) { $0 + $1.shares }
    }

    func exchangeShareAvailability(
        for fund: FundPosition,
        on dateText: String
    ) -> ExchangeShareAvailability {
        let lots = effectiveLots(for: fund)
        let recordsByID = exchangeTradeRecordsByID(for: fund.code)
        var sellableShares = 0.0
        var nextUnlockDate: String?

        for lot in lots {
            guard let sellableDate = exchangeLotSellableDate(
                lot, fund: fund, recordsByID: recordsByID
            ) else { continue }
            if sellableDate.isEmpty || sellableDate <= dateText {
                sellableShares += lot.shares
            } else if nextUnlockDate == nil || sellableDate < nextUnlockDate! {
                nextUnlockDate = sellableDate
            }
        }

        let heldShares = lots.reduce(0) { $0 + $1.shares }
        let normalizedSellableShares = min(max(sellableShares, 0), heldShares)
        return ExchangeShareAvailability(
            heldShares: heldShares,
            sellableShares: normalizedSellableShares,
            lockedShares: max(heldShares - normalizedSellableShares, 0),
            nextUnlockDate: nextUnlockDate
        )
    }

    private func exchangeTradeRecordsByID(for code: String) -> [String: FundTradeRecord] {
        (snapshot.tradeRecords ?? []).reduce(into: [:]) { result, record in
            guard record.code == code, record.status == .confirmed else { return }
            result[record.id] = record
        }
    }

    private func exchangeLotSellableDate(
        _ lot: FundPositionLot,
        fund: FundPosition,
        recordsByID: [String: FundTradeRecord]
    ) -> String? {
        if let unlockAfter = lot.exchangeUnlockAfterDate {
            return TradingCalendar.nextFundTradingDate(after: unlockAfter)
        }
        if let exchangeSellableDate = lot.exchangeSellableDate {
            return exchangeSellableDate
        }
        guard let record = recordsByID[lot.id] else {
            // Unmapped and legacy lots are imported holding baselines, so their
            // recorded position date is already sellable rather than a new buy.
            return lot.positionDate
        }

        guard fund.resolvedExchangeTurnaroundRule == .nextTradingDay,
              record.kind == .buy || record.kind == .conversionIn
        else {
            return record.tradeDate
        }
        return TradingCalendar.nextFundTradingDate(after: record.tradeDate)
    }

    func effectiveLots(for fund: FundPosition) -> [FundPositionLot] {
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

    func validatedExchangeSellableShares(
        requested: Double?,
        held: Double,
        rule: ExchangeTurnaroundRule
    ) throws -> Double {
        guard held.isFinite, held > 0 else {
            throw PortfolioStoreError.invalidPosition
        }
        let sellable = requested ?? held
        guard sellable.isFinite,
              sellable >= -PortfolioPrecision.shareAvailabilityTolerance,
              sellable <= held + PortfolioPrecision.shareAvailabilityTolerance
        else {
            throw PortfolioStoreError.invalidExchangeSellableShares
        }
        if rule == .sameDay,
           sellable + PortfolioPrecision.shareAvailabilityTolerance < held {
            throw PortfolioStoreError.invalidExchangeSellableShares
        }
        return roundedDisplayedShares(min(max(sellable, 0), held))
    }

    func exchangeBaselineLots(
        from baseLot: FundPositionLot,
        draft: FundPositionDraft
    ) throws -> [FundPositionLot] {
        let rule = draft.exchangeTurnaroundRule ?? .nextTradingDay
        let sellableShares = try validatedExchangeSellableShares(
            requested: draft.exchangeSellableShares,
            held: baseLot.shares,
            rule: rule
        )
        let lockedShares = roundedDisplayedShares(baseLot.shares - sellableShares)
        let sellableDate = draft.positionDate
        let lockedSellableDate: String? = lockedShares > PortfolioPrecision.shareAvailabilityTolerance
            ? (rule == .sameDay
                ? sellableDate
                : TradingCalendar.nextFundTradingDate(after: sellableDate))
            : nil

        guard lockedShares > PortfolioPrecision.shareAvailabilityTolerance else {
            var lot = baseLot
            lot.exchangeSellableDate = sellableDate
            return [lot]
        }

        let totalPrincipal = lotPrincipal(baseLot)
        func splitLot(id: String, shares: Double, sellableDate: String?) -> FundPositionLot {
            var lot = baseLot
            lot.id = id
            lot.shares = shares
            lot.principal = totalPrincipal * shares / baseLot.shares
            lot.exchangeSellableDate = sellableDate
            lot.exchangeUnlockAfterDate = sellableDate == nil ? draft.positionDate : nil
            return lot
        }

        var lots: [FundPositionLot] = []
        if sellableShares > PortfolioPrecision.shareAvailabilityTolerance {
            lots.append(splitLot(
                id: "\(baseLot.id)-sellable",
                shares: sellableShares,
                sellableDate: sellableDate
            ))
        }
        lots.append(splitLot(id: "\(baseLot.id)-locked", shares: lockedShares, sellableDate: lockedSellableDate))
        return lots
    }

    func syncAggregateFields(for fund: inout FundPosition) {
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

    func rebuildPendingTradesFromRecords(for code: String) {
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

    func repairPendingTradeIndexFromRecords() {
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

    func rebuildFundPositionFromTradeRecords(code: String) throws {
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
        let recordsByID = records.reduce(into: [String: FundTradeRecord]()) { result, record in
            result[record.id] = record
        }
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
                    lots = exchangeBaselineLots(from: lot, record: record, fund: fund)
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
                if accountKind == .onExchange {
                    lots = try lotsAfterExchangeSelling(
                        shares: sellShares,
                        from: lots,
                        fund: fund,
                        saleDate: record.tradeDate,
                        recordsByID: recordsByID
                    )
                } else {
                    lots = try lotsAfterSelling(shares: sellShares, from: lots)
                }
                fund.positionDate = record.tradeDate
                fund.positionTimeType = record.tradeTimeType
            }
        }

        fund.lots = lots
        syncAggregateFields(for: &fund)
        snapshot.funds[index] = fund
    }

    func resetEmptyPortfolioAggregates(updateTime: Date) {
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

    func shouldRestoreLegacyFundAfterDeletingTrade(
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

    func restoreLegacyFundAfterDeletingTrade(
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

    func lotsAfterRemovingRecentlyAdded(
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

    func lot(from record: FundTradeRecord) -> FundPositionLot? {
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

    func exchangeBaselineLots(
        from baseLot: FundPositionLot,
        record: FundTradeRecord,
        fund: FundPosition
    ) -> [FundPositionLot] {
        guard accountKind == .onExchange,
              let requestedSellableShares = record.exchangeInitialSellableShares,
              requestedSellableShares.isFinite,
              requestedSellableShares >= 0,
              requestedSellableShares <= baseLot.shares + PortfolioPrecision.shareAvailabilityTolerance
        else {
            return [baseLot]
        }

        let sellableShares = roundedDisplayedShares(
            min(max(requestedSellableShares, 0), baseLot.shares)
        )
        let lockedShares = roundedDisplayedShares(baseLot.shares - sellableShares)
        guard lockedShares > PortfolioPrecision.shareAvailabilityTolerance else {
            var lot = baseLot
            lot.exchangeSellableDate = record.tradeDate
            return [lot]
        }
        guard fund.resolvedExchangeTurnaroundRule == .nextTradingDay else {
            return [baseLot]
        }
        let lockedSellableDate = TradingCalendar.nextFundTradingDate(after: record.tradeDate)

        let totalPrincipal = lotPrincipal(baseLot)
        func splitLot(id: String, shares: Double, sellableDate: String?) -> FundPositionLot {
            var lot = baseLot
            lot.id = id
            lot.shares = shares
            lot.principal = totalPrincipal * shares / baseLot.shares
            lot.exchangeSellableDate = sellableDate
            lot.exchangeUnlockAfterDate = sellableDate == nil ? record.tradeDate : nil
            return lot
        }

        var lots: [FundPositionLot] = []
        if sellableShares > PortfolioPrecision.shareAvailabilityTolerance {
            lots.append(splitLot(
                id: "\(record.id)-sellable",
                shares: sellableShares,
                sellableDate: record.tradeDate
            ))
        }
        lots.append(splitLot(
            id: "\(record.id)-locked",
            shares: lockedShares,
            sellableDate: lockedSellableDate
        ))
        return lots
    }

    func confirmedShares(for record: FundTradeRecord) throws -> Double {
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

    func repairAmountModeSharePrecisionFromTradeRecords() {
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

    private func lotsAfterExchangeSelling(
        shares sellShares: Double,
        from sourceLots: [FundPositionLot],
        fund: FundPosition,
        saleDate: String,
        recordsByID: [String: FundTradeRecord]
    ) throws -> [FundPositionLot] {
        guard sellShares > 0 else { throw PortfolioStoreError.invalidPosition }
        var remainingToSell = sellShares
        var lots = sourceLots.sorted { lhs, rhs in
            if lhs.incomeStartDate == rhs.incomeStartDate {
                return lhs.positionDate < rhs.positionDate
            }
            return lhs.incomeStartDate < rhs.incomeStartDate
        }
        let sellableIndices = lots.indices.filter { index in
            guard let sellableDate = exchangeLotSellableDate(
                lots[index], fund: fund, recordsByID: recordsByID
            ) else { return false }
            return sellableDate.isEmpty || sellableDate <= saleDate
        }
        let sellableShares = sellableIndices.reduce(0) { $0 + lots[$1].shares }
        guard sellShares <= sellableShares + PortfolioPrecision.shareAvailabilityTolerance else {
            throw PortfolioStoreError.insufficientShares
        }

        for index in sellableIndices {
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

}
