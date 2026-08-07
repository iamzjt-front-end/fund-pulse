import Foundation

struct FundNetValueTrendScale: Equatable {
    let minimum: Double
    let maximum: Double
    let costReference: Double?

    init(pointValues: [Double], holdingCost: Double?) {
        let validPointValues = pointValues.filter(\.isFinite)
        let validHoldingCost = Self.costReference(from: holdingCost)
        let values = validPointValues + [validHoldingCost].compactMap { $0 }

        guard let minimumValue = values.min(),
              let maximumValue = values.max()
        else {
            minimum = 0
            maximum = 1
            costReference = nil
            return
        }

        let range = max(maximumValue - minimumValue, 0.0001)
        let padding = max(range * 0.12, 0.01)
        minimum = minimumValue - padding
        maximum = maximumValue + padding
        costReference = validHoldingCost
    }

    static func costReference(from holdingCost: Double?) -> Double? {
        holdingCost.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
    }

    func normalizedY(for value: Double) -> Double {
        let range = max(maximum - minimum, 0.0001)
        let clampedValue = min(max(value, minimum), maximum)
        return 1 - (clampedValue - minimum) / range
    }
}
