import Foundation

struct FundQuote: Codable, Equatable {
    var code: String
    var name: String
    var netValue: Double
    var estimatedNetValue: Double
    var growthRate: Double
    var estimateTime: String
    var netValueDate: String
}

struct FundNetValuePoint: Identifiable, Equatable {
    var id: Int64 { timestamp }
    var timestamp: Int64
    var value: Double
    var equityReturn: Double?
}

struct FundStockHolding: Identifiable, Equatable {
    var id: String { code.isEmpty ? name : code }
    var code: String
    var name: String
    var weight: String
    var changeRate: Double?
}

struct FundDetailSupplement: Equatable {
    var trend: [FundNetValuePoint]
    var history: [FundNetValuePoint]
    var topHoldings: [FundStockHolding]
    var yesterdayPoint: FundNetValuePoint?

    static let empty = FundDetailSupplement(
        trend: [],
        history: [],
        topHoldings: [],
        yesterdayPoint: nil
    )
}
