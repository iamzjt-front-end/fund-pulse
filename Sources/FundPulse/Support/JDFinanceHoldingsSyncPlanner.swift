import Foundation

enum JDFinanceHoldingsSyncPlanner {
    static func preview(
        remoteSnapshot: JDFinanceHoldingsSnapshot,
        localSnapshot: PortfolioSnapshot
    ) -> JDFinanceHoldingsSyncPreview {
        let localFundsByCode = Dictionary(uniqueKeysWithValues: localSnapshot.funds.map { ($0.code, $0) })
        let localFundsByName = localFundsByNormalizedName(localSnapshot.funds)
        let remoteProducts = remoteSnapshot.products.map {
            resolvedProduct($0, localFundsByCode: localFundsByCode, localFundsByName: localFundsByName)
        }
        let resolvedProducts = remoteProducts.filter(\.isCodeResolved)
        let unresolvedProducts = remoteProducts.filter { !$0.isCodeResolved }
        let resolvedRemoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: remoteSnapshot.totalAssets,
            yesterdayIncome: remoteSnapshot.yesterdayIncome,
            todayIncome: remoteSnapshot.todayIncome,
            holdIncome: remoteSnapshot.holdIncome,
            totalIncome: remoteSnapshot.totalIncome,
            products: remoteProducts
        )
        let remoteCodes = Set(resolvedProducts.map(\.code))
        let localPendingTradeCodes = Set(localSnapshot.pendingTrades?.map(\.code) ?? [])
        let localPendingConversionCodes = Set((localSnapshot.pendingConversions ?? []).flatMap { [$0.fromCode, $0.toCode] })
        let localTradeRecords = localSnapshot.tradeRecords ?? []

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
            let amountChanged = moneyDifference(product.totalAmount, localAmount)
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
                localHoldingRate: localHoldingRate
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
                localAmount: localAmount
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
            let hasLocalPending = localFund?.status == .pending
                || localPendingTradeCodes.contains(product.code)
                || localPendingConversionCodes.contains(product.code)
            let localPendingMessage: String? = if hasLocalPending {
                "本地已有待确认记录，确认后再参与金额对比"
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
                "本地已确认，京东仍待确认；差额仅展示，不写入本地"
            } else {
                nil
            }

            guard let message = [localPendingMessage, localConfirmedMessage, transactionTipText]
                .compactMap({ $0 })
                .first(where: { !$0.isEmpty })
            else { return nil }

