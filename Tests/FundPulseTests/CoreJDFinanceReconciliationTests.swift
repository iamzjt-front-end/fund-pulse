import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    @MainActor
    func testJDFinanceSyncStoreBuildsPreviewWhenCookieIsAvailable() async throws {
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinanceHoldingsResponse
        ])
        let syncStore = JDFinanceHoldingsSyncStore(service: service)
        let portfolioStore = PortfolioStore(
            dataDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )

        XCTAssertNil(syncStore.lastError)
        XCTAssertNil(syncStore.errorMessage)
        let preview = try XCTUnwrap(syncStore.preview)
        XCTAssertEqual(preview.remoteSnapshot.products.count, 2)
        XCTAssertEqual(syncStore.statusMessage, "已生成同步预览")
    }

    @MainActor
    func testJDFinanceHoldingsPreviewCannotApplyAfterAccountAnchorChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-preview-account-race-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let portfolioStore = PortfolioStore(
            dataDirectory: directory,
            performanceStore: performanceStore
        )
        portfolioStore.load()
        let syncStore = JDFinanceHoldingsSyncStore(
            service: jdFinanceServiceWithMockResponses([
                JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinanceHoldingsResponse
            ])
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=session; pt_pin=preview-account"
        )
        XCTAssertFalse(try XCTUnwrap(syncStore.preview).newHoldings.isEmpty)
        let originalSnapshot = portfolioStore.snapshot
        let differentAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=different-history-account")
        )
        try performanceStore.replace(
            PortfolioPerformanceSnapshot(
                jdFinanceSync: .init(
                    accountKey: differentAccount,
                    coveredFrom: "2026-01-01",
                    coveredThrough: "2026-07-14",
                    lastSyncedAt: .now,
                    isComplete: true
                )
            )
        )

        await syncStore.applyNewHoldings(to: portfolioStore)

        XCTAssertEqual(portfolioStore.snapshot, originalSnapshot)
        XCTAssertEqual(syncStore.errorMessage, PortfolioStoreError.jdFinanceAccountMismatch.localizedDescription)
        XCTAssertEqual(syncStore.statusMessage, "同步失败")
    }

    func testJDFinanceSyncPreviewResolvesUnresolvedCodeByMatchingLocalName() {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 7_632.07,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "113687",
                    code: "",
                    codeResolution: .unresolved,
                    name: "西部利得中证人工智能主题指数增强C",
                    totalAmount: 7_632.07,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: nil,
                    holdRate: nil,
                    transactionTip: nil
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 7_632.07,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "011833",
                    name: "西部利得人工智能主题指数增强C",
                    dateText: "07-04 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    currentAmount: 7_632.065,
                    status: .holding,
                    isUpdated: true
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(preview.remoteSnapshot.products.map(\.code), ["011833"])
        XCTAssertEqual(preview.remoteSnapshot.products.map(\.codeResolution), [.nameMatched])
        XCTAssertTrue(preview.newHoldings.isEmpty)
        XCTAssertFalse(preview.missingLocalHoldings.contains { $0.code == "011833" })
    }

    func testJDFinanceSyncPreviewKeepsUnresolvedHoldingOutOfWritableChanges() {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 14_019.17,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: -1_980.83,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "113387",
                    code: "",
                    codeResolution: .unresolved,
                    name: "华商均衡成长混合C",
                    totalAmount: 14_019.17,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: -1_980.83,
                    holdRate: nil,
                    transactionTip: nil
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertTrue(preview.newHoldings.isEmpty)
        XCTAssertTrue(preview.changedHoldings.isEmpty)
        XCTAssertTrue(preview.pendingNotices.isEmpty)
        XCTAssertEqual(preview.unresolvedHoldings.map(\.skuID), ["113387"])
        XCTAssertEqual(preview.unresolvedHoldings.first?.name, "华商均衡成长混合C")
        XCTAssertFalse(preview.hasActionableChanges)
    }

    func testJDFinanceSyncPreviewFlagsAmountDifferenceEvenWithTransactionTip() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 118_674.41,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: -1_325.58,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1022485",
                    code: "022485",
                    name: "国金中证A500指数增强A",
                    totalAmount: 118_674.41,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: -1_325.58,
                    holdRate: -0.54,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：2笔买入中合计31112.00元",
                        action: .buy,
                        tradeCount: 2,
                        totalAmount: 31_112
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 243_122.42,
            holdingIncome: -1_325.58,
            holdingIncomeRate: -0.54,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "022485",
                    name: "国金中证A500指数增强A",
                    dateText: "07-08 11:23",
                    todayIncome: 777.36,
                    todayRate: 0.32,
                    holdingIncome: -1_325.58,
                    holdingRate: -0.54,
                    currentAmount: 243_122.42,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 244_448
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        let difference = try XCTUnwrap(preview.changedHoldings.first)
        XCTAssertEqual(preview.changedHoldings.map(\.code), ["022485"])
        XCTAssertEqual(difference.jdAmount, 118_674.41, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(difference.localAmount), 243_122.42, accuracy: 0.0001)
        XCTAssertEqual(difference.jdPendingBuyAmount ?? 0, 31_112, accuracy: 0.0001)
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["022485"])
    }

    func testJDFinanceSyncPreviewUsesMatchedTradeRecordCodeWhenHoldingCodeIsMissing() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 31_345.05,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: 0,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1013284",
                    code: "",
                    codeResolution: .unresolved,
                    name: "易方达上证科创50ETF联接C",
                    totalAmount: 31_345.05,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: 0,
                    holdRate: nil,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：1笔买入中合计20000.00元",
                        action: .buy,
                        tradeCount: 1,
                        totalAmount: 20_000
                    ),
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .buy,
                        amount: 20_000,
                        shares: nil,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        statusText: "支付成功",
                        matchedTradeRecords: [
                            JDFinanceTradeOrderRecord(
                                code: "011609",
                                productName: "易方达上证科创50ETF联接C",
                                action: .buy,
                                amount: 20_000,
                                shares: nil,
                                tradeDate: "2026-07-07",
                                tradeTimeType: .before15,
                                statusText: "支付成功"
                            )
                        ]
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 31_345.05,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 10, cost: 1),
                conversionFund(code: "011609", name: "易方达上证科创50ETF联接C", shares: 7_470.237703, cost: 1.5187)
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )
        let notice = try XCTUnwrap(preview.pendingNotices.first)
        let draft = try XCTUnwrap(notice.tradeDraft())

        XCTAssertEqual(preview.remoteSnapshot.products.map(\.code), ["011609"])
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["011609"])
        XCTAssertFalse(preview.pendingNotices.contains { $0.code == "013284" })
        XCTAssertEqual(notice.importKind, .trade(.buy))
        XCTAssertEqual(draft.code, "011609")
        XCTAssertEqual(draft.amount ?? 0, 20_000, accuracy: 0.0001)
    }

    func testJDFinanceFailedAndPaidOrdersNeverBecomeFinalReconciliation() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let localRecord = jdWaitingRecord(
            id: "waiting-buy",
            kind: .buy,
            code: "013284",
            amount: 1_000,
            shares: 100,
            now: now
        )
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 1_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1013284",
                    code: "013284",
                    name: "上银价值增长3个月持有期混合A",
                    totalAmount: 1_000
                )
            ],
            tradeOrders: [
                jdOrder(key: "failed", code: "013284", action: .buy, amount: 900, shares: 90, status: .failed),
                jdOrder(key: "paid", code: "013284", action: .buy, amount: 900, shares: 90, status: .pending)
            ],
            tradeOrderFetchState: .complete
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: jdPortfolio(
                funds: [conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)],
                records: [localRecord],
                now: now
            )
        )

        XCTAssertTrue(preview.automaticConfirmations.isEmpty)
        XCTAssertTrue(preview.overwritableReconciliationNotices.isEmpty)
        XCTAssertEqual(preview.informationalOrders.count, 2)
    }

    func testJDFinanceSyncPreviewIgnoresRateOnlyDifference() {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 19_686.71,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: -919.26,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1024424",
                    code: "024424",
                    name: "东方阿尔法科技优选混合发起C",
                    totalAmount: 19_686.71,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: -919.26,
                    holdRate: -4.46,
                    transactionTip: nil
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 19_686.71,
            holdingIncome: -919.26,
            holdingIncomeRate: -4.45,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "024424",
                    name: "东方阿尔法科技优选混合发起C",
                    dateText: "07-04 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: -919.26,
                    holdingRate: -4.45,
                    currentAmount: 19_686.71,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 20_605.97
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertTrue(preview.changedHoldings.isEmpty)
    }
}
