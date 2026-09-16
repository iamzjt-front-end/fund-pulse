import AppKit
import SwiftUI

enum PortfolioPanelDisplay {
    static let allocationPalette: [Color] = [
        Color(red: 48 / 255, green: 120 / 255, blue: 214 / 255),
        Color(red: 231 / 255, green: 126 / 255, blue: 48 / 255),
        Color(red: 118 / 255, green: 92 / 255, blue: 196 / 255),
        Color(red: 37 / 255, green: 164 / 255, blue: 149 / 255),
        Color(red: 221 / 255, green: 87 / 255, blue: 133 / 255),
        Color(red: 93 / 255, green: 142 / 255, blue: 65 / 255),
        Color(red: 183 / 255, green: 95 / 255, blue: 40 / 255),
        Color(red: 92 / 255, green: 120 / 255, blue: 145 / 255)
    ]

    static func holdingFunds(in snapshot: PortfolioSnapshot) -> [FundPosition] {
        snapshot.funds.filter { fund in
            fund.status == .holding && currentAmount(for: fund) > 0
        }
    }

    static func currentAmount(for fund: FundPosition) -> Double { FundPositionDisplayValues.currentAmount(for: fund) }
    static func principal(for fund: FundPosition) -> Double { FundPositionDisplayValues.principal(for: fund) }
    static func holdingIncome(for fund: FundPosition) -> Double { FundPositionDisplayValues.holdingIncome(for: fund) }
}

