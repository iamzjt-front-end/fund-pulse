import Foundation

enum JDFinanceHoldingsSyncPlanner {
    private struct ConsolidatedProducts {
        var products: [JDFinanceHoldingProduct]
        var warnings: [String]
    }

    private struct ReconciliationResult {
        var notices: [JDFinanceReconciliationNotice]
        var automaticConfirmations: [JDFinanceAutomaticConfirmation]
        var consumedOrderIndices: Set<Int>
        var orders: [JDFinanceTradeOrderRecord]
    }

    static func preview(
        remoteSnapshot: JDFinanceHoldingsSnapshot,
        localSnapshot: PortfolioSnapshot
    ) -> JDFinanceHoldingsSyncPreview {
        let localFundsByCode = localSnapshot.funds.reduce(into: [String: FundPosition]()) { result, fund in
            if result[fund.code] == nil {
                result[fund.code] = fund
            }
        }
        let localFundsByName = localFundsByNormalizedName(localSnapshot.funds)
        let initiallyResolvedProducts = remoteSnapshot.products.map {
            resolvedProduct($0, localFundsByCode: localFundsByCode, localFundsByName: localFundsByName)
        }
        let localTradeRecords = localSnapshot.tradeRecords ?? []
        let consolidation = consolidatedProducts(initiallyResolvedProducts)
        let remoteProducts = consolidation.products.map { product in
            var reconciledProduct = product
            reconciledProduct.reconciledPendingBuyAmount = reconciledPendingBuyAmount(
                for: product,
                localSnapshot: localSnapshot,
                localTradeRecords: localTradeRecords
            )
            return reconciledProduct
        }
        let resolvedProducts = remoteProducts.filter(\.isCodeResolved)
        let unresolvedProducts = remoteProducts.filter { !$0.isCodeResolved }
        let resolvedRemoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: remoteSnapshot.totalAssets,
            yesterdayIncome: remoteSnapshot.yesterdayIncome,
            todayIncome: remoteSnapshot.todayIncome,
            holdIncome: remoteSnapshot.holdIncome,
            totalIncome: remoteSnapshot.totalIncome,
            products: remoteProducts,
            tradeOrders: remoteSnapshot.tradeOrders,
            tradeOrderFetchState: remoteSnapshot.tradeOrderFetchState
        )
        let remoteCodes = Set(resolvedProducts.map(\.code))
        let localPendingTradeCodes = Set(localSnapshot.pendingTrades?.map(\.code) ?? [])
        let localPendingConversionCodes = Set((localSnapshot.pendingConversions ?? []).flatMap { [$0.fromCode, $0.toCode] })

        let newHoldings = resolvedProducts
            .filter { localFundsByCode[$0.code] == nil && !hasPendingTransactionTip($0) }
            .map { JDFinanceHoldingImportCandidate(product: $0) }

        let changedHoldings = resolvedProducts.compactMap { product -> JDFinanceHoldingDifference? in
            guard let localFund = localFundsByCode[product.code],
                  localFund.status == .holding,
                  let localAmount = currentAmount(for: localFund)
            else {
                return nil
            }

            let localHoldingIncome = holdingIncome(for: localFund)
            let localHoldingRate = localFund.holdingRate ?? localFund.confirmedHoldingRate
            let pendingBuyAmount = pendingBuyAmountForComparison(
                product: product,
                localAmount: localAmount
            )
            let comparableJDAmount = max(product.totalAmount - (pendingBuyAmount ?? 0), 0)
            let amountChanged = moneyDifference(comparableJDAmount, localAmount)
            let incomeChanged = optionalMoneyDifference(product.holdIncome, localHoldingIncome)

            guard amountChanged || incomeChanged else {
                return nil
            }

            return JDFinanceHoldingDifference(
                code: product.code,
                name: product.name,
                jdAmount: product.totalAmount,
                localAmount: localAmount,
                jdHoldingIncome: product.holdIncome,
                localHoldingIncome: localHoldingIncome,
                jdHoldingRate: product.holdRate,
                localHoldingRate: localHoldingRate,
                jdPendingBuyAmount: pendingBuyAmount
            )
        }

        let missingLocalHoldings = localSnapshot.funds.compactMap { fund -> JDFinanceMissingLocalHolding? in
            guard fund.status == .holding,
                  !remoteCodes.contains(fund.code),
                  !unresolvedProducts.contains(where: { namesLikelyMatch($0.name, fund.name) }),
                  let localAmount = currentAmount(for: fund),
                  localAmount > 0.01
            else {
                return nil
            }
            return JDFinanceMissingLocalHolding(
                code: fund.code,
                name: fund.name,
                localAmount: localAmount,
                finalOutflowOrder: successfulOutflowEvidence(
                    for: fund,
                    orders: remoteSnapshot.tradeOrders
                )
            )
        }

        let unresolvedHoldings = unresolvedProducts.map { product in
            JDFinanceUnresolvedHolding(
                skuID: product.skuID,
                name: product.name,
                amount: product.totalAmount,
                holdingIncome: product.holdIncome,
                message: "京东未返回明确基金代码，且未能通过基金名称精确匹配；已跳过自动同步。"
            )
        }

        let pendingNotices = resolvedProducts.compactMap { product -> JDFinanceHoldingPendingNotice? in
            let transactionTipText = product.transactionTipText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let localFund = localFundsByCode[product.code]
            let localConfirmedCandidate = localConfirmedCandidate(for: product, records: localTradeRecords)
            let hasLocalPending = hasLocalPendingTransaction(
                for: product,
                localFund: localFund,
                localSnapshot: localSnapshot,
                localTradeRecords: localTradeRecords,
                localPendingTradeCodes: localPendingTradeCodes,
                localPendingConversionCodes: localPendingConversionCodes
            )
            let action = product.pendingDetail?.action ?? product.transactionTip?.action ?? .unknown
            let isPositionCoveredWithoutLedger: Bool = if action == .buy,
                                                          localConfirmedCandidate == nil,
                                                          !hasLocalPending,
                                                          let localFund,
                                                          let localAmount = currentAmount(for: localFund)
            {
                !moneyDifference(product.totalAmount, localAmount)
            } else {
                false
            }
            let localCoverage: JDFinancePendingLocalCoverage = if localConfirmedCandidate != nil {
                .confirmed
            } else if hasLocalPending {
                .pending
            } else if isPositionCoveredWithoutLedger {
                .positionOnly
            } else {
                .none
            }
            let logicalTradeCount = max(
                JDFinanceTradeOrderBatcher.logicalRecords(product.pendingDetail?.matchedTradeRecords ?? []).count,
                product.transactionTip?.tradeCount ?? 1
            )
            var coverageCounts = pendingBuyCoverageCounts(
                for: product,
                localTradeRecords: localTradeRecords
            )
            if localCoverage == .confirmed, coverageCounts.confirmed == 0 {
                coverageCounts.confirmed = logicalTradeCount
            } else if localCoverage == .pending, coverageCounts.pending == 0 {
                coverageCounts.pending = logicalTradeCount
            } else if localCoverage == .positionOnly {
                coverageCounts.positionOnly = logicalTradeCount
            }
            let localPendingMessage: String? = if hasLocalPending {
                localPendingConfirmationMessage(for: product)
            } else {
                nil
            }
            let amount = product.transactionTip?.totalAmount
                ?? product.pendingDetail?.amount
                ?? product.totalAmount
            let syncState = localConfirmedCandidate.map {
                JDFinanceSyncPreviewState.localConfirmedJDPending(
                    difference: pendingDifference(product: product, candidate: $0)
                )
            }
            let localConfirmedMessage: String? = if localConfirmedCandidate != nil {
                "本地已确认，京东状态尚未更新；仅展示状态，不会写入本地。"
            } else {
                nil
            }
            let positionCoveredMessage: String? = if isPositionCoveredWithoutLedger {
                "本地持有金额已覆盖这笔买入，但缺少可唯一匹配的交易流水；仅提示，不会重复写入持仓。"
            } else {
                nil
            }

            guard let message = [localPendingMessage, localConfirmedMessage, positionCoveredMessage, transactionTipText]
                .compactMap({ $0 })
                .first(where: { !$0.isEmpty })
            else { return nil }

            let representedOrderKeys: [String] = if localCoverage == .confirmed || localCoverage == .positionOnly {
                Array(Set(
                    JDFinanceTradeOrderBatcher.logicalRecords(product.pendingDetail?.matchedTradeRecords ?? [])
                        .map(orderIdentityKey)
                )).sorted()
            } else {
                []
            }

            return JDFinanceHoldingPendingNotice(
                code: product.code,
                name: product.name,
                amount: amount,
                holdingIncome: product.holdIncome,
                message: message,
                transactionTip: product.transactionTip,
                yesterdayIncomeNotice: product.yesterdayIncomeNotice,
                pendingDetail: product.pendingDetail,
                importKind: localCoverage == .none ? pendingImportKind(
                    for: product,
                    localFund: localFund,
                    localFundsByCode: localFundsByCode,
                    localFundsByName: localFundsByName,
                    hasLocalPending: hasLocalPending,
                    amount: amount
                ) : nil,
                syncState: syncState,
                localCoverage: localCoverage,
                representedOrderKeys: representedOrderKeys,
                localConfirmedTradeCount: coverageCounts.confirmed,
                localPendingTradeCount: coverageCounts.pending,
                positionCoveredTradeCount: coverageCounts.positionOnly
            )
        }
        let reconciliation = reconciliationResult(
            remoteProducts: resolvedProducts,
            remoteSnapshot: resolvedRemoteSnapshot,
            localTradeRecords: localTradeRecords
        )
        let baselineOrderKeys: [String] = localSnapshot.jdFinanceSyncState == nil
            ? Array(Set(reconciliation.orders.compactMap { order -> String? in
                guard order.effectiveStatus == .succeeded else { return nil }
                return orderIdentityKey(order)
            })).sorted()
            : []
        let unrecordedOrders = localSnapshot.jdFinanceSyncState == nil
            ? []
            : unrecordedOrders(
                orders: reconciliation.orders,
                consumedOrderIndices: reconciliation.consumedOrderIndices,
                localTradeRecords: localTradeRecords,
                syncState: localSnapshot.jdFinanceSyncState
            )
        let informationalOrders = informationalOrders(
            reconciliation.orders,
            products: resolvedProducts,
            localTradeRecords: localTradeRecords,
            syncState: localSnapshot.jdFinanceSyncState
        )
        var warnings = consolidation.warnings + remoteSnapshot.tradeOrderFetchState.warnings
        if remoteSnapshot.totalAssets == nil {
            warnings.append("京东响应未返回账户总资产，本次保留本地旧值")
        }

