import Foundation

struct PortfolioListPresentation {
    var funds: [FundPosition]
    var holdingCount: Int
    var pendingActivities: [PendingTradeActivity]
    var pendingImpact: PendingHeaderImpact?
}

/// Owned by one store, invalidated by its observable snapshot revision. UI-only
/// changes reuse the derivation; filter/sort changes only reorder the small list.
@MainActor
final class PortfolioPresentationCache {
    private var revision: UInt64?
    private var holding: [FundPosition] = []
    private var pending: [FundPosition] = []
    private var activities: [PendingTradeActivity] = []
    private var impact: PendingHeaderImpact?
    private var sorted: [String: [FundPosition]] = [:]
    private(set) var buildCount = 0
    private(set) var sortCount = 0

    func value(snapshot: PortfolioSnapshot, revision: UInt64, filter: FundListFilter, sort: FundSortMode) -> PortfolioListPresentation {
        if self.revision != revision {
            let recordsByCode = Dictionary(grouping: snapshot.tradeRecords ?? [], by: \.code)
            holding = snapshot.funds.filter { FundListDisplayRules.isDisplayedHolding($0, tradeRecords: recordsByCode[$0.code] ?? []) }
            pending = snapshot.funds.filter { FundListDisplayRules.isDisplayedPending($0, tradeRecords: recordsByCode[$0.code] ?? []) }
            activities = PendingTradeActivityBuilder.make(from: snapshot)
            impact = PendingHeaderImpact.make(activities: activities)
            sorted.removeAll(keepingCapacity: true)
            self.revision = revision
            buildCount += 1
        }
        let key = filter.rawValue + "/" + sort.rawValue
        if sorted[key] == nil {
            sorted[key] = FundListSorter.sort(filter == .holding ? holding : pending, mode: sort)
            sortCount += 1
        }
        return PortfolioListPresentation(funds: sorted[key] ?? [], holdingCount: holding.count,
            pendingActivities: activities, pendingImpact: impact)
    }
}
