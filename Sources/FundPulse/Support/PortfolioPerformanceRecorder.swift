import Foundation

enum PortfolioPerformanceRecorder {
    struct Candidate: Equatable, Sendable {
        var date: String
        var profit: Double
        var returnRate: Double
        var status: PortfolioPerformanceRecordStatus
        var updatedAt: Date
    }

    /// Returns `true` when every active holding has an official NAV for the
    /// current Shanghai date, `false` when every holding has at least a current
    /// estimate, and `nil` when the quote set is stale or incomplete.
    static func quoteConfirmationState(
        portfolio: PortfolioSnapshot,
        quotes: [String: FundQuote],
        now: Date
    ) -> Bool? {
        let activeCodes = portfolio.funds
            .filter { ($0.isIncomeActive ?? false) && !$0.status.isPendingDisplay }
            .map(\.code)
        guard !activeCodes.isEmpty else { return nil }

        let today = DateOnlyFormatter.string(from: now)
        var allConfirmed = true
        for code in activeCodes {
            guard let quote = quotes[code] else { return nil }
            let isConfirmed = quote.netValueDate == today
            let isEstimated = quote.estimateTime.hasPrefix(today)
            guard isConfirmed || isEstimated else { return nil }
            allConfirmed = allConfirmed && isConfirmed
        }
        return allConfirmed
    }

    static func candidate(
        from portfolio: PortfolioSnapshot,
        now: Date,
        allQuotesConfirmed: Bool
    ) -> Candidate? {
        guard !portfolio.funds.isEmpty,
              portfolio.todayIncome.isFinite,
              portfolio.todayIncomeRate.isFinite
        else {
            return nil
        }

        return Candidate(
            date: DateOnlyFormatter.string(from: now),
            profit: portfolio.todayIncome,
            returnRate: portfolio.todayIncomeRate,
            status: allQuotesConfirmed ? .confirmed : .estimated,
            updatedAt: now
        )
    }

    static func recording(
        _ candidate: Candidate,
        in snapshot: PortfolioPerformanceSnapshot
    ) -> PortfolioPerformanceSnapshot {
        guard DateOnlyFormatter.parse(candidate.date) != nil,
              candidate.profit.isFinite,
              candidate.returnRate.isFinite
        else {
            return normalized(snapshot)
        }

        var next = normalized(snapshot)
        let day = PortfolioPerformanceDay(
            date: candidate.date,
            profit: candidate.profit,
            returnRate: candidate.returnRate,
            status: candidate.status,
            source: .localQuote,
            updatedAt: candidate.updatedAt
        )

        if let index = next.days.firstIndex(where: { $0.date == candidate.date }) {
            guard shouldReplace(existing: next.days[index], with: day) else {
                return next
            }
            next.days[index] = day
        } else {
            next.days.append(day)
        }

        next.days.sort { $0.date < $1.date }
        if let firstDate = next.days.first?.date {
            next.trackingStartDate = min(next.trackingStartDate ?? firstDate, firstDate)
        }
        next.localRecordingStartDate = min(
            next.localRecordingStartDate ?? candidate.date,
            candidate.date
        )
        return next
    }

    static func normalized(
        _ snapshot: PortfolioPerformanceSnapshot
    ) -> PortfolioPerformanceSnapshot {
        var selected: [String: PortfolioPerformanceDay] = [:]
        selected.reserveCapacity(snapshot.days.count)

        for day in snapshot.days where DateOnlyFormatter.parse(day.date) != nil
            && day.profit.isFinite
            && (day.returnRate?.isFinite ?? true)
        {
            if let existing = selected[day.date] {
                if shouldReplace(existing: existing, with: day) {
                    selected[day.date] = day
                }
            } else {
                selected[day.date] = day
            }
        }

        let days = selected.values.sorted { $0.date < $1.date }
        let firstDate = days.first?.date
        let validTrackingStart = snapshot.trackingStartDate.flatMap { value in
            DateOnlyFormatter.parse(value) == nil ? nil : value
        }
        let trackingStartDate: String?
        if let firstDate {
            trackingStartDate = min(validTrackingStart ?? firstDate, firstDate)
        } else {
            trackingStartDate = nil
        }

        let firstLocalDate = days.first(where: { $0.source == .localQuote })?.date
        let validLocalRecordingStart = snapshot.localRecordingStartDate.flatMap { value in
            DateOnlyFormatter.parse(value) == nil ? nil : value
        }
        let localRecordingStartDate: String?
        if let firstLocalDate {
            localRecordingStartDate = min(validLocalRecordingStart ?? firstLocalDate, firstLocalDate)
        } else {
            localRecordingStartDate = validLocalRecordingStart
        }

        return PortfolioPerformanceSnapshot(
            schemaVersion: PortfolioPerformanceSnapshot.currentSchemaVersion,
            trackingStartDate: trackingStartDate,
            localRecordingStartDate: localRecordingStartDate,
            days: days,
            jdFinanceSync: snapshot.jdFinanceSync
        )
    }

