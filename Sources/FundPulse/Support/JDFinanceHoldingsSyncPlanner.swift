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
        let resolvedRemoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: remoteSnapshot.totalAssets,
            yesterdayIncome: remoteSnapshot.yesterdayIncome,
            todayIncome: remoteSnapshot.todayIncome,
            holdIncome: remoteSnapshot.holdIncome,
            totalIncome: remoteSnapshot.totalIncome,
            products: remoteProducts
        )
        let remoteCodes = Set(remoteProducts.map(\.code))
        let localPendingTradeCodes = Set(localSnapshot.pendingTrades?.map(\.code) ?? [])
        let localPendingConversionCodes = Set((localSnapshot.pendingConversions ?? []).flatMap { [$0.fromCode, $0.toCode] })

        let newHoldings = remoteProducts
            .filter { localFundsByCode[$0.code] == nil && !hasPendingTransactionTip($0) }
            .map { JDFinanceHoldingImportCandidate(product: $0) }

        let changedHoldings = remoteProducts.compactMap { product -> JDFinanceHoldingDifference? in
            guard !hasPendingTransactionTip(product),
                  let localFund = localFundsByCode[product.code],
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

        let pendingNotices = remoteProducts.compactMap { product -> JDFinanceHoldingPendingNotice? in
            let transactionTipText = product.transactionTipText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let localFund = localFundsByCode[product.code]
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

            guard let message = [localPendingMessage, transactionTipText]
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
                importKind: pendingImportKind(
                    for: product,
                    localFund: localFund,
                    localFundsByCode: localFundsByCode,
                    localFundsByName: localFundsByName,
                    hasLocalPending: hasLocalPending,
                    amount: amount
                )
            )
        }

        return JDFinanceHoldingsSyncPreview(
            remoteSnapshot: resolvedRemoteSnapshot,
            newHoldings: newHoldings,
            changedHoldings: changedHoldings,
            missingLocalHoldings: missingLocalHoldings,
            pendingNotices: pendingNotices
        )
    }

    private static func resolvedProduct(
        _ product: JDFinanceHoldingProduct,
        localFundsByCode: [String: FundPosition],
        localFundsByName: [String: FundPosition]
    ) -> JDFinanceHoldingProduct {
        guard localFundsByCode[product.code] == nil,
              let localFund = nameLookupKeys(for: product.name).compactMap({ localFundsByName[$0] }).first
        else {
            return product
        }

        var resolved = product
        resolved.code = localFund.code
        return resolved
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
