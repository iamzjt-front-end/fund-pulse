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

    private static let estimateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = chinaTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func applyingQuotes(
        to snapshot: PortfolioSnapshot,
        quotes: [String: FundQuote],
        now: Date = .now
    ) -> PortfolioSnapshot {
        var next = snapshot
        let tradingDay = tradingDayString(from: now)
        let requestTimestamp = Int64((now.timeIntervalSince1970 * 1000).rounded())

        next.funds = snapshot.funds.map { fund in
            var updatedFund = resetIfNeeded(fund, tradingDay: tradingDay)
            updatedFund = normalizeHistoryIfNeeded(updatedFund)

            guard let quote = quotes[fund.code],
                  quote.growthRate.isFinite,
                  quoteHasCurrentIntradayEstimate(quote, tradingDay: tradingDay),
                  let pointTimestamp = quoteEstimateTimestamp(quote),
                  pointTimestamp <= requestTimestamp,
                  shouldRecord(quote: quote, pointTimestamp: pointTimestamp, for: updatedFund)
            else {
                return updatedFund
            }

            var points = normalizedPoints(updatedFund.intradayRateHistory ?? [])
            let point = FundIntradayRatePoint(
                timestamp: pointTimestamp,
                rate: quote.growthRate,
                estimateTime: quote.estimateTime
            )
            points.removeAll { $0.estimateTime == point.estimateTime }
            points.append(point)
            updatedFund.intradayRateDate = tradingDay
            updatedFund.intradayRateHistory = normalizedPoints(points)
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

    private static func normalizeHistoryIfNeeded(_ fund: FundPosition) -> FundPosition {
        guard let points = fund.intradayRateHistory else { return fund }

        var next = fund
        next.intradayRateHistory = normalizedPoints(points)
        return next
    }

    private static func normalizedPoints(_ points: [FundIntradayRatePoint]) -> [FundIntradayRatePoint] {
        var latestByKey: [String: FundIntradayRatePoint] = [:]
        var keys: [String] = []

        for point in points {
            let key = point.estimateTime.isEmpty ? "timestamp:\(point.timestamp)" : "estimate:\(point.estimateTime)"
            if latestByKey[key] == nil {
                keys.append(key)
            }
            latestByKey[key] = point
        }

        return keys
            .compactMap { latestByKey[$0] }
            .sorted { lhs, rhs in
                let lhsTimestamp = recordedEstimateTimestamp(lhs) ?? lhs.timestamp
                let rhsTimestamp = recordedEstimateTimestamp(rhs) ?? rhs.timestamp
                if lhsTimestamp == rhsTimestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhsTimestamp < rhsTimestamp
            }
    }

    private static func quoteHasCurrentIntradayEstimate(_ quote: FundQuote, tradingDay: String) -> Bool {
        quote.estimateTime.count >= 10 && String(quote.estimateTime.prefix(10)) == tradingDay
    }

    private static func quoteEstimateTimestamp(_ quote: FundQuote) -> Int64? {
        guard let date = estimateTimeFormatter.date(from: quote.estimateTime) else {
            return nil
        }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func shouldRecord(
        quote: FundQuote,
        pointTimestamp: Int64,
        for fund: FundPosition
    ) -> Bool {
        let points = fund.intradayRateHistory ?? []
        if points.contains(where: { $0.estimateTime == quote.estimateTime }) {
            return true
        }

        guard let latestRecordedEstimateTimestamp = points.compactMap(recordedEstimateTimestamp).max() else {
            return true
        }
        return pointTimestamp > latestRecordedEstimateTimestamp
    }

    private static func recordedEstimateTimestamp(_ point: FundIntradayRatePoint) -> Int64? {
        if let date = estimateTimeFormatter.date(from: point.estimateTime) {
            return Int64((date.timeIntervalSince1970 * 1000).rounded())
        }
        return point.timestamp
    }
}
