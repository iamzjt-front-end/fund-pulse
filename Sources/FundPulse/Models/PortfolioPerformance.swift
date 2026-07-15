import Foundation

enum PortfolioPerformanceRecordStatus: String, Codable, Equatable, Sendable {
    case estimated
    case confirmed

    var title: String {
        switch self {
        case .estimated:
            "估值"
        case .confirmed:
            "已确认"
        }
    }
}

enum PortfolioPerformanceSource: String, Codable, Equatable, Sendable {
    case localQuote
    case jdFinance

    var title: String {
        switch self {
        case .localQuote:
            "本地记录"
        case .jdFinance:
            "京东补全"
        }
    }
}

struct PortfolioPerformanceDay: Codable, Identifiable, Equatable, Sendable {
    var id: String { date }
    var date: String
    var profit: Double
    var returnRate: Double?
    var status: PortfolioPerformanceRecordStatus
    var source: PortfolioPerformanceSource
    var sourceAccountKey: String?
    var updatedAt: Date

    init(
        date: String,
        profit: Double,
        returnRate: Double?,
        status: PortfolioPerformanceRecordStatus,
        source: PortfolioPerformanceSource = .localQuote,
        sourceAccountKey: String? = nil,
        updatedAt: Date
    ) {
        self.date = date
        self.profit = profit
        self.returnRate = returnRate
        self.status = status
        self.source = source
        self.sourceAccountKey = sourceAccountKey
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case profit
        case returnRate
        case status
        case source
        case sourceAccountKey
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        profit = try container.decode(Double.self, forKey: .profit)
        returnRate = try container.decodeIfPresent(Double.self, forKey: .returnRate)
        status = try container.decode(PortfolioPerformanceRecordStatus.self, forKey: .status)
        source = try container.decodeIfPresent(PortfolioPerformanceSource.self, forKey: .source)
            ?? .localQuote
        sourceAccountKey = try container.decodeIfPresent(String.self, forKey: .sourceAccountKey)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct JDFinancePerformanceSyncMetadata: Codable, Equatable, Sendable {
    var accountKey: String
    var coveredFrom: String
    var coveredThrough: String
    var lastSyncedAt: Date
    var isComplete: Bool
}

struct PortfolioPerformanceSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let empty = PortfolioPerformanceSnapshot()

    var schemaVersion: Int
    var trackingStartDate: String?
    var localRecordingStartDate: String?
    var days: [PortfolioPerformanceDay]
    var jdFinanceSync: JDFinancePerformanceSyncMetadata?

    init(
        schemaVersion: Int = currentSchemaVersion,
        trackingStartDate: String? = nil,
        localRecordingStartDate: String? = nil,
        days: [PortfolioPerformanceDay] = [],
        jdFinanceSync: JDFinancePerformanceSyncMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.trackingStartDate = trackingStartDate
        self.localRecordingStartDate = localRecordingStartDate
        self.days = days
        self.jdFinanceSync = jdFinanceSync
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case trackingStartDate
        case localRecordingStartDate
        case days
        case jdFinanceSync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = decodedSchemaVersion
        trackingStartDate = try container.decodeIfPresent(String.self, forKey: .trackingStartDate)
        localRecordingStartDate = try container.decodeIfPresent(String.self, forKey: .localRecordingStartDate)
        if decodedSchemaVersion < 2, localRecordingStartDate == nil {
            localRecordingStartDate = trackingStartDate
        }
        days = try container.decodeIfPresent([PortfolioPerformanceDay].self, forKey: .days) ?? []
        jdFinanceSync = try container.decodeIfPresent(
            JDFinancePerformanceSyncMetadata.self,
            forKey: .jdFinanceSync
        )
    }
}

struct PortfolioPerformancePoint: Identifiable, Equatable, Sendable {
    var id: String { day.id }
    var day: PortfolioPerformanceDay
    var cumulativeProfit: Double
}

struct PortfolioPerformanceChartScale: Equatable, Sendable {
    let minimum: Double
    let maximum: Double

    init(values: [Double]) {
        let rawMinimum = min(values.min() ?? 0, 0)
        let rawMaximum = max(values.max() ?? 0, 0)
        if rawMinimum == rawMaximum {
            minimum = -1
            maximum = 1
        } else {
            minimum = rawMinimum
            maximum = rawMaximum
        }
    }

    func normalizedY(for value: Double) -> Double {
        1 - ((value - minimum) / (maximum - minimum))
    }
}

enum PortfolioPerformanceChartTone: Equatable, Sendable {
    case positive
    case negative
    case neutral

    init(value: Double) {
        if value > 0 {
            self = .positive
        } else if value < 0 {
            self = .negative
        } else {
            self = .neutral
        }
    }
}

struct PortfolioPerformanceChartAxisLabels: Equatable, Sendable {
    var maximum: Double?
    var minimum: Double?

    init(maximum: Double?, minimum: Double?) {
        self.maximum = maximum
        self.minimum = minimum
    }

    init(values: [Double], scale: PortfolioPerformanceChartScale) {
        guard values.contains(where: { $0 != 0 }) else {
            maximum = nil
            minimum = nil
            return
        }

        maximum = scale.maximum == 0 ? nil : scale.maximum
        minimum = scale.minimum == 0 ? nil : scale.minimum
    }
}

struct PortfolioPerformanceChartSegmentPortion: Equatable, Sendable {
    var startFraction: Double
    var endFraction: Double
    var tone: PortfolioPerformanceChartTone
}

enum PortfolioPerformanceChartColor {
    static func segmentPortions(
        from startValue: Double,
        to endValue: Double
    ) -> [PortfolioPerformanceChartSegmentPortion] {
        if startValue > 0, endValue < 0 {
            let crossing = startValue / (startValue - endValue)
            return [
                .init(startFraction: 0, endFraction: crossing, tone: .positive),
                .init(startFraction: crossing, endFraction: 1, tone: .negative)
            ]
        }
        if startValue < 0, endValue > 0 {
            let crossing = startValue / (startValue - endValue)
            return [
                .init(startFraction: 0, endFraction: crossing, tone: .negative),
                .init(startFraction: crossing, endFraction: 1, tone: .positive)
            ]
        }
        if startValue == 0, endValue == 0 {
            return [.init(startFraction: 0, endFraction: 1, tone: .neutral)]
        }
        let tone: PortfolioPerformanceChartTone = startValue < 0 || endValue < 0
            ? .negative
            : .positive
        return [.init(startFraction: 0, endFraction: 1, tone: tone)]
    }
}

enum PortfolioPerformanceRange: String, CaseIterable, Identifiable, Sendable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth:
            "1月"
        case .threeMonths:
            "3月"
        case .sixMonths:
            "6月"
        case .oneYear:
            "1年"
        case .all:
            "全部"
        }
    }
}

struct PortfolioPerformanceMonthGrid: Equatable, Sendable {
    var monthKey: String
    var cells: [String?]
}

struct PortfolioPerformanceMonthSummary: Equatable, Sendable {
    var days: [PortfolioPerformanceDay]
    var totalProfit: Double
    var riseDays: Int
    var fallDays: Int
    var estimatedDays: Int
}
