import Foundation

enum OffExchangeQuoteFreshnessPolicy {
    static func acceptedQuote(incoming: FundQuote?, for fund: FundPosition) -> FundQuote? {
        let previous = fund.lastOffExchangeQuote.flatMap { valid($0, code: fund.code) ? $0 : nil }
            ?? legacyValuation(for: fund)
        guard let incoming, valid(incoming, code: fund.code) else { return previous }
        guard let previous else { return incoming }
        // NAV and estimates have independent clocks. Keep the newest official
        // price while allowing a newer intraday estimate to advance separately.
        var result = incoming
        if previous.officialNetValue != nil,
           incoming.officialNetValue == nil || incoming.netValueDate < previous.netValueDate {
            result.netValue = previous.netValue
            result.netValueDate = previous.netValueDate
            result.hasOfficialNetValue = previous.hasOfficialNetValue
        }
        if incoming.estimateTime < previous.estimateTime && incoming.netValueDate <= previous.netValueDate {
            result.estimatedNetValue = previous.estimatedNetValue
            result.estimateTime = previous.estimateTime
            result.growthRate = previous.growthRate
        }
        return result
    }

    private static func valid(_ quote: FundQuote, code: String) -> Bool {
        quote.code == code && quote.netValue.isFinite && quote.netValue > 0
            && quote.estimatedNetValue.isFinite && quote.growthRate.isFinite
    }

    private static func legacyValuation(for fund: FundPosition) -> FundQuote? {
        // Old snapshots did not store quotes. Preserve their valuation without
        // inventing an official NAV date or permitting trade confirmation.
        guard let amount = fund.currentAmount, amount.isFinite, amount > 0,
              let shares = fund.migratedShares, shares.isFinite, shares > 0 else { return nil }
        let price = amount / shares
        guard price.isFinite, price > 0 else { return nil }
        return FundQuote(code: fund.code, name: fund.name, netValue: price,
            estimatedNetValue: price, growthRate: 0, estimateTime: "", netValueDate: "", hasOfficialNetValue: false)
    }
}
