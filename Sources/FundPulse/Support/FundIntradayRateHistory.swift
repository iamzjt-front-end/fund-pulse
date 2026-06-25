import Foundation

enum FundIntradayRateHistoryRecorder {
    private static let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = chinaTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func applyingQuotes(
        to snapshot: PortfolioSnapshot,
        quotes: [String: FundQuote],
        now: Date = .now
    ) -> PortfolioSnapshot {
        var next = snapshot
        let tradingDay = tradingDayString(from: now)
        let isMarketOpen = TradingCalendar.marketSessionState(now: now) == .open
        let requestTimestamp = Int64((now.timeIntervalSince1970 * 1000).rounded())

        next.funds = snapshot.funds.map { fund in
            var updatedFund = resetIfNeeded(fund, tradingDay: tradingDay)

            guard isMarketOpen,
                  let quote = quotes[fund.code],
                  quote.growthRate.isFinite,
                  quoteHasCurrentIntradayEstimate(quote, tradingDay: tradingDay)
            else {
                return updatedFund
            }

            var points = updatedFund.intradayRateHistory ?? []
            points.append(
                FundIntradayRatePoint(
                    timestamp: requestTimestamp,
                    rate: quote.growthRate,
                    estimateTime: quote.estimateTime
                )
            )
            updatedFund.intradayRateDate = tradingDay
            updatedFund.intradayRateHistory = points
            return updatedFund
        }

        return next
    }

    static func activePoints(for fund: FundPosition, now: Date = .now) -> [FundIntradayRatePoint] {
        guard fund.intradayRateDate == tradingDayString(from: now) else {
            return []
        }
        return (fund.intradayRateHistory ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    static func tradingDayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func resetIfNeeded(_ fund: FundPosition, tradingDay: String) -> FundPosition {
        guard fund.intradayRateDate != tradingDay else { return fund }

        var next = fund
        next.intradayRateDate = tradingDay
        next.intradayRateHistory = nil
        return next
    }

    private static func quoteHasCurrentIntradayEstimate(_ quote: FundQuote, tradingDay: String) -> Bool {
        quote.estimateTime.count >= 10 && String(quote.estimateTime.prefix(10)) == tradingDay
    }
}
