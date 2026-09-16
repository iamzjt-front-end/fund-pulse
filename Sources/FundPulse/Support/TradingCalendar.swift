import Foundation

enum MarketSessionState: Equatable {
    case open
    case middayBreak
    case closed

    var title: String {
        switch self {
        case .open:
            "开市"
        case .middayBreak:
            "午休"
        case .closed:
            "休市"
        }
    }
}

enum TradingCalendar {
    static let operationReminderScheduleLimit = 30
    static let supportedYears = 2024...2026
    static let calendarVersion = "SSE-2024-2026-v1"

    static func coverageWarning(on date: Date) -> String? {
        guard !supportedYears.contains(chinaCalendar.component(.year, from: date)) else { return nil }
        return "交易日历仅覆盖 2024–2026 年，请更新应用后再确认该年份的交易日期。"
    }

    private static let marketClosedRanges = [
        // SSE annual closure notices (weekend makeup workdays remain closed):
        // https://www.sse.com.cn/disclosure/dealinstruc/closed/c/c_20231226_5733941.shtml
        ("2024-01-01", "2024-01-01"),
        ("2024-02-09", "2024-02-17"),
        ("2024-04-04", "2024-04-06"),
        ("2024-05-01", "2024-05-05"),
        ("2024-06-10", "2024-06-10"),
        ("2024-09-15", "2024-09-17"),
        ("2024-10-01", "2024-10-07"),
        // https://www.sse.com.cn/disclosure/dealinstruc/closed/c/c_20241223_10767110.shtml
        ("2025-01-01", "2025-01-01"),
        ("2025-01-28", "2025-02-04"),
        ("2025-04-04", "2025-04-06"),
        ("2025-05-01", "2025-05-05"),
        ("2025-05-31", "2025-06-02"),
        ("2025-10-01", "2025-10-08"),
        ("2026-01-01", "2026-01-03"),
        ("2026-02-15", "2026-02-23"),
        ("2026-04-04", "2026-04-06"),
        ("2026-05-01", "2026-05-05"),
        ("2026-06-19", "2026-06-21"),
        ("2026-09-25", "2026-09-27"),
        ("2026-10-01", "2026-10-07")
    ]

    private static var chinaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    static func defaultPositionTimeType(now: Date = .now) -> PositionTimeType {
        chinaCalendar.component(.hour, from: now) >= 15 ? .after15 : .before15
    }

    static func acceptedTradeDate(positionDate: String, timeType: PositionTimeType) -> String {
        guard let date = DateOnlyFormatter.parse(positionDate),
              let accepted = acceptedTradeDate(from: date, timeType: timeType) else {
            return ""
        }
        return DateOnlyFormatter.string(from: accepted)
    }

    static func nextFundTradingDate(after dateText: String) -> String? {
        guard let date = DateOnlyFormatter.parse(dateText),
              let next = nextFundTradingDay(after: date) else {
            return nil
        }
        return DateOnlyFormatter.string(from: next)
    }

    static func isFundTradingDay(_ date: Date) -> Bool {
        let calendar = chinaCalendar
        guard supportedYears.contains(calendar.component(.year, from: date)) else { return false }
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        guard !isWeekend else { return false }

        let value = DateOnlyFormatter.string(from: date)
        return !marketClosedRanges.contains { start, end in
            value >= start && value <= end
        }
    }

    static func marketSessionState(now: Date = .now) -> MarketSessionState {
        let calendar = chinaCalendar
        guard isFundTradingDay(now) else { return .closed }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutes = hour * 60 + minute
        return marketSessionState(minutes: minutes, isTradingDay: true)
    }

    static func isMarketOpen(now: Date = .now) -> Bool {
        marketSessionState(now: now) == .open
    }

    static func nextMarketSessionBoundary(after now: Date = .now) -> Date? {
        let calendar = chinaCalendar
        var day = calendar.startOfDay(for: now)

        for _ in 0..<366 {
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }

            guard isFundTradingDay(day) else { continue }

            for minutes in [9 * 60 + 30, 11 * 60 + 30, 13 * 60, 15 * 60] {
                guard let boundary = calendar.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: day
                ),
                    boundary > now
                else {
                    continue
                }

                return boundary
            }
        }

        return nil
    }

    static func isMarketOpenReminderTime(minutes: Int) -> Bool {
        marketSessionState(minutes: minutes, isTradingDay: true) == .open
    }

    static func nextMarketOpenReminderDates(
        minutes: Int,
        from now: Date = .now,
        limit: Int = operationReminderScheduleLimit
    ) -> [Date] {
        guard limit > 0,
              isMarketOpenReminderTime(minutes: minutes)
        else {
            return []
        }

        let calendar = chinaCalendar
        var dates: [Date] = []
        var day = calendar.startOfDay(for: now)
        let hour = minutes / 60
        let minute = minutes % 60

        for _ in 0..<366 {
            if dates.count >= limit || coverageWarning(on: day) != nil { break }
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }

            guard isFundTradingDay(day),
                  let reminderDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  reminderDate > now
            else {
                continue
            }

            dates.append(reminderDate)
        }

        return dates
    }

    static func notificationDateComponents(from date: Date) -> DateComponents {
        let calendar = chinaCalendar
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    private static func marketSessionState(minutes: Int, isTradingDay: Bool) -> MarketSessionState {
        guard isTradingDay else { return .closed }

        let morningOpen = 9 * 60 + 30
        let morningClose = 11 * 60 + 30
        let afternoonOpen = 13 * 60
        let afternoonClose = 15 * 60

        if (morningOpen..<morningClose).contains(minutes) || (afternoonOpen..<afternoonClose).contains(minutes) {
            return .open
        }
        if (morningClose..<afternoonOpen).contains(minutes) {
            return .middayBreak
        }
        return .closed
    }

    private static func nextFundTradingDay(after date: Date) -> Date? {
        guard coverageWarning(on: date) == nil else { return nil }
        var currentDate = date
        for _ in 0..<366 {
            guard let next = chinaCalendar.date(byAdding: .day, value: 1, to: currentDate),
                  coverageWarning(on: next) == nil else { return nil }
            currentDate = next
            if isFundTradingDay(currentDate) { return currentDate }
        }
        return nil
    }

    private static func acceptedTradeDate(from date: Date, timeType: PositionTimeType) -> Date? {
        if timeType == .before15, isFundTradingDay(date) {
            return date
        }
        return nextFundTradingDay(after: date)
    }
}
