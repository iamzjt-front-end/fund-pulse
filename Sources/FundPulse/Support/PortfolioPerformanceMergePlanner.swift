import Foundation

enum PortfolioPerformanceMergeError: LocalizedError, Equatable {
    case invalidAccount
    case accountMismatch
    case concurrentModification

    var errorDescription: String? {
        switch self {
        case .invalidAccount:
            "无法确认当前京东账号，请重新登录后再试"
        case .accountMismatch:
            "当前京东账号与已有京东同步数据来源不一致，请切回原账号；如需换号，请先清除旧账号的收益记录和持仓同步基线"
        case .concurrentModification:
            "组合收益在预览后发生变化，请重新同步"
        }
    }
}

struct PortfolioPerformanceMergeConflict: Identifiable, Equatable, Sendable {
    var id: String { date }
    var date: String
    var existing: PortfolioPerformanceDay
    var incoming: PortfolioPerformanceDay
}

struct PortfolioPerformanceMergePlan: Equatable, Sendable {
    fileprivate var baseSnapshot: PortfolioPerformanceSnapshot
    fileprivate var automaticDays: [PortfolioPerformanceDay]
    fileprivate var metadata: JDFinancePerformanceSyncMetadata

    var conflicts: [PortfolioPerformanceMergeConflict]
    var insertedCount: Int
    var upgradedCount: Int
    var updatedCount: Int
    var unchangedCount: Int
    var zeroValueSkippedCount: Int
    var invalidValueSkippedCount: Int

    var hasDayChanges: Bool {
        !automaticDays.isEmpty || !conflicts.isEmpty
    }

    func selectedDayChangeCount(overwriteConflicts: Bool) -> Int {
        insertedCount + upgradedCount + updatedCount
            + (overwriteConflicts ? conflicts.count : 0)
    }

    func canApply(overwriteConflicts: Bool) -> Bool {
        selectedDayChangeCount(overwriteConflicts: overwriteConflicts) > 0 || metadataChanged
    }

    var metadataChanged: Bool {
        baseSnapshot.jdFinanceSync != metadata
    }

    var coveredFrom: String { metadata.coveredFrom }
    var coveredThrough: String { metadata.coveredThrough }
    var isComplete: Bool { metadata.isComplete }
    var accountKey: String { metadata.accountKey }
}

enum PortfolioPerformanceMergePlanner {
    static func plan(
        history: JDFinancePerformanceHistory,
        accountKey: String,
        in snapshot: PortfolioPerformanceSnapshot,
        syncedAt: Date
    ) throws -> PortfolioPerformanceMergePlan {
        let normalizedAccountKey = accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccountKey.isEmpty else {
            throw PortfolioPerformanceMergeError.invalidAccount
        }

        let base = PortfolioPerformanceRecorder.normalized(snapshot)
        if let establishedKey = base.jdFinanceSync?.accountKey,
           establishedKey != normalizedAccountKey {
            throw PortfolioPerformanceMergeError.accountMismatch
        }
        if base.days.contains(where: {
            $0.source == .jdFinance
                && $0.sourceAccountKey != nil
                && $0.sourceAccountKey != normalizedAccountKey
        }) {
            throw PortfolioPerformanceMergeError.accountMismatch
        }

        var automaticDays: [PortfolioPerformanceDay] = []
        var conflicts: [PortfolioPerformanceMergeConflict] = []
        var insertedCount = 0
        var upgradedCount = 0
        var updatedCount = 0
        var unchangedCount = 0
        var zeroValueSkippedCount = 0
        var invalidValueSkippedCount = 0
        let existingByDate = Dictionary(uniqueKeysWithValues: base.days.map { ($0.date, $0) })

        for remote in history.days.sorted(by: { $0.date < $1.date }) {
            guard DateOnlyFormatter.parse(remote.date) != nil,
                  remote.incomeAmount.isFinite,
                  remote.incomeRate?.isFinite ?? true
            else {
                invalidValueSkippedCount += 1
                continue
            }
            let existing = existingByDate[remote.date]
            if existing == nil, isZeroValue(remote) {
                zeroValueSkippedCount += 1
                continue
            }

            let incoming = PortfolioPerformanceDay(
                date: remote.date,
                profit: remote.incomeAmount,
                returnRate: remote.incomeRate,
                status: .confirmed,
                source: .jdFinance,
                sourceAccountKey: normalizedAccountKey,
                updatedAt: syncedAt
            )
            guard let existing else {
                automaticDays.append(incoming)
                insertedCount += 1
                continue
            }

            if existing.source == .jdFinance {
                let existingAccountKey = existing.sourceAccountKey ?? base.jdFinanceSync?.accountKey
                guard existingAccountKey == nil || existingAccountKey == normalizedAccountKey else {
                    throw PortfolioPerformanceMergeError.accountMismatch
                }
                if sameOfficialValue(existing, incoming) {
                    unchangedCount += 1
                } else {
                    automaticDays.append(incoming)
                    updatedCount += 1
                }
                continue
            }

            if existing.status == .estimated {
                automaticDays.append(incoming)
                upgradedCount += 1
            } else if sameProfit(existing.profit, incoming.profit) {
                unchangedCount += 1
            } else {
                conflicts.append(.init(date: remote.date, existing: existing, incoming: incoming))
            }
        }

        let metadata = mergedMetadata(
            existing: base.jdFinanceSync,
            accountKey: normalizedAccountKey,
            history: history,
            syncedAt: syncedAt,
            hasAutomaticDayChanges: !automaticDays.isEmpty
        )
        return PortfolioPerformanceMergePlan(
            baseSnapshot: base,
            automaticDays: automaticDays,
            metadata: metadata,
            conflicts: conflicts.sorted { $0.date < $1.date },
            insertedCount: insertedCount,
            upgradedCount: upgradedCount,
            updatedCount: updatedCount,
            unchangedCount: unchangedCount,
            zeroValueSkippedCount: zeroValueSkippedCount,
            invalidValueSkippedCount: invalidValueSkippedCount
        )
    }

