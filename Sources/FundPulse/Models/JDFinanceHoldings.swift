import Foundation

struct JDFinanceHoldingsSnapshot: Equatable {
    var totalAssets: Double?
    var yesterdayIncome: Double?
    var todayIncome: Double?
    var holdIncome: Double?
    var totalIncome: Double?
    var products: [JDFinanceHoldingProduct]
}

struct JDFinanceHoldingProduct: Identifiable, Equatable {
    var id: String { code }
    var skuID: String
    var code: String
    var name: String
    var totalAmount: Double
    var yesterdayIncome: Double?
    var yesterdayIncomeNotice: String? = nil
    var todayIncome: Double?
    var holdIncome: Double?
    var holdRate: Double?
    var transactionTip: JDFinanceTransactionTip? = nil
    var detailRequest: JDFinanceHoldingDetailRequest? = nil
    var pendingDetail: JDFinancePendingTransactionDetail? = nil

    var transactionTipText: String? {
        transactionTip?.text
    }
}

enum JDFinancePendingTradeAction: String, Equatable {
    case buy
    case sell
    case conversion
    case unknown

    var title: String {
        switch self {
        case .buy:
            "买入"
        case .sell:
            "卖出"
        case .conversion:
            "转换"
        case .unknown:
            "交易"
        }
    }

    var fundTradeAction: FundTradeAction? {
        switch self {
        case .buy:
            .buy
        case .sell:
            .sell
        case .conversion:
            nil
        case .unknown:
            nil
        }
    }
}

struct JDFinanceTransactionTip: Equatable {
    var text: String
    var action: JDFinancePendingTradeAction
    var tradeCount: Int?
    var totalAmount: Double?
}

struct JDFinanceHoldingDetailRequest: Equatable {
    var extJSON: String
}

struct JDFinancePendingTransactionDetail: Equatable {
    var action: JDFinancePendingTradeAction?
    var amount: Double?
    var shares: Double?
    var tradeDate: String?
    var tradeTimeType: PositionTimeType?
    var statusText: String?
    var matchedTradeRecords: [JDFinanceTradeOrderRecord] = []
    var candidateTradeRecords: [JDFinanceTradeOrderRecord] = []
}

struct JDFinanceTradeOrderRecord: Equatable {
    var code: String?
    var productName: String?
    var conversionTargetCode: String? = nil
    var conversionTargetName: String? = nil
    var action: JDFinancePendingTradeAction?
    var amount: Double?
    var shares: Double?
    var tradeDate: String?
    var tradeTimeType: PositionTimeType?
    var statusText: String?
}

enum JDFinancePendingImportKind: Equatable {
    case newFund
    case trade(FundTradeAction)
    case conversion(toCode: String, toName: String?)
}

struct JDFinancePendingManualCompletion: Equatable {
    var tradeDate: String
    var tradeTimeType: PositionTimeType
}

struct JDFinanceHoldingImportCandidate: Identifiable, Equatable {
    var id: String { product.code }
    var product: JDFinanceHoldingProduct

    var code: String { product.code }
    var name: String { product.name }
    var amount: Double { product.totalAmount }
    var holdingIncome: Double { product.holdIncome ?? 0 }

    func draft(positionDate: String) -> FundPositionDraft {
        return FundPositionDraft(
            code: code,
            name: name,
            positionMode: .amount,
            positionAmount: amount,
            positionProfit: holdingIncome,
            shares: nil,
            cost: nil,
            positionDate: positionDate,
            positionTimeType: .before15,
            zdfRange: nil,
            jzNotice: nil,
            memo: "京东金融同步导入",
            requiresTradeConfirmation: false
        )
    }
}

struct JDFinanceHoldingDifference: Identifiable, Equatable {
    var id: String { code }
    var code: String
    var name: String
    var jdAmount: Double
    var localAmount: Double?
    var jdHoldingIncome: Double?
    var localHoldingIncome: Double?
    var jdHoldingRate: Double?
    var localHoldingRate: Double?
}

