import Foundation

struct PortfolioSnapshot: Codable, Equatable {
    var updateTime: Date
    var totalAmount: Double
    var holdingIncome: Double
    var holdingIncomeRate: Double
    var todayIncome: Double
    var todayIncomeRate: Double
    var pendingCount: Int
    var funds: [FundPosition]
    var migration: MigrationInfo?
    var pendingTrades: [FundPendingTrade]? = nil
    var pendingConversions: [FundPendingConversion]? = nil
    var tradeRecords: [FundTradeRecord]? = nil
    var syncedAccountTotal: PortfolioSyncedAccountTotal? = nil
    var jdFinanceSyncState: JDFinanceSyncState? = nil
    // Only populated in exported backups. Runtime history lives in
    // portfolio-performance.json so high-frequency quote refreshes do not
    // repeatedly rewrite a growing history array.
    var portfolioPerformanceHistory: PortfolioPerformanceSnapshot? = nil

    static let empty = PortfolioSnapshot(
        updateTime: .now,
        totalAmount: 0,
        holdingIncome: 0,
        holdingIncomeRate: 0,
        todayIncome: 0,
        todayIncomeRate: 0,
        pendingCount: 0,
        funds: [],
        migration: nil
    )

}

struct JDFinanceSyncState: Codable, Equatable {
    var schemaVersion: Int = 1
    var accountKey: String?
    var baselineEstablishedAt: Date
    var lastCompleteTradeOrderSyncAt: Date? = nil
    var representedOrderKeys: [String] = []
    var dismissedOrderKeys: [String] = []
    var trackedPendingOrderKeys: [String] = []
    var trackedPendingStartDate: String? = nil
}

struct PortfolioSyncedAccountTotal: Codable, Equatable {
    var source: PortfolioAccountTotalSource
    var amount: Double
    var syncedAt: Date
}

enum PortfolioAccountTotalSource: String, Codable, Equatable {
    case jdFinance
}

struct FundPosition: Codable, Identifiable, Equatable {
    var id: String { code }
    var code: String
    var name: String
    var dateText: String
    var todayIncome: Double
    var todayRate: Double
    var holdingIncome: Double? = nil
    var holdingRate: Double?
    var confirmedHoldingIncome: Double? = nil
    var confirmedHoldingRate: Double? = nil
    var currentAmount: Double? = nil
    var status: FundHoldingStatus
    var isUpdated: Bool
    var isIncomeActive: Bool? = nil
    var migratedShares: Double? = nil
    var migratedCost: Double? = nil
    var migratedPrincipal: Double? = nil
    var incomeStartDate: String? = nil
    var positionMode: PositionMode? = nil
    var positionDate: String? = nil
    var positionTimeType: PositionTimeType? = nil
    var pendingAmount: Double? = nil
    var pendingProfit: Double? = nil
    // JD's synced holding amount may include today's buy orders before shares are confirmed.
    var syncedPendingBuyAmount: Double? = nil
    var syncedPendingBuyDate: String? = nil
    // JD's daily income is the authoritative value returned by the holdings endpoint.
    var syncedTodayIncome: Double? = nil
    var syncedTodayIncomeDate: String? = nil
    var zdfRange: Double? = nil
    var jzNotice: Double? = nil
    var memo: String? = nil
    var lots: [FundPositionLot]? = nil
    var intradayRateDate: String? = nil
    var intradayRateHistory: [FundIntradayRatePoint]? = nil
}

struct FundPositionLot: Codable, Identifiable, Equatable {
    var id: String
    var shares: Double
    var cost: Double
    var principal: Double? = nil
    var incomeStartDate: String
    var positionDate: String
    var positionTimeType: PositionTimeType
}

struct FundIntradayRatePoint: Codable, Identifiable, Equatable {
    var id: Int64 { timestamp }
    var timestamp: Int64
    var rate: Double
    var estimateTime: String
}

enum FundTradeKind: String, Codable, Equatable {
    case newFund
    case buy
    case sell
    case conversionOut
    case conversionIn

    var title: String {
        switch self {
        case .newFund:
            "新增基金"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
        case .conversionOut:
            "转换转出"
        case .conversionIn:
            "转换转入"
        }
    }
}