        return JDFinanceHoldingsSyncPreview(
            remoteSnapshot: resolvedRemoteSnapshot,
            newHoldings: newHoldings,
            changedHoldings: changedHoldings,
            missingLocalHoldings: missingLocalHoldings,
            unresolvedHoldings: unresolvedHoldings,
            pendingNotices: pendingNotices,
            reconciliationNotices: reconciliation.notices,
            automaticConfirmations: reconciliation.automaticConfirmations,
            unrecordedOrders: unrecordedOrders,
            informationalOrders: informationalOrders,
            warnings: Array(Set(warnings)).sorted(),
            baselineRepresentedCount: baselineOrderKeys.count,
            baselineOrderKeys: baselineOrderKeys
        )
    }

    private static func localPendingConfirmationMessage(
        for product: JDFinanceHoldingProduct
    ) -> String {
        let pendingStatuses = Set(
            (product.pendingDetail?.matchedTradeRecords ?? [])
                .filter { $0.effectiveStatus == .pending }
                .compactMap { $0.statusText?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        if pendingStatuses.count == 1, let status = pendingStatuses.first {
            return "本次同步已完成；京东订单当前为「\(status)」，尚未完成基金份额确认。"
        }

        if let status = product.pendingDetail?.statusText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty,
           JDFinanceTradeOrderStatus.classify(status) == .pending {
            return "本次同步已完成；京东订单当前为「\(status)」，尚未完成基金份额确认。"
        }

        return "本次同步已完成；京东仍标记为交易处理中，尚未完成基金份额确认。"
    }

    private static func consolidatedProducts(_ products: [JDFinanceHoldingProduct]) -> ConsolidatedProducts {
        var unresolved = products.filter { !$0.isCodeResolved }
        var resolvedGroups: [String: [JDFinanceHoldingProduct]] = [:]
        var codeOrder: [String] = []

        for product in products where product.isCodeResolved {
            if resolvedGroups[product.code] == nil {
                codeOrder.append(product.code)
            }
            resolvedGroups[product.code, default: []].append(product)
        }

        var consolidated: [JDFinanceHoldingProduct] = []
        var warnings: [String] = []
        for code in codeOrder {
            guard let group = resolvedGroups[code], let first = group.first else { continue }
            guard group.dropFirst().allSatisfy({ namesLikelyMatch(first.name, $0.name) }) else {
                warnings.append("京东返回基金代码 \(code) 的多条持仓名称不一致，已禁止自动写入")
                unresolved.append(contentsOf: group.map { product in
                    var unresolvedProduct = product
                    unresolvedProduct.code = ""
                    unresolvedProduct.codeResolution = .unresolved
                    return unresolvedProduct
                })
                continue
            }

            guard group.count > 1 else {
                consolidated.append(first)
                continue
            }

            var merged = first
            merged.totalAmount = group.reduce(0) { $0 + $1.totalAmount }
            merged.yesterdayIncome = summedOptional(group.map(\.yesterdayIncome))
            merged.todayIncome = summedOptional(group.map(\.todayIncome))
            merged.holdIncome = summedOptional(group.map(\.holdIncome))
            consolidated.append(merged)
        }

        return ConsolidatedProducts(products: consolidated + unresolved, warnings: warnings)
    }

    private static func summedOptional(_ values: [Double?]) -> Double? {
        let resolved = values.compactMap { $0 }
        return resolved.isEmpty ? nil : resolved.reduce(0, +)
    }

    private static func resolvedProduct(
        _ product: JDFinanceHoldingProduct,
        localFundsByCode: [String: FundPosition],
        localFundsByName: [String: FundPosition]
    ) -> JDFinanceHoldingProduct {
        guard !product.isCodeResolved else {
            return product
        }

        if let orderCode = commonMatchedTradeOrderCode(for: product) {
            var resolved = product
            resolved.code = orderCode
            resolved.codeResolution = .tradeOrderMatched
            return resolved
        }

        guard let localFund = nameLookupKeys(for: product.name).compactMap({ localFundsByName[$0] }).first,
              localFund.code != product.code
        else {
            return product
        }

        if let sameCodeFund = localFundsByCode[product.code],
           namesLikelyMatch(sameCodeFund.name, product.name)
        {
            return product
        }

        var resolved = product
        resolved.code = localFund.code
        resolved.codeResolution = .nameMatched
        return resolved
    }

    private static func commonMatchedTradeOrderCode(for product: JDFinanceHoldingProduct) -> String? {
        let action = product.pendingDetail?.action ?? product.transactionTip?.action ?? .unknown
        guard action != .conversion else { return nil }

        let records = product.pendingDetail?.matchedTradeRecords ?? []
        guard !records.isEmpty else { return nil }

        let codes = Set(records.compactMap { normalizedCode($0.code) })
        guard codes.count == 1,
              let code = codes.first,
              code != product.code
        else {
            return nil
        }

        let namedRecords = records.compactMap(\.productName)
        guard namedRecords.isEmpty || namedRecords.allSatisfy({ namesLikelyMatch($0, product.name) }) else {
            return nil
        }

        return code
    }

    private static func normalizedCode(_ code: String?) -> String? {
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func namesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhsKeys = Set(nameLookupKeys(for: lhs))
        return nameLookupKeys(for: rhs).contains { lhsKeys.contains($0) }
    }

    private static func localFundsByNormalizedName(_ funds: [FundPosition]) -> [String: FundPosition] {
        var result: [String: FundPosition] = [:]
        var duplicateKeys = Set<String>()

        for fund in funds {
            for key in nameLookupKeys(for: fund.name) {
                guard !key.isEmpty, !duplicateKeys.contains(key) else { continue }

                if result[key] != nil {
                    result[key] = nil
                    duplicateKeys.insert(key)
                } else {
                    result[key] = fund
                }
            }
        }

        return result
    }

    private static func nameLookupKeys(for value: String) -> [String] {
        var keys: [String] = []
        appendUnique(normalizedName(value), to: &keys)
        appendUnique(canonicalFundName(value), to: &keys)
        return keys
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    private static func canonicalFundName(_ value: String) -> String {
        normalizedName(value)
            .replacingOccurrences(of: "中证", with: "")
            .replacingOccurrences(of: "转换-", with: "")
            .replacingOccurrences(of: "转入-", with: "")
            .replacingOccurrences(of: "转出-", with: "")
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value)
    }

    private static func optionalMoneyDifference(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs, let rhs else { return false }
        return moneyDifference(lhs, rhs)
    }

    private static func moneyDifference(_ lhs: Double, _ rhs: Double) -> Bool {
        roundedMoney(lhs) != roundedMoney(rhs)
    }

    private static func pendingBuyAmountForComparison(
        product: JDFinanceHoldingProduct,
        localAmount: Double
    ) -> Double? {
        // JD can keep reporting an order as pending after its confirmed NAV has
        // already been applied locally. In that state both full amounts match,
        // so subtracting the remote pending tip would create a false difference.
        guard moneyDifference(product.totalAmount, localAmount) else {
            return nil
        }
        return product.syncedPendingBuyAmount
    }

    private static func roundedMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func roundedShares(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }

    private struct LocalConfirmedCandidate {
        var records: [FundTradeRecord]
        var linkedRecord: FundTradeRecord?

        var record: FundTradeRecord { records[0] }

        init(record: FundTradeRecord, linkedRecord: FundTradeRecord? = nil) {
            records = [record]
            self.linkedRecord = linkedRecord
        }

        init(records: [FundTradeRecord]) {
            self.records = records
            linkedRecord = nil
        }
    }

    private static func localConfirmedCandidate(
        for product: JDFinanceHoldingProduct,
        records: [FundTradeRecord]
    ) -> LocalConfirmedCandidate? {
        let action = product.pendingDetail?.action ?? product.transactionTip?.action ?? .unknown
        let tradeDate = product.pendingDetail?.tradeDate
        let tradeTimeType = product.pendingDetail?.tradeTimeType

        switch action {
        case .buy:
            let candidates = records.filter { record in
                record.status == .confirmed
                    && (record.kind == .buy
                        || (record.kind == .newFund && record.syncSource == .jdFinance))
                    && record.code == product.code
                    && timingMatches(record: record, tradeDate: tradeDate, tradeTimeType: tradeTimeType)
            }
            if let batchCandidate = confirmedBuyBatchCandidate(candidates, product: product) {
                return batchCandidate
            }
            guard let record = uniqueConfirmedCandidate(
                candidates,
                product: product,
                action: action
            ) else { return nil }
            return LocalConfirmedCandidate(record: record)
        case .sell:
            let candidates = records.filter { record in
                record.status == .confirmed
                    && record.kind == .sell
                    && record.code == product.code
                    && timingMatches(record: record, tradeDate: tradeDate, tradeTimeType: tradeTimeType)
            }
            guard let record = uniqueConfirmedCandidate(
                candidates,
                product: product,
                action: action
            ) else { return nil }
            return LocalConfirmedCandidate(record: record)
        case .conversion:
            let candidates = records.filter { record in
                record.status == .confirmed
                    && record.kind == .conversionOut
                    && record.code == product.code
                    && timingMatches(record: record, tradeDate: tradeDate, tradeTimeType: tradeTimeType)
                    && conversionTargetMatches(product: product, record: record)
            }
            guard let record = uniqueConfirmedCandidate(
                candidates,
                product: product,
                action: action
            ) else { return nil }
            let linkedRecord = record.conversionID.flatMap { conversionID in
                records.first { $0.conversionID == conversionID && $0.kind == .conversionIn }
            }
            return LocalConfirmedCandidate(record: record, linkedRecord: linkedRecord)
        case .unknown:
            return nil
        }
    }

    private struct ConfirmedBuyBatchKey: Hashable {
        var date: String
        var timeType: PositionTimeType
        var amountCents: Int64
    }

    private struct PendingBuyCoverageCounts {
        var confirmed = 0
        var pending = 0
        var positionOnly = 0
    }

    private static func confirmedBuyBatchCandidate(
        _ candidates: [FundTradeRecord],
        product: JDFinanceHoldingProduct
    ) -> LocalConfirmedCandidate? {
        let remoteRecords = JDFinanceTradeOrderBatcher.logicalRecords(
            product.pendingDetail?.matchedTradeRecords ?? []
        ).filter { ($0.action ?? .unknown) == .buy }
        guard remoteRecords.count > 1 else { return nil }

        var localRecordsByKey: [ConfirmedBuyBatchKey: [FundTradeRecord]] = [:]
        for record in candidates where record.kind == .buy {
            guard let amount = record.amount else { continue }
            let key = ConfirmedBuyBatchKey(
                date: record.tradeDate,
                timeType: record.tradeTimeType,
                amountCents: Int64((amount * 100).rounded())
            )
            localRecordsByKey[key, default: []].append(record)
        }

        var matchedRecords: [FundTradeRecord] = []
        for remoteRecord in remoteRecords {
            guard let date = remoteRecord.tradeDate,
                  let timeType = remoteRecord.tradeTimeType,
                  let amount = remoteRecord.amount
            else { return nil }
            let key = ConfirmedBuyBatchKey(
                date: date,
                timeType: timeType,
                amountCents: Int64((amount * 100).rounded())
            )
            guard var localRecords = localRecordsByKey[key], !localRecords.isEmpty else {
                return nil
            }
            matchedRecords.append(localRecords.removeFirst())
            localRecordsByKey[key] = localRecords
        }

        return LocalConfirmedCandidate(records: matchedRecords)
    }

    private static func pendingBuyCoverageCounts(
        for product: JDFinanceHoldingProduct,
        localTradeRecords: [FundTradeRecord]
    ) -> PendingBuyCoverageCounts {
        let remoteRecords = JDFinanceTradeOrderBatcher.logicalRecords(
            product.pendingDetail?.matchedTradeRecords ?? []
        ).filter { ($0.action ?? .unknown) == .buy }
        guard !remoteRecords.isEmpty else { return PendingBuyCoverageCounts() }

        var confirmedByKey: [ConfirmedBuyBatchKey: Int] = [:]
        var pendingByKey: [ConfirmedBuyBatchKey: Int] = [:]
        for record in localTradeRecords where record.code == product.code && record.kind == .buy {
            guard let amount = record.amount else { continue }
            let key = ConfirmedBuyBatchKey(
                date: record.tradeDate,
                timeType: record.tradeTimeType,
                amountCents: Int64((amount * 100).rounded())
            )
            if record.status == .confirmed {
                confirmedByKey[key, default: 0] += 1
            } else if record.status == .pending {
                pendingByKey[key, default: 0] += 1
            }
        }

        var result = PendingBuyCoverageCounts()
        for remoteRecord in remoteRecords {
            guard let date = remoteRecord.tradeDate,
                  let timeType = remoteRecord.tradeTimeType,
                  let amount = remoteRecord.amount
            else { continue }
            let key = ConfirmedBuyBatchKey(
                date: date,
                timeType: timeType,
                amountCents: Int64((amount * 100).rounded())
            )
            if let count = confirmedByKey[key], count > 0 {
                result.confirmed += 1
                confirmedByKey[key] = count - 1
            } else if let count = pendingByKey[key], count > 0 {
                result.pending += 1
                pendingByKey[key] = count - 1
            }
        }
        return result
    }

    private static func uniqueConfirmedCandidate(
        _ candidates: [FundTradeRecord],
        product: JDFinanceHoldingProduct,
        action: JDFinancePendingTradeAction
    ) -> FundTradeRecord? {
        let qualified = candidates.filter { record in
            if waitsForJDFinalConfirmation(record) {
                return true
            }
            switch action {
            case .buy:
                guard let jdAmount = product.pendingDetail?.amount ?? product.transactionTip?.totalAmount,
                      let localAmount = record.amount
                else { return false }
                return !moneyDifference(jdAmount, localAmount)
            case .sell, .conversion:
                guard let jdShares = product.pendingDetail?.shares,
                      let localShares = record.confirmedShares ?? record.shares
                else { return false }
                return roundedShares(jdShares) == roundedShares(localShares)
            case .unknown:
                return false
            }
        }
        return qualified.count == 1 ? qualified[0] : nil
    }

    private static func timingMatches(
        record: FundTradeRecord,
        tradeDate: String?,
        tradeTimeType: PositionTimeType?
    ) -> Bool {
        if let tradeDate, record.tradeDate != tradeDate {
            return false
        }
        if let tradeTimeType, record.tradeTimeType != tradeTimeType {
            return false
        }
        return tradeDate != nil || tradeTimeType != nil
    }

    private static func conversionTargetMatches(
        product: JDFinanceHoldingProduct,
        record: FundTradeRecord
    ) -> Bool {
        let conversionRecords = product.pendingDetail?.matchedTradeRecords.filter { $0.action == .conversion } ?? []
        guard !conversionRecords.isEmpty else {
            return true
        }
        return conversionRecords.contains { order in
            if let targetCode = order.conversionTargetCode, !targetCode.isEmpty {
                return record.linkedCode == targetCode
            }
            if let targetName = order.conversionTargetName, !targetName.isEmpty {
                return nameLookupKeys(for: targetName).contains(where: { key in
                    nameLookupKeys(for: record.linkedName ?? "").contains(key)
                })
            }
            return true
        }
    }

    private static func pendingDifference(
        product: JDFinanceHoldingProduct,
        candidate: LocalConfirmedCandidate
    ) -> JDFinanceSyncDifference {
        let pendingAmount = product.pendingDetail?.amount ?? product.transactionTip?.totalAmount
        let pendingShares = product.pendingDetail?.shares
        let localAmount = candidate.records.compactMap(\.amount).reduce(0, +)
        let localShares = candidate.records.compactMap { $0.confirmedShares ?? $0.shares }.reduce(0, +)
        return JDFinanceSyncDifference(
            amountDelta: amountDelta(jd: pendingAmount, local: localAmount),
            sharesDelta: sharesDelta(jd: pendingShares, local: localShares),
            priceDelta: nil
        )
    }

    private enum OrderMatch {
        case matched([Int])
        case missing
        case ambiguous
    }

    private static func reconciliationResult(
        remoteProducts: [JDFinanceHoldingProduct],
        remoteSnapshot: JDFinanceHoldingsSnapshot,
        localTradeRecords: [FundTradeRecord]
    ) -> ReconciliationResult {
        let productsByCode = remoteProducts.reduce(into: [String: JDFinanceHoldingProduct]()) { result, product in
            result[product.code] = result[product.code] ?? product
        }
        let orders = allTradeOrders(remoteSnapshot: remoteSnapshot, remoteProducts: remoteProducts)
        let succeededOrderIndices = orders.indices.filter { orders[$0].effectiveStatus == .succeeded }
        var notices: [JDFinanceReconciliationNotice] = []
        var automaticConfirmations: [JDFinanceAutomaticConfirmation] = []
        var consumedOrderIndices = Set<Int>()
        var handledConversionIDs = Set<String>()

        for record in localTradeRecords
        where record.status != .failed && waitsForJDFinalConfirmation(record)
        {
            if productsByCode[record.code]?.transactionTip != nil {
                continue
            }

            switch record.kind {
            case .newFund, .buy, .sell:
                switch matchingTradeOrderIndex(
                    for: record,
                    in: orders,
                    candidateIndices: succeededOrderIndices,
                    consumedOrderIndices: consumedOrderIndices
                ) {
                case .missing:
                    notices.append(conflictNotice(record: record, message: missingFinalOrderMessage(remoteSnapshot)))
                case .ambiguous:
                    notices.append(conflictNotice(record: record, message: "存在多笔京东流水同时匹配本地记录，已禁止自动覆盖"))
                case .matched(let indices):
                    let matchedOrders = indices.map { orders[$0] }
                    let order: JDFinanceTradeOrderRecord
                    if matchedOrders.count == 1, let first = matchedOrders.first {
                        order = first
                    } else if let combined = JDFinanceTradeOrderBatcher.combinedRecord(matchedOrders) {
                        order = combined
                    } else {
                        notices.append(conflictNotice(
                            record: record,
                            message: "多笔京东支付明细无法安全合并，已禁止自动覆盖"
                        ))
                        continue
                    }
                    consumedOrderIndices.formUnion(indices)
                    let values = reconciliationValues(record: record, order: order)
                    let difference = recordDifference(record: record, values: values)
                    if difference.hasDifference {
                        let action: FundTradeAction = record.kind == .sell ? .sell : .buy
                        notices.append(JDFinanceReconciliationNotice(
                            id: record.id,
                            code: record.code,
                            name: record.name,
                            linkedCode: record.linkedCode,
                            linkedName: record.linkedName,
                            tradeDate: record.tradeDate,
                            tradeTimeType: record.tradeTimeType,
                            kind: .trade(recordID: record.id, action: action),
                            state: .jdConfirmedNeedsOverwrite(difference: difference),
                            localAmount: record.amount,
                            jdAmount: values.amount,
                            localShares: record.confirmedShares ?? record.shares,
                            jdShares: values.shares,
                            values: values,
                            matchedTradeRecords: matchedOrders
                        ))
                    } else {
                        automaticConfirmations.append(JDFinanceAutomaticConfirmation(
                            id: record.id,
                            recordIDs: [record.id],
                            syncKey: values.syncKey,
                            statusText: values.statusText,
                            representedOrderKeys: Array(Set(matchedOrders.map(orderIdentityKey))).sorted()
                        ))
                    }
                }
            case .conversionOut:
                guard let conversionID = record.conversionID,
                      !handledConversionIDs.contains(conversionID)
                else {
                    continue
                }
                handledConversionIDs.insert(conversionID)
                let linkedRecords = localTradeRecords.filter {
                    $0.conversionID == conversionID && $0.kind == .conversionIn
                }
                guard linkedRecords.count == 1, let linkedRecord = linkedRecords.first else {
                    notices.append(conversionConflictNotice(
                        outRecord: record,
                        inRecord: nil,
                        message: "本地转换记录不完整或存在重复，已禁止自动确认和覆盖"
                    ))
                    continue
                }
                switch matchingConversionOrderIndex(
                    for: record,
                    in: orders,
                    candidateIndices: succeededOrderIndices,
                    consumedOrderIndices: consumedOrderIndices
                ) {
                case .missing:
                    notices.append(conversionConflictNotice(
                        outRecord: record,
                        inRecord: linkedRecord,
                        message: missingFinalOrderMessage(remoteSnapshot)
                    ))
                case .ambiguous:
                    notices.append(conversionConflictNotice(
                        outRecord: record,
                        inRecord: linkedRecord,
                        message: "存在多笔京东转换流水同时匹配本地记录，已禁止自动覆盖"
                    ))
                case .matched(let indices):
                    guard indices.count == 1, let index = indices.first else {
                        notices.append(conversionConflictNotice(
                            outRecord: record,
                            inRecord: linkedRecord,
                            message: "存在多笔京东转换流水同时匹配本地记录，已禁止自动覆盖"
                        ))
                        continue
                    }
                    consumedOrderIndices.insert(index)
                    let order = orders[index]
                    let values = reconciliationValues(outRecord: record, inRecord: linkedRecord, order: order)
                    let difference = recordDifference(record: record, values: values)
                    if difference.hasDifference {
                        notices.append(JDFinanceReconciliationNotice(
                            id: conversionID,
                            code: record.code,
                            name: record.name,
                            linkedCode: record.linkedCode,
                            linkedName: record.linkedName,
                            tradeDate: record.tradeDate,
                            tradeTimeType: record.tradeTimeType,
                            kind: .conversion(
                                conversionID: conversionID,
                                outRecordID: record.id,
                                inRecordID: linkedRecord.id
                            ),
                            state: .jdConfirmedNeedsOverwrite(difference: difference),
                            localAmount: record.amount,
                            jdAmount: values.amount,
                            localShares: record.confirmedShares ?? record.shares,
                            jdShares: values.shares,
                            values: values,
                            matchedTradeRecords: [order]
                        ))
                    } else {
                        automaticConfirmations.append(JDFinanceAutomaticConfirmation(
                            id: conversionID,
                            recordIDs: [record.id, linkedRecord.id],
                            syncKey: values.syncKey,
                            statusText: values.statusText,
                            representedOrderKeys: [orderIdentityKey(order)]
                        ))
                    }
                }
            case .conversionIn:
                continue
            }
        }
        return ReconciliationResult(
            notices: notices,
            automaticConfirmations: automaticConfirmations,
            consumedOrderIndices: consumedOrderIndices,
            orders: orders
        )
    }

    private static func waitsForJDFinalConfirmation(_ record: FundTradeRecord) -> Bool {
        record.syncSource == .jdFinance
            && ((record.waitsForExternalConfirmation ?? false)
                || record.externalStatus == .waitingExternalConfirmation)
    }

    private static func allTradeOrders(
        remoteSnapshot: JDFinanceHoldingsSnapshot,
        remoteProducts: [JDFinanceHoldingProduct]
    ) -> [JDFinanceTradeOrderRecord] {
        var records = remoteSnapshot.tradeOrders
        var knownKeys = Set(records.map { orderIdentityKey($0) })
        for product in remoteProducts {
            for record in (product.pendingDetail?.matchedTradeRecords ?? [])
                + (product.pendingDetail?.candidateTradeRecords ?? [])
            {
                let key = record.stableOrderKey
                    ?? JDFinanceSyncFingerprint.tradeOrderRecord(
                        record,
                        fallbackCode: product.code
                    )
                if knownKeys.insert(key).inserted {
                    records.append(record)
                }
            }
        }
        return records
    }

    private static func matchingTradeOrderIndex(
        for record: FundTradeRecord,
        in orders: [JDFinanceTradeOrderRecord],
        candidateIndices: [Int],
        consumedOrderIndices: Set<Int>
    ) -> OrderMatch {
        let availableIndices = candidateIndices.filter { !consumedOrderIndices.contains($0) }
        if let stableMatch = stableOrderMatch(
            syncKey: record.syncKey,
            fallbackCode: record.code,
            candidateIndices: availableIndices,
            orders: orders
        ) {
            return stableMatch
        }
        let candidates = availableIndices.filter {
            tradeOrder(orders[$0], matches: record)
        }
        return selectOrderIndex(for: record, candidates: candidates, orders: orders)
    }

    private static func matchingConversionOrderIndex(
        for record: FundTradeRecord,
        in orders: [JDFinanceTradeOrderRecord],
        candidateIndices: [Int],
        consumedOrderIndices: Set<Int>
    ) -> OrderMatch {
        let availableIndices = candidateIndices.filter { !consumedOrderIndices.contains($0) }
        if let stableMatch = stableOrderMatch(
            syncKey: record.syncKey,
            fallbackCode: record.code,
            candidateIndices: availableIndices,
            orders: orders
        ) {
            return stableMatch
        }
        let candidates = availableIndices.filter {
            conversionOrder(orders[$0], matches: record)
        }
        return selectOrderIndex(for: record, candidates: candidates, orders: orders)
    }

    private static func stableOrderMatch(
        syncKey: String?,
        fallbackCode: String,
        candidateIndices: [Int],
        orders: [JDFinanceTradeOrderRecord]
    ) -> OrderMatch? {
        guard let syncKey, !syncKey.isEmpty else { return nil }
        let matches = candidateIndices.filter {
            orders[$0].stableOrderKey == syncKey
                || JDFinanceSyncFingerprint.tradeOrderRecord(
                    orders[$0],
                    fallbackCode: fallbackCode
                ) == syncKey
        }
        if matches.count == 1 {
            return .matched([matches[0]])
        }
        return matches.isEmpty ? nil : .ambiguous
    }

    private static func selectOrderIndex(
        for record: FundTradeRecord,
        candidates: [Int],
        orders: [JDFinanceTradeOrderRecord]
    ) -> OrderMatch {
        guard !candidates.isEmpty else { return .missing }

        let exactValueMatches = candidates.filter { orderValuesMatch(orders[$0], record: record) }
        if exactValueMatches.count == 1 {
            return .matched([exactValueMatches[0]])
        }
        if exactValueMatches.count > 1 {
            return .ambiguous
        }
        if candidates.count == 1 {
            return .matched(candidates)
        }
        if let combined = JDFinanceTradeOrderBatcher.combinedRecord(candidates.map { orders[$0] }),
           orderValuesMatch(combined, record: record)
        {
            return .matched(candidates)
        }
        return .ambiguous
    }

    private static func orderValuesMatch(_ order: JDFinanceTradeOrderRecord, record: FundTradeRecord) -> Bool {
        var compared = false
        if let orderAmount = order.amount, let localAmount = record.amount {
            compared = true
            guard !moneyDifference(orderAmount, localAmount) else { return false }
        }
        if let orderShares = order.shares, let localShares = record.confirmedShares ?? record.shares {
            compared = true
            guard roundedShares(orderShares) == roundedShares(localShares) else { return false }
        }
        return compared
    }

    private static func tradeOrder(_ order: JDFinanceTradeOrderRecord, matches record: FundTradeRecord) -> Bool {
        guard orderIdentityMatches(order, record: record),
              order.tradeDate == record.tradeDate,
              order.tradeTimeType == record.tradeTimeType
        else {
            return false
        }
        switch record.kind {
        case .newFund, .buy:
            return order.action == .buy
        case .sell:
            return order.action == .sell
        case .conversionOut, .conversionIn:
            return false
        }
    }

    private static func conversionOrder(_ order: JDFinanceTradeOrderRecord, matches record: FundTradeRecord) -> Bool {
        guard order.action == .conversion,
              orderIdentityMatches(order, record: record),
              order.tradeDate == record.tradeDate,
              order.tradeTimeType == record.tradeTimeType
        else {
            return false
        }
        if let targetCode = order.conversionTargetCode, !targetCode.isEmpty {
            return record.linkedCode == targetCode
        }
        return true
    }

    private static func orderIdentityMatches(_ order: JDFinanceTradeOrderRecord, record: FundTradeRecord) -> Bool {
        if let code = normalizedCode(order.code) {
            return code == record.code
        }
        guard let productName = order.productName else { return false }
        return namesLikelyMatch(productName, record.name)
    }

    private static func missingFinalOrderMessage(_ snapshot: JDFinanceHoldingsSnapshot) -> String {
        snapshot.tradeOrderFetchState.isComplete || snapshot.tradeOrderFetchState == .notRequested
            ? "缺少京东最终流水，不能安全覆盖流水"
            : "京东交易流水拉取不完整，暂不能判断是否缺少最终流水"
    }

    private static func unrecordedOrders(
        orders: [JDFinanceTradeOrderRecord],
        consumedOrderIndices: Set<Int>,
        localTradeRecords: [FundTradeRecord],
        syncState: JDFinanceSyncState?
    ) -> [JDFinanceUnrecordedOrder] {
        var consumedLocalRecordIndices = Set<Int>()
        var result: [JDFinanceUnrecordedOrder] = []
        let representedKeys = Set(syncState?.representedOrderKeys ?? [])
        let dismissedKeys = Set(syncState?.dismissedOrderKeys ?? [])

        for index in orders.indices {
            let order = orders[index]
            let orderKey = orderIdentityKey(order)
            guard order.effectiveStatus == .succeeded,
                  !consumedOrderIndices.contains(index),
                  !representedKeys.contains(orderKey),
                  !dismissedKeys.contains(orderKey)
            else {
                continue
            }
            let localMatches = localTradeRecords.indices.filter {
                !consumedLocalRecordIndices.contains($0)
                    && localOrderEquivalent(order, record: localTradeRecords[$0])
            }
            if localMatches.count == 1, let matchedLocalIndex = localMatches.first {
                consumedLocalRecordIndices.insert(matchedLocalIndex)
                continue
            }
            let identity = order.stableOrderKey
                ?? "\(JDFinanceSyncFingerprint.tradeOrderRecord(order))-\(index)"
            result.append(JDFinanceUnrecordedOrder(
                id: identity,
                record: order,
                message: localMatches.count > 1
                    ? "存在多条本地交易同时匹配，已禁止自动导入"
                    : "京东存在成功流水，但本地没有对应交易；确认后可导入",
                blockingReason: localMatches.count > 1 ? "本地匹配不唯一" : nil
            ))
        }
        return result
    }

    private static func orderIdentityKey(_ order: JDFinanceTradeOrderRecord) -> String {
        order.stableOrderKey ?? JDFinanceSyncFingerprint.tradeOrderRecord(order)
    }

    private static func successfulOutflowEvidence(
        for fund: FundPosition,
        orders: [JDFinanceTradeOrderRecord]
    ) -> JDFinanceTradeOrderRecord? {
        orders
            .filter { order in
                guard order.effectiveStatus == .succeeded,
                      order.action == .sell || order.action == .conversion
                else { return false }
                if let code = normalizedCode(order.code) {
                    return code == fund.code
                }
                return order.productName.map { namesLikelyMatch($0, fund.name) } == true
            }
            .max { lhs, rhs in
                let lhsValue = lhs.submittedAt ?? lhs.tradeDate ?? ""
                let rhsValue = rhs.submittedAt ?? rhs.tradeDate ?? ""
                return lhsValue < rhsValue
            }
    }

    private static func informationalOrders(
        _ orders: [JDFinanceTradeOrderRecord],
        products: [JDFinanceHoldingProduct],
        localTradeRecords: [FundTradeRecord],
        syncState: JDFinanceSyncState?
    ) -> [JDFinanceTradeOrderRecord] {
        let representedByPendingNoticeKeys = Set(products.flatMap { product in
            product.pendingDetail?.matchedTradeRecords.map { record in
                record.stableOrderKey
                    ?? JDFinanceSyncFingerprint.tradeOrderRecord(
                        record,
                        fallbackCode: product.code
                    )
            } ?? []
        })
        let nonSucceeded = orders.filter { order in
            order.effectiveStatus != .succeeded
                && !representedByPendingNoticeKeys.contains(orderIdentityKey(order))
        }
        let isRelevantToWaitingRecord: (JDFinanceTradeOrderRecord) -> Bool = { order in
            localTradeRecords.contains { record in
                guard waitsForJDFinalConfirmation(record) else { return false }
                switch record.kind {
                case .newFund, .buy, .sell:
                    return tradeOrder(order, matches: record)
                case .conversionOut:
                    return conversionOrder(order, matches: record)
                case .conversionIn:
                    return false
                }
            }
        }
        guard let syncState else {
            let pendingProductCodes = Set(products.filter { $0.transactionTip != nil }.map(\.code))
            return nonSucceeded.filter { order in
                isRelevantToWaitingRecord(order)
                    || (order.effectiveStatus == .pending
                        && order.code.map(pendingProductCodes.contains) == true)
            }
        }

        let baselineDate = DateOnlyFormatter.string(from: syncState.baselineEstablishedAt)
        let trackedKeys = Set(syncState.trackedPendingOrderKeys)
        return nonSucceeded.filter { order in
            isRelevantToWaitingRecord(order)
                || trackedKeys.contains(orderIdentityKey(order))
                || order.tradeDate.map { $0 >= baselineDate } == true
        }
    }

    private static func localOrderEquivalent(
        _ order: JDFinanceTradeOrderRecord,
        record: FundTradeRecord
    ) -> Bool {
        if let stableOrderKey = order.stableOrderKey,
           record.syncKey == stableOrderKey
        {
            return true
        }
        let identityMatches: Bool
        switch record.kind {
        case .newFund, .buy, .sell:
            identityMatches = tradeOrder(order, matches: record)
        case .conversionOut:
            identityMatches = conversionOrder(order, matches: record)
        case .conversionIn:
            identityMatches = false
        }
        return identityMatches && orderValuesMatch(order, record: record)
    }

    private static func reconciliationValues(
        record: FundTradeRecord,
        order: JDFinanceTradeOrderRecord
    ) -> JDFinanceReconciliationValues {
        let finalShares: Double?
        if record.kind == .sell {
            finalShares = order.shares ?? record.confirmedShares ?? record.shares
        } else {
            finalShares = order.shares ?? record.confirmedShares ?? record.shares
        }
        let finalAmount = order.amount ?? record.amount
        let finalPrice = price(amount: finalAmount, shares: finalShares, fallback: record.price)
        return JDFinanceReconciliationValues(
            amount: finalAmount,
            shares: finalShares,
            price: finalPrice,
            statusText: order.statusText,
            syncKey: JDFinanceSyncFingerprint.tradeOrderRecord(order, fallbackCode: record.code)
        )
    }

    private static func reconciliationValues(
        outRecord: FundTradeRecord,
        inRecord: FundTradeRecord?,
        order: JDFinanceTradeOrderRecord
    ) -> JDFinanceReconciliationValues {
        let finalOutShares = order.shares ?? outRecord.confirmedShares ?? outRecord.shares
        let finalOutAmount = order.amount ?? outRecord.amount
        let finalOutPrice = price(amount: finalOutAmount, shares: finalOutShares, fallback: outRecord.price)
        return JDFinanceReconciliationValues(
            amount: finalOutAmount,
            shares: finalOutShares,
            price: finalOutPrice,
            inAmount: inRecord?.amount,
            inShares: inRecord?.confirmedShares ?? inRecord?.shares,
            inPrice: inRecord?.price,
            statusText: order.statusText,
            syncKey: JDFinanceSyncFingerprint.tradeOrderRecord(order, fallbackCode: outRecord.code)
        )
    }

    private static func recordDifference(
        record: FundTradeRecord,
        values: JDFinanceReconciliationValues
    ) -> JDFinanceSyncDifference {
        JDFinanceSyncDifference(
            amountDelta: amountDelta(jd: values.amount, local: record.amount),
            sharesDelta: sharesDelta(jd: values.shares, local: record.confirmedShares ?? record.shares),
            priceDelta: priceDelta(jd: values.price, local: record.price)
        )
    }

    private static func amountDelta(jd: Double?, local: Double?) -> Double? {
        guard let jd, let local else { return nil }
        let delta = roundedMoney(jd) - roundedMoney(local)
        return abs(delta) >= 0.01 ? delta : nil
    }

    private static func sharesDelta(jd: Double?, local: Double?) -> Double? {
        guard let jd, let local else { return nil }
        let delta = roundedShares(jd) - roundedShares(local)
        return abs(delta) >= 0.000001 ? delta : nil
    }

    private static func priceDelta(jd: Double?, local: Double?) -> Double? {
        guard let jd, let local else { return nil }
        let delta = roundedShares(jd) - roundedShares(local)
        return abs(delta) >= 0.000001 ? delta : nil
    }

    private static func price(amount: Double?, shares: Double?, fallback: Double?) -> Double? {
        guard let amount, let shares, amount > 0, shares > 0 else {
            return fallback
        }
        return roundedShares(amount / shares)
    }

    private static func conflictNotice(
        record: FundTradeRecord,
        message: String
    ) -> JDFinanceReconciliationNotice {
        let action: FundTradeAction = record.kind == .sell ? .sell : .buy
        return JDFinanceReconciliationNotice(
            id: "conflict-\(record.id)",
            code: record.code,
            name: record.name,
            linkedCode: record.linkedCode,
            linkedName: record.linkedName,
            tradeDate: record.tradeDate,
            tradeTimeType: record.tradeTimeType,
            kind: .trade(recordID: record.id, action: action),
            state: .conflict(message),
            localAmount: record.amount,
            jdAmount: nil,
            localShares: record.confirmedShares ?? record.shares,
            jdShares: nil,
            values: JDFinanceReconciliationValues(),
            matchedTradeRecords: []
        )
    }

    private static func conversionConflictNotice(
        outRecord: FundTradeRecord,
        inRecord: FundTradeRecord?,
        message: String
    ) -> JDFinanceReconciliationNotice {
        JDFinanceReconciliationNotice(
            id: "conflict-\(outRecord.conversionID ?? outRecord.id)",
            code: outRecord.code,
            name: outRecord.name,
            linkedCode: outRecord.linkedCode,
            linkedName: outRecord.linkedName,
            tradeDate: outRecord.tradeDate,
            tradeTimeType: outRecord.tradeTimeType,
            kind: .conversion(
                conversionID: outRecord.conversionID ?? outRecord.id,
                outRecordID: outRecord.id,
                inRecordID: inRecord?.id
            ),
            state: .conflict(message),
            localAmount: outRecord.amount,
            jdAmount: nil,
            localShares: outRecord.confirmedShares ?? outRecord.shares,
            jdShares: nil,
            values: JDFinanceReconciliationValues(),
            matchedTradeRecords: []
        )
    }

    private static func hasPendingTransactionTip(_ product: JDFinanceHoldingProduct) -> Bool {
        product.transactionTipText?.isEmpty == false
    }

    private struct PendingBatchKey: Hashable {
        var date: String
        var timeType: String
        var action: String
    }

    private static func hasLocalPendingTransaction(
        for product: JDFinanceHoldingProduct,
        localFund: FundPosition?,
        localSnapshot: PortfolioSnapshot,
        localTradeRecords: [FundTradeRecord],
        localPendingTradeCodes: Set<String>,
        localPendingConversionCodes: Set<String>
    ) -> Bool {
        let fallback = localFund?.status == .pending
            || localPendingTradeCodes.contains(product.code)
            || localPendingConversionCodes.contains(product.code)
        let remoteTotals = pendingBatchTotals(for: product)
        guard !remoteTotals.isEmpty else {
            return fallback
        }

        let localTotals = pendingBatchTotals(
            in: localSnapshot,
            tradeRecords: localTradeRecords,
            code: product.code,
            includingLocallyConfirmed: true
        )
        guard !localTotals.isEmpty else {
            // Older snapshots can retain only the fund-level pending marker.
            // Without transaction-level evidence, preserve that legacy state.
            return fallback
        }

        if remoteTotals.allSatisfy({ localTotals[$0.key] == $0.value }) {
            let pendingOnlyTotals = pendingOnlyBatchTotals(
                in: localSnapshot,
                tradeRecords: localTradeRecords,
                code: product.code
            )
            let hasMatchedPendingBatch = pendingOnlyTotals.contains { batch in
                guard let remoteValue = remoteTotals[batch.key] else { return false }
                return remoteValue >= batch.value
            }
            return hasMatchedPendingBatch || fallback
        }
        return positionCoveredPendingBuyAmount(
            for: product,
            localFund: localFund,
            localSnapshot: localSnapshot,
            localTradeRecords: localTradeRecords
        ) != nil
    }

    private static func pendingBatchTotals(
        for product: JDFinanceHoldingProduct
    ) -> [PendingBatchKey: Int64] {
        let expectedAction = product.pendingDetail?.action ?? product.transactionTip?.action
        var totals: [PendingBatchKey: Int64] = [:]

        for record in product.pendingDetail?.matchedTradeRecords ?? [] {
            let action = record.action ?? expectedAction
            guard let action,
                  let date = record.tradeDate,
                  let timeType = record.tradeTimeType,
                  let value = pendingBatchValue(action: action, amount: record.amount, shares: record.shares)
            else {
                continue
            }
            let key = PendingBatchKey(
                date: date,
                timeType: timeType.rawValue,
                action: action.rawValue
            )
            totals[key, default: 0] += value
        }

        if totals.isEmpty,
           let detail = product.pendingDetail,
           let action = detail.action ?? product.transactionTip?.action,
           let date = detail.tradeDate,
           let timeType = detail.tradeTimeType,
           let value = pendingBatchValue(action: action, amount: detail.amount ?? product.transactionTip?.totalAmount, shares: detail.shares)
        {
            let key = PendingBatchKey(
                date: date,
                timeType: timeType.rawValue,
                action: action.rawValue
            )
            totals[key] = value
        }

        return totals
    }

    private static func pendingBatchTotals(
        in snapshot: PortfolioSnapshot,
        tradeRecords: [FundTradeRecord],
        code: String,
        includingLocallyConfirmed: Bool = false
    ) -> [PendingBatchKey: Int64] {
        var totals: [PendingBatchKey: Int64] = [:]
        let representedRecordIDs = Set((snapshot.pendingTrades ?? []).compactMap(\.recordID))

        for record in tradeRecords
        where record.code == code
            && isJDFinanceTrackedPendingBatchRecord(
                record,
                includingLocallyConfirmed: includingLocallyConfirmed
            )
        {
            guard let action = pendingBatchAction(for: record.kind),
                  let value = pendingBatchValue(action: action, amount: record.amount, shares: record.shares ?? record.confirmedShares)
            else {
                continue
            }
            addPendingBatchValue(
                value,
                date: record.tradeDate,
                timeType: record.tradeTimeType,
                action: action,
                to: &totals
            )
        }

        for pendingTrade in snapshot.pendingTrades ?? [] {
            if let recordID = pendingTrade.recordID, representedRecordIDs.contains(recordID) {
                continue
            }
            guard pendingTrade.code == code,
                  pendingTrade.syncSource == .jdFinance,
                  let value = pendingBatchValue(
                      action: pendingBatchAction(for: pendingTrade.action),
                      amount: pendingTrade.amount,
                      shares: pendingTrade.shares
                  )
            else {
                continue
            }
            addPendingBatchValue(
                value,
                date: pendingTrade.tradeDate,
                timeType: pendingTrade.tradeTimeType,
                action: pendingBatchAction(for: pendingTrade.action),
                to: &totals
            )
        }

        return totals
    }

    private static func reconciledPendingBuyAmount(
        for product: JDFinanceHoldingProduct,
        localSnapshot: PortfolioSnapshot,
        localTradeRecords: [FundTradeRecord]
    ) -> Double? {
        guard (product.pendingDetail?.action ?? product.transactionTip?.action) == .buy,
              product.syncedPendingBuyAmount != nil
        else {
            return nil
        }

        let remoteTotals = pendingBatchTotals(for: product)
        guard !remoteTotals.isEmpty else { return nil }
        let localTrackedTotals = pendingBatchTotals(
            in: localSnapshot,
            tradeRecords: localTradeRecords,
            code: product.code,
            includingLocallyConfirmed: true
        )
        guard remoteTotals.allSatisfy({ localTrackedTotals[$0.key] == $0.value }) else {
            return positionCoveredPendingBuyAmount(
                for: product,
                localFund: localSnapshot.funds.first { $0.code == product.code },
                localSnapshot: localSnapshot,
                localTradeRecords: localTradeRecords
            )
        }

        let pendingOnlyTotals = pendingOnlyBatchTotals(
            in: localSnapshot,
            tradeRecords: localTradeRecords,
            code: product.code
        )
        let pendingCents = remoteTotals.keys.reduce(Int64(0)) {
            $0 + (pendingOnlyTotals[$1] ?? 0)
        }
        return Double(pendingCents) / 100
    }

    private static func positionCoveredPendingBuyAmount(
        for product: JDFinanceHoldingProduct,
        localFund: FundPosition?,
        localSnapshot: PortfolioSnapshot,
        localTradeRecords: [FundTradeRecord]
    ) -> Double? {
        guard (product.pendingDetail?.action ?? product.transactionTip?.action) == .buy,
              let localFund,
              let localAmount = currentAmount(for: localFund)
        else {
            return nil
        }

        let pendingBuyTotals = pendingOnlyBatchTotals(
            in: localSnapshot,
            tradeRecords: localTradeRecords,
            code: product.code
        ).filter { batch in
            batch.key.action == JDFinancePendingTradeAction.buy.rawValue
        }
        guard !pendingBuyTotals.isEmpty else { return nil }
        let remoteTotals = pendingBatchTotals(for: product)
        guard pendingBuyTotals.allSatisfy({ batch in
            guard let remoteValue = remoteTotals[batch.key] else { return false }
            return remoteValue >= batch.value
        }) else {
            return nil
        }
        let pendingBuyCents = pendingBuyTotals.reduce(Int64(0)) { $0 + $1.value }
        let pendingBuyAmount = Double(pendingBuyCents) / 100
        guard !moneyDifference(localAmount + pendingBuyAmount, product.totalAmount) else {
            return nil
        }
        return pendingBuyAmount
    }

    private static func pendingOnlyBatchTotals(
        in snapshot: PortfolioSnapshot,
        tradeRecords: [FundTradeRecord],
        code: String
    ) -> [PendingBatchKey: Int64] {
        var totals: [PendingBatchKey: Int64] = [:]
        let tradeRecordIDs = Set(tradeRecords.map(\.id))

        for record in tradeRecords where record.code == code
            && record.status == .pending
            && isJDFinanceTrackedPendingBatchRecord(record)
        {
            guard let action = pendingBatchAction(for: record.kind),
                  let value = pendingBatchValue(
                    action: action,
                    amount: record.amount,
                    shares: record.shares ?? record.confirmedShares
                  )
            else {
                continue
            }
            addPendingBatchValue(
                value,
                date: record.tradeDate,
                timeType: record.tradeTimeType,
                action: action,
                to: &totals
            )
        }

        for pendingTrade in snapshot.pendingTrades ?? [] {
            if let recordID = pendingTrade.recordID, tradeRecordIDs.contains(recordID) {
                continue
            }
            guard pendingTrade.code == code,
                  pendingTrade.syncSource == .jdFinance,
                  let value = pendingBatchValue(
                    action: pendingBatchAction(for: pendingTrade.action),
                    amount: pendingTrade.amount,
                    shares: pendingTrade.shares
                  )
            else {
                continue
            }
            addPendingBatchValue(
                value,
                date: pendingTrade.tradeDate,
                timeType: pendingTrade.tradeTimeType,
                action: pendingBatchAction(for: pendingTrade.action),
                to: &totals
            )
        }

        return totals
    }

    private static func isJDFinanceTrackedPendingBatchRecord(
        _ record: FundTradeRecord,
        includingLocallyConfirmed: Bool = false
    ) -> Bool {
        guard record.status != .failed,
              record.isReconciliationBaseline != true
        else {
            return false
        }
        let isJDFinanceTracked = record.syncSource == .jdFinance
            || record.externalStatus == .waitingExternalConfirmation
            || record.waitsForExternalConfirmation == true
        guard isJDFinanceTracked else { return false }
        return record.status == .pending
            || waitsForJDFinalConfirmation(record)
            || (includingLocallyConfirmed && record.status == .confirmed)
    }

    private static func pendingBatchAction(for kind: FundTradeKind) -> JDFinancePendingTradeAction? {
        switch kind {
        case .newFund, .buy:
            .buy
        case .sell:
            .sell
        case .conversionOut:
            .conversion
        case .conversionIn:
            nil
        }
    }

    private static func pendingBatchAction(for action: FundTradeAction) -> JDFinancePendingTradeAction {
        switch action {
        case .buy:
            .buy
        case .sell:
            .sell
        }
    }

    private static func pendingBatchValue(
        action: JDFinancePendingTradeAction,
        amount: Double?,
        shares: Double?
    ) -> Int64? {
        switch action {
        case .buy:
            guard let amount, amount > 0 else { return nil }
            return Int64((amount * 100).rounded())
        case .sell, .conversion:
            guard let shares, shares > 0 else { return nil }
            return Int64((shares * 1_000_000).rounded())
        case .unknown:
            return nil
        }
    }

    private static func addPendingBatchValue(
        _ value: Int64,
        date: String,
        timeType: PositionTimeType,
        action: JDFinancePendingTradeAction,
        to totals: inout [PendingBatchKey: Int64]
    ) {
        let key = PendingBatchKey(
            date: date,
            timeType: timeType.rawValue,
            action: action.rawValue
        )
        totals[key, default: 0] += value
    }

    private static func pendingImportKind(
        for product: JDFinanceHoldingProduct,
        localFund: FundPosition?,
        localFundsByCode: [String: FundPosition],
        localFundsByName: [String: FundPosition],
        hasLocalPending: Bool,
        amount: Double
    ) -> JDFinancePendingImportKind? {
        guard hasPendingTransactionTip(product),
              !hasLocalPending
        else {
            return nil
        }

        let action = product.pendingDetail?.action ?? product.transactionTip?.action ?? .unknown

        if localFund == nil {
            guard action != .sell, amount > 0 else { return nil }
            return .newFund
        }

        guard localFund?.status == .holding || localFund?.status == .pending else {
            return nil
        }

        switch action {
        case .buy:
            return amount > 0 ? .trade(.buy) : nil
        case .sell:
            return .trade(.sell)
        case .conversion:
            return conversionImportKind(
                for: product,
                localFundsByCode: localFundsByCode,
                localFundsByName: localFundsByName
            )
        case .unknown:
            return nil
        }
    }

    private static func conversionImportKind(
        for product: JDFinanceHoldingProduct,
        localFundsByCode: [String: FundPosition],
        localFundsByName: [String: FundPosition]
    ) -> JDFinancePendingImportKind? {
        let conversionRecords = product.pendingDetail?.matchedTradeRecords.filter { $0.action == .conversion } ?? []
        for record in conversionRecords {
            if let targetCode = record.conversionTargetCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !targetCode.isEmpty,
               targetCode != product.code
            {
                let targetName = localFundsByCode[targetCode]?.name ?? record.conversionTargetName
                return .conversion(toCode: targetCode, toName: targetName)
            }

            guard let targetName = record.conversionTargetName else {
                continue
            }
            guard let targetFund = nameLookupKeys(for: targetName)
                .compactMap({ localFundsByName[$0] })
                .first,
                targetFund.code != product.code
            else {
                continue
            }
            return .conversion(toCode: targetFund.code, toName: targetFund.name)
        }
        return nil
    }

    private static func currentAmount(for fund: FundPosition) -> Double? {
        guard fund.status == .holding else {
            return nil
        }

        if let currentAmount = fund.currentAmount {
            return currentAmount
        }

        let principal = fund.migratedPrincipal ?? 0
        let income = holdingIncome(for: fund) ?? 0
        let amount = principal + income
        return amount > 0 ? amount : nil
    }

    private static func holdingIncome(for fund: FundPosition) -> Double? {
        fund.holdingIncome ?? fund.confirmedHoldingIncome
    }
}
