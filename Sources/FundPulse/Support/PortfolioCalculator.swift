import Foundation

enum PortfolioCalculator {
    static func applyingQuotes(
        to snapshot: PortfolioSnapshot,
        quotes: [String: FundQuote],
        now: Date = .now,
        accountKind: PortfolioAccountKind = .offExchange
    ) -> PortfolioSnapshot {
        let tradeRecords = snapshot.tradeRecords ?? []
        let confirmedTradeRecordsByID = tradeRecords.reduce(
            into: [String: FundTradeRecord]()
        ) { result, record in
            guard record.status == .confirmed else { return }
            result[record.id] = record
        }
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
            let allDailyIncomeShares = sharesParticipatingInDailyIncome(lots: lots, fund: fund, now: now)
            let embeddedPendingBuyAmount = syncedPendingBuyAmount(
                for: fund,
                tradeRecords: tradeRecords,
                now: now
            )
            let dailyIncomeShares = max(
                allDailyIncomeShares - (embeddedPendingBuyAmount ?? 0) / max(netValue, 1e-12),
                0
            )
            let displayPendingBuyAmount = max(embeddedPendingBuyAmount ?? 0, 0)
            let manualDailyIncomeAmount = shouldPreserveSyncedManualAmount
                ? manualAmount.map { max($0 - displayPendingBuyAmount, 0) }
                : nil
            let holdingNetValue = confirmedHoldingNetValue(for: quote, fallback: cost)
            let confirmedHoldingIncome = calculatedConfirmedHoldingIncome(lots: lots, quote: quote, netValue: netValue) + manualProfit
            let holdingIncome = calculatedHoldingIncome(lots: lots, quote: quote, netValue: holdingNetValue) + manualProfit
            let todayIncome = quote.map { quote in
                if accountKind == .onExchange {
                    return calculatedExchangeTodayIncome(
                        lots: lots,
                        currentPrice: netValue,
                        quote: quote,
                        dailyState: dailyState,
                        tradeRecordsByID: confirmedTradeRecordsByID,
                        now: now
                    )
                }
                return calculatedTodayIncome(
                    confirmedShares: dailyIncomeShares,
                    netValue: netValue,
                    quote: quote,
                    dailyState: dailyState
                ) + calculatedManualTodayIncome(amount: manualDailyIncomeAmount, quote: quote, dailyState: dailyState)
            } ?? 0
            let todayIncomeBase = quote.map { quote in
                if accountKind == .onExchange {
                    return calculatedExchangeTodayIncomeBase(
                        lots: lots,
                        currentPrice: netValue,
                        quote: quote,
                        dailyState: dailyState,
                        tradeRecordsByID: confirmedTradeRecordsByID,
                        now: now
                    )
                }
                return calculatedTodayIncomeBase(
                    confirmedShares: dailyIncomeShares,
                    netValue: netValue,
                    quote: quote,
                    dailyState: dailyState
                ) + calculatedManualTodayIncomeBase(amount: manualDailyIncomeAmount, dailyState: dailyState)
            } ?? 0
            let holdingCostTotal = max(fundCostTotal - displayPendingBuyAmount, 0)
            let confirmedHoldingRate = holdingCostTotal > 0 ? confirmedHoldingIncome / holdingCostTotal * 100 : nil
            let holdingRate = holdingCostTotal > 0 ? holdingIncome / holdingCostTotal * 100 : nil
            let fundCurrentTotal = max(
                currentAmount(lots: lots, quote: quote, netValue: holdingNetValue) + (manualAmount ?? 0) - displayPendingBuyAmount,
                0
            )
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
            costTotal += holdingCostTotal
            currentTotal += fundCurrentTotal
            holdingIncomeTotal += holdingIncome
            todayIncomeTotal += todayIncome
            todayIncomeBaseTotal += todayIncomeBase

            if let quote {
                next.name = quote.name.isEmpty ? fund.name : quote.name
                next.dateText = shortDateText(quote: quote, fallback: fund.dateText, now: now)
                let hasDailyPosition = accountKind == .onExchange
                    ? totalShares > 0
                    : (dailyIncomeShares > 0 || (manualDailyIncomeAmount ?? 0) > 0)
                next.todayRate = dailyState.isActive && hasDailyPosition
                    ? quote.growthRate
                    : 0
                next.isUpdated = FundQuoteUpdatePolicy.isOfficiallyUpdated(quote, on: now)
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

        let reconciliation = accountKind == .onExchange ? snapshot.exchangeAccountReconciliation : nil
        let today = DateOnlyFormatter.string(from: now)
        let usesReportedBaseline = reconciliation?.date == today
        let effectiveTodayIncome = usesReportedBaseline
            ? finite(reconciliation?.reportedTodayIncome)
            : todayIncomeTotal
        let effectiveHoldingIncome = usesReportedBaseline
            ? finite(reconciliation?.reportedHoldingIncome)
            : holdingIncomeTotal
        let todayIncomeBase = accountKind == .onExchange ? currentTotal : todayIncomeBaseTotal
        let holdingIncomeBase = usesReportedBaseline
            ? max(currentTotal - effectiveHoldingIncome, 0)
            : costTotal
        let todayIncomeRate = todayIncomeBase > 0 ? effectiveTodayIncome / todayIncomeBase * 100 : 0
        let holdingIncomeRate = holdingIncomeBase > 0 ? effectiveHoldingIncome / holdingIncomeBase * 100 : 0

        return PortfolioSnapshot(
            updateTime: now,
            totalAmount: currentTotal,
            holdingIncome: effectiveHoldingIncome,
            holdingIncomeRate: holdingIncomeRate,
            todayIncome: effectiveTodayIncome,
            todayIncomeRate: todayIncomeRate,
            pendingCount: pendingCount,
            funds: funds,
            migration: snapshot.migration,
            pendingTrades: snapshot.pendingTrades,
            pendingConversions: snapshot.pendingConversions,
            tradeRecords: snapshot.tradeRecords,
            syncedAccountTotal: snapshot.syncedAccountTotal,
            jdFinanceSyncState: snapshot.jdFinanceSyncState,
            exchangeAccountReconciliation: snapshot.exchangeAccountReconciliation,
            portfolioPerformanceHistory: snapshot.portfolioPerformanceHistory
        )
    }

    private static func finite(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return value
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

    private static func sharesParticipatingInDailyIncome(lots: [FundPositionLot], fund: FundPosition, now: Date) -> Double {
        if fund.status == .holding, fund.positionMode == .amount {
            return lots.reduce(0) { $0 + $1.shares }
        }
        let today = DateOnlyFormatter.string(from: now)
        return lots.reduce(0) { total, lot in
            guard DateOnlyFormatter.parse(lot.incomeStartDate) != nil else {
                return total + lot.shares
            }
            return lot.incomeStartDate < today ? total + lot.shares : total
        }
    }

    private static func syncedPendingBuyAmount(
        for fund: FundPosition,
        tradeRecords: [FundTradeRecord],
        now: Date
    ) -> Double? {
        let today = DateOnlyFormatter.string(from: now)
        if fund.syncedPendingBuyDate == today,
           let amount = fund.syncedPendingBuyAmount,
           amount > 0 {
            return amount
        }

        let hasSameDayJDBaseline = tradeRecords.contains { record in
            record.code == fund.code
                && record.kind == .newFund
                && record.status == .confirmed
                && record.mode == .amount
                && record.tradeDate == today
                && record.syncSource == .jdFinance
                && record.isReconciliationBaseline == true
        }
        guard hasSameDayJDBaseline else { return nil }

        let amount = tradeRecords
            .filter { record in
                record.code == fund.code
                    && record.kind == .buy
                    && record.status == .pending
                    && record.mode == .amount
                    && record.tradeDate == today
                    && record.syncSource == .jdFinance
            }
            .compactMap(\.amount)
            .filter { $0 > 0 }
            .reduce(0, +)
        return amount > 0 ? amount : nil
    }

    private static func shortDateText(quote: FundQuote, fallback: String, now: Date) -> String {
        if let marketPriceTime = quote.marketPriceTime, marketPriceTime.count >= 16 {
            return String(marketPriceTime.dropFirst(5).prefix(11))
        }
        if dailyQuoteState(for: quote, now: now) == .intradayEstimate, quote.estimateTime.count >= 16 {
            return String(quote.estimateTime.dropFirst(5).prefix(11))
        }
        if quote.netValueDate.count >= 10 {
            return String(quote.netValueDate.dropFirst(5)) + " 15:00"
        }
        return fallback
    }

    private static func dailyQuoteState(for quote: FundQuote, now: Date) -> DailyQuoteState {
        guard TradingCalendar.isFundTradingDay(now) else { return .inactive }

        let today = DateOnlyFormatter.string(from: now)
        if quote.netValueDate == today {
            return .officialUpdated
        }
        if FundQuoteUpdatePolicy.hasCurrentIntradayEstimate(quote, on: now) {
            return .intradayEstimate
        }
        if FundQuoteUpdatePolicy.isDelayedQDIIOfficialUpdate(quote, on: now) {
            return .officialUpdated
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

    private static func calculatedExchangeTodayIncome(
        lots: [FundPositionLot],
        currentPrice: Double,
        quote: FundQuote,
        dailyState: DailyQuoteState,
        tradeRecordsByID: [String: FundTradeRecord],
        now: Date
    ) -> Double {
        guard dailyState.isActive,
              currentPrice > 0,
              let previousClose = exchangePreviousClose(currentPrice: currentPrice, quote: quote),
              previousClose > 0
        else {
            return 0
        }

        let today = DateOnlyFormatter.string(from: now)
        return lots.reduce(0) { total, lot in
            guard lot.positionDate <= today else { return total }
            if isSameDayExchangeBuy(
                lot,
                today: today,
                tradeRecordsByID: tradeRecordsByID
            ) {
                return total + lot.shares * currentPrice - lotPrincipal(lot)
            }
            return total + lot.shares * (currentPrice - previousClose)
        }
    }

    private static func calculatedExchangeTodayIncomeBase(
        lots: [FundPositionLot],
        currentPrice: Double,
        quote: FundQuote,
        dailyState: DailyQuoteState,
        tradeRecordsByID: [String: FundTradeRecord],
        now: Date
    ) -> Double {
        guard dailyState.isActive,
              currentPrice > 0,
              let previousClose = exchangePreviousClose(currentPrice: currentPrice, quote: quote),
              previousClose > 0
        else {
            return 0
        }

        let today = DateOnlyFormatter.string(from: now)
        return lots.reduce(0) { total, lot in
            guard lot.positionDate <= today else { return total }
            if isSameDayExchangeBuy(
                lot,
                today: today,
                tradeRecordsByID: tradeRecordsByID
            ) {
                return total + lotPrincipal(lot)
            }
            return total + lot.shares * previousClose
        }
    }

    private static func isSameDayExchangeBuy(
        _ lot: FundPositionLot,
        today: String,
        tradeRecordsByID: [String: FundTradeRecord]
    ) -> Bool {
        guard let record = tradeRecordsByID[lot.id],
              record.kind == .buy || record.kind == .conversionIn
        else {
            // Initial `.newFund` lots are imported holding baselines. Their
            // position date may be the day they were entered into the app, so
            // it must not be interpreted as an exchange execution date.
            return false
        }
        return record.tradeDate == today
    }

    private static func exchangePreviousClose(currentPrice: Double, quote: FundQuote) -> Double? {
        if let previousClose = quote.previousClose,
           previousClose.isFinite,
           previousClose > 0 {
            return previousClose
        }
        let multiplier = 1 + quote.growthRate / 100
        guard multiplier.isFinite, multiplier > 0 else { return nil }
        return currentPrice / multiplier
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

enum FundQuoteUpdatePolicy {
    static func isOfficiallyUpdated(_ quote: FundQuote, on date: Date) -> Bool {
        let today = DateOnlyFormatter.string(from: date)
        if quote.netValueDate == today {
            return true
        }
        return isDelayedQDIIOfficialUpdate(quote, on: date)
    }

    static func hasCurrentIntradayEstimate(_ quote: FundQuote, on date: Date) -> Bool {
        let today = DateOnlyFormatter.string(from: date)
        return quote.estimateTime.count >= 10 && String(quote.estimateTime.prefix(10)) == today
    }

    static func isDelayedQDIIOfficialUpdate(_ quote: FundQuote, on date: Date) -> Bool {
        guard TradingCalendar.isFundTradingDay(date),
              quote.name.range(of: "QDII", options: [.caseInsensitive, .diacriticInsensitive]) != nil,
              !hasCurrentIntradayEstimate(quote, on: date)
        else {
            return false
        }

        let today = DateOnlyFormatter.string(from: date)
        return TradingCalendar.nextFundTradingDate(after: quote.netValueDate) == today
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
