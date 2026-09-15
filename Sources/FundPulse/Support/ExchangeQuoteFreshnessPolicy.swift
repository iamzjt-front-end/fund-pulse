import Foundation

enum ExchangeQuoteFreshnessPolicy {
    static func acceptedQuote(incoming: FundQuote?, for fund: FundPosition) -> FundQuote? {
        let previous = fund.lastExchangeQuote.flatMap { $0.code == fund.code ? $0 : nil }
        guard let incoming, incoming.code == fund.code,
              incoming.netValue.isFinite, incoming.netValue > 0
        else { return previous }
        if let previous {
            if let timestamp = incoming.marketTimestamp,
               let previousTimestamp = previous.marketTimestamp {
                if !timestamp.isFinite || timestamp < previousTimestamp { return previous }
            } else if (incoming.marketPriceTime ?? incoming.estimateTime)
                        < (previous.marketPriceTime ?? previous.estimateTime) {
                return previous
            }
        }
        return incoming
    }
}
