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
    var industryCode: String?
    var industryName: String?
    var positionChangeType: String?
    var positionChangeRate: Double?
    var market: String?

    init(
        code: String,
        name: String,
        weight: String,
        changeRate: Double?,
        industryCode: String? = nil,
        industryName: String? = nil,
        positionChangeType: String? = nil,
        positionChangeRate: Double? = nil,
        market: String? = nil
    ) {
        self.code = code
        self.name = name
        self.weight = weight
        self.changeRate = changeRate
        self.industryCode = industryCode
        self.industryName = industryName
        self.positionChangeType = positionChangeType
        self.positionChangeRate = positionChangeRate
        self.market = market
    }
}

struct FundSectorExposure: Identifiable, Equatable {
    enum Source: String, Equatable {
        case topHoldings
        case disclosedIndustry
    }

    var id: String { "\(source.rawValue)-\(code ?? name)" }
    var code: String?
    var name: String
    var weight: Double
    var date: String?
    var source: Source
}

struct FundAssetAllocationItem: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var weight: Double
    var date: String?
}

struct FundDetailSupplement: Equatable {
    var trend: [FundNetValuePoint]
    var history: [FundNetValuePoint]
    var topHoldings: [FundStockHolding]
    var relatedSectors: [FundSectorExposure]
    var industryAllocation: [FundSectorExposure]
    var assetAllocation: [FundAssetAllocationItem]
    var holdingDisclosureDate: String?
    var industryDisclosureDate: String?
    var assetAllocationDate: String?
    var yesterdayPoint: FundNetValuePoint?

    static let empty = FundDetailSupplement(
        trend: [],
        history: [],
        topHoldings: [],
        relatedSectors: [],
        industryAllocation: [],
        assetAllocation: [],
        holdingDisclosureDate: nil,
        industryDisclosureDate: nil,
        assetAllocationDate: nil,
        yesterdayPoint: nil
    )
}