            return JDFinanceHoldingPendingNotice(
                code: product.code,
                name: product.name,
                amount: amount,
                holdingIncome: product.holdIncome,
                message: message,
                transactionTip: product.transactionTip,
                yesterdayIncomeNotice: product.yesterdayIncomeNotice,
                pendingDetail: product.pendingDetail,
                importKind: localConfirmedCandidate == nil ? pendingImportKind(
                    for: product,
                    localFund: localFund,
                    localFundsByCode: localFundsByCode,
                    localFundsByName: localFundsByName,
                    hasLocalPending: hasLocalPending,
                    amount: amount
                ) : nil,
                syncState: syncState
            )
        }
        let reconciliationNotices = reconciliationNotices(
            remoteProducts: resolvedProducts,
            localTradeRecords: localTradeRecords
        )

        return JDFinanceHoldingsSyncPreview(
            remoteSnapshot: resolvedRemoteSnapshot,
            newHoldings: newHoldings,
            changedHoldings: changedHoldings,
            missingLocalHoldings: missingLocalHoldings,
            unresolvedHoldings: unresolvedHoldings,
            pendingNotices: pendingNotices,
            reconciliationNotices: reconciliationNotices
        )
    }

    private static func resolvedProduct(
        _ product: JDFinanceHoldingProduct,
        localFundsByCode: [String: FundPosition],
        localFundsByName: [String: FundPosition]
    ) -> JDFinanceHoldingProduct {
        if let orderCode = commonMatchedTradeOrderCode(for: product) {
            var resolved = product
            resolved.code = orderCode
            if !product.isCodeResolved {
                resolved.codeResolution = .nameMatched
            }
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

    private static func roundedMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func roundedShares(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }

    private struct LocalConfirmedCandidate {
        var record: FundTradeRecord
        var linkedRecord: FundTradeRecord?
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
            guard let record = records.first(where: { record in
                record.status == .confirmed
                    && (record.kind == .newFund || record.kind == .buy)
                    && record.code == product.code
                    && timingMatches(record: record, tradeDate: tradeDate, tradeTimeType: tradeTimeType)
            }) else {
                return nil
            }
            return LocalConfirmedCandidate(record: record)
        case .sell:
            guard let record = records.first(where: { record in
                record.status == .confirmed
                    && record.kind == .sell
                    && record.code == product.code
                    && timingMatches(record: record, tradeDate: tradeDate, tradeTimeType: tradeTimeType)
            }) else {
                return nil
            }
            return LocalConfirmedCandidate(record: record)
        case .conversion:
            guard let record = records.first(where: { record in
                record.status == .confirmed
                    && record.kind == .conversionOut
                    && record.code == product.code
                    && timingMatches(record: record, tradeDate: tradeDate, tradeTimeType: tradeTimeType)
                    && conversionTargetMatches(product: product, record: record)
            }) else {
                return nil
            }
            let linkedRecord = record.conversionID.flatMap { conversionID in
                records.first { $0.conversionID == conversionID && $0.kind == .conversionIn }
            }
            return LocalConfirmedCandidate(record: record, linkedRecord: linkedRecord)
        case .unknown:
            return nil
        }
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
        let localAmount = candidate.record.amount
        let localShares = candidate.record.confirmedShares ?? candidate.record.shares
        return JDFinanceSyncDifference(
            amountDelta: amountDelta(jd: pendingAmount, local: localAmount),
            sharesDelta: sharesDelta(jd: pendingShares, local: localShares),
            priceDelta: nil
        )
    }

    private static func reconciliationNotices(
        remoteProducts: [JDFinanceHoldingProduct],
        localTradeRecords: [FundTradeRecord]
    ) -> [JDFinanceReconciliationNotice] {
        let productsByCode = Dictionary(uniqueKeysWithValues: remoteProducts.map { ($0.code, $0) })
        var notices: [JDFinanceReconciliationNotice] = []
        var handledConversionIDs = Set<String>()

        for record in localTradeRecords where record.status == .confirmed && waitsForJDFinalConfirmation(record) {
            switch record.kind {
            case .newFund, .buy, .sell:
                if let notice = tradeReconciliationNotice(record: record, product: productsByCode[record.code]) {
                    notices.append(notice)
                }
            case .conversionOut:
                guard let conversionID = record.conversionID,
                      !handledConversionIDs.contains(conversionID)
                else {
                    continue
                }
                handledConversionIDs.insert(conversionID)
                let linkedRecord = localTradeRecords.first {
                    $0.conversionID == conversionID && $0.kind == .conversionIn
                }
                if let notice = conversionReconciliationNotice(
                    outRecord: record,
                    inRecord: linkedRecord,
                    product: productsByCode[record.code]
                ) {
                    notices.append(notice)
                }
            case .conversionIn:
                continue
            }
        }
        return notices
    }

    private static func waitsForJDFinalConfirmation(_ record: FundTradeRecord) -> Bool {
        record.syncSource == .jdFinance
            && ((record.waitsForExternalConfirmation ?? false)
                || record.externalStatus == .waitingExternalConfirmation)
    }

    private static func tradeReconciliationNotice(
        record: FundTradeRecord,
        product: JDFinanceHoldingProduct?
    ) -> JDFinanceReconciliationNotice? {
        guard product?.transactionTip == nil else {
            return nil
        }
        let finalRecords = product.map(finalTradeOrderRecords) ?? []
        guard !finalRecords.isEmpty else {
            return conflictNotice(
                record: record,
                message: "缺少京东最终流水，不能安全覆盖流水"
            )
        }
        guard let order = finalRecords.first(where: { tradeOrder($0, matches: record) }) else {
            return conflictNotice(
                record: record,
                message: "京东已确认，但未匹配到本地流水，不能自动覆盖"
            )
        }

        let values = reconciliationValues(record: record, order: order)
        let difference = recordDifference(record: record, values: values)
        guard difference.hasDifference else {
            return nil
        }
        let action: FundTradeAction = record.kind == .sell ? .sell : .buy
        return JDFinanceReconciliationNotice(
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
            matchedTradeRecords: [order]
        )
    }

    private static func conversionReconciliationNotice(
        outRecord: FundTradeRecord,
        inRecord: FundTradeRecord?,
        product: JDFinanceHoldingProduct?
    ) -> JDFinanceReconciliationNotice? {
        guard product?.transactionTip == nil else {
            return nil
        }
        guard let conversionID = outRecord.conversionID else {
            return nil
        }
        let finalRecords = product.map(finalTradeOrderRecords) ?? []
        guard !finalRecords.isEmpty else {
            return conversionConflictNotice(
                outRecord: outRecord,
                inRecord: inRecord,
                message: "缺少京东最终流水，不能安全覆盖流水"
            )
        }
        guard let order = finalRecords.first(where: { conversionOrder($0, matches: outRecord) }) else {
            return conversionConflictNotice(
                outRecord: outRecord,
                inRecord: inRecord,
                message: "京东已确认，但未匹配到本地转换流水，不能自动覆盖"
            )
        }

        let values = reconciliationValues(outRecord: outRecord, inRecord: inRecord, order: order)
        let difference = recordDifference(record: outRecord, values: values)
        guard difference.hasDifference else {
            return nil
        }
        return JDFinanceReconciliationNotice(
            id: conversionID,
            code: outRecord.code,
            name: outRecord.name,
            linkedCode: outRecord.linkedCode,
            linkedName: outRecord.linkedName,
            tradeDate: outRecord.tradeDate,
            tradeTimeType: outRecord.tradeTimeType,
            kind: .conversion(
                conversionID: conversionID,
                outRecordID: outRecord.id,
                inRecordID: inRecord?.id
            ),
            state: .jdConfirmedNeedsOverwrite(difference: difference),
            localAmount: outRecord.amount,
            jdAmount: values.amount,
            localShares: outRecord.confirmedShares ?? outRecord.shares,
            jdShares: values.shares,
            values: values,
            matchedTradeRecords: [order]
        )
    }

    private static func finalTradeOrderRecords(for product: JDFinanceHoldingProduct) -> [JDFinanceTradeOrderRecord] {
        var records: [JDFinanceTradeOrderRecord] = []
        for record in product.pendingDetail?.matchedTradeRecords ?? [] {
            appendUniqueTradeRecord(record, to: &records)
        }
        for record in product.pendingDetail?.candidateTradeRecords ?? [] {
            appendUniqueTradeRecord(record, to: &records)
        }
        return records.filter(isFinalTradeOrderRecord)
    }

    private static func appendUniqueTradeRecord(
        _ record: JDFinanceTradeOrderRecord,
        to records: inout [JDFinanceTradeOrderRecord]
    ) {
        let key = JDFinanceSyncFingerprint.tradeOrderRecord(record)
        guard !records.contains(where: { JDFinanceSyncFingerprint.tradeOrderRecord($0) == key }) else {
            return
        }
        records.append(record)
    }

    private static func isFinalTradeOrderRecord(_ record: JDFinanceTradeOrderRecord) -> Bool {
        guard let statusText = record.statusText?.uppercased() else {
            return true
        }
        let pendingTokens = ["处理中", "确认中", "待确认", "受理", "申请", "PENDING", "PROCESS"]
        return !pendingTokens.contains { statusText.contains($0) }
    }

    private static func tradeOrder(_ order: JDFinanceTradeOrderRecord, matches record: FundTradeRecord) -> Bool {
        guard order.code == nil || order.code == record.code,
              order.tradeDate == record.tradeDate,
              order.tradeTimeType == record.tradeTimeType
        else {
            return false
        }
        switch record.kind {
        case .newFund, .buy:
            return order.action == nil || order.action == .buy || order.action == .unknown
        case .sell:
            return order.action == nil || order.action == .sell || order.action == .unknown
        case .conversionOut, .conversionIn:
            return false
        }
    }

    private static func conversionOrder(_ order: JDFinanceTradeOrderRecord, matches record: FundTradeRecord) -> Bool {
        guard order.action == nil || order.action == .conversion,
              order.code == nil || order.code == record.code,
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
        let finalOutShares = order.shares ?? order.amount ?? outRecord.confirmedShares ?? outRecord.shares
        let finalOutAmount = order.shares == nil ? outRecord.amount : (order.amount ?? outRecord.amount)
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

        guard localFund?.status == .holding else {
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
