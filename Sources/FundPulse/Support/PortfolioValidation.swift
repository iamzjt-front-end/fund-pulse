import Foundation

enum PortfolioValidation {
    static let schemaVersion = 1

    struct InvalidData: LocalizedError {
        let reason: String
        var errorDescription: String? { "持仓数据校验失败：\(reason)" }
    }

    static func validate(_ snapshot: PortfolioSnapshot, accountKind: PortfolioAccountKind? = nil) throws {
        if let version = snapshot.schemaVersion, !(0...schemaVersion).contains(version) {
            throw InvalidData(reason: "不支持备份版本 \(version)，请更新应用")
        }
        if let expected = accountKind, let actual = snapshot.accountKind, expected != actual {
            throw InvalidData(reason: "备份账户类型与当前账户不一致")
        }
        try unique(snapshot.funds.map(\.code), label: "基金代码")
        try unique((snapshot.tradeRecords ?? []).map(\.id), label: "流水 ID")
        try unique((snapshot.pendingTrades ?? []).map(\.id), label: "待确认交易 ID")
        try unique((snapshot.pendingConversions ?? []).map(\.id), label: "转换 ID")
        try finite([snapshot.totalAmount, snapshot.holdingIncome, snapshot.holdingIncomeRate,
                    snapshot.todayIncome, snapshot.todayIncomeRate])
        guard snapshot.pendingCount >= 0, snapshot.updateTime.timeIntervalSince1970.isFinite else {
            throw InvalidData(reason: "汇总信息无效")
        }
        let codes = Set(snapshot.funds.map(\.code))
        let records = Dictionary(uniqueKeysWithValues: (snapshot.tradeRecords ?? []).map { ($0.id, $0) })
        for fund in snapshot.funds {
            try nonnegative([fund.migratedShares, fund.migratedCost, fund.migratedPrincipal, fund.pendingAmount, fund.currentAmount])
            try finite([fund.todayIncome, fund.todayRate, fund.holdingIncome, fund.holdingRate, fund.pendingProfit])
            try dates([fund.positionDate, fund.incomeStartDate])
            try unique((fund.lots ?? []).map(\.id), label: "\(fund.code) 的持仓批次 ID")
            for lot in fund.lots ?? [] {
                try nonnegative([lot.shares, lot.cost, lot.principal])
                try dates([lot.positionDate, lot.incomeStartDate, lot.exchangeSellableDate, lot.exchangeUnlockAfterDate])
            }
        }
        for record in snapshot.tradeRecords ?? [] {
            guard !record.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InvalidData(reason: "流水基金代码为空")
            }
            try nonnegative([record.amount, record.shares, record.confirmedShares, record.price, record.buyFeeRate,
                             record.sellFeeValue, record.feeAmount, record.exchangeInitialSellableShares])
            try finite([record.profit])
            try dates([record.tradeDate, record.acceptedDate])
        }
        for trade in snapshot.pendingTrades ?? [] {
            guard codes.contains(trade.code) else { throw InvalidData(reason: "待确认交易引用不存在的基金") }
            try nonnegative([trade.amount, trade.shares, trade.buyFeeRate, trade.sellFeeValue])
            try dates([trade.tradeDate])
            // Pending arrays are a repairable index in legacy backups: an ID
            // may be missing or already confirmed. A resolved cross-fund link
            // is never safe and must be rejected.
            if let id = trade.recordID, let record = records[id] {
                guard record.code == trade.code else {
                    throw InvalidData(reason: "待确认交易与流水引用不一致")
                }
            }
        }
        for conversion in snapshot.pendingConversions ?? [] {
            guard codes.contains(conversion.fromCode), !conversion.toCode.isEmpty,
                  conversion.fromCode != conversion.toCode else {
                throw InvalidData(reason: "转换引用的基金无效")
            }
            try nonnegative([conversion.shares, conversion.buyFeeRate, conversion.sellFeeValue])
            try dates([conversion.tradeDate, conversion.acceptedDate])
            for (id, code) in [(conversion.outRecordID, conversion.fromCode), (conversion.inRecordID, conversion.toCode)] {
                if let id, let record = records[id] {
                    guard record.code == code, record.conversionID == conversion.id else {
                        throw InvalidData(reason: "转换流水引用不一致")
                    }
                }
            }
        }
        if let history = snapshot.portfolioPerformanceHistory,
           history.schemaVersion > PortfolioPerformanceSnapshot.currentSchemaVersion {
            throw InvalidData(reason: "收益历史版本过高")
        }
    }

    private static func unique(_ values: [String], label: String) throws {
        guard values.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              Set(values).count == values.count else { throw InvalidData(reason: "\(label) 为空或重复") }
    }

    private static func finite(_ values: [Double?]) throws {
        guard values.compactMap({ $0 }).allSatisfy(\.isFinite) else { throw InvalidData(reason: "包含非有限数值") }
    }

    private static func nonnegative(_ values: [Double?]) throws {
        try finite(values)
        guard values.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else { throw InvalidData(reason: "金额、份额或成本为负数") }
    }

    private static func dates(_ values: [String?]) throws {
        for text in values.compactMap({ $0 }) {
            guard let date = DateOnlyFormatter.parse(text), DateOnlyFormatter.string(from: date) == text else {
                throw InvalidData(reason: "无效日期 \(text)")
            }
        }
    }
}
