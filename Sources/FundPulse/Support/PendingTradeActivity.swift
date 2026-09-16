import Foundation

struct PendingTradeActivity: Identifiable {
    var id: String
    var recordID: String?
    var conversionID: String?
    var kind: FundTradeKind
    var code: String
    var name: String
    var linkedCode: String?
    var linkedName: String?
    var mode: PositionMode
    var amount: Double?
    var shares: Double?
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var acceptedDate: String
    var createdAt: Date
    var displayAmount: PendingActivityAmount?
    var fund: FundPosition?
    var failureReason: String? = nil
    var waitsForExternalConfirmation: Bool = false

    var isConversion: Bool {
        kind == .conversionOut || kind == .conversionIn || conversionID != nil
    }
}

struct PendingActivityPresentation: Equatable {
    static let noticeText = "系统会在受理日次日持续检查正式净值，净值就绪后自动确认；\nQDII 等基金净值发布较晚，继续待确认通常正常。"

    var orderText: String
    var waitingText: String

    init(activity: PendingTradeActivity) {
        let code = FundCodeFormatter.display(activity.code)
        let tradeDate = Self.shortDateText(activity.tradeDate)
        orderText = "\(code) · \(tradeDate) \(activity.tradeTimeType.title)\(activity.isConversion ? "发起" : "下单")"

        if let failureReason = Self.clean(activity.failureReason) {
            waitingText = "暂无法确认 · \(failureReason)"
        } else {
            waitingText = "次日检查确认 · 净值就绪后自动更新"
        }
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shortDateText(_ value: String) -> String {
        guard value.count >= 10 else { return value }
        return String(value.dropFirst(5).prefix(5))
    }
}

enum PendingActivityNoticePolicy {
    static func shouldShow(
        activityIDs: [String],
        dismissedActivityIDs: Set<String>
    ) -> Bool {
        let currentIDs = Set(activityIDs)
        guard !currentIDs.isEmpty else { return false }
        return dismissedActivityIDs.isEmpty || !currentIDs.isSubset(of: dismissedActivityIDs)
    }

    static func normalizedDismissedActivityIDs(
        activityIDs: [String],
        dismissedActivityIDs: Set<String>
    ) -> Set<String> {
        let currentIDs = Set(activityIDs)
        guard !currentIDs.isEmpty, !dismissedActivityIDs.isEmpty else { return [] }
        return currentIDs.isSubset(of: dismissedActivityIDs) ? dismissedActivityIDs : []
    }

    static func encodeDismissedActivityIDs(_ activityIDs: Set<String>) -> String {
        activityIDs.sorted().joined(separator: "\n")
    }

    static func decodeDismissedActivityIDs(from rawValue: String) -> Set<String> {
        Set(rawValue.split(separator: "\n").map(String.init))
    }
}

struct PendingActivityAmount {
    enum Source {
        case enteredAmount
        case estimatedNetValue
        case confirmedNetValue
        case latestNetValue
    }

