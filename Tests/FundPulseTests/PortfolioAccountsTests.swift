import XCTest
@testable import FundPulse

final class PortfolioAccountsTests: XCTestCase {
    func testAccountBarIsShownForAnyLoadedAccountCount() {
        XCTAssertFalse(PortfolioAccountPresentation.showsAccountBar(accountCount: 0))
        XCTAssertTrue(PortfolioAccountPresentation.showsAccountBar(accountCount: 1))
        XCTAssertTrue(PortfolioAccountPresentation.showsAccountBar(accountCount: 2))
    }

    @MainActor
    func testFirstLoadRegistersLegacyPortfolioWithoutMovingOrRewritingIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacySnapshot = snapshot(
            code: "000001",
            totalAmount: 12_345.67,
            holdingIncome: 345.67,
            todayIncome: 12.34
        )
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        try repository.save(legacySnapshot)
        let originalBytes = try Data(contentsOf: repository.dataFileURL)

        let accountsStore = PortfolioAccountsStore(dataDirectory: directory)
        accountsStore.load()

        XCTAssertEqual(accountsStore.loadState, .loaded)
        XCTAssertEqual(accountsStore.accounts, [
            PortfolioAccount.defaultAccount(createdAt: accountsStore.accounts[0].createdAt)
        ])
        XCTAssertEqual(accountsStore.selection, .account(PortfolioAccount.defaultAccountID))
        XCTAssertEqual(accountsStore.defaultStore.snapshot, legacySnapshot)
        XCTAssertEqual(accountsStore.dataDirectory(for: accountsStore.accounts[0]), directory)
        XCTAssertEqual(try Data(contentsOf: repository.dataFileURL), originalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountsStore.registryFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountsStore.accountsDataDirectory.path))
    }

    @MainActor
    func testNewAccountsPersistInDistinctDirectoriesAndRestoreSelection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let accountsStore = PortfolioAccountsStore(dataDirectory: directory)
        accountsStore.load()
        let securities = try accountsStore.createAccount(name: "证券账户", kind: .onExchange)
        let pension = try accountsStore.createAccount(name: "长期定投", kind: .offExchange)

        let securitiesDirectory = accountsStore.dataDirectory(for: securities)
        let pensionDirectory = accountsStore.dataDirectory(for: pension)
        XCTAssertNotEqual(securitiesDirectory, pensionDirectory)
        XCTAssertNotEqual(securitiesDirectory, directory)
        XCTAssertNotEqual(pensionDirectory, directory)
        XCTAssertEqual(accountsStore.store(for: securities.id)?.dataDirectory, securitiesDirectory)
        XCTAssertEqual(accountsStore.store(for: pension.id)?.dataDirectory, pensionDirectory)
        XCTAssertEqual(accountsStore.store(for: securities.id)?.accountKind, .onExchange)
        XCTAssertEqual(accountsStore.store(for: pension.id)?.accountKind, .offExchange)
        XCTAssertTrue(FileManager.default.fileExists(atPath: securitiesDirectory.appending(path: "portfolio.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pensionDirectory.appending(path: "portfolio.json").path))

        try JSONPortfolioRepository(dataDirectory: securitiesDirectory).save(
            snapshot(code: "510300", totalAmount: 10_000, holdingIncome: 100, todayIncome: 20)
        )
        try JSONPortfolioRepository(dataDirectory: pensionDirectory).save(
            snapshot(code: "000002", totalAmount: 20_000, holdingIncome: 500, todayIncome: -10)
        )
        accountsStore.select(.all)

        let reloaded = PortfolioAccountsStore(dataDirectory: directory)
        reloaded.load()

        XCTAssertEqual(reloaded.selection, .all)
        XCTAssertEqual(reloaded.focusedAccount.id, pension.id)
        XCTAssertEqual(reloaded.store(for: securities.id)?.snapshot.funds.map(\.code), ["510300"])
        XCTAssertEqual(reloaded.store(for: pension.id)?.snapshot.funds.map(\.code), ["000002"])
        XCTAssertTrue(reloaded.defaultStore.snapshot.funds.isEmpty)
    }

    @MainActor
    func testRenameAndOrderingPersistAcrossReload() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let accountsStore = PortfolioAccountsStore(dataDirectory: directory)
        accountsStore.load()
        let first = try accountsStore.createAccount(name: "账户 A", kind: .offExchange)
        let second = try accountsStore.createAccount(name: "账户 B", kind: .onExchange)

        try accountsStore.renameAccount(id: first.id, name: "京东基金")
        try accountsStore.moveAccount(id: second.id, by: -1)

        let reloaded = PortfolioAccountsStore(dataDirectory: directory)
        reloaded.load()
        XCTAssertEqual(reloaded.accounts.map(\.id), [PortfolioAccount.defaultAccountID, second.id, first.id])
        XCTAssertEqual(reloaded.account(id: first.id)?.name, "京东基金")
        XCTAssertEqual(reloaded.account(id: second.id)?.kind, .onExchange)
    }

    @MainActor
    func testDuplicateAccountNamesAreRejectedCaseInsensitively() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let accountsStore = PortfolioAccountsStore(dataDirectory: directory)
        accountsStore.load()
        _ = try accountsStore.createAccount(name: "Broker", kind: .onExchange)

        XCTAssertThrowsError(try accountsStore.createAccount(name: "broker", kind: .offExchange)) { error in
            XCTAssertEqual(error as? PortfolioAccountsStoreError, .duplicateName)
        }
    }

    @MainActor
    func testArchiveMovesAccountDataToRecoverableDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 1_787_500_000)
        let accountsStore = PortfolioAccountsStore(dataDirectory: directory, now: { now })
        accountsStore.load()
        let account = try accountsStore.createAccount(name: "可归档账户", kind: .onExchange)
        let sourceDirectory = accountsStore.dataDirectory(for: account)
        let sourcePortfolio = sourceDirectory.appending(path: "portfolio.json")
        let originalBytes = try Data(contentsOf: sourcePortfolio)

        try accountsStore.archiveAccount(id: account.id)

        XCTAssertNil(accountsStore.account(id: account.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceDirectory.path))
        let archiveRoot = directory.appending(path: "Archived Accounts")
        let archivedDirectories = try FileManager.default.contentsOfDirectory(
            at: archiveRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(archivedDirectories.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: archivedDirectories[0].appending(path: "portfolio.json")),
            originalBytes
        )
        XCTAssertThrowsError(try accountsStore.archiveAccount(id: PortfolioAccount.defaultAccountID)) { error in
            XCTAssertEqual(error as? PortfolioAccountsStoreError, .cannotArchiveDefaultAccount)
        }
    }

    @MainActor
    func testUnreadableRegistryDoesNotOverwriteLegacyPortfolio() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let repository = JSONPortfolioRepository(dataDirectory: directory)
        try repository.save(snapshot(code: "000003", totalAmount: 300, holdingIncome: 30, todayIncome: 3))
        let originalPortfolioBytes = try Data(contentsOf: repository.dataFileURL)
        let registryURL = directory.appending(path: "accounts.json")
        let invalidRegistryBytes = Data("{do-not-overwrite".utf8)
        try invalidRegistryBytes.write(to: registryURL, options: .atomic)

        let accountsStore = PortfolioAccountsStore(dataDirectory: directory)
        accountsStore.load()

        guard case .failed = accountsStore.loadState else {
            return XCTFail("Expected a failed accounts registry load")
        }
        XCTAssertEqual(accountsStore.defaultStore.snapshot.funds.map(\.code), ["000003"])
        XCTAssertEqual(try Data(contentsOf: repository.dataFileURL), originalPortfolioBytes)
        XCTAssertEqual(try Data(contentsOf: registryURL), invalidRegistryBytes)
        XCTAssertThrowsError(try accountsStore.createAccount(name: "不会创建", kind: .offExchange))
        XCTAssertEqual(try Data(contentsOf: registryURL), invalidRegistryBytes)
    }

    func testAggregateSummaryUsesCombinedPrincipalsInsteadOfAveragingRates() {
        let first = snapshot(
            code: "A",
            totalAmount: 110,
            holdingIncome: 10,
            todayIncome: 1,
            pendingCount: 1
        )
        let second = snapshot(
            code: "B",
            totalAmount: 210,
            holdingIncome: 10,
            todayIncome: -1,
            pendingCount: 2
        )

        let summary = PortfolioAccountsSummary.aggregating([first, second])

        XCTAssertEqual(summary.totalAmount, 320, accuracy: 0.0001)
        XCTAssertEqual(summary.holdingIncome, 20, accuracy: 0.0001)
        XCTAssertEqual(summary.holdingIncomeRate, 20 / 300 * 100, accuracy: 0.0001)
        XCTAssertEqual(summary.todayIncome, 0, accuracy: 0.0001)
        XCTAssertEqual(summary.todayIncomeRate, 0, accuracy: 0.0001)
        XCTAssertEqual(summary.pendingCount, 3)
        XCTAssertEqual(summary.fundCount, 2)
        XCTAssertEqual(summary.accountCount, 2)
    }

    func testJDFinanceTargetResolverPrefersExplicitThenFocusedThenBoundAccount() {
        let accounts = [
            PortfolioAccount(
                id: "off-a",
                name: "长期定投",
                kind: .offExchange,
                createdAt: .now,
                directoryName: "off-a"
            ),
            PortfolioAccount(
                id: "on-a",
                name: "证券账户",
                kind: .onExchange,
                createdAt: .now,
                directoryName: "on-a"
            ),
            PortfolioAccount(
                id: "off-b",
                name: "京东基金",
                kind: .offExchange,
                createdAt: .now,
                directoryName: "off-b"
            )
        ]

        XCTAssertEqual(
            JDFinanceTargetResolver.resolve(
                accounts: accounts,
                focusedAccountID: "on-a",
                preferredAccountID: "off-b",
                boundAccountIDs: ["off-a"]
            )?.id,
            "off-b"
        )
        XCTAssertEqual(
            JDFinanceTargetResolver.resolve(
                accounts: accounts,
                focusedAccountID: "off-a",
                preferredAccountID: nil,
                boundAccountIDs: ["off-b"]
            )?.id,
            "off-a"
        )
        XCTAssertEqual(
            JDFinanceTargetResolver.resolve(
                accounts: accounts,
                focusedAccountID: "on-a",
                preferredAccountID: nil,
                boundAccountIDs: ["off-b"]
            )?.id,
            "off-b"
        )
    }

    func testJDFinanceTargetResolverLeavesMultipleUnboundAccountsUnselected() {
        let accounts = [
            PortfolioAccount(
                id: "off-a",
                name: "场外一",
                kind: .offExchange,
                createdAt: .now,
                directoryName: "off-a"
            ),
            PortfolioAccount(
                id: "off-b",
                name: "场外二",
                kind: .offExchange,
                createdAt: .now,
                directoryName: "off-b"
            )
        ]

        XCTAssertNil(
            JDFinanceTargetResolver.resolve(
                accounts: accounts,
                focusedAccountID: nil,
                preferredAccountID: nil,
                boundAccountIDs: []
            )
        )
    }

    func testSingleEffectiveAccountKeepsItsPublishedTodayIncomeRate() {
        var active = snapshot(
            code: "A",
            totalAmount: 290_183.23,
            holdingIncome: -35_811.12,
            todayIncome: -6_705.64
        )
        active.todayIncomeRate = -2.40
        let empty = PortfolioSnapshot.empty

        let summary = PortfolioAccountsSummary.aggregating([active, empty])

        XCTAssertEqual(summary.todayIncomeRate, -2.40, accuracy: 0.0001)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-accounts-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func snapshot(
        code: String,
        totalAmount: Double,
        holdingIncome: Double,
        todayIncome: Double,
        pendingCount: Int = 0
    ) -> PortfolioSnapshot {
        PortfolioSnapshot(
            updateTime: Date(timeIntervalSince1970: 1_787_500_000),
            totalAmount: totalAmount,
            holdingIncome: holdingIncome,
            holdingIncomeRate: 0,
            todayIncome: todayIncome,
            todayIncomeRate: 0,
            pendingCount: pendingCount,
            funds: [
                FundPosition(
                    code: code,
                    name: "测试基金 \(code)",
                    dateText: "08-24 15:00",
                    todayIncome: todayIncome,
                    todayRate: 0,
                    holdingIncome: holdingIncome,
                    holdingRate: 0,
                    currentAmount: totalAmount,
                    status: .holding,
                    isUpdated: true
                )
            ],
            migration: nil
        )
    }
}
