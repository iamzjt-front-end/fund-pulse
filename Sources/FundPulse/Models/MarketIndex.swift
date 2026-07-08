import Foundation

enum MarketIndexID: String, Codable, CaseIterable, Identifiable, Equatable {
    case shanghaiComposite
    case shenzhenComponent
    case chinext
    case csi300
    case sciTech50
    case shanghaiTotalReturn
    case shanghai50
    case csi500
    case beijing50
    case hangSengIndex
    case nikkei225
    case dowJones
    case nasdaq
    case sp500

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shanghaiComposite:
            "上证指数"
        case .shenzhenComponent:
            "深证成指"
        case .chinext:
            "创业板指"
        case .csi300:
            "沪深300"
        case .sciTech50:
            "科创50"
        case .shanghaiTotalReturn:
            "上证收益"
        case .shanghai50:
            "上证50"
        case .csi500:
            "中证500"
        case .beijing50:
            "北证50"
        case .hangSengIndex:
            "恒生指数"
        case .nikkei225:
            "日经225"
        case .dowJones:
            "道琼斯指数"
        case .nasdaq:
            "纳斯达克"
        case .sp500:
            "标普500"
        }
    }

    var eastmoneySecID: String {
        switch self {
        case .shanghaiComposite:
            "1.000001"
        case .shenzhenComponent:
            "0.399001"
        case .chinext:
            "0.399006"
        case .csi300:
            "1.000300"
        case .sciTech50:
            "1.000688"
        case .shanghaiTotalReturn:
            "1.000888"
        case .shanghai50:
            "1.000016"
        case .csi500:
            "1.000905"
        case .beijing50:
            "0.899050"
        case .hangSengIndex:
            "100.HSI"
        case .nikkei225:
            "100.N225"
        case .dowJones:
            "100.DJIA"
        case .nasdaq:
            "100.NDX"
        case .sp500:
            "100.SPX"
        }
    }

    var eastmoneyQuoteCode: String {
        eastmoneySecID.split(separator: ".").last.map(String.init) ?? eastmoneySecID
    }
}

struct MarketIndexQuote: Codable, Equatable, Identifiable {
    var id: MarketIndexID
    var name: String
    var value: Double
    var change: Double
    var changeRate: Double
    var updateTime: Date

    init(
        id: MarketIndexID,
        name: String,
        value: Double,
        change: Double,
        changeRate: Double,
        updateTime: Date = .now
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.change = change
        self.changeRate = changeRate
        self.updateTime = updateTime
    }
}

struct MarketBreadth: Codable, Equatable {
    var risingCount: Int
    var fallingCount: Int
    var distribution: [Int]
    var limitUpCount: Int?
    var limitDownCount: Int?
    var updateTime: Date

    init(
        risingCount: Int,
        fallingCount: Int,
        distribution: [Int] = [],
        limitUpCount: Int? = nil,
        limitDownCount: Int? = nil,
        updateTime: Date = .now
    ) {
        self.risingCount = risingCount
        self.fallingCount = fallingCount
        self.distribution = distribution
        self.limitUpCount = limitUpCount
        self.limitDownCount = limitDownCount
        self.updateTime = updateTime
    }

    var activeCount: Int {
        risingCount + fallingCount
    }

    var hasData: Bool {
        risingCount > 0 || fallingCount > 0
    }
}
