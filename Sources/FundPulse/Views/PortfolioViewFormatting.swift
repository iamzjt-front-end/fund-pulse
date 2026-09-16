import AppKit
import SwiftUI

func toneColor(for value: Double) -> Color {
    if value > 0 { return Color(red: 239 / 255, green: 77 / 255, blue: 98 / 255) }
    if value < 0 { return .fundPulseGreen }
    return Color.secondary
}

func todayIncomeAmount(_ value: Double, isMasked: Bool = false) -> Text {
    if isMasked {
        return Text("***")
            .font(.system(size: 30, weight: .semibold))
    }
    let sign = value > 0 ? "+" : value < 0 ? "-" : ""
    let amount = abs(value).formatted(.number.precision(.fractionLength(2)))
    return Text("\(sign)\(amount)")
        .font(.system(size: 30, weight: .semibold))
}

func inferredInitialTradeRecord(for fund: FundPosition) -> FundTradeRecord? {
    let shares = fund.migratedShares ?? 0
    let amount = inferredInitialTradeRecordAmount(for: fund)
    guard shares > 0 || (amount ?? 0) > 0 else {
        return nil
    }

    let tradeDate = fund.positionDate ?? fund.incomeStartDate ?? ""
    let acceptedDate = fund.incomeStartDate ?? fund.positionDate ?? tradeDate
    let status: FundTradeRecordStatus = fund.status.isPendingDisplay ? .pending : .confirmed
    return FundTradeRecord(
        id: inferredInitialTradeRecordID(for: fund.code),
        kind: .newFund,
        status: status,
        code: fund.code,
        name: fund.name,
        mode: fund.positionMode ?? .share,
        amount: amount,
        shares: fund.positionMode == .amount ? nil : (shares > 0 ? shares : nil),
        confirmedShares: fund.positionMode == .amount ? nil : (status == .confirmed && shares > 0 ? shares : nil),
        price: fund.positionMode == .amount ? nil : fund.migratedCost,
        profit: fund.positionMode == .amount ? fund.pendingProfit : nil,
        tradeDate: tradeDate,
        tradeTimeType: fund.positionTimeType ?? .before15,
        acceptedDate: acceptedDate,
        createdAt: .distantPast,
        confirmedAt: status == .confirmed ? .distantPast : nil,
        failureReason: nil
    )
}

private func inferredInitialTradeRecordAmount(for fund: FundPosition) -> Double? {
    if fund.positionMode == .amount {
        return firstPositiveAmount(fund.pendingAmount, fund.migratedPrincipal, fund.currentAmount)
    }
    return firstPositiveAmount(fund.migratedPrincipal, fund.pendingAmount, fund.currentAmount)
}

private func firstPositiveAmount(_ values: Double?...) -> Double? {
    for value in values {
        if let value, value > 0 {
            return value
        }
    }
    return nil
}

private func inferredInitialTradeRecordID(for code: String) -> String {
    "inferred-new-fund-\(code)"
}

func isInferredInitialTradeRecord(_ record: FundTradeRecord) -> Bool {
    record.id == inferredInitialTradeRecordID(for: record.code)
}

func tradeRecordTimeDescending(_ lhs: FundTradeRecord, _ rhs: FundTradeRecord) -> Bool {
    if lhs.tradeDate != rhs.tradeDate {
        return lhs.tradeDate > rhs.tradeDate
    }
    if lhs.tradeTimeType != rhs.tradeTimeType {
        return lhs.tradeTimeType.sortOrder > rhs.tradeTimeType.sortOrder
    }
    if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt > rhs.createdAt
    }
    return lhs.id > rhs.id
}

private extension PositionTimeType {
    var sortOrder: Int {
        switch self {
        case .before15:
            0
        case .after15:
            1
        }
    }
}

