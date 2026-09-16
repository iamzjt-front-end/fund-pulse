import AppKit
import SwiftUI

enum FundListFilter: String, CaseIterable, Identifiable {
    case holding
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holding:
            "持仓"
        case .pending:
            "待确认"
        }
    }
}

enum FundListFilterPolicy {
    static func visibleFilters(for accountKind: PortfolioAccountKind) -> [FundListFilter] {
        switch accountKind {
        case .offExchange:
            FundListFilter.allCases
        case .onExchange:
            [.holding]
        }
    }
}

enum FundSortMode: String, CaseIterable, Identifiable {
    case todayRate
    case costAmount
    case todayIncome
    case todayTotal
    case holdingIncome
    case holdingRate
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayRate:
            "今日涨幅"
        case .costAmount:
            "持仓成本"
        case .todayIncome:
            "今日收益"
        case .todayTotal:
            "今日总值"
        case .holdingIncome:
            "持仓收益"
        case .holdingRate:
            "持仓收益率"
        case .name:
            "名称(A-Z)"
        }
    }
}

enum FundListSorter {
    static func sort(_ funds: [FundPosition], mode: FundSortMode) -> [FundPosition] {
        switch mode {
        case .todayRate:
            return sortDescending(funds) { $0.todayRate }
        case .costAmount:
            return sortDescending(funds, value: costAmount)
        case .todayIncome:
            return sortDescending(funds) { $0.todayIncome }
        case .todayTotal:
            return sortDescending(funds, value: currentTotal)
        case .holdingIncome:
            return sortDescending(funds, value: holdingIncome)
        case .holdingRate:
            return sortDescending(funds) { $0.holdingRate ?? -Double.greatestFiniteMagnitude }
        case .name:
            return funds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    static func costAmount(for fund: FundPosition) -> Double {
        if let shares = fund.migratedShares, let cost = fund.migratedCost {
            return shares * cost
        }
        return fund.migratedPrincipal ?? 0
    }

    static func holdingIncome(for fund: FundPosition) -> Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else { return 0 }
        return costAmount(for: fund) * holdingRate / 100
    }

    static func currentTotal(for fund: FundPosition) -> Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        if let shares = fund.migratedShares,
           let cost = fund.migratedCost {
            let costTotal = shares * cost
            return costTotal + holdingIncome(for: fund)
        }
        return fund.migratedPrincipal ?? 0
    }

    private static func sortDescending(
        _ funds: [FundPosition],
        value: (FundPosition) -> Double
    ) -> [FundPosition] {
        funds.sorted { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

