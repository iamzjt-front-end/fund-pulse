import XCTest
@testable import FundPulse

final class PortfolioPerformanceMergeTests: XCTestCase {
    func testPlanBackfillsUpgradesAndKeepsConfirmedLocalConflictExplicit() throws {
        let localUpdate = try date("2026-07-12T12:00:00Z")
        let syncTime = try date("2026-07-15T12:00:00Z")
        let snapshot = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-10",
            localRecordingStartDate: "2026-07-10",
            days: [
                localDay("2026-07-10", profit: 5, status: .confirmed, updatedAt: localUpdate),
                localDay("2026-07-11", profit: 2, status: .estimated, updatedAt: localUpdate),
                localDay("2026-07-12", profit: 4, status: .confirmed, updatedAt: localUpdate)
            ]
        )
        let history = JDFinancePerformanceHistory(
            days: [
                .init(date: "2026-07-09", incomeAmount: 1, incomeRate: 0.01),
                .init(date: "2026-07-10", incomeAmount: 6, incomeRate: 0.06),
                .init(date: "2026-07-11", incomeAmount: 3, incomeRate: 0.03),
                .init(date: "2026-07-12", incomeAmount: 4, incomeRate: 0.04),
                .init(date: "2026-07-13", incomeAmount: 0, incomeRate: 0)
            ],
            coveredFrom: "2026-07-09",
            coveredThrough: "2026-07-14",
            isComplete: true
        )

