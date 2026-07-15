import Foundation

struct JDFinancePerformanceDay: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { date }

    var date: String
    var incomeAmount: Double
    var incomeRate: Double?

    init(date: String, incomeAmount: Double, incomeRate: Double?) {
        self.date = date
        self.incomeAmount = incomeAmount
        self.incomeRate = incomeRate
    }
}

struct JDFinancePerformanceHistory: Codable, Equatable, Sendable {
    var days: [JDFinancePerformanceDay]
    var coveredFrom: String
    var coveredThrough: String
    var isComplete: Bool

    init(
        days: [JDFinancePerformanceDay],
        coveredFrom: String,
        coveredThrough: String,
        isComplete: Bool
    ) {
        self.days = days
        self.coveredFrom = coveredFrom
        self.coveredThrough = coveredThrough
        self.isComplete = isComplete
    }

    static let empty = JDFinancePerformanceHistory(
        days: [],
        coveredFrom: "",
        coveredThrough: "",
        isComplete: false
    )
}

struct JDFinancePerformanceHistoryRange: Equatable, Sendable {
    var from: String
    var through: String

    init(from: String, through: String) {
        self.from = from
        self.through = through
    }
}

enum JDFinancePerformanceHistoryError: LocalizedError, Equatable {
    case notLoggedIn
    case invalidDateRange
    case invalidResponse
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            "请先登录京东账号"
        case .invalidDateRange:
            "京东历史收益同步日期范围无效"
        case .invalidResponse:
            "京东历史收益接口结构变化，暂时无法解析"
        case .server(let message):
            message
        case .network(let message):
            message
        }
    }
}
