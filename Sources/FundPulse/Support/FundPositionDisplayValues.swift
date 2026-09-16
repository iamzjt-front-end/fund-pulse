import Foundation

enum FundPositionDisplayValues {
    static func currentAmount(for fund: FundPosition) -> Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        return principal(for: fund) + holdingIncome(for: fund)
    }

    static func principal(for fund: FundPosition) -> Double {
        if let migratedPrincipal = fund.migratedPrincipal {
            return migratedPrincipal
        }
        guard let shares = fund.migratedShares,
              let cost = fund.migratedCost
        else {
            return 0
        }
        return shares * cost
    }

    static func holdingIncome(for fund: FundPosition) -> Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else {
            return 0
        }
        return principal(for: fund) * holdingRate / 100
    }
}