    var value: Double
    var source: Source
    var price: Double?
    var shares: Double?
}

enum PendingTradeActivityBuilder {
    static func make(from snapshot: PortfolioSnapshot) -> [PendingTradeActivity] {
        let fundsByCode = Dictionary(uniqueKeysWithValues: snapshot.funds.map { ($0.code, $0) })
        let records = snapshot.tradeRecords ?? []
        let pendingTrades = snapshot.pendingTrades ?? []
        let pendingTradeRecordIDs = Set(pendingTrades.compactMap(\.recordID))
        let pendingConversionTargetCodes = Set((snapshot.pendingConversions ?? []).map(\.toCode))

        var activities: [PendingTradeActivity] = pendingTrades.map { pendingTrade in
            let record = pendingTrade.recordID.flatMap { id in
                records.first { $0.id == id }
            }
            let fund = fundsByCode[pendingTrade.code]
            let acceptedDate = record?.acceptedDate ?? TradingCalendar.acceptedTradeDate(
                positionDate: pendingTrade.tradeDate,
                timeType: pendingTrade.tradeTimeType
            )
            let kind = record?.kind ?? tradeKind(for: pendingTrade.action)
            let waitsForExternalConfirmation = waitsForExternalConfirmation(
                syncSource: record?.syncSource ?? pendingTrade.syncSource,
                externalStatus: record?.externalStatus ?? pendingTrade.externalStatus,
                explicitFlag: (record?.waitsForExternalConfirmation ?? false)
                    || (pendingTrade.waitsForExternalConfirmation ?? false)
            )
            return PendingTradeActivity(
                id: "pending-trade-\(pendingTrade.id)",
                recordID: record?.id ?? pendingTrade.recordID,
                conversionID: record?.conversionID,
                kind: kind,
                code: pendingTrade.code,
                name: record?.name ?? fund?.name ?? pendingTrade.code,
                linkedCode: record?.linkedCode,
                linkedName: record?.linkedName,
                mode: record?.mode ?? pendingTrade.mode,
                amount: record?.amount ?? pendingTrade.amount,
                shares: record?.shares ?? pendingTrade.shares,
                tradeDate: pendingTrade.tradeDate,
                tradeTimeType: pendingTrade.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: pendingTrade.createdAt,
                displayAmount: pendingDisplayAmount(
                    kind: kind,
                    amount: record?.amount ?? pendingTrade.amount,
                    shares: record?.shares ?? pendingTrade.shares,
                    acceptedDate: acceptedDate,
                    fund: fund,
                    snapshot: snapshot
                ),
                fund: fund,
                failureReason: record?.failureReason,
                waitsForExternalConfirmation: waitsForExternalConfirmation
            )
        }

        let pendingRecords = records.filter {
            $0.status == .pending
                && !pendingTradeRecordIDs.contains($0.id)
                && $0.kind != .conversionIn
        }
        activities.append(contentsOf: pendingRecords.map { record in
            PendingTradeActivity(
                id: "pending-record-\(record.id)",
                recordID: record.id,
                conversionID: record.conversionID,
                kind: record.kind,
                code: record.code,
                name: record.name,
                linkedCode: record.linkedCode,
                linkedName: record.linkedName,
                mode: record.mode,
                amount: record.amount,
                shares: record.shares,
                tradeDate: record.tradeDate,
                tradeTimeType: record.tradeTimeType,
                acceptedDate: record.acceptedDate,
                createdAt: record.createdAt,
                displayAmount: pendingDisplayAmount(
                    kind: record.kind,
                    amount: record.amount,
                    shares: record.shares,
                    acceptedDate: record.acceptedDate,
                    fund: fundsByCode[record.code],
                    snapshot: snapshot
                ),
                fund: fundsByCode[record.code],
                failureReason: record.failureReason,
                waitsForExternalConfirmation: waitsForExternalConfirmation(
                    syncSource: record.syncSource,
                    externalStatus: record.externalStatus,
                    explicitFlag: record.waitsForExternalConfirmation ?? false
                )
            )
        })

        let pendingNewFundCodes = Set(
            activities
                .filter { $0.kind == .newFund }
                .map(\.code)
        )
        let legacyPendingFunds = snapshot.funds.filter {
            FundListDisplayRules.isDisplayedPending($0, tradeRecords: records)
                && !pendingNewFundCodes.contains($0.code)
                && !pendingConversionTargetCodes.contains($0.code)
        }
        activities.append(contentsOf: legacyPendingFunds.map { fund in
            let tradeDate = fund.positionDate ?? DateOnlyFormatter.string(from: .now)
            let timeType = fund.positionTimeType ?? .before15
            let acceptedDate = TradingCalendar.acceptedTradeDate(positionDate: tradeDate, timeType: timeType)
            return PendingTradeActivity(
                id: "pending-fund-\(fund.code)",
                recordID: nil,
                conversionID: nil,
                kind: .newFund,
                code: fund.code,
                name: fund.name,
                linkedCode: nil,
                linkedName: nil,
                mode: fund.positionMode ?? .amount,
                amount: fund.pendingAmount,
                shares: fund.migratedShares,
                tradeDate: tradeDate,
                tradeTimeType: timeType,
                acceptedDate: acceptedDate,
                createdAt: .distantPast,
                displayAmount: pendingDisplayAmount(
                    kind: .newFund,
                    amount: fund.pendingAmount,
                    shares: fund.migratedShares,
                    acceptedDate: acceptedDate,
                    fund: fund,
                    snapshot: snapshot
                ),
                fund: fund
            )
        })

        return activities.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func tradeKind(for action: FundTradeAction) -> FundTradeKind {
        switch action {
        case .buy:
            .buy
        case .sell:
            .sell
        }
    }

    private static func waitsForExternalConfirmation(
        syncSource: FundTradeSyncSource?,
        externalStatus: FundTradeExternalStatus?,
        explicitFlag: Bool
    ) -> Bool {
        syncSource == .jdFinance
            && (explicitFlag || externalStatus == .waitingExternalConfirmation)
    }

    private static func pendingDisplayAmount(
        kind: FundTradeKind,
        amount: Double?,
        shares: Double?,
        acceptedDate: String,
        fund: FundPosition?,
        snapshot: PortfolioSnapshot
    ) -> PendingActivityAmount? {
        if let amount, amount > 0 {
            return PendingActivityAmount(value: amount, source: .enteredAmount, price: nil, shares: shares)
        }
        guard let shares, shares > 0,
              let reference = pendingReferenceValue(for: fund, acceptedDate: acceptedDate, snapshot: snapshot)
        else {
            return nil
        }
        return PendingActivityAmount(
            value: shares * reference.price,
            source: reference.source,
            price: reference.price,
            shares: shares
        )
    }

    private static func pendingReferenceValue(
        for fund: FundPosition?,
        acceptedDate: String,
        snapshot: PortfolioSnapshot
    ) -> (price: Double, source: PendingActivityAmount.Source)? {
        guard let fund else { return nil }
        let shares = fund.migratedShares ?? 0
        let currentAmount = FundPositionDisplayValues.currentAmount(for: fund)
        let basePrice: Double
        if shares > 0, currentAmount > 0 {
            basePrice = currentAmount / shares
        } else if let migratedCost = fund.migratedCost, migratedCost > 0 {
            basePrice = migratedCost
        } else {
            return nil
        }

        let acceptedShortDate = String(acceptedDate.dropFirst(5))
        let updateDate = DateOnlyFormatter.string(from: snapshot.updateTime)
        let dateMatchesAcceptedNetValue = fund.dateText.hasPrefix(acceptedShortDate)
        if dateMatchesAcceptedNetValue && (fund.isUpdated || acceptedDate != updateDate) {
            return (basePrice, .confirmedNetValue)
        }

        if acceptedDate == updateDate, !fund.isUpdated, fund.todayRate != 0 {
            return (basePrice * (1 + fund.todayRate / 100), .estimatedNetValue)
        }

        return (basePrice, .latestNetValue)
    }
}

struct PendingHeaderImpact {
    var count: Int
    var buyAmount: Double = 0
    var sellAmount: Double = 0
    var conversionCount = 0
    var hasEstimatedAmount = false

    static func make(activities: [PendingTradeActivity]) -> PendingHeaderImpact? {
        var impact = PendingHeaderImpact(count: activities.count)
        var conversionKeys = Set<String>()

        for activity in activities {
            if activity.isConversion {
                conversionKeys.insert(activity.conversionID ?? activity.id)
                continue
            }

            guard let displayAmount = activity.displayAmount else {
                continue
            }

            switch activity.kind {
            case .newFund, .buy:
                impact.buyAmount += displayAmount.value
            case .sell:
                impact.sellAmount += displayAmount.value
            case .conversionOut, .conversionIn:
                conversionKeys.insert(activity.conversionID ?? activity.id)
            }

            if displayAmount.source == .estimatedNetValue {
                impact.hasEstimatedAmount = true
            }
        }

        impact.conversionCount = conversionKeys.count
        guard impact.hasAmount || impact.conversionCount > 0 else { return nil }
        return impact
    }

    var hasAmount: Bool {
        buyAmount > 0 || sellAmount > 0
    }

    var netAmount: Double {
        buyAmount - sellAmount
    }
}