struct JDFinanceMissingLocalHolding: Identifiable, Equatable {
    var id: String { code }
    var code: String
    var name: String
    var localAmount: Double?
}

struct JDFinanceSyncDifference: Equatable {
    var amountDelta: Double?
    var sharesDelta: Double?
    var priceDelta: Double?

    var hasDifference: Bool {
        (amountDelta.map { abs($0) >= 0.01 } ?? false)
            || (sharesDelta.map { abs($0) >= 0.000001 } ?? false)
            || (priceDelta.map { abs($0) >= 0.000001 } ?? false)
    }
}

enum JDFinanceSyncPreviewState: Equatable {
    case localConfirmedJDPending(difference: JDFinanceSyncDifference)
    case jdConfirmedNeedsOverwrite(difference: JDFinanceSyncDifference)
    case conflict(String)
}

enum JDFinanceReconciliationKind: Equatable {
    case trade(recordID: String, action: FundTradeAction)
    case conversion(conversionID: String, outRecordID: String?, inRecordID: String?)
}

struct JDFinanceReconciliationValues: Equatable {
    var amount: Double? = nil
    var shares: Double? = nil
    var price: Double? = nil
    var inAmount: Double? = nil
    var inShares: Double? = nil
    var inPrice: Double? = nil
    var statusText: String? = nil
    var syncKey: String? = nil
}

struct JDFinanceReconciliationNotice: Identifiable, Equatable {
    var id: String
    var code: String
    var name: String
    var linkedCode: String?
    var linkedName: String?
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var kind: JDFinanceReconciliationKind
    var state: JDFinanceSyncPreviewState
    var localAmount: Double?
    var jdAmount: Double?
    var localShares: Double?
    var jdShares: Double?
    var values: JDFinanceReconciliationValues
    var matchedTradeRecords: [JDFinanceTradeOrderRecord]

    var isOverwritable: Bool {
        if case .jdConfirmedNeedsOverwrite = state {
            return true
        }
        return false
    }
}

struct JDFinanceHoldingPendingNotice: Identifiable, Equatable {
    var id: String { code }
    var code: String
    var name: String
    var amount: Double
    var holdingIncome: Double?
    var message: String
    var transactionTip: JDFinanceTransactionTip? = nil
    var yesterdayIncomeNotice: String? = nil
    var pendingDetail: JDFinancePendingTransactionDetail? = nil
    var importKind: JDFinancePendingImportKind? = nil
    var syncState: JDFinanceSyncPreviewState? = nil

    var isImportable: Bool {
        canBuildLocalDraft(manualCompletion: nil)
    }

    var requiresManualCompletion: Bool {
        importKind != nil && !isImportable
    }

    var detailStatusText: String? {
        pendingDetail?.statusText
    }

    var matchedTradeRecords: [JDFinanceTradeOrderRecord] {
        pendingDetail?.matchedTradeRecords ?? []
    }

    var candidateTradeRecords: [JDFinanceTradeOrderRecord] {
        pendingDetail?.candidateTradeRecords ?? []
    }

    var tradeCountText: String? {
        transactionTip?.tradeCount.map { "\($0) 笔" }
    }

    var actionTitle: String {
        (pendingDetail?.action ?? transactionTip?.action ?? .unknown).title
    }

    func canBuildLocalDraft(manualCompletion: JDFinancePendingManualCompletion?) -> Bool {
        switch importKind {
        case .newFund:
            return localTradeDate(manualCompletion: manualCompletion) != nil
                && localTradeTimeType(manualCompletion: manualCompletion) != nil
                && amount > 0
        case .trade(.buy):
            if !matchedTradeDrafts().isEmpty { return true }
            return localTradeDate(manualCompletion: manualCompletion) != nil
                && localTradeTimeType(manualCompletion: manualCompletion) != nil
                && amount > 0
        case .trade(.sell):
            if !matchedTradeDrafts().isEmpty { return true }
            return localTradeDate(manualCompletion: manualCompletion) != nil
                && localTradeTimeType(manualCompletion: manualCompletion) != nil
                && (pendingDetail?.shares ?? 0) > 0
        case .conversion:
            return !conversionDrafts(manualCompletion: manualCompletion).isEmpty
        case nil:
            return false
        }
    }