enum FundTradeRecordStatus: String, Codable, Equatable {
    case pending
    case confirmed
    case failed

    var title: String {
        switch self {
        case .pending:
            "待确认"
        case .confirmed:
            "已确认"
        case .failed:
            "失败"
        }
    }
}

enum FundTradeSyncSource: String, Codable, Equatable {
    case jdFinance
}

enum FundTradeExternalStatus: String, Codable, Equatable {
    case waitingExternalConfirmation
    case externalConfirmed
    case conflict
}

struct FundTradeSyncMetadata: Codable, Equatable {
    var source: FundTradeSyncSource
    var syncKey: String?
    var externalStatus: FundTradeExternalStatus?
    var externalStatusText: String?
    var waitsForExternalConfirmation: Bool? = nil
}

struct FundTradeRecord: Codable, Identifiable, Equatable {
    var id: String
    var kind: FundTradeKind
    var status: FundTradeRecordStatus
    var code: String
    var name: String
    var mode: PositionMode
    var amount: Double?
    var shares: Double?
    var confirmedShares: Double?
    var price: Double?
    var profit: Double? = nil
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var acceptedDate: String
    var createdAt: Date
    var confirmedAt: Date?
    var failureReason: String?
    var buyFeeRate: Double? = nil
    var sellFeeMode: TradeFeeMode? = nil
    var sellFeeValue: Double? = nil
    var conversionID: String? = nil
    var linkedCode: String? = nil
    var linkedName: String? = nil
    var feeAmount: Double? = nil
    var syncSource: FundTradeSyncSource? = nil
    var syncKey: String? = nil
    var externalStatus: FundTradeExternalStatus? = nil
    var externalStatusText: String? = nil
    var waitsForExternalConfirmation: Bool? = nil
    var isReconciliationBaseline: Bool? = nil
}

enum FundTradeAction: String, Codable, CaseIterable, Identifiable, Equatable {
    case buy
    case sell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buy:
            "加仓"
        case .sell:
            "减仓"
        }
    }
}

enum TradeFeeMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case rate
    case amount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rate:
            "费率"
        case .amount:
            "金额"
        }
    }
}

struct FundTradeDraft: Equatable {
    var action: FundTradeAction
    var code: String
    var mode: PositionMode
    var amount: Double?
    var shares: Double?
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var buyFeeRate: Double? = nil
    var sellFeeMode: TradeFeeMode? = nil
    var sellFeeValue: Double? = nil
}

struct FundPendingTrade: Codable, Identifiable, Equatable {
    var id: String
    var recordID: String? = nil
    var action: FundTradeAction
    var code: String
    var mode: PositionMode
    var amount: Double?
    var shares: Double?
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var createdAt: Date
    var buyFeeRate: Double? = nil
    var sellFeeMode: TradeFeeMode? = nil
    var sellFeeValue: Double? = nil
    var syncSource: FundTradeSyncSource? = nil
    var syncKey: String? = nil
    var externalStatus: FundTradeExternalStatus? = nil
    var externalStatusText: String? = nil
    var waitsForExternalConfirmation: Bool? = nil

    var draft: FundTradeDraft {
        FundTradeDraft(
            action: action,
            code: code,
            mode: mode,
            amount: amount,
            shares: shares,
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType,
            buyFeeRate: buyFeeRate,
            sellFeeMode: sellFeeMode,
            sellFeeValue: sellFeeValue
        )
    }
}

struct FundConversionDraft: Equatable {
    var fromCode: String
    var toCode: String
    var toName: String? = nil
    var shares: Double
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var sellFeeMode: TradeFeeMode = .rate
    var sellFeeValue: Double = 0
    var buyFeeRate: Double = 0
}

struct FundPendingConversion: Codable, Identifiable, Equatable {
    var id: String
    var outRecordID: String? = nil
    var inRecordID: String? = nil
    var fromCode: String
    var toCode: String
    var toName: String?
    var shares: Double
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var acceptedDate: String
    var createdAt: Date
    var sellFeeMode: TradeFeeMode = .rate
    var sellFeeValue: Double = 0
    var buyFeeRate: Double = 0
    var failureReason: String? = nil
    var syncSource: FundTradeSyncSource? = nil
    var syncKey: String? = nil
    var externalStatus: FundTradeExternalStatus? = nil
    var externalStatusText: String? = nil
    var waitsForExternalConfirmation: Bool? = nil