        let plan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: snapshot,
            syncedAt: syncTime
        )

        XCTAssertEqual(plan.insertedCount, 1)
        XCTAssertEqual(plan.upgradedCount, 1)
        XCTAssertEqual(plan.updatedCount, 0)
        XCTAssertEqual(plan.unchangedCount, 1)
        XCTAssertEqual(plan.zeroValueSkippedCount, 1)
        XCTAssertEqual(plan.conflicts.map(\.date), ["2026-07-10"])
        XCTAssertEqual(plan.selectedDayChangeCount(overwriteConflicts: false), 2)
        XCTAssertEqual(plan.selectedDayChangeCount(overwriteConflicts: true), 3)
        XCTAssertTrue(plan.canApply(overwriteConflicts: false))

        let merged = try PortfolioPerformanceMergePlanner.applying(
            plan,
            to: snapshot,
            overwriteConflicts: false
        )

        XCTAssertEqual(merged.days.map(\.date), ["2026-07-09", "2026-07-10", "2026-07-11", "2026-07-12"])
        XCTAssertEqual(merged.days.first(where: { $0.date == "2026-07-10" })?.profit, 5)
        XCTAssertEqual(merged.days.first(where: { $0.date == "2026-07-10" })?.source, .localQuote)
        XCTAssertEqual(merged.days.first(where: { $0.date == "2026-07-11" })?.profit, 3)
        XCTAssertEqual(merged.days.first(where: { $0.date == "2026-07-11" })?.source, .jdFinance)
        XCTAssertEqual(merged.trackingStartDate, "2026-07-09")
        XCTAssertEqual(merged.localRecordingStartDate, "2026-07-10")
        XCTAssertEqual(merged.jdFinanceSync?.accountKey, "jd-account-a")
        XCTAssertEqual(merged.jdFinanceSync?.coveredThrough, "2026-07-14")
    }

    func testConflictOverrideIsExplicitAndRepeatedSyncIsIdempotent() throws {
        let localUpdate = try date("2026-07-12T12:00:00Z")
        let syncTime = try date("2026-07-15T12:00:00Z")
        let snapshot = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-10",
            localRecordingStartDate: "2026-07-10",
            days: [localDay("2026-07-10", profit: 5, status: .confirmed, updatedAt: localUpdate)]
        )
        let history = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-10", incomeAmount: 6, incomeRate: nil)],
            coveredFrom: "2026-07-10",
            coveredThrough: "2026-07-10",
            isComplete: true
        )
        let firstPlan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: snapshot,
            syncedAt: syncTime
        )

        let overwritten = try PortfolioPerformanceMergePlanner.applying(
            firstPlan,
            to: snapshot,
            overwriteConflicts: true
        )
        XCTAssertEqual(overwritten.days.first?.profit, 6)
        XCTAssertNil(overwritten.days.first?.returnRate)
        XCTAssertEqual(overwritten.days.first?.source, .jdFinance)

        let repeatedPlan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: overwritten,
            syncedAt: syncTime.addingTimeInterval(60)
        )
        XCTAssertFalse(repeatedPlan.hasDayChanges)
        XCTAssertTrue(repeatedPlan.conflicts.isEmpty)
        XCTAssertEqual(repeatedPlan.unchangedCount, 1)
    }

    func testConflictOnlyPlanBecomesANoopAfterSavingCoverageWithoutOverwrite() throws {
        let localUpdate = try date("2026-07-12T12:00:00Z")
        let firstSync = try date("2026-07-15T12:00:00Z")
        let snapshot = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-10",
            localRecordingStartDate: "2026-07-10",
            days: [localDay("2026-07-10", profit: 5, status: .confirmed, updatedAt: localUpdate)]
        )
        let history = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-10", incomeAmount: 6, incomeRate: nil)],
            coveredFrom: "2026-07-10",
            coveredThrough: "2026-07-10",
            isComplete: true
        )
        let firstPlan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: snapshot,
            syncedAt: firstSync
        )

        XCTAssertEqual(firstPlan.selectedDayChangeCount(overwriteConflicts: false), 0)
        XCTAssertTrue(firstPlan.canApply(overwriteConflicts: false))
        let preserved = try PortfolioPerformanceMergePlanner.applying(
            firstPlan,
            to: snapshot,
            overwriteConflicts: false
        )
        XCTAssertEqual(preserved.days.first?.source, .localQuote)

        let repeatedPlan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: preserved,
            syncedAt: firstSync.addingTimeInterval(60)
        )
        XCTAssertEqual(repeatedPlan.conflicts.count, 1)
        XCTAssertFalse(repeatedPlan.metadataChanged)
        XCTAssertFalse(repeatedPlan.canApply(overwriteConflicts: false))
    }

    func testSameAccountJDFinanceCorrectionUpdatesWithoutConflict() throws {
        let oldSync = try date("2026-07-14T12:00:00Z")
        let newSync = try date("2026-07-15T12:00:00Z")
        let snapshot = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-10",
            days: [
                PortfolioPerformanceDay(
                    date: "2026-07-10",
                    profit: 5,
                    returnRate: 0.05,
                    status: .confirmed,
                    source: .jdFinance,
                    sourceAccountKey: "jd-account-a",
                    updatedAt: oldSync
                )
            ],
            jdFinanceSync: .init(
                accountKey: "jd-account-a",
                coveredFrom: "2026-07-10",
                coveredThrough: "2026-07-10",
                lastSyncedAt: oldSync,
                isComplete: true
            )
        )
        let history = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-10", incomeAmount: 5.5, incomeRate: 0.055)],
            coveredFrom: "2026-07-10",
            coveredThrough: "2026-07-10",
            isComplete: true
        )

        let plan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: snapshot,
            syncedAt: newSync
        )

        XCTAssertEqual(plan.updatedCount, 1)
        XCTAssertTrue(plan.conflicts.isEmpty)
        let merged = try PortfolioPerformanceMergePlanner.applying(plan, to: snapshot)
        XCTAssertEqual(merged.days.first?.profit, 5.5)
        XCTAssertEqual(merged.days.first?.updatedAt, newSync)
    }

    func testSameAccountJDFinanceCanCorrectANonzeroDayToZero() throws {
        let oldSync = try date("2026-07-14T12:00:00Z")
        let newSync = try date("2026-07-15T12:00:00Z")
        let snapshot = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-10",
            days: [
                PortfolioPerformanceDay(
                    date: "2026-07-10",
                    profit: 5,
                    returnRate: 0.05,
                    status: .confirmed,
                    source: .jdFinance,
                    sourceAccountKey: "jd-account-a",
                    updatedAt: oldSync
                )
            ],
            jdFinanceSync: .init(
                accountKey: "jd-account-a",
                coveredFrom: "2026-07-10",
                coveredThrough: "2026-07-10",
                lastSyncedAt: oldSync,
                isComplete: true
            )
        )
        let history = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-10", incomeAmount: 0, incomeRate: 0)],
            coveredFrom: "2026-07-10",
            coveredThrough: "2026-07-10",
            isComplete: true
        )

        let plan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: snapshot,
            syncedAt: newSync
        )

        XCTAssertEqual(plan.updatedCount, 1)
        XCTAssertEqual(plan.zeroValueSkippedCount, 0)
        let merged = try PortfolioPerformanceMergePlanner.applying(plan, to: snapshot)
        XCTAssertEqual(merged.days.first?.profit, 0)
        XCTAssertEqual(merged.days.first?.returnRate, 0)
    }

    func testDifferentJDFinanceAccountIsRejectedBeforePlanning() throws {
        let syncTime = try date("2026-07-15T12:00:00Z")
        let snapshot = PortfolioPerformanceSnapshot(
            jdFinanceSync: .init(
                accountKey: "jd-account-a",
                coveredFrom: "2026-01-01",
                coveredThrough: "2026-07-14",
                lastSyncedAt: syncTime,
                isComplete: true
            )
        )
        let history = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-14", incomeAmount: 1, incomeRate: 0.01)],
            coveredFrom: "2026-07-14",
            coveredThrough: "2026-07-14",
            isComplete: true
        )

        XCTAssertThrowsError(
            try PortfolioPerformanceMergePlanner.plan(
                history: history,
                accountKey: "jd-account-b",
                in: snapshot,
                syncedAt: syncTime
            )
        ) { error in
            XCTAssertEqual(error as? PortfolioPerformanceMergeError, .accountMismatch)
        }
    }

    @MainActor
    func testStoreMergePersistsMetadataEvenWhenHistoryContainsOnlyZeroRows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-merge-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioPerformanceStore(dataDirectory: directory)
        let syncTime = try date("2026-07-15T12:00:00Z")
        let history = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-14", incomeAmount: 0, incomeRate: 0)],
            coveredFrom: "2015-01-01",
            coveredThrough: "2026-07-14",
            isComplete: true
        )
        let plan = try PortfolioPerformanceMergePlanner.plan(
            history: history,
            accountKey: "jd-account-a",
            in: store.snapshot,
            syncedAt: syncTime
        )

        XCTAssertTrue(try store.applyJDFinancePerformanceMerge(plan))
        XCTAssertTrue(store.snapshot.days.isEmpty)
        XCTAssertEqual(store.snapshot.jdFinanceSync?.coveredFrom, "2015-01-01")

        let reloaded = PortfolioPerformanceStore(dataDirectory: directory)
        XCTAssertEqual(reloaded.snapshot.jdFinanceSync, store.snapshot.jdFinanceSync)
    }

    private func localDay(
        _ date: String,
        profit: Double,
        status: PortfolioPerformanceRecordStatus,
        updatedAt: Date
    ) -> PortfolioPerformanceDay {
        PortfolioPerformanceDay(
            date: date,
            profit: profit,
            returnRate: profit / 100,
            status: status,
            updatedAt: updatedAt
        )
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
