import Foundation

extension PortfolioStore {
    func appendInitialTradeRecord(
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
            createdAt: nowProvider(),
            confirmedAt: status == .confirmed ? nowProvider() : nil,
            exchangeInitialSellableShares: accountKind == .onExchange
                ? (draft.exchangeSellableShares ?? confirmedShares)
                : nil
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

    func confirmedInitialShares(
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

    func confirmedInitialPrice(
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

    func confirmPendingTradeRecord(
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

    func confirmPendingConversionRecords(
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

    func markPendingConversion(_ conversionID: String, failureReason: String?) {
        guard var records = snapshot.tradeRecords, !records.isEmpty else {
            return
        }
        for index in records.indices where records[index].conversionID == conversionID {
            records[index].status = .pending
            records[index].failureReason = failureReason
        }
        snapshot.tradeRecords = records
    }

    func confirmInitialTradeRecord(
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

    func tradeRecord(
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
        syncMetadata: FundTradeSyncMetadata? = nil,
        exchangeInitialSellableShares: Double? = nil
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
            waitsForExternalConfirmation: syncMetadata?.waitsForExternalConfirmation,
            exchangeInitialSellableShares: exchangeInitialSellableShares
        )
    }

    func appendTradeRecord(_ record: FundTradeRecord) {
        var records = snapshot.tradeRecords ?? []
        records.append(record)
        snapshot.tradeRecords = records
    }

    func hasImportedTrade(matching draft: FundTradeDraft) -> Bool {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return false }

        if (snapshot.pendingTrades ?? []).contains(where: { pendingTradeMatches($0, draft: draft, code: code) }) {
            return true
        }

        return (snapshot.tradeRecords ?? []).contains { tradeRecordMatches($0, draft: draft, code: code) }
    }

    func markImportedTrade(
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

    func overwriteJDFinanceTradeRecord(
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

    func overwriteJDFinanceConversionRecords(
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

    func hasImportedConversion(matching draft: FundConversionDraft) -> Bool {
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

    func markImportedConversion(
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

    func syncMetadata(from pendingTrade: FundPendingTrade) -> FundTradeSyncMetadata? {
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

    func resetTradeHistoryForEditedFund(
        codes: Set<String>,
        preservingRecordIDs: Set<String> = []
    ) {
        let normalizedCodes = Set(codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !normalizedCodes.isEmpty else { return }

        var removedRecordIDs = Set<String>()
        var removedConversionIDs = Set<String>()
        let preservedConversionIDs = Set((snapshot.tradeRecords ?? []).compactMap { record in
            preservingRecordIDs.contains(record.id) ? record.conversionID : nil
        })
        if var records = snapshot.tradeRecords {
            for record in records
            where !preservingRecordIDs.contains(record.id)
                && record.conversionID.map(preservedConversionIDs.contains) != true
                && (normalizedCodes.contains(record.code) || record.linkedCode.map(normalizedCodes.contains) == true)
            {
                removedRecordIDs.insert(record.id)
                if let conversionID = record.conversionID {
                    removedConversionIDs.insert(conversionID)
                }
            }

            records.removeAll { record in
                if preservingRecordIDs.contains(record.id)
                    || record.conversionID.map(preservedConversionIDs.contains) == true
                {
                    return false
                }
                return normalizedCodes.contains(record.code)
                    || record.linkedCode.map(normalizedCodes.contains) == true
                    || record.conversionID.map(removedConversionIDs.contains) == true
            }
            snapshot.tradeRecords = records.isEmpty ? nil : records
        }

        snapshot.pendingTrades?.removeAll { pendingTrade in
            if preservingRecordIDs.contains(pendingTrade.id)
                || pendingTrade.recordID.map(preservingRecordIDs.contains) == true
            {
                return false
            }
            return normalizedCodes.contains(pendingTrade.code)
                || pendingTrade.recordID.map(removedRecordIDs.contains) == true
        }
        if snapshot.pendingTrades?.isEmpty == true {
            snapshot.pendingTrades = nil
        }

        snapshot.pendingConversions?.removeAll { pendingConversion in
            if preservedConversionIDs.contains(pendingConversion.id) {
                return false
            }
            return normalizedCodes.contains(pendingConversion.fromCode)
                || normalizedCodes.contains(pendingConversion.toCode)
                || removedConversionIDs.contains(pendingConversion.id)
        }
        if snapshot.pendingConversions?.isEmpty == true {
            snapshot.pendingConversions = nil
        }
    }

    func syncInitialTradeRecordsFromFunds() {
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

    func updateTradeRecord(
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

    func tradeKind(for action: FundTradeAction) -> FundTradeKind {
        switch action {
        case .buy:
            .buy
        case .sell:
            .sell
        }
    }

}
