import Foundation

enum PortfolioCalculator {
    static func applyingQuotes(
        to snapshot: PortfolioSnapshot,
        quotes: [String: FundQuote],
        now: Date = .now
    ) -> PortfolioSnapshot {
        let tradeRecords = snapshot.tradeRecords ?? []
        var costTotal = 0.0
        var currentTotal = 0.0
        var todayIncomeTotal = 0.0
        var todayIncomeBaseTotal = 0.0
        var holdingIncomeTotal = 0.0
        var pendingCount = (snapshot.pendingTrades?.count ?? 0) + (snapshot.pendingConversions?.count ?? 0)
        let pendingConversionTargetCodes = Set(snapshot.pendingConversions?.map(\.toCode) ?? [])

        let funds = snapshot.funds.map { fund in
            var next = fund
            let quote = quotes[fund.code]
            let shouldPreserveSyncedManualAmount = preservesSyncedManualAmount(for: fund)
            let storedLots = effectiveLots(for: fund)
            var lots = shouldPreserveSyncedManualAmount ? [] : storedLots
            if lots.isEmpty,
               !shouldPreserveSyncedManualAmount,
               let amount = manualHoldingAmount(for: fund),
               let referenceNetValue = quoteNetValue(quote),
               let backfilledLot = amountPositionLot(
                    code: fund.code,
                    amount: amount,
                    profit: fund.pendingProfit ?? 0,
                    referenceNetValue: referenceNetValue,
                    fund: fund
               ) {
                lots = [backfilledLot]
                next.lots = lots
                next.pendingAmount = nil
                next.pendingProfit = nil
            }
            let displayLots = shouldPreserveSyncedManualAmount ? storedLots : lots
            let totalShares = lots.reduce(0) { $0 + $1.shares }
            let lotCostTotal = lots.reduce(0) { $0 + lotPrincipal($1) }
            let displayShares = displayLots.reduce(0) { $0 + $1.shares }
            let displayCostTotal = displayLots.reduce(0) { $0 + lotPrincipal($1) }
            let displayCost = displayShares > 0
                ? displayCostTotal / displayShares
                : fund.migratedCost
            let manualAmount = shouldPreserveSyncedManualAmount ? manualHoldingAmount(for: fund) : (lots.isEmpty ? manualHoldingAmount(for: fund) : nil)
            let manualProfit = manualAmount == nil ? 0 : (fund.pendingProfit ?? 0)
            let manualPrincipal = manualAmount.map { max($0 - manualProfit, 0) } ?? 0
            let fundCostTotal = lotCostTotal + manualPrincipal
            let cost = totalShares > 0 ? lotCostTotal / totalShares : (fund.migratedCost ?? 0)
            let hasManualHolding = manualPrincipal > 0 || (manualAmount ?? 0) > 0
            let status = effectiveStatus(totalShares: totalShares, hasManualHolding: hasManualHolding)
            let netValue = quote?.netValue ?? cost
            let dailyState = quote.map { dailyQuoteState(for: $0, now: now) } ?? .inactive
            let dailyIncomeShares = sharesParticipatingInDailyIncome(lots: lots, now: now)
            let manualDailyIncomeAmount = shouldPreserveSyncedManualAmount ? manualAmount : nil
            let holdingNetValue = confirmedHoldingNetValue(for: quote, fallback: cost)
            let confirmedHoldingIncome = calculatedConfirmedHoldingIncome(lots: lots, quote: quote, netValue: netValue) + manualProfit
            let holdingIncome = calculatedHoldingIncome(lots: lots, quote: quote, netValue: holdingNetValue) + manualProfit
            let todayIncome = quote.map {
                calculatedTodayIncome(confirmedShares: dailyIncomeShares, netValue: netValue, quote: $0, dailyState: dailyState)
                    + calculatedManualTodayIncome(amount: manualDailyIncomeAmount, quote: $0, dailyState: dailyState)
            } ?? 0
            let todayIncomeBase = quote.map {
                calculatedTodayIncomeBase(confirmedShares: dailyIncomeShares, netValue: netValue, quote: $0, dailyState: dailyState)
                    + calculatedManualTodayIncomeBase(amount: manualDailyIncomeAmount, dailyState: dailyState)
            } ?? 0
            let confirmedHoldingRate = fundCostTotal > 0 ? confirmedHoldingIncome / fundCostTotal * 100 : nil
            let holdingRate = fundCostTotal > 0 ? holdingIncome / fundCostTotal * 100 : nil
            let fundCurrentTotal = currentAmount(lots: lots, quote: quote, netValue: holdingNetValue) + (manualAmount ?? 0)
            let isIncomeActive = totalShares > 0 || hasManualHolding

            let isConversionPlaceholder = pendingConversionTargetCodes.contains(fund.code)
                && totalShares == 0
                && manualPrincipal == 0
                && fund.pendingAmount == nil
            let isClosedZeroPosition = PendingFundDisplayRules.isClosedZeroPosition(
                next,
                tradeRecords: tradeRecords
            )
            if status == .pending && !isConversionPlaceholder && !isClosedZeroPosition {
                pendingCount += 1
            }
            costTotal += fundCostTotal
            currentTotal += fundCurrentTotal
            holdingIncomeTotal += holdingIncome
            todayIncomeTotal += todayIncome
            todayIncomeBaseTotal += todayIncomeBase

            if let quote {
                next.name = quote.name.isEmpty ? fund.name : quote.name
                next.dateText = shortDateText(quote: quote, fallback: fund.dateText, now: now)
                next.todayRate = dailyState.isActive && (dailyIncomeShares > 0 || (manualDailyIncomeAmount ?? 0) > 0)
                    ? quote.growthRate
                    : 0
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
            next.migratedShares = displayShares > 0 ? displayShares : totalShares
            next.migratedCost = displayShares > 0 ? displayCost : (totalShares > 0 ? cost : fund.migratedCost)
            next.migratedPrincipal = fundCostTotal
            return next
        }

        let todayIncomeRate = todayIncomeBaseTotal > 0 ? todayIncomeTotal / todayIncomeBaseTotal * 100 : 0
        let holdingIncomeRate = costTotal > 0 ? holdingIncomeTotal / costTotal * 100 : 0

        return PortfolioSnapshot(
            updateTime: now,
            totalAmount: snapshot.syncedAccountTotal?.amount ?? currentTotal,
            holdingIncome: holdingIncomeTotal,
            holdingIncomeRate: holdingIncomeRate,
            todayIncome: todayIncomeTotal,
            todayIncomeRate: todayIncomeRate,
            pendingCount: pendingCount,
            funds: funds,
            migration: snapshot.migration,
            pendingTrades: snapshot.pendingTrades,
            pendingConversions: snapshot.pendingConversions,
            tradeRecords: snapshot.tradeRecords,
            syncedAccountTotal: snapshot.syncedAccountTotal
        )
    }

    private static func effectiveStatus(totalShares: Double, hasManualHolding: Bool = false) -> FundHoldingStatus {
        totalShares > 0 || hasManualHolding ? .holding : .pending
    }

    private static func manualHoldingAmount(for fund: FundPosition) -> Double? {
        guard fund.positionMode == .amount,
              !fund.status.isPendingDisplay,
              let amount = fund.pendingAmount,
              amount > 0
        else {
            return nil
        }
        return amount
    }

    private static func preservesSyncedManualAmount(for fund: FundPosition) -> Bool {
        guard fund.positionMode == .amount,
              let pendingAmount = fund.pendingAmount,
              pendingAmount > 0,
              fund.memo?.contains("京东金融同步") == true
        else {
            return false
        }
        return true
    }

    private static func effectiveLots(for fund: FundPosition) -> [FundPositionLot] {
        if let lots = fund.lots {
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

    private static func amountPositionLot(
        code: String,
        amount: Double,
        profit: Double,
        referenceNetValue: Double,
        fund: FundPosition
    ) -> FundPositionLot? {
        guard amount > 0, referenceNetValue > 0 else { return nil }
        let principal = amount - profit
        guard principal > 0 else { return nil }
        let shares = rounded(amount / referenceNetValue, places: PortfolioPrecision.storedSharePlaces)
        guard shares > 0 else { return nil }
        let cost = rounded(principal / shares, places: PortfolioPrecision.costPlaces)
        guard cost > 0 else { return nil }
        return FundPositionLot(
            id: "\(code)-amount-backfill",
            shares: shares,
            cost: cost,
            principal: principal,
            incomeStartDate: fund.incomeStartDate ?? fund.positionDate ?? "",
            positionDate: fund.positionDate ?? "",
            positionTimeType: fund.positionTimeType ?? .before15
        )
    }

    private static func sharesParticipatingInDailyIncome(lots: [FundPositionLot], now: Date) -> Double {
        let today = DateOnlyFormatter.string(from: now)
        return lots.reduce(0) { total, lot in
            guard DateOnlyFormatter.parse(lot.incomeStartDate) != nil else {
                return total + lot.shares
            }
            return lot.incomeStartDate < today ? total + lot.shares : total
        }
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

    private static func calculatedTodayIncomeBase(
        confirmedShares: Double,
        netValue: Double,
        quote: FundQuote,
        dailyState: DailyQuoteState
    ) -> Double {
        guard confirmedShares > 0 else { return 0 }
        switch dailyState {
        case .intradayEstimate:
            guard netValue > 0 else { return 0 }
            return confirmedShares * netValue
        case .officialUpdated:
            let multiplier = 1 + quote.growthRate / 100
            guard multiplier != 0 else { return 0 }
            let previousNetValue = netValue / multiplier
            guard previousNetValue > 0 else { return 0 }
            return confirmedShares * previousNetValue
        case .inactive:
            return 0
        }
    }

    private static func calculatedManualTodayIncome(
        amount: Double?,
        quote: FundQuote,
        dailyState: DailyQuoteState
    ) -> Double {
        guard dailyState.isActive,
              let amount,
              amount > 0
        else {
            return 0
        }
        return amount * quote.growthRate / 100
    }

    private static func calculatedManualTodayIncomeBase(
        amount: Double?,
        dailyState: DailyQuoteState
    ) -> Double {
        guard dailyState.isActive,
              let amount,
              amount > 0
        else {
            return 0
        }
        return amount
    }

    private static func calculatedConfirmedHoldingIncome(
        lots: [FundPositionLot],
        quote: FundQuote?,
        netValue: Double
    ) -> Double {
        guard quote != nil else { return 0 }
        return lots.reduce(0) { $0 + $1.shares * netValue - lotPrincipal($1) }
    }

    private static func calculatedHoldingIncome(
        lots: [FundPositionLot],
        quote: FundQuote?,
        netValue: Double
    ) -> Double {
        guard quote != nil else { return 0 }
        return lots.reduce(0) { $0 + $1.shares * netValue - lotPrincipal($1) }
    }

    private static func confirmedHoldingNetValue(for quote: FundQuote?, fallback: Double) -> Double {
        guard let quote, quote.netValue > 0 else {
            return fallback
        }
        return quote.netValue
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

    private static func quoteNetValue(_ quote: FundQuote?) -> Double? {
        guard let quote else { return nil }
        if quote.netValue > 0 { return quote.netValue }
        if quote.estimatedNetValue > 0 { return quote.estimatedNetValue }
        return nil
    }

    private static func lotPrincipal(_ lot: FundPositionLot) -> Double {
        lot.principal ?? (lot.shares * lot.cost)
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
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
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
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