    func fundPositionDraft(manualCompletion: JDFinancePendingManualCompletion? = nil) -> FundPositionDraft? {
        guard importKind == .newFund,
              let tradeDate = localTradeDate(manualCompletion: manualCompletion),
              let tradeTimeType = localTradeTimeType(manualCompletion: manualCompletion)
        else {
            return nil
        }

        return FundPositionDraft(
            code: code,
            name: name,
            positionMode: .amount,
            positionAmount: amount,
            positionProfit: holdingIncome ?? 0,
            shares: nil,
            cost: nil,
            positionDate: tradeDate,
            positionTimeType: tradeTimeType,
            zdfRange: nil,
            jzNotice: nil,
            memo: "京东金融同步待确认",
            requiresTradeConfirmation: true
        )
    }

    func tradeDraft(manualCompletion: JDFinancePendingManualCompletion? = nil) -> FundTradeDraft? {
        if let firstDraft = tradeDrafts(manualCompletion: manualCompletion)?.first {
            return firstDraft
        }

        return nil
    }

    func tradeDrafts(manualCompletion: JDFinancePendingManualCompletion? = nil) -> [FundTradeDraft]? {
        let matchedDrafts = matchedTradeDrafts()
        if !matchedDrafts.isEmpty {
            return matchedDrafts
        }

        guard case let .trade(action) = importKind,
              let tradeDate = localTradeDate(manualCompletion: manualCompletion),
              let tradeTimeType = localTradeTimeType(manualCompletion: manualCompletion)
        else {
            return nil
        }

        switch action {
        case .buy:
            guard amount > 0 else { return nil }
            return [FundTradeDraft(
                action: .buy,
                code: code,
                mode: .amount,
                amount: amount,
                shares: nil,
                tradeDate: tradeDate,
                tradeTimeType: tradeTimeType
            )]
        case .sell:
            guard let shares = pendingDetail?.shares, shares > 0 else { return nil }
            return [FundTradeDraft(
                action: .sell,
                code: code,
                mode: .share,
                amount: nil,
                shares: shares,
                tradeDate: tradeDate,
                tradeTimeType: tradeTimeType
            )]
        }
    }

    func conversionDraft(manualCompletion: JDFinancePendingManualCompletion? = nil) -> FundConversionDraft? {
        conversionDrafts(manualCompletion: manualCompletion).first
    }

    func conversionDrafts(manualCompletion: JDFinancePendingManualCompletion? = nil) -> [FundConversionDraft] {
        guard case let .conversion(toCode, toName) = importKind,
              let tradeDate = localTradeDate(manualCompletion: manualCompletion),
              let tradeTimeType = localTradeTimeType(manualCompletion: manualCompletion)
        else {
            return []
        }

        let conversionRecords = matchedTradeRecords.filter { $0.action == .conversion }
        if !conversionRecords.isEmpty {
            return conversionRecords.compactMap { record in
                guard let shares = record.shares ?? record.amount,
                      shares > 0
                else {
                    return nil
                }
                return FundConversionDraft(
                    fromCode: code,
                    toCode: toCode,
                    toName: toName,
                    shares: shares,
                    tradeDate: record.tradeDate ?? tradeDate,
                    tradeTimeType: record.tradeTimeType ?? tradeTimeType
                )
            }
        }

        guard let shares = pendingDetail?.shares,
              shares > 0
        else {
            return []
        }

        return [FundConversionDraft(
            fromCode: code,
            toCode: toCode,
            toName: toName,
            shares: shares,
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType
        )]
    }

