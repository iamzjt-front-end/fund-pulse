import XCTest
@testable import FundPulse

final class AppStoreFeatureIntegrationTests: XCTestCase {
    @MainActor
    func testPortfolioBackupRoundTripCarriesPerformanceHistoryWithoutEmbeddingItInLivePortfolio() throws {
        let sourceDirectory = temporaryDirectory()
        let destinationDirectory = temporaryDirectory()
        let exportURL = temporaryDirectory().appending(path: "fund-pulse-backup.json")
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: destinationDirectory)
            try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent())
        }

        let sourcePerformance = PortfolioPerformanceStore(dataDirectory: sourceDirectory)
        try sourcePerformance.replace(performanceSnapshot())
        try seedPortfolio(portfolioSnapshot(), in: sourceDirectory)
        let sourceStore = PortfolioStore(
            dataDirectory: sourceDirectory,
            performanceStore: sourcePerformance
        )
        sourceStore.load()

        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sourceStore.exportPortfolio(to: exportURL)

        let exported = try decodePortfolio(at: exportURL)
        XCTAssertEqual(exported.portfolioPerformanceHistory, performanceSnapshot())

        let destinationPerformance = PortfolioPerformanceStore(dataDirectory: destinationDirectory)
        let destinationStore = PortfolioStore(
            dataDirectory: destinationDirectory,
            performanceStore: destinationPerformance
        )
        try destinationStore.importPortfolio(from: exportURL)

        XCTAssertEqual(destinationStore.snapshot.funds.map(\.code), ["DEMO001"])
        XCTAssertEqual(destinationPerformance.snapshot, performanceSnapshot())
        XCTAssertNil(try decodePortfolio(at: destinationStore.dataFileURL).portfolioPerformanceHistory)
    }

    @MainActor
    func testLegacyImportClearsHistoryFromThePreviousPortfolio() throws {
        let directory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importURL = importDirectory.appending(path: "legacy.json")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: importDirectory)
        }

        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        try performanceStore.replace(performanceSnapshot())
        let store = PortfolioStore(dataDirectory: directory, performanceStore: performanceStore)
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        try encodedPortfolio(portfolioSnapshot()).write(to: importURL, options: .atomic)

        try store.importPortfolio(from: importURL)

        XCTAssertEqual(store.snapshot.funds.map(\.code), ["DEMO001"])
        XCTAssertEqual(performanceStore.snapshot, .empty)
    }

    @MainActor
    func testClearAllHoldingsAlsoClearsPerformanceHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        try performanceStore.replace(performanceSnapshot())
        try seedPortfolio(portfolioSnapshot(), in: directory)
        let store = PortfolioStore(dataDirectory: directory, performanceStore: performanceStore)
        store.load()

        try store.clearAllHoldings()

        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertEqual(performanceStore.snapshot, .empty)
    }

    @MainActor
    func testFailedClearKeepsUnreadablePerformanceFileBytesUntouched() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try seedPortfolio(portfolioSnapshot(), in: directory)

        let performanceURL = directory.appending(path: "portfolio-performance.json")
        let unreadableData = Data("{existing-history-must-survive".utf8)
        try unreadableData.write(to: performanceURL, options: .atomic)
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let store = PortfolioStore(dataDirectory: directory, performanceStore: performanceStore)
        store.load()
        let originalSnapshot = store.snapshot

        try FileManager.default.removeItem(at: store.dataFileURL)
        try FileManager.default.createDirectory(
            at: store.dataFileURL,
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(try store.clearAllHoldings())
        XCTAssertEqual(store.snapshot, originalSnapshot)
        XCTAssertTrue(performanceStore.hasUnreadablePersistedData)
        XCTAssertEqual(try Data(contentsOf: performanceURL), unreadableData)
    }

    @MainActor
    func testFailedImportNeverOverwritesAnUnreadableExistingPerformanceFile() throws {
        let directory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importURL = importDirectory.appending(path: "future-backup.json")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: importDirectory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        let performanceURL = directory.appending(path: "portfolio-performance.json")
        let unreadableData = Data("{existing-history-must-survive".utf8)
        try unreadableData.write(to: performanceURL, options: .atomic)
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let store = PortfolioStore(dataDirectory: directory, performanceStore: performanceStore)
        store.load()

        var backup = portfolioSnapshot()
        backup.portfolioPerformanceHistory = PortfolioPerformanceSnapshot(
            schemaVersion: PortfolioPerformanceSnapshot.currentSchemaVersion + 1
        )
        try encodedPortfolio(backup).write(to: importURL, options: .atomic)

        XCTAssertThrowsError(try store.importPortfolio(from: importURL))
        XCTAssertTrue(performanceStore.hasUnreadablePersistedData)
        XCTAssertEqual(try Data(contentsOf: performanceURL), unreadableData)
    }

    func testNewChildPanelRoutesAreStableWithoutASelectedFund() {
        let routes: [ChildPanelRoute] = [
            .privacyDisclaimer(origin: .settings),
            .onboarding(origin: .firstLaunch),
            .sampleExperience(origin: .firstLaunch),
            .portfolioPerformance,
            .jdFinancePerformanceSync,
            .todayIncomeRanking(.amount),
            .onboardingAddFund(origin: .firstLaunch)
        ]

        for route in routes {
            XCTAssertNil(route.selectedFundCode)
            XCTAssertEqual(
                ChildPanelRouteResolver.disposition(for: route, in: .empty),
                .available
            )
        }
    }

    func testBothJDFinanceSyncRoutesOwnTheLoginPanelLifecycle() {
        XCTAssertTrue(ChildPanelRoute.jdFinanceSync.ownsJDFinanceLoginPanel)
        XCTAssertTrue(ChildPanelRoute.jdFinancePerformanceSync.ownsJDFinanceLoginPanel)
        XCTAssertFalse(ChildPanelRoute.portfolioPerformance.ownsJDFinanceLoginPanel)
        XCTAssertFalse(ChildPanelRoute.settings.ownsJDFinanceLoginPanel)
    }

    func testHoldingPerformanceUsesExactlyTheRequestedThreeModules() {
        XCTAssertEqual(
            HoldingPerformancePage.allCases.map(\.title),
            ["持有收益排行", "收益曲线", "收益日历"]
        )
        XCTAssertEqual(
            IncomeRankingMetric.allCases.map(\.holdingPickerTitle),
            ["按金额", "按收益率"]
        )
    }

    func testHoldingPerformanceHeaderMatchesTheSelectedRankingMetric() {
        XCTAssertEqual(
            HoldingPerformancePresentation.rankingSubtitle(
                holdingCount: 2,
                holdingIncome: -120,
                holdingIncomeRate: -5.75,
                metric: .rate,
                hidesAmounts: false
            ),
            "2 只持仓 · -5.75%"
        )
        XCTAssertEqual(
            HoldingPerformancePresentation.rankingSubtitle(
                holdingCount: 2,
                holdingIncome: -120,
                holdingIncomeRate: -5.75,
                metric: .amount,
                hidesAmounts: true
            ),
            "2 只持仓 · ••••"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-app-store-feature-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func portfolioSnapshot() -> PortfolioSnapshot {
        PortfolioSnapshot(
            updateTime: Date(timeIntervalSince1970: 1_752_552_000),
            totalAmount: 10_120,
            holdingIncome: 120,
            holdingIncomeRate: 1.2,
            todayIncome: 20,
            todayIncomeRate: 0.2,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "DEMO001",
                    name: "测试基金",
                    dateText: "07-15 15:00",
                    todayIncome: 20,
                    todayRate: 0.2,
                    holdingRate: 1.2,
                    status: .holding,
                    isUpdated: true
                )
            ],
            migration: nil
        )
    }

    private func performanceSnapshot() -> PortfolioPerformanceSnapshot {
        PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-15",
            localRecordingStartDate: "2026-07-15",
            days: [
                PortfolioPerformanceDay(
                    date: "2026-07-15",
                    profit: 20,
                    returnRate: 0.2,
                    status: .confirmed,
                    updatedAt: Date(timeIntervalSince1970: 1_752_552_000)
                )
            ]
        )
    }

    private func seedPortfolio(_ snapshot: PortfolioSnapshot, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encodedPortfolio(snapshot).write(
            to: directory.appending(path: "portfolio.json"),
            options: .atomic
        )
    }

    private func encodedPortfolio(_ snapshot: PortfolioSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func decodePortfolio(at url: URL) throws -> PortfolioSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortfolioSnapshot.self, from: Data(contentsOf: url))
    }
}
