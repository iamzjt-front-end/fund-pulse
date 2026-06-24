import Foundation

struct FundThresholdReminder: Equatable {
    enum Kind: String, Equatable {
        case dailyGrowth = "daily-growth"
        case netValue = "net-value"
    }

    let code: String
    let name: String
    let kind: Kind
    let threshold: Double
    let currentValue: Double
    let dateKey: String

    var dedupeKey: String {
        "\(kind.rawValue).\(displayCode).\(thresholdKey)"
    }

    var notificationIdentifier: String {
        "fund-pulse.threshold.\(kind.rawValue).\(dateKey).\(displayCode).\(thresholdKey)"
    }

    var title: String {
        displayName
    }

    var body: String {
        switch kind {
        case .dailyGrowth:
            let direction = currentValue >= 0 ? "涨幅" : "跌幅"
            return "涨跌幅提醒：当前\(direction) \(MoneyFormatter.percent(currentValue, signed: true))，阈值 \(MoneyFormatter.percent(abs(threshold)))。"
        case .netValue:
            return "净值提醒：当前净值 \(Self.numberText(currentValue, places: 4))，目标 \(Self.numberText(threshold, places: 4))。"
        }
    }

    private var displayCode: String {
        FundCodeFormatter.display(code)
    }

    private var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayCode : name
    }

    private var thresholdKey: String {
        Self.numberText(threshold, places: kind == .netValue ? 4 : 2)
            .replacingOccurrences(of: ".", with: "_")
    }

    private static func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }
}

enum FundThresholdReminderEvaluator {
    static func reminders(in snapshot: PortfolioSnapshot, date: Date = .now) -> [FundThresholdReminder] {
        let dateKey = DateOnlyFormatter.string(from: date)
        return snapshot.funds.flatMap { reminders(for: $0, dateKey: dateKey) }
    }

    static func eligibleReminders(
        in snapshot: PortfolioSnapshot,
        now: Date = .now,
        lastSentAt: [String: Date],
        interval: TimeInterval
    ) -> [FundThresholdReminder] {
        guard TradingCalendar.isMarketOpen(now: now) else {
            return []
        }

        return reminders(in: snapshot, date: now).filter { reminder in
            guard let lastSentDate = lastSentAt[reminder.dedupeKey] else {
                return true
            }
            return now.timeIntervalSince(lastSentDate) >= interval
        }
    }

    static func reminders(for fund: FundPosition, dateKey: String) -> [FundThresholdReminder] {
        var reminders: [FundThresholdReminder] = []

        if let dailyGrowthReminder = dailyGrowthReminder(for: fund, dateKey: dateKey) {
            reminders.append(dailyGrowthReminder)
        }

        if let netValueReminder = netValueReminder(for: fund, dateKey: dateKey) {
            reminders.append(netValueReminder)
        }

        return reminders
    }

    private static func dailyGrowthReminder(for fund: FundPosition, dateKey: String) -> FundThresholdReminder? {
        guard let threshold = fund.zdfRange,
              threshold != 0,
              abs(fund.todayRate) >= abs(threshold)
        else {
            return nil
        }

        return FundThresholdReminder(
            code: fund.code,
            name: fund.name,
            kind: .dailyGrowth,
            threshold: threshold,
            currentValue: fund.todayRate,
            dateKey: dateKey
        )
    }

    private static func netValueReminder(for fund: FundPosition, dateKey: String) -> FundThresholdReminder? {
        guard let targetNetValue = fund.jzNotice,
              targetNetValue > 0,
              let currentNetValue = currentNetValue(for: fund),
              currentNetValue >= targetNetValue
        else {
            return nil
        }

        return FundThresholdReminder(
            code: fund.code,
            name: fund.name,
            kind: .netValue,
            threshold: targetNetValue,
            currentValue: currentNetValue,
            dateKey: dateKey
        )
    }

    private static func currentNetValue(for fund: FundPosition) -> Double? {
        let lotShares = fund.lots?.reduce(0) { $0 + $1.shares } ?? 0
        let shares = fund.migratedShares ?? lotShares
        guard let currentAmount = fund.currentAmount, shares > 0 else {
            return nil
        }
        return currentAmount / shares
    }
}
