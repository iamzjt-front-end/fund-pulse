import Foundation

extension PortfolioStore {
    func processPendingTrades(quotes: [String: FundQuote]) async {
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

    func processPendingConversions(quotes: [String: FundQuote]) async {
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

    func shouldConfirmPendingTrade(acceptedDate: String) -> Bool {
        guard let date = DateOnlyFormatter.parse(acceptedDate), TradingCalendar.coverageWarning(on: date) == nil else {
            return false
        }
        return acceptedDate < DateOnlyFormatter.string(from: nowProvider())
    }

    func resolvedInitialAcceptedDate(
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

    func resolvedInitialConfirmedNetValue(
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
              quote.officialNetValue != nil
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

    func restorePendingInitialPosition(for code: String, records: [FundTradeRecord]) {
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

    func processPendingPositions(quotes: [String: FundQuote]) async {
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

}
