import Foundation
import Observation

enum JDFinancePerformanceSyncPolicy {
    static let fullHistoryStartDate = "2000-01-01"
    static let overlapDays = 7

    static func startDate(
        for snapshot: PortfolioPerformanceSnapshot,
        now _: Date
    ) -> String {
        guard let coveredThrough = snapshot.jdFinanceSync?.coveredThrough,
              let coveredDate = DateOnlyFormatter.parse(coveredThrough),
              let overlapStart = Calendar.shanghai.date(
                byAdding: .day,
                value: -overlapDays,
                to: coveredDate
              )
        else {
            return fullHistoryStartDate
        }
        return max(fullHistoryStartDate, DateOnlyFormatter.string(from: overlapStart))
    }
}

enum JDFinancePerformanceAccountMismatchSource: Equatable, Sendable {
    case holdingsBaseline
    case performanceHistory
    case holdingsBaselineAndPerformanceHistory

    var canClearPerformanceHistory: Bool {
        self == .performanceHistory
    }

    var involvesHoldingsBaseline: Bool {
        self != .performanceHistory
    }

    var message: String {
        switch self {
        case .holdingsBaseline:
            "当前京东账号与持仓同步基线不一致。请先返回并在京东持仓同步中切回原账号，或重置持仓同步基线后再重试。"
        case .performanceHistory:
            "当前京东账号与已有京东历史收益来源不一致。确认切换账号后，可清除旧账号的京东收益再重新同步。"
        case .holdingsBaselineAndPerformanceHistory:
            "当前京东账号同时与持仓同步基线和历史收益来源不一致。请先处理持仓同步基线；只清除历史收益无法完成账号切换。"
        }
    }
}

@Observable
@MainActor
final class JDFinancePerformanceSyncStore {
    typealias FetchHistory = (
        _ cookieHeader: String?,
        _ startDate: String,
        _ endDate: String?,
        _ existing: JDFinancePerformanceHistory,
        _ now: Date
    ) async throws -> JDFinancePerformanceHistory

    private(set) var plan: PortfolioPerformanceMergePlan?
    private(set) var isSyncing = false
    private(set) var isApplying = false
    private(set) var needsLogin = false
    private(set) var accountMismatchSource: JDFinancePerformanceAccountMismatchSource?
    private(set) var didApply = false
    private(set) var statusMessage = "正在检查京东登录状态..."
    private(set) var errorMessage: String?
    private(set) var lastSyncedAt: Date?

    private let fetchHistory: FetchHistory
    private let nowProvider: () -> Date
    private var generation = 0
    private var syncTask: Task<Void, Never>?

    var hasAccountMismatch: Bool {
        accountMismatchSource != nil
    }

    var canClearPerformanceHistoryForAccountMismatch: Bool {
        accountMismatchSource?.canClearPerformanceHistory == true
    }

    convenience init(
        service: JDFinancePerformanceHistoryService = JDFinancePerformanceHistoryService(),
        now: @escaping () -> Date = { .now }
    ) {
        self.init(
            fetchHistory: { cookieHeader, startDate, endDate, existing, requestNow in
                try await service.fetchHistory(
                    cookieHeader: cookieHeader,
                    from: startDate,
                    through: endDate,
                    existing: existing,
                    now: requestNow
                )
            },
            now: now
        )
    }

    init(
        fetchHistory: @escaping FetchHistory,
        now: @escaping () -> Date = { .now }
    ) {
        self.fetchHistory = fetchHistory
        self.nowProvider = now
    }

