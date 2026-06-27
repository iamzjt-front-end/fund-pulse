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

    private static let marketClosedRanges = [
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
        guard let date = DateOnlyFormatter.parse(positionDate) else {
            return positionDate
        }
        return DateOnlyFormatter.string(from: acceptedTradeDate(from: date, timeType: timeType))
    }

    static func nextFundTradingDate(after dateText: String) -> String? {
        guard let date = DateOnlyFormatter.parse(dateText) else {
            return nil
        }
        return DateOnlyFormatter.string(from: nextFundTradingDay(after: date))
    }

    static func isFundTradingDay(_ date: Date) -> Bool {
        let calendar = chinaCalendar
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

        while dates.count < limit {
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

    private static func nextFundTradingDay(after date: Date) -> Date {
        var currentDate = date
        repeat {
            currentDate = chinaCalendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        } while !isFundTradingDay(currentDate)
        return currentDate
    }

    private static func acceptedTradeDate(from date: Date, timeType: PositionTimeType) -> Date {
        if timeType == .before15, isFundTradingDay(date) {
            return date
        }
        return nextFundTradingDay(after: date)
    }
}
