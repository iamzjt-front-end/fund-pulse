import Foundation

enum PortfolioCalculator {
    static func applyingQuotes(
        to snapshot: PortfolioSnapshot,
        quotes: [String: FundQuote],
        now: Date = .now
    ) -> PortfolioSnapshot {
        var costTotal = 0.0
        var currentTotal = 0.0
        var todayIncomeTotal = 0.0
        var holdingIncomeTotal = 0.0
        var pendingCount = snapshot.pendingTrades?.count ?? 0

        let funds = snapshot.funds.map { fund in
            var next = fund
            let lots = effectiveLots(for: fund)
            let quote = quotes[fund.code]
            let totalShares = lots.reduce(0) { $0 + $1.shares }
            let fundCostTotal = lots.reduce(0) { $0 + $1.shares * $1.cost }
            let cost = totalShares > 0 ? fundCostTotal / totalShares : (fund.migratedCost ?? 0)
            let status = effectiveStatus(totalShares: totalShares)
            let netValue = quote?.netValue ?? cost
            let dailyState = quote.map { dailyQuoteState(for: $0, now: now) } ?? .inactive
            let confirmedHoldingIncome = calculatedConfirmedHoldingIncome(lots: lots, quote: quote, netValue: netValue)
            let holdingIncome = confirmedHoldingIncome
            let todayIncome = quote.map {
                calculatedTodayIncome(confirmedShares: totalShares, netValue: netValue, quote: $0, dailyState: dailyState)
            } ?? 0
            let confirmedHoldingRate = fundCostTotal > 0 ? confirmedHoldingIncome / fundCostTotal * 100 : nil
            let holdingRate = fundCostTotal > 0 ? holdingIncome / fundCostTotal * 100 : nil
            let fundCurrentTotal = currentAmount(lots: lots, quote: quote, netValue: netValue)
            let isIncomeActive = totalShares > 0

            if status == .pending {
                pendingCount += 1
            }
            costTotal += fundCostTotal
            currentTotal += fundCurrentTotal
            holdingIncomeTotal += holdingIncome
            todayIncomeTotal += todayIncome

            if let quote {
                next.name = quote.name.isEmpty ? fund.name : quote.name
                next.dateText = shortDateText(quote: quote, fallback: fund.dateText, now: now)
                next.todayRate = dailyState.isActive && isIncomeActive ? quote.growthRate : 0
                next.isUpdated = isQuoteUpdated(quote, now: now)
            }
            next.status = status
            next.isIncomeActive = isIncomeActive
            next.todayIncome = todayIncome
            next.holdingIncome = holdingIncome
            next.holdingRate = holdingRate
            next.confirmedHoldingIncome = confirmedHoldingIncome
            next.confirmedHoldingRate = confirmedHoldingRate
            next.currentAmount = fundCurrentTotal
            next.migratedShares = totalShares
            next.migratedCost = totalShares > 0 ? cost : fund.migratedCost
            next.migratedPrincipal = fundCostTotal
            return next
        }

        let todayIncomeRate = currentTotal > 0 ? todayIncomeTotal / currentTotal * 100 : 0
        let holdingIncomeRate = costTotal > 0 ? holdingIncomeTotal / costTotal * 100 : 0

        return PortfolioSnapshot(
            updateTime: now,
            totalAmount: currentTotal,
            holdingIncome: holdingIncomeTotal,
            holdingIncomeRate: holdingIncomeRate,
            todayIncome: todayIncomeTotal,
            todayIncomeRate: todayIncomeRate,
            pendingCount: pendingCount,
            funds: funds,
            migration: snapshot.migration,
            pendingTrades: snapshot.pendingTrades,
            tradeRecords: snapshot.tradeRecords
        )
    }

    private static func effectiveStatus(totalShares: Double) -> FundHoldingStatus {
        totalShares > 0 ? .holding : .pending
    }

    private static func effectiveLots(for fund: FundPosition) -> [FundPositionLot] {
        if let lots = fund.lots, !lots.isEmpty {
            return lots
        }
        guard let shares = fund.migratedShares,
              let cost = fund.migratedCost,
              shares > 0,
              cost > 0
        else {
            return []
        }
        return [
            FundPositionLot(
                id: "\(fund.code)-legacy",
                shares: shares,
                cost: cost,
                incomeStartDate: fund.incomeStartDate ?? "",
                positionDate: fund.positionDate ?? "",
                positionTimeType: fund.positionTimeType ?? .before15
            )
        ]
    }

    private static func shortDateText(quote: FundQuote, fallback: String, now: Date) -> String {
        if dailyQuoteState(for: quote, now: now) == .intradayEstimate, quote.estimateTime.count >= 16 {
            return String(quote.estimateTime.dropFirst(5).prefix(11))
        }
        if quote.netValueDate.count >= 10 {
            return String(quote.netValueDate.dropFirst(5)) + " 15:00"
        }
        return fallback
    }

    private static func isQuoteUpdated(_ quote: FundQuote, now: Date) -> Bool {
        guard let date = DateOnlyFormatter.parse(quote.netValueDate) else {
            return false
        }
        return Calendar.current.isDate(date, inSameDayAs: now)
    }

    private static func dailyQuoteState(for quote: FundQuote, now: Date) -> DailyQuoteState {
        guard TradingCalendar.isFundTradingDay(now) else { return .inactive }

        let today = DateOnlyFormatter.string(from: now)
        if quote.netValueDate == today {
            return .officialUpdated
        }
        if quote.estimateTime.count >= 10, String(quote.estimateTime.prefix(10)) == today {
            return .intradayEstimate
        }
        return .inactive
    }

    private static func calculatedTodayIncome(
        confirmedShares: Double,
        netValue: Double,
        quote: FundQuote,
        dailyState: DailyQuoteState
    ) -> Double {
        switch dailyState {
        case .intradayEstimate:
            return confirmedShares * (quote.estimatedNetValue - netValue)
        case .officialUpdated:
            let denominator = 100 + quote.growthRate
            guard denominator != 0 else { return 0 }
            return confirmedShares * netValue * quote.growthRate / denominator
        case .inactive:
            return 0
        }
    }

    private static func calculatedConfirmedHoldingIncome(
        lots: [FundPositionLot],
        quote: FundQuote?,
        netValue: Double
    ) -> Double {
        guard quote != nil else { return 0 }
        return lots.reduce(0) { $0 + $1.shares * (netValue - $1.cost) }
    }

    private static func currentAmount(
        lots: [FundPositionLot],
        quote: FundQuote?,
        netValue: Double
    ) -> Double {
        guard quote != nil else {
            return lots.reduce(0) { $0 + $1.shares * $1.cost }
        }
        return lots.reduce(0) { $0 + $1.shares * netValue }
    }
}

private enum DailyQuoteState {
    case inactive
    case intradayEstimate
    case officialUpdated

    var isActive: Bool {
        self != .inactive
    }
}

enum DateOnlyFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        formatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
