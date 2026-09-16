import Foundation

extension PortfolioStore {
    func upsertExchangeFund(
        _ draft: FundPositionDraft,
        replacing existingCode: String?
    ) async throws {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ExchangeFundQuoteService.securityID(for: code) != nil else {
            throw PortfolioStoreError.invalidExchangeCode
        }

        let baseSnapshot = snapshot
        let existingFund = snapshot.funds.first { $0.code == (existingCode ?? code) }
        let quote = try? await exchangeQuoteService.fetchQuote(code: code)
        guard snapshot == baseSnapshot else { throw PortfolioStoreError.concurrentModification }
        let confirmedPrice: Double?
        switch draft.positionMode {
        case .amount:
            guard let marketPrice = quote?.netValue, marketPrice > 0 else {
                throw PortfolioStoreError.missingExchangeMarketPrice
            }
            confirmedPrice = marketPrice
        case .share:
            confirmedPrice = draft.cost
        }

        let acceptedDate = draft.positionDate
        var normalizedDraft = draft
        normalizedDraft.code = code
        normalizedDraft.exchangeTurnaroundRule = draft.exchangeTurnaroundRule
            ?? existingFund?.resolvedExchangeTurnaroundRule
            ?? .nextTradingDay
        switch normalizedDraft.positionMode {
        case .amount:
            normalizedDraft.shares = nil
            normalizedDraft.cost = nil
        case .share:
            normalizedDraft.positionAmount = nil
            normalizedDraft.positionProfit = 0
            let position = try resolvedPosition(draft: normalizedDraft, netValue: confirmedPrice)
            normalizedDraft.exchangeSellableShares = try validatedExchangeSellableShares(
                requested: draft.exchangeSellableShares,
                held: position.shares,
                rule: normalizedDraft.exchangeTurnaroundRule ?? .nextTradingDay
            )
        }
        normalizedDraft.positionTimeType = .before15
        normalizedDraft.requiresTradeConfirmation = false

        var fund = try makeFundPosition(
            from: normalizedDraft,
            existingFund: existingFund,
            quote: quote,
            confirmedNetValue: confirmedPrice,
            isEditingExistingFund: existingFund != nil,
            acceptedDateOverride: acceptedDate
        )
        if let quote {
            fund.dateText = dateText(for: quote, fallback: fund.dateText)
        } else if acceptedDate.count >= 10 {
            fund.dateText = String(acceptedDate.dropFirst(5).prefix(5))
        }

        var funds = snapshot.funds.filter { $0.code != (existingCode ?? code) && $0.code != code }
        if let existingCode,
           let index = snapshot.funds.firstIndex(where: { $0.code == existingCode }) {
            funds.insert(fund, at: min(index, funds.count))
        } else {
            funds.insert(fund, at: 0)
        }
        snapshot.funds = funds

        if existingFund != nil {
            resetTradeHistoryForEditedFund(codes: Set([existingCode ?? code, code]))
        }
        // The new share/sellable baseline replaces the legacy account-level
        // first-day P&L override. Keep that old field readable for backups,
        // but never let it shadow a newly entered exchange baseline.
        snapshot.exchangeAccountReconciliation = nil
        appendInitialTradeRecord(
            draft: normalizedDraft,
            fund: fund,
            acceptedDate: acceptedDate,
            confirmedNetValue: confirmedPrice
        )
        try save(snapshot)
        await refreshQuotes()
    }

    func recordExchangeTrade(_ draft: FundTradeDraft) async throws {
        let resolved = try resolvedExchangeTrade(draft)
        let fund = snapshot.funds[resolved.fundIndex]
        let record = FundTradeRecord(
            id: UUID().uuidString,
            kind: tradeKind(for: draft.action),
            status: .confirmed,
            code: resolved.code,
            name: fund.name,
            mode: .share,
            amount: resolved.cashAmount,
            shares: resolved.shares,
            confirmedShares: resolved.shares,
            price: resolved.price,
            tradeDate: draft.tradeDate,
            tradeTimeType: .before15,
            acceptedDate: draft.tradeDate,
            createdAt: nowProvider(),
            confirmedAt: nowProvider(),
            failureReason: nil,
            feeAmount: resolved.feeAmount
        )
        appendTradeRecord(record)
        try rebuildFundPositionFromTradeRecords(code: resolved.code)
        try save(snapshot)
        await refreshQuotes()
    }

