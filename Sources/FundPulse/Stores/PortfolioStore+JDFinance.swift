import Foundation

extension PortfolioStore {
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

}
