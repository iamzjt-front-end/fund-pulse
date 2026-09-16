import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    func testInferredInitialTradeRecordUsesPrincipalForConfirmedAmountFund() throws {
        let fund = FundPosition(
            code: "290008",
            name: "泰信发展主题混合",
            dateText: "06-26 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: -15.06,
            currentAmount: 5_521.02,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: 2_615.36,
            migratedCost: 2.4853,
            migratedPrincipal: 6_500.02,
            incomeStartDate: "2026-06-23",
            positionMode: .amount,
            positionDate: "2026-06-23",
            positionTimeType: .before15,
            pendingAmount: nil,
            pendingProfit: nil,
            lots: [
                FundPositionLot(
                    id: "seed",
                    shares: 2_615.36,
                    cost: 2.4853,
                    incomeStartDate: "2026-06-23",
                    positionDate: "2026-06-23",
                    positionTimeType: .before15
                )
            ]
        )

        let record = try XCTUnwrap(inferredInitialTradeRecord(for: fund))
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.mode, .amount)
        XCTAssertEqual(record.amount ?? 0, 6_500.02, accuracy: 0.0001)
        XCTAssertNil(record.shares)
        XCTAssertNil(record.confirmedShares)
    }

    func testFundRowAmountPrivacyMasksOnlyMoneyFields() {
        XCTAssertEqual(
            FundRowAmountPrivacyFormatter.plainMoney(16_069.12, isMasked: true),
            "***"
        )
        XCTAssertEqual(
            FundRowAmountPrivacyFormatter.signedCompactMoney(69.12, isMasked: true),
            "***"
        )
        XCTAssertEqual(
            FundRowAmountPrivacyFormatter.plainMoney(16_069.12, isMasked: false),
            "¥ 16,069.12"
        )
        XCTAssertEqual(
            FundRowAmountPrivacyFormatter.signedCompactMoney(69.12, isMasked: false),
            "+69.12"
        )
        XCTAssertEqual(
            FundRowAmountPrivacyFormatter.signedCompactHoldingIncome(
                69.1234,
                accountKind: .onExchange,
                isMasked: false
            ),
            "+69.123"
        )
        XCTAssertEqual(
            FundRowAmountPrivacyFormatter.signedCompactHoldingIncome(
                69.1234,
                accountKind: .offExchange,
                isMasked: false
            ),
            "+69.12"
        )
        XCTAssertEqual(MoneyFormatter.percent(3.78, signed: true), "+3.78%")
    }

    func testTodayIncomeSortUsesIncomeAmountNotGrowthRate() {
        let funds = [
            sortTestFund(code: "high-rate", name: "涨幅最高", todayIncome: 30, todayRate: 9.8),
            sortTestFund(code: "high-income", name: "收益最高", todayIncome: 210, todayRate: 1.2),
            sortTestFund(code: "middle-income", name: "收益居中", todayIncome: 90, todayRate: 3.4),
            sortTestFund(code: "loss", name: "亏损", todayIncome: -20, todayRate: -0.5)
        ]

        XCTAssertEqual(
            FundListSorter.sort(funds, mode: .todayIncome).map(\.code),
            ["high-income", "middle-income", "high-rate", "loss"]
        )
        XCTAssertEqual(
            FundListSorter.sort(funds, mode: .todayRate).map(\.code),
            ["high-rate", "middle-income", "high-income", "loss"]
        )
    }

    @MainActor
    func testAmountPositionDerivesSharesAndCostLikeFundBaby() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-18",
                netValue: 2.3773,
                estimatedNetValue: 2.3773,
                growthRate: 3.94,
                estimateTime: "2026-06-18 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-18</td><td class='tor bold'>2.3773</td><td>2.3773</td><td class='red'>3.94%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let now = try chinaDate("2026-06-22 16:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let draft = FundPositionDraft(
            code: "026210",
            name: "",
            positionMode: .amount,
            positionAmount: 2377.30,
            positionProfit: 177.30,
            shares: nil,
            cost: nil,
            positionDate: "2026-06-18",
            positionTimeType: .before15,
            memo: ""
        )

        try await store.upsertFund(draft)

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "026210" })
        XCTAssertEqual(fund.name, "平安科技精选混合发起式A")
        XCTAssertEqual(fund.migratedShares ?? 0, 1000, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.2, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 2200, accuracy: 0.0001)
        XCTAssertEqual(fund.status, .holding)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount ?? 0, 2377.30, accuracy: 0.0001)
        XCTAssertEqual(record.profit ?? 0, 177.30, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 1000, accuracy: 0.0001)
        XCTAssertEqual(record.price ?? 0, 2.3773, accuracy: 0.0001)
    }

    @MainActor
    func testConfirmedSameDayManualNewFundStaysHolding() async throws {
        let now = try chinaDate("2026-06-23 21:48")
        let createdAt = try chinaDate("2026-06-23 15:41")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "025833",
                name: "天弘电网设备特高压指数C",
                netValueDate: "2026-06-23",
                netValue: 1.5130,
                estimatedNetValue: 1.5130,
                growthRate: -2.76,
                estimateTime: "2026-06-23 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=025833&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-23</td><td class='tor bold'>1.5130</td><td>1.5130</td><td class='green'>-2.76%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-premature-new-fund-confirmation-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 5_000,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: -142.10,
                todayIncomeRate: -2.76,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "025833",
                        name: "天弘电网设备特高压指数C",
                        dateText: "06-23 15:00",
                        todayIncome: -142.10,
                        todayRate: -2.76,
                        holdingRate: 0,
                        status: .holding,
                        isUpdated: true,
                        isIncomeActive: true,
                        migratedShares: 3304.69,
                        migratedCost: 1.5130,
                        migratedPrincipal: 5_000,
                        incomeStartDate: "2026-06-23",
                        positionMode: .amount,
                        positionDate: "2026-06-23",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "premature-lot",
                                shares: 3304.69,
                                cost: 1.5130,
                                incomeStartDate: "2026-06-23",
                                positionDate: "2026-06-23",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "premature-record",
                        kind: .newFund,
                        status: .confirmed,
                        code: "025833",
                        name: "天弘电网设备特高压指数C",
                        mode: .amount,
                        amount: 5_000,
                        shares: nil,
                        confirmedShares: 3304.69,
                        price: 1.5130,
                        tradeDate: "2026-06-23",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-06-23",
                        createdAt: createdAt,
                        confirmedAt: createdAt,
                        failureReason: nil
                    )
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        await store.refreshQuotes()

        let restoredFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(restoredFund.status, .holding)
        XCTAssertEqual(restoredFund.migratedShares ?? 0, 3304.692664, accuracy: 0.000001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        let restoredRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(restoredRecord.status, .confirmed)
        XCTAssertEqual(restoredRecord.confirmedShares ?? 0, 3304.692664, accuracy: 0.000001)
        XCTAssertEqual(restoredRecord.price ?? 0, 1.5130, accuracy: 0.0001)
        XCTAssertNotNil(restoredRecord.confirmedAt)
    }

    @MainActor
    func testConfirmedBuyTradeCreatesRecordAndUpdatesWeightedCost() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-18",
                netValue: 2.3773,
                estimatedNetValue: 2.3773,
                growthRate: 3.94,
                estimateTime: "2026-06-18 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-18</td><td class='tor bold'>2.3773</td><td>2.3773</td><td class='red'>3.94%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-trade-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service)
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 1,
                        migratedPrincipal: 100,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "seed",
                                shares: 100,
                                cost: 1,
                                incomeStartDate: "2026-06-17",
                                positionDate: "2026-06-17",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .buy,
                code: "026210",
                mode: .amount,
                amount: 237.73,
                shares: nil,
                tradeDate: "2026-06-18",
                tradeTimeType: .before15
            )
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "026210" })
        XCTAssertEqual(fund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1.6887, accuracy: 0.0001)
        XCTAssertEqual(fund.lots?.count, 2)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(record.kind, .buy)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount ?? 0, 237.73, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(record.price ?? 0, 2.3773, accuracy: 0.0001)
    }

    @MainActor
    func testBuyTradeRequiresAmountMode() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-buy-mode-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 1,
                        migratedPrincipal: 100,
                        incomeStartDate: "2026-06-22",
                        positionMode: .amount,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 100, cost: 1, incomeStartDate: "2026-06-22", positionDate: "2026-06-22", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "buy-record", kind: .buy, status: .pending, code: "026210", name: "平安科技精选混合发起式A", mode: .amount, amount: 100, shares: nil, confirmedShares: nil, price: nil, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: nil, failureReason: nil)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        do {
            try await store.adjustFundPosition(
                FundTradeDraft(
                    action: .buy,
                    code: "026210",
                    mode: .share,
                    amount: nil,
                    shares: 100,
                    tradeDate: "2026-06-23",
                    tradeTimeType: .before15
                )
            )
            XCTFail("Expected share-mode buy trade to be rejected")
        } catch PortfolioStoreError.buyTradeRequiresAmount {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await store.editTradeRecord(
                id: "buy-record",
                with: FundTradeDraft(
                    action: .buy,
                    code: "026210",
                    mode: .share,
                    amount: nil,
                    shares: 100,
                    tradeDate: "2026-06-23",
                    tradeTimeType: .before15
                )
            )
            XCTFail("Expected share-mode buy record edit to be rejected")
        } catch PortfolioStoreError.buyTradeRequiresAmount {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.mode, .amount)

        do {
            try await store.adjustFundPosition(
                FundTradeDraft(
                    action: .sell,
                    code: "026210",
                    mode: .amount,
                    amount: 100,
                    shares: nil,
                    tradeDate: "2026-06-23",
                    tradeTimeType: .before15
                )
            )
            XCTFail("Expected amount-mode sell trade to be rejected")
        } catch PortfolioStoreError.sellTradeRequiresShare {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testPendingBuyTradeWaitsUntilNextDayBeforeUpdatingHolding() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-18",
                netValue: 2.3773,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 14:30"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-18</td><td class='tor bold'>2.3773</td><td>2.3773</td><td class='red'>3.94%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-pending-trade-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 1,
                        migratedPrincipal: 100,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "seed",
                                shares: 100,
                                cost: 1,
                                incomeStartDate: "2026-06-17",
                                positionDate: "2026-06-17",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .buy,
                code: "026210",
                mode: .amount,
                amount: 250,
                shares: nil,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.kind, .buy)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.0001)

        MockURLProtocol.responseStore.set([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Data(Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-22",
                netValue: 2.5000,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 15:00"
            ).utf8),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": Data("""
            var apidata={ content:"<table><tbody><tr><td>2026-06-22</td><td class='tor bold'>2.5000</td><td>2.5000</td><td class='red'>5.16%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """.utf8)
        ])

        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        let stillPendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(stillPendingRecord.id, pendingRecord.id)
        XCTAssertEqual(stillPendingRecord.status, .pending)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.totalAmount, 250, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.holdingIncome, 150, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.holdingIncomeRate, 150, accuracy: 0.0001)
        let expectedTodayIncome = 100 * 2.5 * 5.16 / 105.16
        XCTAssertEqual(store.snapshot.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.todayIncomeRate, 5.16, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.id, pendingRecord.id)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 200, accuracy: 0.0001)
    }

    @MainActor
    func testEditingConfirmedBuyTradeRecalculatesSharesWhenBuyFeeRateChanges() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = tradeQuoteService(date: "2026-06-22", netValue: 2.5)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-buy-fee-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let newRecordDate = try chinaDate("2026-06-17 15:00")
        let buyRecordDate = try chinaDate("2026-06-22 15:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1.7625,
                        migratedPrincipal: 352.5,
                        incomeStartDate: "2026-06-17",
                        positionMode: .amount,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 100, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15),
                            FundPositionLot(id: "buy-record", shares: 100, cost: 2.525, incomeStartDate: "2026-06-22", positionDate: "2026-06-22", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "new-record", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 100, shares: 100, confirmedShares: 100, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: newRecordDate, confirmedAt: newRecordDate, failureReason: nil),
                    FundTradeRecord(id: "buy-record", kind: .buy, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .amount, amount: 252.5, shares: nil, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: buyRecordDate, confirmedAt: buyRecordDate, failureReason: nil, buyFeeRate: 1)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editTradeRecord(
            id: "buy-record",
            with: FundTradeDraft(
                action: .buy,
                code: Self.tradeTestCode,
                mode: .amount,
                amount: 252.5,
                shares: nil,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                buyFeeRate: 0
            )
        )

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "buy-record" })
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.buyFeeRate ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 101, accuracy: 0.0001)
        XCTAssertEqual(record.price ?? 0, 2.5, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(fund.migratedShares ?? 0, 201, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 352.5, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1.7537, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

    @MainActor
    func testDeletingConfirmedBuyTradeRecalculatesHolding() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = tradeQuoteService(date: "2026-06-22", netValue: 2.5)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-delete-buy-record-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let newRecordDate = try chinaDate("2026-06-17 15:00")
        let buyRecordDate = try chinaDate("2026-06-22 15:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1.75,
                        migratedPrincipal: 350,
                        incomeStartDate: "2026-06-17",
                        positionMode: .amount,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 100, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15),
                            FundPositionLot(id: "buy-record", shares: 100, cost: 2.5, incomeStartDate: "2026-06-22", positionDate: "2026-06-22", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "new-record", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 100, shares: 100, confirmedShares: 100, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: newRecordDate, confirmedAt: newRecordDate, failureReason: nil),
                    FundTradeRecord(id: "buy-record", kind: .buy, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .amount, amount: 250, shares: nil, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: buyRecordDate, confirmedAt: buyRecordDate, failureReason: nil)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteTradeRecord(id: "buy-record")

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(fund.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.tradeRecords?.contains { $0.id == "buy-record" }, false)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

    @MainActor
    func testPendingSellTradeWaitsUntilNextDayBeforeReducingHolding() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-22",
                netValue: 2.5000,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-22</td><td class='tor bold'>2.5000</td><td>2.5000</td><td class='red'>5.16%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-pending-sell-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "seed",
                                shares: 200,
                                cost: 1,
                                incomeStartDate: "2026-06-17",
                                positionDate: "2026-06-17",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .sell,
                code: "026210",
                mode: .share,
                amount: nil,
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.kind, .sell)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 200, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.id, pendingRecord.id)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.0001)
    }

    @MainActor
    func testPendingSellTradePreservesSellFeeSettingsAndKeepsCostUnchanged() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-22",
                netValue: 2.5000,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-22</td><td class='tor bold'>2.5000</td><td>2.5000</td><td class='red'>5.16%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-sell-fee-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "seed",
                                shares: 200,
                                cost: 1,
                                incomeStartDate: "2026-06-17",
                                positionDate: "2026-06-17",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .sell,
                code: "026210",
                mode: .share,
                amount: nil,
                shares: 80,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 0.5
            )
        )

        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(pendingRecord.sellFeeMode, .rate)
        XCTAssertEqual(pendingRecord.sellFeeValue ?? 0, 0.5, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.sellFeeMode, .rate)
        XCTAssertEqual(confirmedRecord.sellFeeValue ?? 0, 0.5, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.migratedShares ?? 0, 120, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 120, accuracy: 0.0001)
    }

    @MainActor
    func testPendingSellAfter15WaitsForNextTradingDayThenReducesHolding() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = tradeQuoteService(date: "2026-06-23", netValue: 3)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-sell-after15-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "seed", shares: 200, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .sell,
                code: Self.tradeTestCode,
                mode: .share,
                amount: nil,
                shares: 80,
                tradeDate: "2026-06-22",
                tradeTimeType: .after15
            )
        )

        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(pendingRecord.acceptedDate, "2026-06-23")
        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 200, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 15:30")
        await store.refreshQuotes()

        let stillPendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(stillPendingRecord.status, .pending)
        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 200, accuracy: 0.0001)

        now = try chinaDate("2026-06-24 09:30")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.acceptedDate, "2026-06-23")
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 3, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.migratedShares ?? 0, 120, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 120, accuracy: 0.0001)
    }

    @MainActor
    func testPendingSellTradePreservesFixedFeeAmount() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = tradeQuoteService(date: "2026-06-22", netValue: 2.5)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-sell-fixed-fee-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "seed", shares: 200, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .sell,
                code: Self.tradeTestCode,
                mode: .share,
                amount: nil,
                shares: 40,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .amount,
                sellFeeValue: 3.5
            )
        )

        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(pendingRecord.sellFeeMode, .amount)
        XCTAssertEqual(pendingRecord.sellFeeValue ?? 0, 3.5, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 40, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.sellFeeMode, .amount)
        XCTAssertEqual(confirmedRecord.sellFeeValue ?? 0, 3.5, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.migratedShares ?? 0, 160, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 160, accuracy: 0.0001)
    }

    @MainActor
    func testClearingAllHoldingsRemovesFundsPendingRecordsAndSyncedTotal() throws {
        let now = try chinaDate("2026-07-08 14:30")
        let createdAt = try chinaDate("2026-07-08 14:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-clear-all-holdings-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: quoteServiceWithMockResponses([:]), now: { now })
        let pendingTrade = FundPendingTrade(
            id: "pending-buy",
            recordID: "pending-buy-record",
            action: .buy,
            code: "588760",
            mode: .amount,
            amount: 1000,
            shares: nil,
            tradeDate: "2026-07-08",
            tradeTimeType: .before15,
            createdAt: createdAt
        )
        let pendingConversion = FundPendingConversion(
            id: "conversion-1",
            outRecordID: "conversion-out",
            inRecordID: "conversion-in",
            fromCode: "588760",
            toCode: "026210",
            toName: Self.tradeTestName,
            shares: 100,
            tradeDate: "2026-07-08",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-08",
            createdAt: createdAt,
            sellFeeMode: .rate,
            sellFeeValue: 0.5,
            buyFeeRate: 0.15,
            failureReason: nil
        )
        let tradeRecord = FundTradeRecord(
            id: "pending-buy-record",
            kind: .buy,
            status: .pending,
            code: "588760",
            name: "科创人工智能ETF广发",
            mode: .amount,
            amount: 1000,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: "2026-07-08",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-08",
            createdAt: createdAt,
            confirmedAt: nil,
            failureReason: nil
        )
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: createdAt,
                totalAmount: 12_345,
                holdingIncome: 123,
                holdingIncomeRate: 1,
                todayIncome: 45,
                todayIncomeRate: 0.5,
                pendingCount: 2,
                funds: [
                    FundPosition(
                        code: "588760",
                        name: "科创人工智能ETF广发",
                        dateText: "07-08 15:00前确认",
                        todayIncome: 45,
                        todayRate: 1.2,
                        holdingIncome: 123,
                        holdingRate: 1,
                        currentAmount: 12_345,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 1.2
                    )
                ],
                migration: MigrationInfo(
                    source: "legacy",
                    currentWalletCode: "default",
                    walletName: "默认钱包",
                    eyeStatus: true
                ),
                pendingTrades: [pendingTrade],
                pendingConversions: [pendingConversion],
                tradeRecords: [tradeRecord],
                syncedAccountTotal: PortfolioSyncedAccountTotal(source: .jdFinance, amount: 20_000, syncedAt: createdAt)
            ),
            into: store,
            directory: tempDirectory
        )

        try store.clearAllHoldings()

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.snapshot.updateTime, now)
        XCTAssertEqual(store.snapshot.totalAmount, 0)
        XCTAssertEqual(store.snapshot.holdingIncome, 0)
        XCTAssertEqual(store.snapshot.todayIncome, 0)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertNil(store.snapshot.migration)
        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertNil(store.snapshot.pendingConversions)
        XCTAssertNil(store.snapshot.tradeRecords)
        XCTAssertNil(store.snapshot.syncedAccountTotal)

        let reloadedStore = PortfolioStore(dataDirectory: tempDirectory, quoteService: quoteServiceWithMockResponses([:]), now: { now })
        reloadedStore.load()
        XCTAssertEqual(reloadedStore.loadState, .loaded)
        XCTAssertTrue(reloadedStore.snapshot.funds.isEmpty)
        XCTAssertNil(reloadedStore.snapshot.tradeRecords)
        XCTAssertNil(reloadedStore.snapshot.syncedAccountTotal)
    }

    @MainActor
    func testPendingSellTradeWithInsufficientSharesStaysPending() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = tradeQuoteService(date: "2026-06-22", netValue: 2.5)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-sell-insufficient-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        dateText: "06-18 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "seed", shares: 200, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .sell,
                code: Self.tradeTestCode,
                mode: .share,
                amount: nil,
                shares: 250,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(record.status, .pending)
        XCTAssertNil(record.confirmedShares)
        XCTAssertNil(record.price)
        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 200, accuracy: 0.0001)
    }

    @MainActor
    func testEditingConfirmedBuyTradeRecalculatesHolding() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-22",
                netValue: 2.5000,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-22</td><td class='tor bold'>2.5000</td><td>2.5000</td><td class='red'>5.16%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-record-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let newRecordDate = try chinaDate("2026-06-17 15:00")
        let buyRecordDate = try chinaDate("2026-06-22 15:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1.75,
                        migratedPrincipal: 350,
                        incomeStartDate: "2026-06-17",
                        positionMode: .amount,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 100, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15),
                            FundPositionLot(id: "buy-record", shares: 100, cost: 2.5, incomeStartDate: "2026-06-22", positionDate: "2026-06-22", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "new-record", kind: .newFund, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .share, amount: 100, shares: 100, confirmedShares: 100, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: newRecordDate, confirmedAt: newRecordDate, failureReason: nil),
                    FundTradeRecord(id: "buy-record", kind: .buy, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .amount, amount: 250, shares: nil, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: buyRecordDate, confirmedAt: buyRecordDate, failureReason: nil)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editTradeRecord(
            id: "buy-record",
            with: FundTradeDraft(
                action: .buy,
                code: "026210",
                mode: .amount,
                amount: 500,
                shares: nil,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "026210" })
        XCTAssertEqual(fund.migratedShares ?? 0, 300, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.0, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 600, accuracy: 0.0001)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "buy-record" })
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount ?? 0, 500, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

    @MainActor
    func testEditingConfirmedNewFundTradeRecalculatesInitialHolding() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-22",
                netValue: 2.5000,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-22</td><td class='tor bold'>2.5000</td><td>2.5000</td><td class='red'>5.16%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-new-fund-record-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-17 15:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-17 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 1,
                        migratedPrincipal: 100,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 100, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "new-record", kind: .newFund, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .share, amount: 100, shares: 100, confirmedShares: 100, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editTradeRecord(
            id: "new-record",
            with: FundTradeDraft(
                action: .buy,
                code: "026210",
                mode: .amount,
                amount: 500,
                shares: nil,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "026210" })
        XCTAssertEqual(fund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 500, accuracy: 0.0001)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "new-record" })
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount ?? 0, 500, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(record.price ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

    @MainActor
    func testDeletingConfirmedSellTradeRecalculatesHolding() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-22",
                netValue: 2.5000,
                estimatedNetValue: 2.5000,
                growthRate: 5.16,
                estimateTime: "2026-06-22 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-22</td><td class='tor bold'>2.5000</td><td>2.5000</td><td class='red'>5.16%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-delete-record-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let newRecordDate = try chinaDate("2026-06-17 15:00")
        let sellRecordDate = try chinaDate("2026-06-22 15:00")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "026210",
                        name: "平安科技精选混合发起式A",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 1,
                        migratedPrincipal: 100,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 100, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "new-record", kind: .newFund, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .share, amount: 200, shares: 200, confirmedShares: 200, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: newRecordDate, confirmedAt: newRecordDate, failureReason: nil),
                    FundTradeRecord(id: "sell-record", kind: .sell, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .amount, amount: 250, shares: nil, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: sellRecordDate, confirmedAt: sellRecordDate, failureReason: nil)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteTradeRecord(id: "sell-record")

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "026210" })
        XCTAssertEqual(fund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.tradeRecords?.contains { $0.id == "sell-record" }, false)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

    @MainActor
    func testRefreshRepairsLegacyAmountFundSharesToStoredPrecision() async throws {
        let now = try chinaDate("2026-06-27 21:20")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "007818",
                name: "国泰中证全指通信设备ETF联接C",
                netValueDate: "2026-06-26",
                netValue: 4.7655,
                estimatedNetValue: 4.7655,
                growthRate: 0,
                estimateTime: "2026-06-26 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=007818&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-26</td><td class='tor bold'>4.7655</td><td>4.7655</td><td class='red'>0.00%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-legacy-amount-share-precision-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let createdAt = try chinaDate("2026-06-27 21:08")
        let snapshot = PortfolioSnapshot(
            updateTime: createdAt,
            totalAmount: 15_455.09,
            holdingIncome: -544.91,
            holdingIncomeRate: -3.41,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "007818",
                    name: "国泰中证全指通信设备ETF联接C",
                    dateText: "06-26 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: -544.91164,
                    holdingRate: -3.41,
                    confirmedHoldingIncome: -544.91164,
                    confirmedHoldingRate: -3.41,
                    currentAmount: 15_455.08836,
                    status: .holding,
                    isUpdated: true,
                    isIncomeActive: true,
                    migratedShares: 3_243.12,
                    migratedCost: 4.9335,
                    migratedPrincipal: 16_000,
                    incomeStartDate: "2026-06-26",
                    positionMode: .amount,
                    positionDate: "2026-06-26",
                    positionTimeType: .before15,
                    pendingAmount: nil,
                    pendingProfit: nil,
                    lots: [
                        FundPositionLot(
                            id: "legacy-lot",
                            shares: 3_243.12,
                            cost: 4.9335,
                            principal: 16_000,
                            incomeStartDate: "2026-06-26",
                            positionDate: "2026-06-26",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil,
            tradeRecords: [
                FundTradeRecord(
                    id: "legacy-record",
                    kind: .newFund,
                    status: .confirmed,
                    code: "007818",
                    name: "国泰中证全指通信设备ETF联接C",
                    mode: .amount,
                    amount: 15_455.10,
                    shares: 3_243.12,
                    confirmedShares: 3_243.12,
                    price: 4.7655,
                    profit: -544.90,
                    tradeDate: "2026-06-26",
                    tradeTimeType: .before15,
                    acceptedDate: "2026-06-26",
                    createdAt: createdAt,
                    confirmedAt: createdAt,
                    failureReason: nil
                )
            ]
        )
        try seedPortfolio(snapshot, into: store, directory: tempDirectory)

        await store.refreshQuotes()

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "007818" })
        XCTAssertEqual(fund.migratedShares ?? 0, 3243.122443, accuracy: 0.000001)
        XCTAssertEqual(((fund.migratedShares ?? 0) * 100).rounded() / 100, 3243.12, accuracy: 0.0001)
        XCTAssertEqual((fund.currentAmount ?? 0).roundedMoneyForTest, 15_455.10, accuracy: 0.0001)
        XCTAssertEqual((fund.holdingIncome ?? 0).roundedMoneyForTest, -544.90, accuracy: 0.0001)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.code == "007818" })
        XCTAssertNil(record.shares)
        XCTAssertEqual(record.confirmedShares ?? 0, 3243.122443, accuracy: 0.000001)
    }

    func testPortfolioCalculatorBackfillsManualAmountEntrySharesLikeFundBaby() throws {
        let now = try chinaDate("2026-06-24 13:07")
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "024418",
                    name: "华夏上证科创板半导体材料设备主题ETF联接A",
                    dateText: "06-24 13:02",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    isIncomeActive: true,
                    migratedShares: 0,
                    migratedCost: nil,
                    migratedPrincipal: 5_000,
                    incomeStartDate: "2026-06-23",
                    positionMode: .amount,
                    positionDate: "2026-06-23",
                    positionTimeType: .before15,
                    pendingAmount: 5_232.22,
                    pendingProfit: 232.22,
                    lots: []
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "024418",
            name: "华夏上证科创板半导体材料设备主题ETF联接A",
            netValue: 2.5709,
            estimatedNetValue: 2.5709,
            growthRate: 0,
            estimateTime: "2026-06-24 13:02",
            netValueDate: "2026-06-23"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["024418": quote],
            now: now
        )

        let fund = result.funds[0]
        XCTAssertEqual(fund.migratedShares ?? 0, 2035.170563, accuracy: 0.000001)
        XCTAssertEqual(((fund.migratedShares ?? 0) * 100).rounded() / 100, 2035.17, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.4568, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertNil(fund.pendingAmount)
        XCTAssertNil(fund.pendingProfit)
        XCTAssertEqual(fund.currentAmount ?? 0, 5_232.22, accuracy: 0.01)
    }

    func testHistoricalAmountHoldingEnteredTodayParticipatesInTodayIncome() throws {
        let now = try chinaDate("2026-07-08 15:09")
        let amount = 122_552.60
        let profit = -3_447.40
        let principal = amount - profit
        let netValue = 1.5051
        let shares = 81_424.888712
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "022485",
                    name: "国金中证A500指数增强A",
                    dateText: "07-08 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: profit / principal * 100,
                    status: .holding,
                    isUpdated: true,
                    isIncomeActive: true,
                    migratedShares: shares,
                    migratedCost: principal / shares,
                    migratedPrincipal: principal,
                    incomeStartDate: "2026-07-08",
                    positionMode: .amount,
                    positionDate: "2026-07-08",
                    positionTimeType: .before15,
                    lots: [
                        FundPositionLot(
                            id: "022485-new",
                            shares: shares,
                            cost: principal / shares,
                            principal: principal,
                            incomeStartDate: "2026-07-08",
                            positionDate: "2026-07-08",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "022485",
            name: "国金中证A500指数增强A",
            netValue: netValue,
            estimatedNetValue: 1.5153,
            growthRate: -1.79,
            estimateTime: "2026-07-08 15:00",
            netValueDate: "2026-07-08"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["022485": quote],
            now: now
        )

        let fund = result.funds[0]
        let expectedTodayIncome = shares * netValue * quote.growthRate / (100 + quote.growthRate)
        let expectedTodayBase = shares * netValue / (1 + quote.growthRate / 100)
        XCTAssertEqual(fund.status, .holding)
        XCTAssertEqual(fund.todayRate, -1.79, accuracy: 0.0001)
        XCTAssertEqual(fund.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncomeRate, expectedTodayIncome / expectedTodayBase * 100, accuracy: 0.0001)
    }

    func testPortfolioCalculatorUsesLocalHoldingSumInsteadOfSyncedAccountTotal() throws {
        let now = try chinaDate("2026-07-08 11:52")
        let syncedAt = try chinaDate("2026-07-08 10:30")
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 100,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "022485",
                    name: "国金中证A500指数增强A",
                    dateText: "07-07 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 1,
                    migratedPrincipal: 100,
                    incomeStartDate: "2026-07-07"
                ),
                FundPosition(
                    code: "018178",
                    name: "华夏科创50指数增强C",
                    dateText: "07-07 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 200,
                    migratedCost: 1,
                    migratedPrincipal: 200,
                    incomeStartDate: "2026-07-07"
                )
            ],
            migration: nil,
            syncedAccountTotal: PortfolioSyncedAccountTotal(
                source: .jdFinance,
                amount: 306_651.24,
                syncedAt: syncedAt
            )
        )
        let quote = FundQuote(
            code: "022485",
            name: "国金中证A500指数增强A",
            netValue: 1.1,
            estimatedNetValue: 1.1,
            growthRate: 0,
            estimateTime: "2026-07-08 11:30",
            netValueDate: "2026-07-07"
        )
        let localQuote = FundQuote(
            code: "018178",
            name: "华夏科创50指数增强C",
            netValue: 1.2,
            estimatedNetValue: 1.2,
            growthRate: 0,
            estimateTime: "2026-07-08 11:30",
            netValueDate: "2026-07-07"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["022485": quote, "018178": localQuote],
            now: now
        )

        XCTAssertEqual(result.funds[0].currentAmount ?? 0, 110, accuracy: 0.0001)
        XCTAssertEqual(result.funds[1].currentAmount ?? 0, 240, accuracy: 0.0001)
        XCTAssertEqual(result.totalAmount, 350, accuracy: 0.0001)
        XCTAssertEqual(result.syncedAccountTotal?.source, .jdFinance)
        XCTAssertEqual(result.syncedAccountTotal?.amount ?? 0, 306_651.24, accuracy: 0.0001)
    }

    func testPortfolioCalculatorIgnoresIncomeStartDateForConfirmedHolding() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-21"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 100,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "588760",
                    name: "科创人工智能ETF广发",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 1,
                    migratedPrincipal: 100,
                    incomeStartDate: "2026-06-19",
                    positionMode: .amount,
                    positionDate: "2026-06-18",
                    positionTimeType: .before15
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "588760",
            name: "科创人工智能ETF广发",
            netValue: 1.1,
            estimatedNetValue: 1.2,
            growthRate: 9.09,
            estimateTime: "2026-06-18 15:00",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["588760": quote],
            now: now
        )

        XCTAssertEqual(result.totalAmount, 110, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncome, 10, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncomeRate, 10, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, 0)
        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertEqual(result.funds[0].status, .holding)
        XCTAssertEqual(result.funds[0].incomeStartDate, "2026-06-19")
        XCTAssertEqual(result.funds[0].migratedShares, 100)
        XCTAssertEqual(result.funds[0].migratedCost, 1)
        XCTAssertEqual(result.funds[0].todayRate, 0)
        XCTAssertEqual(result.funds[0].holdingRate ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].isIncomeActive, true)
    }

    func testPortfolioCalculatorTreatsLegacyWatchAsPending() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-21"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "007818",
                    name: "国泰中证通信ETF联接C",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .watch,
                    isUpdated: false,
                    migratedShares: 0,
                    migratedCost: 4.7536,
                    migratedPrincipal: 0,
                    incomeStartDate: "2026-06-22",
                    positionMode: .amount,
                    positionDate: "2026-06-18",
                    positionTimeType: .before15
                )
            ],
            migration: nil
        )

        let result = PortfolioCalculator.applyingQuotes(to: snapshot, quotes: [:], now: now)

        XCTAssertEqual(result.pendingCount, 1)
        XCTAssertEqual(result.funds[0].status, .pending)
        XCTAssertEqual(result.funds[0].status.title, "待确认")
    }

    func testConfirmedSharesCalculateHoldingWithoutIncomeStartDelay() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-21"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "588760",
                    name: "科创人工智能ETF广发",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .pending,
                    isUpdated: false,
                    migratedShares: 11518.08,
                    migratedCost: 0.8682,
                    migratedPrincipal: 9999.99,
                    incomeStartDate: "2026-06-22",
                    positionMode: .amount,
                    positionDate: "2026-06-18",
                    positionTimeType: .before15
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "588760",
            name: "科创人工智能ETF广发",
            netValue: 0.8682,
            estimatedNetValue: 0.8682,
            growthRate: 4.21,
            estimateTime: "",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["588760": quote],
            now: now
        )

        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertEqual(result.funds[0].status, .holding)
        XCTAssertEqual(result.funds[0].migratedCost, 0.8682)
        XCTAssertEqual(result.funds[0].migratedShares, 11518.08)
        XCTAssertEqual(result.funds[0].todayRate, 0)
        XCTAssertEqual(result.funds[0].holdingRate ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].isIncomeActive, true)
        XCTAssertEqual(result.holdingIncome, 0)
        XCTAssertEqual(result.todayIncome, 0)
    }

    func testPortfolioCalculatorIgnoresIntradayEstimateOnMarketHoliday() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-21"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 100,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 1,
                    migratedPrincipal: 100,
                    incomeStartDate: "2026-06-18"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 1.1,
            estimatedNetValue: 1.2,
            growthRate: 9.09,
            estimateTime: "2026-06-21 14:30",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["026210": quote],
            now: now
        )

        XCTAssertEqual(result.todayIncome, 0)
        XCTAssertEqual(result.todayIncomeRate, 0)
        XCTAssertEqual(result.funds[0].todayIncome, 0)
        XCTAssertEqual(result.funds[0].todayRate, 0)
        XCTAssertFalse(result.funds[0].isUpdated)
        XCTAssertEqual(result.funds[0].dateText, "06-18 15:00")
    }

    func testPortfolioCalculatorUsesOfficialDailyGrowthAfterNavUpdated() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-18"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 100,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "06-17 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 2.2,
                    migratedPrincipal: 220,
                    incomeStartDate: "2026-06-17"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2.3773,
            estimatedNetValue: 2.3773,
            growthRate: 3.9439,
            estimateTime: "",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["026210": quote],
            now: now
        )

        let expectedTodayIncome = 100 * 2.3773 * 3.9439 / 103.9439
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayRate, 3.9439, accuracy: 0.0001)
        XCTAssertTrue(result.funds[0].isUpdated)
        XCTAssertEqual(result.funds[0].dateText, "06-18 15:00")
    }

    func testPortfolioCalculatorTreatsPreviousTradingDayQDIINAVAsUpdatedToday() throws {
        let now = try chinaDate("2026-08-25 20:20")
        let shares = 1_976.230129
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "022184",
                    name: "富国全球科技互联网股票(QDII)C",
                    dateText: "08-21 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: shares,
                    migratedCost: 5.4143,
                    migratedPrincipal: 10_700,
                    incomeStartDate: "2026-08-20"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "022184",
            name: "富国全球科技互联网股票(QDII)C",
            netValue: 5.0156,
            estimatedNetValue: 5.0156,
            growthRate: -4.82,
            estimateTime: "",
            netValueDate: "2026-08-24"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["022184": quote],
            now: now
        )

        let expectedTodayIncome = shares * quote.netValue * quote.growthRate / (100 + quote.growthRate)
        let expectedTodayBase = shares * quote.netValue / (1 + quote.growthRate / 100)
        XCTAssertEqual(result.funds[0].todayRate, -4.82, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertTrue(result.funds[0].isUpdated)
        XCTAssertEqual(result.funds[0].dateText, "08-24 15:00")
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncomeRate, expectedTodayIncome / expectedTodayBase * 100, accuracy: 0.0001)
    }

    func testPortfolioCalculatorKeepsPreviousTradingDayDomesticNAVInactive() throws {
        let now = try chinaDate("2026-08-25 20:20")
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "08-24 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 2,
                    migratedPrincipal: 200,
                    incomeStartDate: "2026-08-20"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2.1,
            estimatedNetValue: 2.1,
            growthRate: -4.82,
            estimateTime: "",
            netValueDate: "2026-08-24"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["026210": quote],
            now: now
        )

        XCTAssertEqual(result.funds[0].todayRate, 0)
        XCTAssertEqual(result.funds[0].todayIncome, 0)
        XCTAssertFalse(result.funds[0].isUpdated)
        XCTAssertEqual(result.todayIncome, 0)
    }

    func testPortfolioCalculatorDoesNotRepeatOlderQDIINAVAsTodayUpdate() throws {
        let now = try chinaDate("2026-08-25 20:20")
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "022184",
                    name: "富国全球科技互联网股票(QDII)C",
                    dateText: "08-21 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 5,
                    migratedPrincipal: 500,
                    incomeStartDate: "2026-08-20"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "022184",
            name: "富国全球科技互联网股票(QDII)C",
            netValue: 5.2696,
            estimatedNetValue: 5.2696,
            growthRate: -0.27,
            estimateTime: "",
            netValueDate: "2026-08-21"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["022184": quote],
            now: now
        )

        XCTAssertEqual(result.funds[0].todayRate, 0)
        XCTAssertEqual(result.funds[0].todayIncome, 0)
        XCTAssertFalse(result.funds[0].isUpdated)
    }

    func testPortfolioCalculatorKeepsOrdinaryPendingBuyInTodayIncome() throws {
        let now = try chinaDate("2026-07-16 16:00")
        let amount = 10_000.0
        let netValue = 0.9
        let shares = amount / netValue
        let fund = FundPosition(
            code: "026210",
            name: "平安科技精选混合发起式A",
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: 0,
            holdingRate: 0,
            currentAmount: amount,
            status: .holding,
            isUpdated: true,
            isIncomeActive: true,
            migratedShares: shares,
            migratedCost: 1,
            migratedPrincipal: amount,
            incomeStartDate: "2026-07-15",
            positionMode: .amount,
            positionDate: "2026-07-15",
            positionTimeType: .before15,
            lots: [
                FundPositionLot(
                    id: "ordinary-sync",
                    shares: shares,
                    cost: 1,
                    principal: amount,
                    incomeStartDate: "2026-07-15",
                    positionDate: "2026-07-15",
                    positionTimeType: .before15
                )
            ]
        )
        let pending = FundTradeRecord(
            id: "manual-pending-026210",
            kind: .buy,
            status: .pending,
            code: fund.code,
            name: fund.name,
            mode: .amount,
            amount: 2_000,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: now,
            confirmedAt: nil,
            failureReason: nil
        )
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: amount,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 1,
            funds: [fund],
            migration: nil,
            tradeRecords: [pending]
        )
        let quote = FundQuote(
            code: fund.code,
            name: fund.name,
            netValue: netValue,
            estimatedNetValue: netValue,
            growthRate: -10,
            estimateTime: "2026-07-16 15:00",
            netValueDate: "2026-07-16"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: [fund.code: quote],
            now: now
        )

        let expectedTodayIncome = amount * quote.growthRate / (100 + quote.growthRate)
        XCTAssertEqual(result.funds[0].todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
    }

    func testPortfolioCalculatorExcludesSameDayLotFromTodayIncomeAfterNavUpdated() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-24"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "06-23 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 200,
                    migratedCost: 1.5,
                    migratedPrincipal: 300,
                    incomeStartDate: "2026-06-23",
                    lots: [
                        FundPositionLot(
                            id: "old",
                            shares: 100,
                            cost: 1,
                            incomeStartDate: "2026-06-23",
                            positionDate: "2026-06-23",
                            positionTimeType: .before15
                        ),
                        FundPositionLot(
                            id: "today-buy",
                            shares: 100,
                            cost: 2,
                            incomeStartDate: "2026-06-24",
                            positionDate: "2026-06-24",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2.5,
            estimatedNetValue: 2.5,
            growthRate: 25,
            estimateTime: "",
            netValueDate: "2026-06-24"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["026210": quote],
            now: now
        )

        XCTAssertEqual(result.totalAmount, 500, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncome, 200, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncomeRate, 200.0 / 300.0 * 100, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, 50, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncomeRate, 25, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, 50, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].currentAmount ?? 0, 500, accuracy: 0.0001)
    }

    func testFundDailyIncomeRowsIncludeSameDayLotOnlyInCumulativeIncome() throws {
        let lots = [
            FundPositionLot(
                id: "old",
                shares: 100,
                cost: 1,
                incomeStartDate: "2026-06-23",
                positionDate: "2026-06-23",
                positionTimeType: .before15
            ),
            FundPositionLot(
                id: "today-buy",
                shares: 100,
                cost: 2,
                incomeStartDate: "2026-06-24",
                positionDate: "2026-06-24",
                positionTimeType: .before15
            )
        ]
        let points = [
            FundNetValuePoint(timestamp: try timestamp("2026-06-23"), value: 2.0, equityReturn: nil),
            FundNetValuePoint(timestamp: try timestamp("2026-06-24"), value: 2.5, equityReturn: nil),
            FundNetValuePoint(timestamp: try timestamp("2026-06-25"), value: 2.6, equityReturn: nil)
        ]

        let rows = FundDailyIncomeCalculator.rows(lots: lots, points: points)

        XCTAssertEqual(rows.map(\.dateText), ["2026-06-25", "2026-06-24", "2026-06-23"])
        XCTAssertEqual(rows[0].dailyIncome, 20, accuracy: 0.0001)
        XCTAssertEqual(rows[0].entryIncome, 0, accuracy: 0.0001)
        XCTAssertEqual(rows[0].cumulativeIncome, 220, accuracy: 0.0001)
        XCTAssertEqual(rows[0].cumulativeRate ?? 0, 220.0 / 300.0 * 100, accuracy: 0.0001)
        XCTAssertEqual(rows[1].dailyIncome, 50, accuracy: 0.0001)
        XCTAssertEqual(rows[1].entryIncome, 50, accuracy: 0.0001)
        XCTAssertEqual(rows[1].cumulativeIncome, 200, accuracy: 0.0001)
        XCTAssertEqual(rows[1].cumulativeRate ?? 0, 200.0 / 300.0 * 100, accuracy: 0.0001)
        XCTAssertEqual(rows[2].dailyIncome, 0, accuracy: 0.0001)
        XCTAssertEqual(rows[2].entryIncome, 100, accuracy: 0.0001)
        XCTAssertEqual(rows[2].cumulativeIncome, 100, accuracy: 0.0001)
    }

    func testPortfolioCalculatorKeepsExistingLotsActiveWhenNewLotIsPending() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-21"))
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 150,
                    migratedCost: 1.3333,
                    migratedPrincipal: 200,
                    incomeStartDate: "2026-06-18",
                    lots: [
                        FundPositionLot(
                            id: "old",
                            shares: 100,
                            cost: 1,
                            incomeStartDate: "2026-06-18",
                            positionDate: "2026-06-17",
                            positionTimeType: .before15
                        ),
                        FundPositionLot(
                            id: "new",
                            shares: 50,
                            cost: 2,
                            incomeStartDate: "2026-06-22",
                            positionDate: "2026-06-18",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.1,
            growthRate: 5,
            estimateTime: "2026-06-21 14:30",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["026210": quote],
            now: now
        )

        XCTAssertEqual(result.totalAmount, 300)
        XCTAssertEqual(result.holdingIncome, 100)
        XCTAssertEqual(result.funds[0].status, .holding)
        XCTAssertEqual(result.funds[0].migratedShares, 150)
        XCTAssertEqual(result.funds[0].isIncomeActive, true)
        XCTAssertEqual(result.todayIncome, 0)
    }

    @MainActor
    func testClearAllHoldingsKeepsPublishedSnapshotWhenPersistenceFails() throws {
        let tempDirectory = temporaryPortfolioDirectory(prefix: "clear-transaction")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let store = PortfolioStore(dataDirectory: tempDirectory)
        try seedPortfolio(transactionTestSnapshot(), into: store, directory: tempDirectory)
        let originalSnapshot = store.snapshot
        try makePortfolioStorageUnwritable(for: store)

        XCTAssertThrowsError(try store.clearAllHoldings())
        XCTAssertEqual(store.snapshot, originalSnapshot)
    }
}