    static func applying(
        _ plan: PortfolioPerformanceMergePlan,
        to snapshot: PortfolioPerformanceSnapshot,
        overwriteConflicts: Bool = false
    ) throws -> PortfolioPerformanceSnapshot {
        let base = PortfolioPerformanceRecorder.normalized(snapshot)
        guard base == plan.baseSnapshot else {
            throw PortfolioPerformanceMergeError.concurrentModification
        }

        var next = base
        let selectedDays = plan.automaticDays + (overwriteConflicts ? plan.conflicts.map(\.incoming) : [])
        for day in selectedDays {
            if let index = next.days.firstIndex(where: { $0.date == day.date }) {
                next.days[index] = day
            } else {
                next.days.append(day)
            }
        }
        next.jdFinanceSync = plan.metadata
        return PortfolioPerformanceRecorder.normalized(next)
    }

    private static func isZeroValue(_ day: JDFinancePerformanceDay) -> Bool {
        abs(day.incomeAmount) < 0.000_000_1
            && abs(day.incomeRate ?? 0) < 0.000_000_1
    }

    private static func sameOfficialValue(
        _ lhs: PortfolioPerformanceDay,
        _ rhs: PortfolioPerformanceDay
    ) -> Bool {
        sameProfit(lhs.profit, rhs.profit)
            && sameOptionalRate(lhs.returnRate, rhs.returnRate)
    }

    private static func sameProfit(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.005
    }

    private static func sameOptionalRate(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            abs(lhs - rhs) < 0.000_001
        case (nil, _), (_, nil):
            false
        }
    }

    private static func mergedMetadata(
        existing: JDFinancePerformanceSyncMetadata?,
        accountKey: String,
        history: JDFinancePerformanceHistory,
        syncedAt: Date,
        hasAutomaticDayChanges: Bool
    ) -> JDFinancePerformanceSyncMetadata {
        let coveredFrom = min(existing?.coveredFrom ?? history.coveredFrom, history.coveredFrom)
        let coveredThrough = max(existing?.coveredThrough ?? history.coveredThrough, history.coveredThrough)
        let isComplete: Bool
        if let existing,
           existing.isComplete,
           existing.coveredFrom <= history.coveredFrom,
           existing.coveredThrough >= history.coveredThrough {
            isComplete = true
        } else {
            isComplete = history.isComplete
        }

        if let existing,
           existing.accountKey == accountKey,
           existing.coveredFrom == coveredFrom,
           existing.coveredThrough == coveredThrough,
           existing.isComplete == isComplete,
           !hasAutomaticDayChanges {
            return existing
        }
        return JDFinancePerformanceSyncMetadata(
            accountKey: accountKey,
            coveredFrom: coveredFrom,
            coveredThrough: coveredThrough,
            lastSyncedAt: syncedAt,
            isComplete: isComplete
        )
    }
}
