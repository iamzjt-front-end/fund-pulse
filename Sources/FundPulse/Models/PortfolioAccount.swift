import Foundation

enum PortfolioAccountKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case offExchange
    case onExchange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .offExchange:
            "场外"
        case .onExchange:
            "场内"
        }
    }

    var accountTitle: String {
        switch self {
        case .offExchange:
            "场外基金账户"
        case .onExchange:
            "场内基金账户"
        }
    }

    var detail: String {
        switch self {
        case .offExchange:
            "按基金净值确认，适合平台申购、赎回的基金"
        case .onExchange:
            "按交易所成交价即时记账，数据与场外持仓完全隔离"
        }
    }
}

struct PortfolioAccount: Codable, Identifiable, Equatable {
    static let defaultAccountID = "default-off-exchange"

    var id: String
    var name: String
    var kind: PortfolioAccountKind
    var createdAt: Date
    /// `nil` keeps the pre-multi-account files at the application-support root.
    /// New accounts always use a generated child-directory name.
    var directoryName: String?

    var isDefault: Bool {
        id == Self.defaultAccountID
    }

    static func defaultAccount(createdAt: Date = .now) -> PortfolioAccount {
        PortfolioAccount(
            id: defaultAccountID,
            name: "场外基金",
            kind: .offExchange,
            createdAt: createdAt,
            directoryName: nil
        )
    }
}

enum PortfolioAccountSelection: Hashable, Equatable {
    case all
    case account(String)

    var accountID: String? {
        guard case .account(let id) = self else { return nil }
        return id
    }
}

enum JDFinanceTargetResolver {
    static func resolve(
        accounts: [PortfolioAccount],
        focusedAccountID: String?,
        preferredAccountID: String?,
        boundAccountIDs: Set<String>
    ) -> PortfolioAccount? {
        let candidates = accounts.filter { $0.kind == .offExchange }
        if let preferredAccountID,
           let preferred = candidates.first(where: { $0.id == preferredAccountID }) {
            return preferred
        }
        if let focusedAccountID,
           let focused = candidates.first(where: { $0.id == focusedAccountID }) {
            return focused
        }
        if let bound = candidates.first(where: { boundAccountIDs.contains($0.id) }) {
            return bound
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

struct PortfolioAccountsSummary: Equatable {
    var totalAmount: Double
    var holdingIncome: Double
    var holdingIncomeRate: Double
    var todayIncome: Double
    var todayIncomeRate: Double
    var pendingCount: Int
    var fundCount: Int
    var accountCount: Int

    static let empty = PortfolioAccountsSummary(
        totalAmount: 0,
        holdingIncome: 0,
        holdingIncomeRate: 0,
        todayIncome: 0,
        todayIncomeRate: 0,
        pendingCount: 0,
        fundCount: 0,
        accountCount: 0
    )

    static func aggregating(_ snapshots: [PortfolioSnapshot]) -> PortfolioAccountsSummary {
        guard !snapshots.isEmpty else { return .empty }

        let totalAmount = snapshots.reduce(0) { $0 + finite($1.totalAmount) }
        let holdingIncome = snapshots.reduce(0) { $0 + finite($1.holdingIncome) }
        let todayIncome = snapshots.reduce(0) { $0 + finite($1.todayIncome) }
        let holdingPrincipal = snapshots.reduce(0) {
            $0 + max(finite($1.totalAmount) - finite($1.holdingIncome), 0)
        }
        let todayIncomeBase = snapshots.reduce(0) { $0 + inferredTodayIncomeBase(for: $1) }

        return PortfolioAccountsSummary(
            totalAmount: totalAmount,
            holdingIncome: holdingIncome,
            holdingIncomeRate: holdingPrincipal > 0 ? holdingIncome / holdingPrincipal * 100 : 0,
            todayIncome: todayIncome,
            todayIncomeRate: todayIncomeBase > 0 ? todayIncome / todayIncomeBase * 100 : 0,
            pendingCount: snapshots.reduce(0) { $0 + $1.pendingCount },
            fundCount: snapshots.reduce(0) { $0 + $1.funds.count },
            accountCount: snapshots.count
        )
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func inferredTodayIncomeBase(for snapshot: PortfolioSnapshot) -> Double {
        let income = finite(snapshot.todayIncome)
        let rate = finite(snapshot.todayIncomeRate)
        if abs(rate) > 1e-12 {
            let derivedBase = income / (rate / 100)
            if derivedBase.isFinite, derivedBase > 0 {
                return derivedBase
            }
        }
        return max(finite(snapshot.totalAmount) - income, 0)
    }

}
