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
    var tradeRecords: [FundTradeRecord]? = nil

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

    static let sample = PortfolioSnapshot(
        updateTime: .now,
        totalAmount: 19_579.27,
        holdingIncome: -420.74,
        holdingIncomeRate: -2.10,
        todayIncome: 86.65,
        todayIncomeRate: 0.44,
        pendingCount: 3,
        funds: [
            FundPosition(
                code: "588760",
                name: "科创人工智能ETF广发",
                dateText: "06-18 15:00",
                todayIncome: 0,
                todayRate: 4.21,
                holdingRate: nil,
                status: .pending,
                isUpdated: false
            ),
            FundPosition(
                code: "026210",
                name: "平安科技精选混合发起式A",
                dateText: "06-18 15:00",
                todayIncome: 57.24,
                todayRate: 2.80,
                holdingRate: 5.07,
                status: .holding,
                isUpdated: true
            ),
            FundPosition(
                code: "018926",
                name: "南方中证电池ETF联接A",
                dateText: "06-18 15:00",
                todayIncome: -33.20,
                todayRate: -1.01,
                holdingRate: -6.88,
                status: .holding,
                isUpdated: true
            )
        ],
        migration: nil
    )
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

    var title: String {
        switch self {
        case .newFund:
            "新增基金"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
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
    var zdfRange: Double?
    var jzNotice: Double?
    var memo: String
    var requiresTradeConfirmation: Bool = true
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