    func editExchangeTradeRecord(id: String, with draft: FundTradeDraft) async throws {
        guard var records = snapshot.tradeRecords,
              let recordIndex = records.firstIndex(where: { $0.id == id })
        else {
            throw PortfolioStoreError.tradeRecordNotFound
        }
        let originalKind = records[recordIndex].kind
        guard originalKind == .newFund || originalKind == .buy || originalKind == .sell else {
            throw PortfolioStoreError.operationUnavailableForAccount
        }

        var normalizedDraft = draft
        normalizedDraft.code = records[recordIndex].code
        if originalKind == .newFund {
            normalizedDraft.action = .buy
        }
        let editableSellShares = originalKind == .sell
            ? (records[recordIndex].confirmedShares ?? records[recordIndex].shares ?? 0)
            : 0
        let resolved = try resolvedExchangeTrade(
            normalizedDraft,
            additionalAvailableSellShares: editableSellShares
        )
        let previousSnapshot = snapshot

        records[recordIndex].kind = originalKind == .newFund ? .newFund : tradeKind(for: normalizedDraft.action)
        records[recordIndex].status = .confirmed
        records[recordIndex].name = snapshot.funds[resolved.fundIndex].name
        records[recordIndex].mode = .share
        records[recordIndex].amount = resolved.cashAmount
        records[recordIndex].shares = resolved.shares
        records[recordIndex].confirmedShares = resolved.shares
        records[recordIndex].price = resolved.price
        records[recordIndex].profit = nil
        records[recordIndex].tradeDate = normalizedDraft.tradeDate
        records[recordIndex].tradeTimeType = .before15
        records[recordIndex].acceptedDate = normalizedDraft.tradeDate
        records[recordIndex].confirmedAt = nowProvider()
        records[recordIndex].failureReason = nil
        records[recordIndex].buyFeeRate = nil
        records[recordIndex].sellFeeMode = nil
        records[recordIndex].sellFeeValue = nil
        records[recordIndex].feeAmount = resolved.feeAmount
        snapshot.tradeRecords = records

        do {
            rebuildPendingTradesFromRecords(for: resolved.code)
            try rebuildFundPositionFromTradeRecords(code: resolved.code)
            try save(snapshot)
        } catch {
            snapshot = previousSnapshot
            throw error
        }
        await refreshQuotes()
    }

    private func resolvedExchangeTrade(
        _ draft: FundTradeDraft,
        additionalAvailableSellShares: Double = 0
    ) throws -> (code: String, fundIndex: Int, shares: Double, price: Double, feeAmount: Double, cashAmount: Double) {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ExchangeFundQuoteService.securityID(for: code) != nil else {
            throw PortfolioStoreError.invalidExchangeCode
        }
        guard let fundIndex = snapshot.funds.firstIndex(where: { $0.code == code }) else {
            throw PortfolioStoreError.fundNotFound
        }
        guard draft.mode == .share else {
            throw PortfolioStoreError.exchangeTradeRequiresShares
        }

        let shares = roundedDisplayedShares(draft.shares ?? 0)
        guard shares > 0 else { throw PortfolioStoreError.invalidPosition }
        let price = roundedCost(draft.price ?? 0)
        guard price > 0 else { throw PortfolioStoreError.invalidExecutionPrice }
        let feeAmount = roundedMoney(draft.feeAmount ?? 0)
        guard feeAmount >= 0 else { throw PortfolioStoreError.invalidTradeFee }

        if draft.action == .sell {
            let availableShares = exchangeShareAvailability(
                for: snapshot.funds[fundIndex],
                on: draft.tradeDate
            ).sellableShares
                + max(additionalAvailableSellShares, 0)
            guard shares <= availableShares + PortfolioPrecision.shareAvailabilityTolerance else {
                throw PortfolioStoreError.insufficientShares
            }
        }

        let grossAmount = roundedMoney(shares * price)
        if draft.action == .sell, feeAmount > grossAmount {
            throw PortfolioStoreError.invalidTradeFee
        }
        let cashAmount = draft.action == .buy
            ? roundedMoney(grossAmount + feeAmount)
            : roundedMoney(grossAmount - feeAmount)
        return (code, fundIndex, shares, price, feeAmount, cashAmount)
    }

}
