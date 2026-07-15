import Foundation

struct JDFinanceHoldingsSnapshot: Equatable {
    var totalAssets: Double?
    var yesterdayIncome: Double?
    var todayIncome: Double?
    var holdIncome: Double?
    var totalIncome: Double?
    var products: [JDFinanceHoldingProduct]
    var tradeOrders: [JDFinanceTradeOrderRecord] = []
    var tradeOrderFetchState: JDFinanceTradeOrderFetchState = .notRequested
}

enum JDFinanceTradeOrderFetchState: Equatable {
    case notRequested
    case complete
    case incomplete([String])

    var isComplete: Bool {
        if case .complete = self {
            return true
        }
        return false
    }

    var warnings: [String] {
        if case .incomplete(let warnings) = self {
            return warnings
        }
        return []
    }
}

struct JDFinanceHoldingProduct: Identifiable, Equatable {
    var id: String {
        if isCodeResolved {
            return code
        }
        return "unresolved-\(skuID)-\(name)"
    }

    var skuID: String
    var code: String
    var codeResolution: JDFinanceFundCodeResolution = .explicit
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

    var isCodeResolved: Bool {
        codeResolution.isResolved && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum JDFinanceFundCodeResolution: String, Equatable {
    case explicit
    case nameMatched
    case tradeOrderMatched
    case unresolved

    var isResolved: Bool {
        self != .unresolved
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
    var stableOrderKey: String? = nil
    var sourceOrderKeys: [String] = []
    var code: String?
    var codeResolution: JDFinanceFundCodeResolution = .unresolved
    var productName: String?
    var conversionTargetCode: String? = nil
    var conversionTargetName: String? = nil
    var action: JDFinancePendingTradeAction?
    var amount: Double?
    var shares: Double?
    var tradeDate: String?
    var tradeTimeType: PositionTimeType?
    var submittedAt: String? = nil
    var status: JDFinanceTradeOrderStatus? = nil
    var statusCode: String? = nil
    var statusText: String?

    var effectiveStatus: JDFinanceTradeOrderStatus {
        status ?? JDFinanceTradeOrderStatus.classify(statusCode: statusCode, statusText: statusText)
    }

    var isCodeResolved: Bool {
        codeResolution.isResolved
            && !(code?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

enum JDFinanceTradeOrderStatus: String, Equatable {
    case pending
    case succeeded
    case cancelled
    case failed
    case unknown

    static func classify(_ statusText: String?) -> JDFinanceTradeOrderStatus {
        classify(statusCode: nil, statusText: statusText)
    }

    static func classify(statusCode: String?, statusText: String?) -> JDFinanceTradeOrderStatus {
        let normalizedCode = statusCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        let normalizedText = statusText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        guard !normalizedCode.isEmpty || !normalizedText.isEmpty else { return .unknown }

        let exactCancelledCodes = ["REFUND_SUCC", "CANCELED", "CANCELLED", "REVOKED"]
        if exactCancelledCodes.contains(normalizedCode) {
            return .cancelled
        }

        let exactFailedCodes = ["FAIL", "FAILED", "ERROR", "REJECT", "REJECTED"]
        if exactFailedCodes.contains(normalizedCode) {
            return .failed
        }

        let exactPendingCodes = ["PAY_SUCC", "PAY_SUCCESS", "PROCESS", "PROCESSING", "REDEEM", "PENDING"]
        if exactPendingCodes.contains(normalizedCode) {
            return .pending
        }

        let exactSucceededCodes = ["COMPLETE", "COMPLETED", "CONFIRMED", "REDEEM_SUCC", "TRADE_SUCCESS"]
        if exactSucceededCodes.contains(normalizedCode) {
            return .succeeded
        }

        let cancelledTokens = ["取消", "撤单", "撤销", "退款", "CANCEL", "REFUND", "REVOKE"]
        if cancelledTokens.contains(where: normalizedText.contains) {
            return .cancelled
        }

        let failedTokens = ["失败", "FAIL", "ERROR", "REJECT"]
        if failedTokens.contains(where: normalizedText.contains) {
            return .failed
        }

        let pendingTokens = [
            "支付成功", "处理中", "确认中", "待确认", "受理", "申请", "转出中",
            "PENDING", "PROCESS", "PROCESSING", "ACCEPTED", "PAID",
            "PAY_SUCCESS", "PAYMENT_SUCCESS", "PAY_SUCCESSFUL"
        ]
        if pendingTokens.contains(where: normalizedText.contains) {
            return .pending
        }

        let succeededTokens = [
            "确认成功", "交易成功", "订单完成", "赎回成功", "转出完成", "转换成功", "已确认",
            "CONFIRMED", "COMPLETED", "TRADE_SUCCESS", "SUCCESS"
        ]
        if succeededTokens.contains(where: normalizedText.contains) {
            return .succeeded
        }

        return .unknown
    }
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
    var finalOutflowOrder: JDFinanceTradeOrderRecord? = nil

    var canClear: Bool {
        guard let finalOutflowOrder,
              finalOutflowOrder.effectiveStatus == .succeeded
        else { return false }
        return finalOutflowOrder.action == .sell || finalOutflowOrder.action == .conversion
    }
}

struct JDFinanceUnresolvedHolding: Identifiable, Equatable {
    var id: String { "\(skuID)-\(name)" }
    var skuID: String
    var name: String
    var amount: Double
    var holdingIncome: Double?
    var message: String
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

struct JDFinanceAutomaticConfirmation: Identifiable, Equatable {
    var id: String
    var recordIDs: [String]
    var syncKey: String?
    var statusText: String?
    var representedOrderKeys: [String] = []
}

struct JDFinanceUnrecordedOrder: Identifiable, Equatable {
    var id: String
    var record: JDFinanceTradeOrderRecord
    var message: String
    var blockingReason: String? = nil

    var code: String { record.code ?? "" }
    var name: String { record.productName ?? "未命名基金" }
    var missingFields: [String] {
        var fields: [String] = []
        if code.isEmpty { fields.append("基金代码") }
        if record.action == nil || record.action == .unknown { fields.append("交易方向") }
        if record.tradeDate == nil { fields.append("交易日期") }
        if record.tradeTimeType == nil { fields.append("交易时段") }
        switch record.action {
        case .buy:
            if (record.amount ?? 0) <= 0 { fields.append("交易金额") }
        case .sell:
            if (record.shares ?? 0) <= 0 { fields.append("交易份额") }
        case .conversion:
            if (record.shares ?? 0) <= 0 { fields.append("转出份额") }
            if (record.conversionTargetCode ?? "").isEmpty { fields.append("目标基金代码") }
        case .unknown, nil:
            break
        }
        return fields
    }

    var isImportable: Bool {
        guard blockingReason == nil,
              missingFields.isEmpty,
              record.effectiveStatus == .succeeded,
              record.tradeDate != nil
        else {
            return false
        }

        switch record.action {
        case .buy:
            return (record.amount ?? 0) > 0
        case .sell:
            return (record.shares ?? 0) > 0
        case .conversion:
            return (record.shares ?? 0) > 0
                && !(record.conversionTargetCode ?? "").isEmpty
        case .unknown, nil:
            return false
        }
    }

    func tradeDraft() -> FundTradeDraft? {
        guard let action = record.action?.fundTradeAction,
              let tradeDate = record.tradeDate,
              let tradeTimeType = record.tradeTimeType,
              !code.isEmpty
        else {
            return nil
        }

        switch action {
        case .buy:
            guard let amount = record.amount, amount > 0 else { return nil }
            return FundTradeDraft(
                action: .buy,
                code: code,
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
                code: code,
                mode: .share,
                amount: nil,
                shares: shares,
                tradeDate: tradeDate,
                tradeTimeType: tradeTimeType
            )
        }
    }

    func conversionDraft() -> FundConversionDraft? {
        guard record.action == .conversion,
              let toCode = record.conversionTargetCode,
              !code.isEmpty,
              !toCode.isEmpty,
              let shares = record.shares,
              shares > 0,
              let tradeDate = record.tradeDate,
              let tradeTimeType = record.tradeTimeType
        else {
            return nil
        }
        return FundConversionDraft(
            fromCode: code,
            toCode: toCode,
            toName: record.conversionTargetName,
            shares: shares,
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType
        )
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

    var logicalMatchedTradeRecords: [JDFinanceTradeOrderRecord] {
        JDFinanceTradeOrderBatcher.logicalRecords(matchedTradeRecords)
    }

    var candidateTradeRecords: [JDFinanceTradeOrderRecord] {
        pendingDetail?.candidateTradeRecords ?? []
    }

    var tradeCountText: String? {
        "\(logicalTradeCount) 笔"
    }

    var logicalTradeCount: Int {
        if !logicalMatchedTradeRecords.isEmpty {
            return logicalMatchedTradeRecords.count
        }
        return max(transactionTip?.tradeCount ?? 1, 1)
    }

    var actionTitle: String {
        (pendingDetail?.action ?? transactionTip?.action ?? .unknown).title
    }

    func canBuildLocalDraft(manualCompletion: JDFinancePendingManualCompletion?) -> Bool {
        switch importKind {
        case .newFund:
            if !matchedTradeDrafts().isEmpty { return true }
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
        guard importKind == .newFund else {
            return nil
        }

        if let firstDraft = matchedTradeDrafts().first,
           let positionAmount = firstDraft.amount,
           positionAmount > 0
        {
            return FundPositionDraft(
                code: code,
                name: name,
                positionMode: .amount,
                positionAmount: positionAmount,
                positionProfit: holdingIncome ?? 0,
                shares: nil,
                cost: nil,
                positionDate: firstDraft.tradeDate,
                positionTimeType: firstDraft.tradeTimeType,
                memo: "京东金融同步待确认",
                requiresTradeConfirmation: true
            )
        }

        guard
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
                guard let shares = record.shares,
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
        let action: FundTradeAction
        switch importKind {
        case .newFund:
            action = .buy
        case .trade(let pendingAction):
            action = pendingAction
        case .conversion, nil:
            return []
        }
        let records = logicalMatchedTradeRecords.sorted(by: tradeRecordComesBefore)
        guard !records.isEmpty else { return [] }

        let drafts: [FundTradeDraft] = records.compactMap { record in
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
        return drafts.count == records.count ? drafts : []
    }

    private func tradeRecordComesBefore(
        _ lhs: JDFinanceTradeOrderRecord,
        _ rhs: JDFinanceTradeOrderRecord
    ) -> Bool {
        let lhsDate = lhs.tradeDate ?? ""
        let rhsDate = rhs.tradeDate ?? ""
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return tradeTimeOrder(lhs.tradeTimeType) < tradeTimeOrder(rhs.tradeTimeType)
    }

    private func tradeTimeOrder(_ timeType: PositionTimeType?) -> Int {
        switch timeType {
        case .before15:
            0
        case .after15:
            1
        case nil:
            2
        }
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
    var unresolvedHoldings: [JDFinanceUnresolvedHolding] = []
    var pendingNotices: [JDFinanceHoldingPendingNotice]
    var reconciliationNotices: [JDFinanceReconciliationNotice] = []
    var automaticConfirmations: [JDFinanceAutomaticConfirmation] = []
    var unrecordedOrders: [JDFinanceUnrecordedOrder] = []
    var informationalOrders: [JDFinanceTradeOrderRecord] = []
    var warnings: [String] = []
    var autoConfirmedCount: Int = 0
    var baselineRepresentedCount: Int = 0
    var baselineOrderKeys: [String] = []

    var hasImportableChanges: Bool {
        !newHoldings.isEmpty
    }

    var hasActionableChanges: Bool {
        !newHoldings.isEmpty
            || !changedHoldings.isEmpty
            || !importablePendingNotices.isEmpty
            || !overwritableReconciliationNotices.isEmpty
            || !importableUnrecordedOrders.isEmpty
    }

    var importablePendingNotices: [JDFinanceHoldingPendingNotice] {
        pendingNotices.filter(\.isImportable)
    }

    var pendingTradeCount: Int {
        pendingNotices.map(\.logicalTradeCount).reduce(0, +)
    }

    var importablePendingTradeCount: Int {
        importablePendingNotices.map(\.logicalTradeCount).reduce(0, +)
    }

    var overwritableReconciliationNotices: [JDFinanceReconciliationNotice] {
        reconciliationNotices.filter(\.isOverwritable)
    }

    var importableUnrecordedOrders: [JDFinanceUnrecordedOrder] {
        unrecordedOrders.filter(\.isImportable)
    }

    var isEmpty: Bool {
        newHoldings.isEmpty
            && changedHoldings.isEmpty
            && missingLocalHoldings.isEmpty
            && unresolvedHoldings.isEmpty
            && pendingNotices.isEmpty
            && reconciliationNotices.isEmpty
            && unrecordedOrders.isEmpty
            && informationalOrders.isEmpty
            && warnings.isEmpty
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
        guard digits.count == 6, digits.first != "1" else { return nil }
        return digits
    }
}
