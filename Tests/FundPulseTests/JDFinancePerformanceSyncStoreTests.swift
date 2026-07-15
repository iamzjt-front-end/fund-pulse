import XCTest
@testable import FundPulse

final class JDFinancePerformanceSyncStoreTests: XCTestCase {
    @MainActor
    func testSynchronizationBuildsPreviewWithoutWritingBeforeApply() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let now = try date("2026-07-15T12:00:00Z")
        let remote = JDFinancePerformanceHistory(
            days: [
                .init(date: "2026-07-13", incomeAmount: 8, incomeRate: 0.08),
                .init(date: "2026-07-14", incomeAmount: -2, incomeRate: -0.02)
            ],
            coveredFrom: "2000-01-01",
            coveredThrough: "2026-07-14",
            isComplete: true
        )
        let syncStore = JDFinancePerformanceSyncStore(
            fetchHistory: { _, _, _, _, _ in remote },
            now: { now }
        )

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_pin=fixture-user; pt_key=fixture-session"
        )

        XCTAssertFalse(syncStore.needsLogin)
        XCTAssertNil(syncStore.errorMessage)
        XCTAssertEqual(syncStore.plan?.insertedCount, 2)
        XCTAssertTrue(performanceStore.snapshot.days.isEmpty)

        XCTAssertTrue(syncStore.apply(to: performanceStore, overwriteConflicts: false))
        XCTAssertEqual(performanceStore.snapshot.days.map(\.date), ["2026-07-13", "2026-07-14"])
        XCTAssertTrue(performanceStore.snapshot.days.allSatisfy { $0.source == .jdFinance })
    }

    @MainActor
    func testMissingSessionShowsLoginStateWithoutCallingFetcher() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let syncStore = JDFinancePerformanceSyncStore(
            fetchHistory: { _, _, _, _, _ in
                XCTFail("Fetcher must not run without a usable JD session")
                return .empty
            }
        )

        await syncStore.synchronize(performanceStore: performanceStore, cookieHeader: nil)

        XCTAssertTrue(syncStore.needsLogin)
        XCTAssertNil(syncStore.plan)
        XCTAssertFalse(syncStore.isSyncing)
    }

    @MainActor
    func testDifferentEstablishedHoldingsAccountIsRejectedBeforeFetchingHistory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        var didFetch = false
        let syncStore = JDFinancePerformanceSyncStore(
            fetchHistory: { _, _, _, _, _ in
                didFetch = true
                return .empty
            }
        )
        let holdingsAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=holdings-account")
        )

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_key=session; pt_pin=another-account",
            expectedAccountKey: holdingsAccount
        )

        XCTAssertFalse(didFetch)
        XCTAssertTrue(syncStore.hasAccountMismatch)
        XCTAssertEqual(syncStore.accountMismatchSource, .holdingsBaseline)
        XCTAssertFalse(syncStore.canClearPerformanceHistoryForAccountMismatch)
        XCTAssertTrue(syncStore.accountMismatchSource?.involvesHoldingsBaseline == true)
        XCTAssertNil(syncStore.plan)
        XCTAssertTrue(performanceStore.snapshot.days.isEmpty)
    }

    @MainActor
    func testDifferentPerformanceHistoryAccountAllowsOnlyPerformanceHistoryRecovery() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let establishedAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=history-account")
        )
        try performanceStore.replace(
            PortfolioPerformanceSnapshot(
                jdFinanceSync: .init(
                    accountKey: establishedAccount,
                    coveredFrom: "2026-01-01",
                    coveredThrough: "2026-07-14",
                    lastSyncedAt: try date("2026-07-15T12:00:00Z"),
                    isComplete: true
                )
            )
        )
        var didFetch = false
        let syncStore = JDFinancePerformanceSyncStore(fetchHistory: { _, _, _, _, _ in
            didFetch = true
            return .empty
        })

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_key=session; pt_pin=another-account"
        )

        XCTAssertFalse(didFetch)
        XCTAssertEqual(syncStore.accountMismatchSource, .performanceHistory)
        XCTAssertTrue(syncStore.canClearPerformanceHistoryForAccountMismatch)
        XCTAssertFalse(syncStore.accountMismatchSource?.involvesHoldingsBaseline == true)
        XCTAssertTrue(syncStore.errorMessage?.contains("历史收益") == true)
    }

    @MainActor
    func testHoldingsAndPerformanceMismatchNeverSuggestsClearingOnlyPerformanceHistory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let establishedAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=established-account")
        )
        try performanceStore.replace(
            PortfolioPerformanceSnapshot(
                jdFinanceSync: .init(
                    accountKey: establishedAccount,
                    coveredFrom: "2026-01-01",
                    coveredThrough: "2026-07-14",
                    lastSyncedAt: try date("2026-07-15T12:00:00Z"),
                    isComplete: true
                )
            )
        )
        let syncStore = JDFinancePerformanceSyncStore(fetchHistory: { _, _, _, _, _ in
            XCTFail("Fetcher must not run while either account binding mismatches")
            return .empty
        })

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_key=session; pt_pin=another-account",
            expectedAccountKey: establishedAccount
        )

        XCTAssertEqual(
            syncStore.accountMismatchSource,
            .holdingsBaselineAndPerformanceHistory
        )
        XCTAssertFalse(syncStore.canClearPerformanceHistoryForAccountMismatch)
        XCTAssertTrue(syncStore.accountMismatchSource?.involvesHoldingsBaseline == true)
        XCTAssertTrue(syncStore.errorMessage?.contains("只清除历史收益无法") == true)
    }

    @MainActor
    func testApplyRechecksHoldingsAccountAfterPreview() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let remote = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-14", incomeAmount: 8, incomeRate: 0.08)],
            coveredFrom: "2026-07-14",
            coveredThrough: "2026-07-14",
            isComplete: true
        )
        let syncStore = JDFinancePerformanceSyncStore(fetchHistory: { _, _, _, _, _ in remote })

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_key=session; pt_pin=preview-account"
        )
        let changedAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=changed-account")
        )

        XCTAssertNotNil(syncStore.plan)
        XCTAssertFalse(
            syncStore.apply(
                to: performanceStore,
                overwriteConflicts: false,
                expectedAccountKey: changedAccount
            )
        )
        XCTAssertTrue(syncStore.hasAccountMismatch)
        XCTAssertEqual(syncStore.accountMismatchSource, .holdingsBaseline)
        XCTAssertFalse(syncStore.canClearPerformanceHistoryForAccountMismatch)
        XCTAssertNil(syncStore.plan)
        XCTAssertTrue(performanceStore.snapshot.days.isEmpty)
    }

    @MainActor
    func testApplyKeepsConfirmedLocalConflictUnlessUserOptsIn() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let localUpdate = try date("2026-07-14T12:00:00Z")
        try performanceStore.replace(
            PortfolioPerformanceSnapshot(
                trackingStartDate: "2026-07-14",
                localRecordingStartDate: "2026-07-14",
                days: [
                    PortfolioPerformanceDay(
                        date: "2026-07-14",
                        profit: 5,
                        returnRate: 0.05,
                        status: .confirmed,
                        updatedAt: localUpdate
                    )
                ]
            )
        )
        let remote = JDFinancePerformanceHistory(
            days: [.init(date: "2026-07-14", incomeAmount: 6, incomeRate: 0.06)],
            coveredFrom: "2026-07-14",
            coveredThrough: "2026-07-14",
            isComplete: true
        )
        let syncStore = JDFinancePerformanceSyncStore(
            fetchHistory: { _, _, _, _, _ in remote },
            now: { localUpdate.addingTimeInterval(60) }
        )

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_pin=fixture-user; pt_key=fixture-session"
        )
        XCTAssertEqual(syncStore.plan?.conflicts.count, 1)
        XCTAssertTrue(syncStore.apply(to: performanceStore, overwriteConflicts: false))
        XCTAssertEqual(performanceStore.snapshot.days.first?.profit, 5)
        XCTAssertEqual(performanceStore.snapshot.days.first?.source, .localQuote)

        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: "pt_pin=fixture-user; pt_key=fixture-session"
        )
        XCTAssertTrue(syncStore.apply(to: performanceStore, overwriteConflicts: true))
        XCTAssertEqual(performanceStore.snapshot.days.first?.profit, 6)
        XCTAssertEqual(performanceStore.snapshot.days.first?.source, .jdFinance)
    }

    @MainActor
    func testClearJDFinanceHistoryPreservesLocalRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioPerformanceStore(dataDirectory: directory)
        let update = try date("2026-07-15T12:00:00Z")
        try store.replace(
            PortfolioPerformanceSnapshot(
                trackingStartDate: "2026-07-13",
                localRecordingStartDate: "2026-07-15",
                days: [
                    PortfolioPerformanceDay(
                        date: "2026-07-13",
                        profit: 1,
                        returnRate: 0.01,
                        status: .confirmed,
                        source: .jdFinance,
                        sourceAccountKey: "jd-account-hash",
                        updatedAt: update
                    ),
                    PortfolioPerformanceDay(
                        date: "2026-07-15",
                        profit: 2,
                        returnRate: 0.02,
                        status: .confirmed,
                        updatedAt: update
                    )
                ],
                jdFinanceSync: .init(
                    accountKey: "jd-account-hash",
                    coveredFrom: "2000-01-01",
                    coveredThrough: "2026-07-14",
                    lastSyncedAt: update,
                    isComplete: true
                )
            )
        )

        try JDFinancePerformanceSyncStore.clearJDFinanceHistory(in: store)

        XCTAssertEqual(store.snapshot.days.map(\.date), ["2026-07-15"])
        XCTAssertEqual(store.snapshot.days.first?.source, .localQuote)
        XCTAssertEqual(store.snapshot.trackingStartDate, "2026-07-15")
        XCTAssertEqual(store.snapshot.localRecordingStartDate, "2026-07-15")
        XCTAssertNil(store.snapshot.jdFinanceSync)
    }

    func testPolicyUsesFullRangeInitiallyAndSevenDayOverlapAfterward() throws {
        let now = try date("2026-07-15T12:00:00Z")
        XCTAssertEqual(
            JDFinancePerformanceSyncPolicy.startDate(for: .empty, now: now),
            "2000-01-01"
        )

        let snapshot = PortfolioPerformanceSnapshot(
            jdFinanceSync: .init(
                accountKey: "jd-account-hash",
                coveredFrom: "2000-01-01",
                coveredThrough: "2026-07-14",
                lastSyncedAt: now,
                isComplete: true
            )
        )
        XCTAssertEqual(
            JDFinancePerformanceSyncPolicy.startDate(for: snapshot, now: now),
            "2026-07-07"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-performance-sync-\(UUID().uuidString)")
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