    private func matchedTradeDrafts() -> [FundTradeDraft] {
        guard case let .trade(action) = importKind,
              !matchedTradeRecords.isEmpty
        else {
            return []
        }

        let drafts: [FundTradeDraft] = matchedTradeRecords.compactMap { record in
            guard let tradeDate = record.tradeDate,
                  let tradeTimeType = record.tradeTimeType
            else {
                return nil
            }

            switch action {
            case .buy:
                guard let amount = record.amount, amount > 0 else { return nil }
                return FundTradeDraft(
                    action: .buy,
                    code: normalizedRecordCode(record) ?? code,
                    mode: .amount,
                    amount: amount,
                    shares: nil,
                    tradeDate: tradeDate,
                    tradeTimeType: tradeTimeType
                )
            case .sell:
                guard let shares = record.shares, shares > 0 else { return nil }
                return FundTradeDraft(
                    action: .sell,
                    code: normalizedRecordCode(record) ?? code,
                    mode: .share,
                    amount: nil,
                    shares: shares,
                    tradeDate: tradeDate,
                    tradeTimeType: tradeTimeType
                )
            }
        }
        return drafts.count == matchedTradeRecords.count ? drafts : []
    }

    private func normalizedRecordCode(_ record: JDFinanceTradeOrderRecord) -> String? {
        let trimmed = record.code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localTradeDate(manualCompletion: JDFinancePendingManualCompletion?) -> String? {
        pendingDetail?.tradeDate ?? manualCompletion?.tradeDate
    }

    private func localTradeTimeType(manualCompletion: JDFinancePendingManualCompletion?) -> PositionTimeType? {
        pendingDetail?.tradeTimeType ?? manualCompletion?.tradeTimeType
    }
}

struct JDFinanceHoldingsSyncPreview: Equatable {
    var remoteSnapshot: JDFinanceHoldingsSnapshot
    var newHoldings: [JDFinanceHoldingImportCandidate]
    var changedHoldings: [JDFinanceHoldingDifference]
    var missingLocalHoldings: [JDFinanceMissingLocalHolding]
    var pendingNotices: [JDFinanceHoldingPendingNotice]
    var reconciliationNotices: [JDFinanceReconciliationNotice] = []

    var hasImportableChanges: Bool {
        !newHoldings.isEmpty
    }

    var hasActionableChanges: Bool {
        !newHoldings.isEmpty || !changedHoldings.isEmpty || !importablePendingNotices.isEmpty || !overwritableReconciliationNotices.isEmpty
    }

    var importablePendingNotices: [JDFinanceHoldingPendingNotice] {
        pendingNotices.filter(\.isImportable)
    }

    var overwritableReconciliationNotices: [JDFinanceReconciliationNotice] {
        reconciliationNotices.filter(\.isOverwritable)
    }

    var isEmpty: Bool {
        newHoldings.isEmpty
            && changedHoldings.isEmpty
            && missingLocalHoldings.isEmpty
            && pendingNotices.isEmpty
            && reconciliationNotices.isEmpty
    }
}

enum JDFinanceHoldingsError: LocalizedError, Equatable {
    case notLoggedIn
    case emptyHoldings
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            "请先登录京东账号"
        case .emptyHoldings:
            "没有读取到京东基金持仓"
        case .invalidResponse:
            "京东持仓接口结构变化，暂时无法解析"
        case .network(let message):
            message
        }
    }
}

enum JDFinanceFundCodeMapper {
    static func inferCode(from skuID: String) -> String? {
        let digits = skuID.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        if digits.count == 7, digits.first == "1" {
            return String(digits.suffix(6))
        }

        if digits.count == 6, digits.first == "1" {
            return "0" + String(digits.suffix(5))
        }

        if digits.count == 6 {
            return digits
        }

        if digits.count == 5 {
            return "0" + digits
        }

        if digits.count > 6 {
            return String(digits.suffix(6))
        }

        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
}
