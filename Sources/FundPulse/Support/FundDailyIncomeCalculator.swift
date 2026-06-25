import Foundation

struct FundDailyIncomeRow: Identifiable, Equatable {
    var id: String { dateText }

    let dateText: String
    let netValue: Double
    let dailyIncome: Double
    let entryIncome: Double
    let cumulativeIncome: Double
    let cumulativeRate: Double?
}

enum FundDailyIncomeCalculator {
    static func rows(
        lots: [FundPositionLot],
        points: [FundNetValuePoint]
    ) -> [FundDailyIncomeRow] {
        let dailyPoints = uniqueDailyPoints(from: points)
        guard !dailyPoints.isEmpty else { return [] }

        var previousCumulativeIncome = 0.0
        var rows: [FundDailyIncomeRow] = []

        for (index, point) in dailyPoints.enumerated() {
            let activeLots = lots.filter { isActive($0, on: point.dateText) }
            guard !activeLots.isEmpty else { continue }

            let previousPoint = index > 0 ? dailyPoints[index - 1] : nil
            let dailyLots = lots.filter { participatesInDailyIncome($0, on: point.dateText) }
            let dailyIncome = calculatedDailyIncome(
                lots: dailyLots,
                point: point,
                previousPoint: previousPoint
            )
            let cumulativeIncome = activeLots.reduce(0) { total, lot in
                total + lot.shares * (point.value - lot.cost)
            }
            let principal = activeLots.reduce(0) { total, lot in
                total + lot.shares * lot.cost
            }
            let cumulativeRate = principal > 0 ? cumulativeIncome / principal * 100 : nil
            let entryIncome = cumulativeIncome - previousCumulativeIncome - dailyIncome

            rows.append(FundDailyIncomeRow(
                dateText: point.dateText,
                netValue: point.value,
                dailyIncome: dailyIncome,
                entryIncome: entryIncome,
                cumulativeIncome: cumulativeIncome,
                cumulativeRate: cumulativeRate
            ))
            previousCumulativeIncome = cumulativeIncome
        }

        return rows.reversed()
    }

    private static func calculatedDailyIncome(
        lots: [FundPositionLot],
        point: DailyNetValuePoint,
        previousPoint: DailyNetValuePoint?
    ) -> Double {
        guard let previousPoint else { return 0 }

        return lots.reduce(0) { total, lot in
            let baseline = baselineNetValue(for: lot, previousPoint: previousPoint)
            return total + lot.shares * (point.value - baseline)
        }
    }

    private static func baselineNetValue(
        for lot: FundPositionLot,
        previousPoint: DailyNetValuePoint
    ) -> Double {
        guard DateOnlyFormatter.parse(lot.incomeStartDate) != nil else {
            return previousPoint.value
        }
        return previousPoint.dateText >= lot.incomeStartDate ? previousPoint.value : lot.cost
    }

    private static func isActive(_ lot: FundPositionLot, on dateText: String) -> Bool {
        guard lot.shares > 0 else { return false }
        guard DateOnlyFormatter.parse(lot.incomeStartDate) != nil else { return true }
        return lot.incomeStartDate <= dateText
    }

    private static func participatesInDailyIncome(_ lot: FundPositionLot, on dateText: String) -> Bool {
        guard lot.shares > 0 else { return false }
        guard DateOnlyFormatter.parse(lot.incomeStartDate) != nil else { return true }
        return lot.incomeStartDate < dateText
    }

    private static func uniqueDailyPoints(from points: [FundNetValuePoint]) -> [DailyNetValuePoint] {
        var pointsByDate: [String: DailyNetValuePoint] = [:]
        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) where point.value > 0 {
            let dateText = DateOnlyFormatter.string(
                from: Date(timeIntervalSince1970: TimeInterval(point.timestamp) / 1000)
            )
            pointsByDate[dateText] = DailyNetValuePoint(
                dateText: dateText,
                timestamp: point.timestamp,
                value: point.value
            )
        }
        return pointsByDate.values.sorted {
            if $0.dateText != $1.dateText {
                return $0.dateText < $1.dateText
            }
            return $0.timestamp < $1.timestamp
        }
    }
}

private struct DailyNetValuePoint: Equatable {
    let dateText: String
    let timestamp: Int64
    let value: Double
}