    func synchronize(
        performanceStore: PortfolioPerformanceStore,
        cookieHeader: String?,
        expectedAccountKey: String? = nil
    ) async {
        generation &+= 1
        let currentGeneration = generation
        syncTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await runSynchronization(
                performanceStore: performanceStore,
                cookieHeader: cookieHeader,
                expectedAccountKey: expectedAccountKey,
                generation: currentGeneration
            )
        }
        syncTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        generation &+= 1
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
    }

    @discardableResult
    func apply(
        to performanceStore: PortfolioPerformanceStore,
        overwriteConflicts: Bool,
        expectedAccountKey: String? = nil
    ) -> Bool {
        guard let plan, !isSyncing, !isApplying, !didApply else { return false }
        if let source = Self.accountMismatchSource(
            currentAccountKey: plan.accountKey,
            expectedAccountKey: expectedAccountKey,
            performanceSnapshot: performanceStore.snapshot
        ) {
            registerAccountMismatch(source)
            return false
        }
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }

        do {
            let changed = try performanceStore.applyJDFinancePerformanceMerge(
                plan,
                overwriteConflicts: overwriteConflicts
            )
            didApply = true
            statusMessage = changed ? "历史收益同步完成" : "历史收益已是最新"
            return changed
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "补全失败"
            return false
        }
    }

    static func clearJDFinanceHistory(in performanceStore: PortfolioPerformanceStore) throws {
        var replacement = performanceStore.snapshot
        replacement.days.removeAll { $0.source == .jdFinance }
        replacement.trackingStartDate = replacement.days.map(\.date).min()
        replacement.jdFinanceSync = nil
        try performanceStore.replace(replacement)
    }

    private func runSynchronization(
        performanceStore: PortfolioPerformanceStore,
        cookieHeader: String?,
        expectedAccountKey: String?,
        generation currentGeneration: Int
    ) async {
        plan = nil
        didApply = false
        errorMessage = nil
        needsLogin = false
        accountMismatchSource = nil

        guard !performanceStore.hasUnreadablePersistedData else {
            let message = performanceStore.lastError ?? "收益历史暂时无法读取"
            errorMessage = message
            statusMessage = message
            return
        }

        guard JDFinanceWebSession.hasUsableCookieHeader(cookieHeader) else {
            needsLogin = true
            statusMessage = "需要登录京东金融"
            return
        }
        guard let accountKey = JDFinanceSyncFingerprint.accountKey(cookieHeader: cookieHeader) else {
            needsLogin = true
            statusMessage = "无法确认京东账号"
            return
        }
        if let source = Self.accountMismatchSource(
            currentAccountKey: accountKey,
            expectedAccountKey: expectedAccountKey,
            performanceSnapshot: performanceStore.snapshot
        ) {
            registerAccountMismatch(source)
            return
        }

        isSyncing = true
        statusMessage = performanceStore.snapshot.jdFinanceSync == nil
            ? "首次补全会按年度读取，请稍候..."
            : "正在读取最新历史收益..."
        defer {
            if currentGeneration == generation {
                isSyncing = false
                syncTask = nil
            }
        }

        do {
            let requestNow = nowProvider()
            let startDate = JDFinancePerformanceSyncPolicy.startDate(
                for: performanceStore.snapshot,
                now: requestNow
            )
            let existing = existingHistory(from: performanceStore.snapshot)
            let history = try await fetchHistory(
                cookieHeader,
                startDate,
                nil,
                existing,
                requestNow
            )
            try Task.checkCancellation()
            let planned = try PortfolioPerformanceMergePlanner.plan(
                history: history,
                accountKey: accountKey,
                in: performanceStore.snapshot,
                syncedAt: requestNow
            )
            try Task.checkCancellation()
            guard currentGeneration == generation else { return }

            plan = planned
            lastSyncedAt = requestNow
            if planned.hasDayChanges || planned.metadataChanged {
                statusMessage = "已生成补全预览"
            } else {
                statusMessage = "历史收益已是最新"
            }
        } catch is CancellationError {
            return
        } catch let error as JDFinancePerformanceHistoryError {
            guard currentGeneration == generation else { return }
            if error == .notLoggedIn {
                needsLogin = true
            }
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        } catch let error as PortfolioPerformanceMergeError {
            guard currentGeneration == generation else { return }
            if error == .accountMismatch {
                registerAccountMismatch(
                    Self.accountMismatchSource(
                        currentAccountKey: accountKey,
                        expectedAccountKey: expectedAccountKey,
                        performanceSnapshot: performanceStore.snapshot
                    ) ?? .performanceHistory
                )
            } else {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        } catch {
            guard currentGeneration == generation else { return }
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func registerAccountMismatch(
        _ source: JDFinancePerformanceAccountMismatchSource
    ) {
        plan = nil
        accountMismatchSource = source
        errorMessage = source.message
        statusMessage = source.message
    }

    private static func accountMismatchSource(
        currentAccountKey: String,
        expectedAccountKey: String?,
        performanceSnapshot: PortfolioPerformanceSnapshot
    ) -> JDFinancePerformanceAccountMismatchSource? {
        let normalizedExpectedAccountKey = normalizedAccountKey(expectedAccountKey)
        let holdingsMismatch = normalizedExpectedAccountKey.map { $0 != currentAccountKey } ?? false
        let performanceAccountKeys = Set(
            ([performanceSnapshot.jdFinanceSync?.accountKey]
                + performanceSnapshot.days.compactMap { day in
                    day.source == .jdFinance ? day.sourceAccountKey : nil
                })
                .compactMap(normalizedAccountKey)
        )
        let performanceMismatch = performanceAccountKeys.count > 1
            || (performanceAccountKeys.first.map { $0 != currentAccountKey } ?? false)

        switch (holdingsMismatch, performanceMismatch) {
        case (true, true):
            return .holdingsBaselineAndPerformanceHistory
        case (true, false):
            return .holdingsBaseline
        case (false, true):
            return .performanceHistory
        case (false, false):
            return nil
        }
    }

    private static func normalizedAccountKey(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }

    private func existingHistory(
        from snapshot: PortfolioPerformanceSnapshot
    ) -> JDFinancePerformanceHistory {
        let days = snapshot.days.compactMap { day -> JDFinancePerformanceDay? in
            guard day.source == .jdFinance else { return nil }
            return JDFinancePerformanceDay(
                date: day.date,
                incomeAmount: day.profit,
                incomeRate: day.returnRate
            )
        }
        return JDFinancePerformanceHistory(
            days: days,
            coveredFrom: snapshot.jdFinanceSync?.coveredFrom ?? "",
            coveredThrough: snapshot.jdFinanceSync?.coveredThrough ?? "",
            isComplete: snapshot.jdFinanceSync?.isComplete ?? false
        )
    }
}

private extension Calendar {
    static var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
}
