import Foundation

struct SampleDailyPerformance: Identifiable, Equatable {
    var id: Date { date }

    let date: Date
    let dailyIncome: Double
    let dailyIncomeRate: Double
    let cumulativeIncome: Double
}

struct SampleExperience: Equatable {
    let generatedAt: Date
    let portfolio: PortfolioSnapshot
    let dailyPerformance: [SampleDailyPerformance]
}

enum SampleExperienceFactory {
    /// Creates an entirely in-memory, deterministic experience. It intentionally
    /// has no repository or service dependency, so opening the sample cannot
    /// write portfolio/history data or trigger a network request.
    static func make(now: Date = .now) -> SampleExperience {
        let calendar = chinaCalendar
        let today = calendar.startOfDay(for: now)
        let totalAmount = 32_680.00
        var cumulativeIncome = 260.00
        var tradingIndex = 0
        var points: [SampleDailyPerformance] = []

        for dayOffset in -89 ... 0 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            guard (2 ... 6).contains(weekday) else { continue }

            let phase = Double(tradingIndex)
            let dailyIncome = rounded(
                sin(phase * 0.47) * 46
                    + cos(phase * 0.19) * 27
                    + (tradingIndex.isMultiple(of: 9) ? -18 : 5)
            )
            cumulativeIncome = rounded(cumulativeIncome + dailyIncome)
            points.append(
                SampleDailyPerformance(
                    date: date,
                    dailyIncome: dailyIncome,
                    dailyIncomeRate: rounded(dailyIncome / totalAmount * 100, places: 3),
                    cumulativeIncome: cumulativeIncome
                )
            )
            tradingIndex += 1
        }

        let todayIncome = points.last?.dailyIncome ?? 0
        let holdingIncome = points.last?.cumulativeIncome ?? 0
        let principal = totalAmount - holdingIncome
        let dateText = dateTextFormatter.string(from: now)
        let firstIncome = rounded(holdingIncome * 0.58)
        let secondIncome = rounded(holdingIncome * -0.16)
        let thirdIncome = rounded(holdingIncome - firstIncome - secondIncome)
        let allocations: [(String, String, Double, Double, Double)] = [
            ("DEMO001", "示例·稳健成长", 13_200, firstIncome, 0.44),
            ("DEMO002", "示例·科技趋势", 10_180, secondIncome, -0.31),
            ("DEMO003", "示例·红利价值", 9_300, thirdIncome, 0.19)
        ]
        let samplePositionDates = [-75, -50, -25].map { offset in
            DateOnlyFormatter.string(
                from: calendar.date(byAdding: .day, value: offset, to: today) ?? today
            )
        }

        let funds = allocations.enumerated().map { index, item in
            let (code, name, amount, income, todayRate) = item
            let weight = amount / totalAmount
            return FundPosition(
                code: code,
                name: name,
                dateText: dateText,
                todayIncome: rounded(todayIncome * weight),
                todayRate: todayRate,
                holdingIncome: income,
                holdingRate: rounded(income / max(amount - income, 1) * 100),
                confirmedHoldingIncome: income,
                confirmedHoldingRate: rounded(income / max(amount - income, 1) * 100),
                currentAmount: amount,
                status: .holding,
                isUpdated: true,
                isIncomeActive: true,
                positionMode: .amount,
                positionDate: samplePositionDates[index],
                positionTimeType: .before15
            )
        }

        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: totalAmount,
            holdingIncome: holdingIncome,
            holdingIncomeRate: rounded(holdingIncome / max(principal, 1) * 100),
            todayIncome: todayIncome,
            todayIncomeRate: rounded(todayIncome / totalAmount * 100, places: 3),
            pendingCount: 0,
            funds: funds,
            migration: nil
        )
        return SampleExperience(generatedAt: now, portfolio: snapshot, dailyPerformance: points)
    }

    private static var chinaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private static let dateTextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static func rounded(_ value: Double, places: Int = 2) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}
