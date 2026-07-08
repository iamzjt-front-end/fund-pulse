import Foundation

struct FundThresholdReminder: Equatable {
    enum Kind: String, Equatable {
        case dailyGrowth = "daily-growth"
    }

    enum Direction: String, Equatable {
        case rise
        case fall

        var title: String {
            switch self {
            case .rise:
                "涨幅"
            case .fall:
                "跌幅"
            }
        }
    }

    let code: String
    let name: String
    let kind: Kind
    let direction: Direction
    let threshold: Double
    let currentValue: Double
    let dateKey: String

    var dedupeKey: String {
        "\(kind.rawValue).\(dateKey).\(displayCode).\(direction.rawValue).\(thresholdKey)"
    }

    var sameDayDirectionDedupePrefix: String {
        "\(kind.rawValue).\(dateKey).\(displayCode).\(direction.rawValue)."
    }

    var notificationIdentifier: String {
        "fund-pulse.threshold.\(kind.rawValue).\(dateKey).\(displayCode).\(direction.rawValue).\(thresholdKey)"
    }

    var title: String {
        displayName
    }

    var body: String {
        switch kind {
        case .dailyGrowth:
            return "涨跌幅提醒：当前\(direction.title) \(MoneyFormatter.percent(currentValue, signed: true))，已达 \(MoneyFormatter.percent(threshold, signed: false))档。"
        }
    }

    private var displayCode: String {
        FundCodeFormatter.display(code)
    }

    private var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayCode : name
    }

    private var thresholdKey: String {
        Self.numberText(threshold, places: 2)
            .replacingOccurrences(of: ".", with: "_")
    }

    private static func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }
}

enum FundThresholdReminderEvaluator {
    static func reminders(
        in snapshot: PortfolioSnapshot,
        settings: AppSettings,
        date: Date = .now
    ) -> [FundThresholdReminder] {
        let dateKey = DateOnlyFormatter.string(from: date)
        return snapshot.funds.flatMap { reminders(for: $0, settings: settings, dateKey: dateKey) }
    }

    static func eligibleReminders(
        in snapshot: PortfolioSnapshot,
        settings: AppSettings,
        now: Date = .now,
        lastSentAt: [String: Date]
    ) -> [FundThresholdReminder] {
        guard TradingCalendar.isMarketOpen(now: now) else {
            return []
        }

        return reminders(in: snapshot, settings: settings, date: now).filter { reminder in
            let sentSameDirectionThresholds = lastSentAt.keys.compactMap {
                reminder.sentThresholdFromSameDayDirectionKey($0)
            }
            return !sentSameDirectionThresholds.contains { $0 >= reminder.threshold }
        }
    }

    static func reminders(for fund: FundPosition, settings: AppSettings, dateKey: String) -> [FundThresholdReminder] {
        guard let dailyGrowthReminder = dailyGrowthReminder(for: fund, settings: settings, dateKey: dateKey) else {
            return []
        }
        return [dailyGrowthReminder]
    }

    private static func dailyGrowthReminder(
        for fund: FundPosition,
        settings: AppSettings,
        dateKey: String
    ) -> FundThresholdReminder? {
        guard settings.dailyGrowthReminderEnabled,
              fund.todayRate != 0
        else {
            return nil
        }

        let direction: FundThresholdReminder.Direction = fund.todayRate > 0 ? .rise : .fall
        let tiers = direction == .rise ? settings.dailyGrowthRiseTiers : settings.dailyGrowthFallTiers
        let absoluteRate = abs(fund.todayRate)
        guard let threshold = tiers.map(\.value).filter({ absoluteRate >= $0 }).max() else {
            return nil
        }

        return FundThresholdReminder(
            code: fund.code,
            name: fund.name,
            kind: .dailyGrowth,
            direction: direction,
            threshold: threshold,
            currentValue: fund.todayRate,
            dateKey: dateKey
        )
    }
}

private extension FundThresholdReminder {
    func sentThresholdFromSameDayDirectionKey(_ key: String) -> Double? {
        guard key.hasPrefix(sameDayDirectionDedupePrefix) else {
            return nil
        }
        let rawThreshold = key.dropFirst(sameDayDirectionDedupePrefix.count)
            .replacingOccurrences(of: "_", with: ".")
        return Double(rawThreshold)
    }
}