    private static func shouldReplace(
        existing: PortfolioPerformanceDay,
        with candidate: PortfolioPerformanceDay
    ) -> Bool {
        if existing.source == .jdFinance,
           existing.status == .confirmed,
           candidate.source == .localQuote {
            return false
        }
        if existing.status == .confirmed, candidate.status == .estimated {
            return false
        }
        if existing.status == .estimated, candidate.status == .confirmed {
            return true
        }
        if existing.status == candidate.status,
           existing.profit == candidate.profit,
           existing.returnRate == candidate.returnRate {
            return false
        }
        return candidate.updatedAt >= existing.updatedAt
    }
}

enum PortfolioPerformanceSeries {
    static func cumulativePoints(
        in snapshot: PortfolioPerformanceSnapshot
    ) -> [PortfolioPerformancePoint] {
        let days = PortfolioPerformanceRecorder.normalized(snapshot).days
        var runningTotal = 0.0
        return days.map { day in
            runningTotal += day.profit
            return PortfolioPerformancePoint(day: day, cumulativeProfit: runningTotal)
        }
    }

    static func points(
        in snapshot: PortfolioPerformanceSnapshot,
        range: PortfolioPerformanceRange,
        through endDate: Date
    ) -> [PortfolioPerformancePoint] {
        let points = cumulativePoints(in: snapshot)
        guard let cutoff = cutoffDate(for: range, through: endDate) else {
            return points
        }
        let cutoffText = DateOnlyFormatter.string(from: cutoff)
        let endText = DateOnlyFormatter.string(from: endDate)
        return points.filter { $0.day.date >= cutoffText && $0.day.date <= endText }
    }

    private static func cutoffDate(
        for range: PortfolioPerformanceRange,
        through endDate: Date
    ) -> Date? {
        let component: DateComponents
        switch range {
        case .oneMonth:
            component = DateComponents(month: -1)
        case .threeMonths:
            component = DateComponents(month: -3)
        case .sixMonths:
            component = DateComponents(month: -6)
        case .oneYear:
            component = DateComponents(year: -1)
        case .all:
            return nil
        }
        return PortfolioPerformanceCalendar.shanghaiCalendar.date(byAdding: component, to: endDate)
    }
}

enum PortfolioPerformanceCalendar {
    static var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    static func grid(monthContaining date: Date) -> PortfolioPerformanceMonthGrid {
        let calendar = shanghaiCalendar
        guard let monthStart = monthStart(containing: date),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return PortfolioPerformanceMonthGrid(monthKey: "", cells: [])
        }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<String?>(repeating: nil, count: leadingBlanks)
        cells.reserveCapacity(42)

        for day in dayRange {
            guard let value = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                continue
            }
            cells.append(DateOnlyFormatter.string(from: value))
        }

        let trailingBlanks = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array<String?>(repeating: nil, count: trailingBlanks))

        return PortfolioPerformanceMonthGrid(
            monthKey: String(DateOnlyFormatter.string(from: monthStart).prefix(7)),
            cells: cells
        )
    }

    static func summary(
        in snapshot: PortfolioPerformanceSnapshot,
        monthContaining date: Date
    ) -> PortfolioPerformanceMonthSummary {
        let prefix = grid(monthContaining: date).monthKey + "-"
        let days = PortfolioPerformanceRecorder.normalized(snapshot).days.filter {
            $0.date.hasPrefix(prefix)
        }
        return PortfolioPerformanceMonthSummary(
            days: days,
            totalProfit: days.reduce(0) { $0 + $1.profit },
            riseDays: days.count { $0.profit > 0 },
            fallDays: days.count { $0.profit < 0 },
            estimatedDays: days.count { $0.status == .estimated }
        )
    }

    static func shiftedMonth(from date: Date, by offset: Int) -> Date {
        let calendar = shanghaiCalendar
        return calendar.date(byAdding: .month, value: offset, to: date) ?? date
    }

    static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = shanghaiCalendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = shanghaiCalendar.timeZone
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }

    static func monthStart(containing date: Date) -> Date? {
        let calendar = shanghaiCalendar
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)
    }
}