    var draft: FundConversionDraft {
        FundConversionDraft(
            fromCode: fromCode,
            toCode: toCode,
            toName: toName,
            shares: shares,
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType,
            sellFeeMode: sellFeeMode,
            sellFeeValue: sellFeeValue,
            buyFeeRate: buyFeeRate
        )
    }
}

struct FundPositionDraft: Equatable {
    var code: String
    var name: String
    var positionMode: PositionMode
    var positionAmount: Double?
    var positionProfit: Double
    var shares: Double?
    var cost: Double?
    var positionDate: String
    var positionTimeType: PositionTimeType
    var memo: String
    var requiresTradeConfirmation: Bool = true

    init(
        code: String,
        name: String,
        positionMode: PositionMode,
        positionAmount: Double? = nil,
        positionProfit: Double,
        shares: Double? = nil,
        cost: Double? = nil,
        positionDate: String,
        positionTimeType: PositionTimeType,
        memo: String,
        requiresTradeConfirmation: Bool = true
    ) {
        self.code = code
        self.name = name
        self.positionMode = positionMode
        self.positionAmount = positionAmount
        self.positionProfit = positionProfit
        self.shares = shares
        self.cost = cost
        self.positionDate = positionDate
        self.positionTimeType = positionTimeType
        self.memo = memo
        self.requiresTradeConfirmation = requiresTradeConfirmation
    }
}

struct FundAmountPositionSyncUpdate: Equatable {
    var code: String
    var amount: Double
    var holdingIncome: Double?
    var syncedPendingBuyAmount: Double? = nil
    var syncedAt: Date? = nil
}

struct MigrationInfo: Codable, Equatable {
    var source: String
    var currentWalletCode: String
    var walletName: String
    var eyeStatus: Bool
}

enum FundHoldingStatus: String, Codable, Equatable {
    case holding
    case pending
    case watch

    var title: String {
        switch self {
        case .holding:
            "持有"
        case .pending:
            "待确认"
        case .watch:
            "待确认"
        }
    }

    var isPendingDisplay: Bool {
        self == .pending || self == .watch
    }
}

enum PendingFundDisplayRules {
    static func isClosedZeroPosition(
        _ fund: FundPosition,
        tradeRecords: [FundTradeRecord]
    ) -> Bool {
        let shares = fund.migratedShares ?? 0
        let principal = fund.migratedPrincipal ?? 0
        let currentAmount = fund.currentAmount ?? 0
        let pendingAmount = fund.pendingAmount ?? 0
        let hasLots = fund.lots?.isEmpty == false

        guard shares <= 0.0001,
              principal <= 0.0001,
              currentAmount <= 0.0001,
              pendingAmount <= 0.0001,
              !hasLots
        else {
            return false
        }

        return tradeRecords.contains {
            $0.code == fund.code && $0.status == .confirmed
        }
    }
}

enum FundListDisplayRules {
    static func isDisplayedHolding(
        _ fund: FundPosition,
        tradeRecords: [FundTradeRecord]
    ) -> Bool {
        fund.status == .holding
            || PendingFundDisplayRules.isClosedZeroPosition(fund, tradeRecords: tradeRecords)
    }

    static func isDisplayedPending(
        _ fund: FundPosition,
        tradeRecords: [FundTradeRecord]
    ) -> Bool {
        fund.status.isPendingDisplay
            && !PendingFundDisplayRules.isClosedZeroPosition(fund, tradeRecords: tradeRecords)
    }
}

enum PositionMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case amount
    case share

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amount:
            "按金额"
        case .share:
            "按份额"
        }
    }
}

enum PositionTimeType: String, Codable, CaseIterable, Identifiable, Equatable {
    case before15
    case after15

    var id: String { rawValue }

    var title: String {
        switch self {
        case .before15:
            "15:00前"
        case .after15:
            "15:00后"
        }
    }
}
