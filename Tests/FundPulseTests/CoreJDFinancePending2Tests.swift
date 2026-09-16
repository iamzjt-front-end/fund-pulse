import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    func testJDFinancePlannerRecognizesNewPendingBatchForSameFund() throws {
        let now = try chinaDate("2026-07-16 16:00")
        let name = "富国全球科技互联网股票(QDII)C"
        let currentOrders = [
            JDFinanceTradeOrderRecord(
                code: "022184",
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: 600,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            ),
            JDFinanceTradeOrderRecord(
                code: "022184",
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: 400,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            )
        ]
        let product = JDFinanceHoldingProduct(
            skuID: "1022184",
            code: "022184",
            name: name,
            totalAmount: 1_000,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：2笔买入中合计1000.00元",
                action: .buy,
                tradeCount: 2,
                totalAmount: 1_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 1_000,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                statusText: "支付成功",
                matchedTradeRecords: currentOrders
            )
        )
        let olderRecords = [
            FundTradeRecord(
                id: "jd-pending-022184-old-1",
                kind: .buy,
                status: .pending,
                code: "022184",
                name: name,
                mode: .amount,
                amount: 900,
                shares: nil,
                confirmedShares: nil,
                price: nil,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-15",
                createdAt: now,
                confirmedAt: nil,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .waitingExternalConfirmation,
                waitsForExternalConfirmation: true
            ),
            FundTradeRecord(
                id: "jd-pending-022184-old-2",
                kind: .buy,
                status: .pending,
                code: "022184",
                name: name,
                mode: .amount,
                amount: 100,
                shares: nil,
                confirmedShares: nil,
                price: nil,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-15",
                createdAt: now,
                confirmedAt: nil,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .waitingExternalConfirmation,
                waitsForExternalConfirmation: true
            )
        ]
        var fund = conversionFund(code: "022184", name: name, shares: 0, cost: 1)
        fund.status = .pending
        fund.currentAmount = 0
        fund.pendingAmount = 1_000

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 1_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [product]
            ),
            localSnapshot: jdPortfolio(
                funds: [fund],
                records: olderRecords,
                now: now
            )
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertEqual(notice.importKind, .trade(.buy))
        XCTAssertTrue(notice.isImportable)
    }

    func testJDFinancePlannerDoesNotOfferAlreadySyncedMixedPendingBatches() throws {
        let now = try chinaDate("2026-07-16 23:00")
        let name = "富国全球科技互联网股票(QDII)C"
        let remoteOrders = [
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-022184-0715-card",
                code: "022184",
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: 900,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            ),
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-022184-0715-balance",
                code: "022184",
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: 100,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            ),
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-022184-0716-card",
                code: "022184",
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: 900,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            ),
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-022184-0716-balance",
                code: "022184",
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: 100,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            )
        ]
        let product = JDFinanceHoldingProduct(
            skuID: "1022184",
            code: "022184",
            name: name,
            totalAmount: 3_004.61,
            holdIncome: 4.61,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：4笔买入中合计2000.00元",
                action: .buy,
                tradeCount: 4,
                totalAmount: 2_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 2_000,
                tradeDate: nil,
                tradeTimeType: .before15,
                statusText: "匹配交易记录：4 笔",
                matchedTradeRecords: remoteOrders
            )
        )
        let localRecords = [
            FundTradeRecord(
                id: "local-confirmed-022184-0715-card",
                kind: .buy,
                status: .confirmed,
                code: "022184",
                name: name,
                mode: .amount,
                amount: 900,
                shares: nil,
                confirmedShares: 158.21,
                price: 5.6886,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-15",
                createdAt: now,
                confirmedAt: now,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .externalConfirmed,
                waitsForExternalConfirmation: false
            ),
            FundTradeRecord(
                id: "local-confirmed-022184-0715-balance",
                kind: .buy,
                status: .confirmed,
                code: "022184",
                name: name,
                mode: .amount,
                amount: 100,
                shares: nil,
                confirmedShares: 17.58,
                price: 5.6886,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-15",
                createdAt: now,
                confirmedAt: now,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .externalConfirmed,
                waitsForExternalConfirmation: false
            ),
            FundTradeRecord(
                id: "local-pending-022184-0716-card",
                kind: .buy,
                status: .pending,
                code: "022184",
                name: name,
                mode: .amount,
                amount: 900,
                shares: nil,
                confirmedShares: nil,
                price: nil,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-16",
                createdAt: now,
                confirmedAt: nil,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .waitingExternalConfirmation,
                waitsForExternalConfirmation: true
            ),
            FundTradeRecord(
                id: "local-pending-022184-0716-balance",
                kind: .buy,
                status: .pending,
                code: "022184",
                name: name,
                mode: .amount,
                amount: 100,
                shares: nil,
                confirmedShares: nil,
                price: nil,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-16",
                createdAt: now,
                confirmedAt: nil,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .waitingExternalConfirmation,
                waitsForExternalConfirmation: true
            )
        ]
        let fund = FundPosition(
            code: "022184",
            name: name,
            dateText: "07-16 15:00",
            todayIncome: 4.61,
            todayRate: 0.15,
            holdingIncome: 4.61,
            holdingRate: 0.46,
            currentAmount: 1_004.61,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 3_004.61,
                yesterdayIncome: nil,
                todayIncome: 4.63,
                holdIncome: 4.61,
                totalIncome: nil,
                products: [product],
                tradeOrders: remoteOrders,
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [fund], records: localRecords, now: now)
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertNil(notice.importKind)
        XCTAssertFalse(notice.isImportable)
        XCTAssertEqual(preview.localConfirmedJDPendingTradeCount, 2)
        XCTAssertEqual(preview.localPendingTradeCount, 2)
        let difference = try XCTUnwrap(preview.changedHoldings.first)
        XCTAssertEqual(difference.code, "022184")
        XCTAssertEqual(difference.jdPendingBuyAmount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(difference.comparableJDAmount, 2_004.61, accuracy: 0.0001)
    }

    func testJDFinanceWholePositionRecordDoesNotMasqueradeAsPendingOrder() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let baselineRecord = FundTradeRecord(
            id: "whole-position",
            kind: .newFund,
            status: .confirmed,
            code: "022364",
            name: "永赢科技智选混合发起A",
            mode: .amount,
            amount: 20_534.59,
            shares: nil,
            confirmedShares: 10_000,
            price: 2.053459,
            tradeDate: "2026-07-13",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-13",
            createdAt: now,
            confirmedAt: now,
            failureReason: nil
        )
        let product = JDFinanceHoldingProduct(
            skuID: "1022364",
            code: "022364",
            name: "永赢科技智选混合发起A",
            totalAmount: 20_534.59,
            transactionTip: JDFinanceTransactionTip(
                text: "订单完成",
                action: .buy,
                tradeCount: 1,
                totalAmount: 2_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 2_000,
                shares: nil,
                tradeDate: "2026-07-13",
                tradeTimeType: .before15,
                statusText: "订单完成"
            )
        )
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 20_534.59,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [product]
            ),
            localSnapshot: jdPortfolio(
                funds: [conversionFund(code: "022364", name: product.name, shares: 10_000, cost: 2)],
                records: [baselineRecord],
                now: now
            )
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertNil(notice.syncState)
        XCTAssertFalse(notice.message.contains("本地已确认"))
    }

    @MainActor
    func testJDFinanceIncrementalStartKeepsTrackedPendingLookback() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let lastComplete = try chinaDate("2026-07-14 09:00")
        var snapshot = PortfolioSnapshot.empty
        snapshot.jdFinanceSyncState = JDFinanceSyncState(
            baselineEstablishedAt: lastComplete,
            lastCompleteTradeOrderSyncAt: lastComplete,
            trackedPendingOrderKeys: ["pending"],
            trackedPendingStartDate: "2026-07-10"
        )
        let store = PortfolioStore(repository: RecordingPortfolioRepository(initialSnapshot: snapshot))
        store.load()

        XCTAssertEqual(store.jdFinanceTradeOrderStartDate(now: now), "2026-07-10")
    }

    func testJDFinanceSyncPreviewImportsMatchedPendingRedeemWithoutManualCompletion() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 7_171.54,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: 0,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1008998",
                    code: "008998",
                    name: "同泰竞争优势混合C",
                    totalAmount: 7_171.54,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：1笔赎回中合计7171.54份",
                        action: .sell,
                        tradeCount: 1,
                        totalAmount: 7_171.54
                    ),
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .sell,
                        amount: 7_171.54,
                        shares: 7_171.54,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        statusText: "转出中",
                        matchedTradeRecords: [
                            JDFinanceTradeOrderRecord(
                                code: "008998",
                                productName: "转出-同泰竞争优势混合C",
                                action: .sell,
                                amount: 7_171.54,
                                shares: 7_171.54,
                                tradeDate: "2026-07-07",
                                tradeTimeType: .before15,
                                statusText: "转出中"
                            )
                        ]
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 20_000,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "008998",
                    name: "同泰竞争优势混合C",
                    dateText: "07-06 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    currentAmount: 20_000,
                    status: .holding,
                    isUpdated: true,
                    migratedShares: 8_000,
                    migratedCost: 1,
                    migratedPrincipal: 8_000,
                    positionMode: .share,
                    lots: [
                        FundPositionLot(
                            id: "008998-seed",
                            shares: 8_000,
                            cost: 1,
                            incomeStartDate: "2026-07-06",
                            positionDate: "2026-07-06",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertTrue(notice.isImportable)
        XCTAssertFalse(notice.requiresManualCompletion)
        let draft = try XCTUnwrap(notice.tradeDraft())
        XCTAssertEqual(draft.action, .sell)
        XCTAssertEqual(draft.mode, .share)
        XCTAssertEqual(draft.shares ?? 0, 7_171.54, accuracy: 0.0001)
        XCTAssertEqual(draft.tradeDate, "2026-07-07")
        XCTAssertEqual(draft.tradeTimeType, .before15)
    }

    @MainActor
    func testJDFinancePendingNewFundUsesLocalConfirmedNetValueInsteadOfExternalStatus() async throws {
        var now = try chinaDate("2026-07-20 21:30")
        let createdAt = try chinaDate("2026-07-20 14:30")
        let code = "016186"
        let name = "广发中证全指电力ETF发起式联接C"
        let service = tradeQuoteService(
            code: code,
            name: name,
            date: "2026-07-20",
            netValue: 1.1175
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-pending-new-fund-local-confirm-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 1,
                funds: [
                    FundPosition(
                        code: code,
                        name: name,
                        dateText: "07-21 09:30",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingIncome: 0,
                        currentAmount: 0,
                        status: .pending,
                        isUpdated: false,
                        isIncomeActive: false,
                        migratedShares: 0,
                        migratedPrincipal: 0,
                        incomeStartDate: "2026-07-20",
                        positionMode: .amount,
                        positionDate: "2026-07-20",
                        positionTimeType: .before15,
                        pendingAmount: 10_000,
                        memo: "京东金融同步待确认"
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "jd-pending-new-fund-016186",
                        kind: .newFund,
                        status: .pending,
                        code: code,
                        name: name,
                        mode: .amount,
                        amount: 10_000,
                        shares: nil,
                        confirmedShares: nil,
                        price: nil,
                        tradeDate: "2026-07-20",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-20",
                        createdAt: createdAt,
                        confirmedAt: nil,
                        failureReason: nil,
                        syncSource: .jdFinance,
                        syncKey: "trade|buy|016186|2026-07-20|before15|10000.00|",
                        externalStatus: .waitingExternalConfirmation,
                        externalStatusText: "支付成功",
                        waitsForExternalConfirmation: true
                    )
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot.funds.first?.status, .pending)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.status, .pending)

        now = try chinaDate("2026-07-21 09:30")
        await store.refreshQuotes()

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == code })
        XCTAssertEqual(fund.status, .holding)
        XCTAssertNil(fund.pendingAmount)
        XCTAssertEqual(fund.migratedShares ?? 0, 8948.545861, accuracy: 0.000001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 10_000, accuracy: 0.0001)
        XCTAssertEqual(fund.currentAmount ?? 0, 10_000, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.price ?? 0, 1.1175, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 8948.545861, accuracy: 0.000001)
        XCTAssertEqual(record.externalStatus, .externalConfirmed)
        XCTAssertEqual(record.waitsForExternalConfirmation, false)
    }

    @MainActor
    func testJDFinanceOlderPendingBuysConfirmFromCurrentJSONHistoryEndpoint() async throws {
        let now = try chinaDate("2026-08-07 15:30")
        let createdAt = try chinaDate("2026-08-07 13:11")
        let code = "022184"
        let name = "富国全球科技互联网股票(QDII)C"
        let acceptedDates = ["2026-08-03", "2026-08-04"]
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: code,
                name: name,
                netValueDate: "2026-08-05",
                netValue: 5.3627,
                estimatedNetValue: 5.2593,
                growthRate: 0.67,
                estimateTime: "2026-08-07 14:54"
            ),
            "https://api.fund.eastmoney.com/f10/lsjz": """
            {
              "Data": {
                "LSJZList": [
                  {"FSRQ":"2026-08-05","DWJZ":"5.3627"},
                  {"FSRQ":"2026-08-04","DWJZ":"5.3271"},
                  {"FSRQ":"2026-08-03","DWJZ":"5.2248"}
                ]
              },
              "ErrCode": 0
            }
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-json-history-pending-buy-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let records = acceptedDates.map { date in
            FundTradeRecord(
                id: "jd-buy-\(date)",
                kind: .buy,
                status: .pending,
                code: code,
                name: name,
                mode: .amount,
                amount: 200,
                shares: nil,
                confirmedShares: nil,
                price: nil,
                tradeDate: date,
                tradeTimeType: .before15,
                acceptedDate: date,
                createdAt: createdAt,
                confirmedAt: nil,
                failureReason: nil,
                syncSource: .jdFinance,
                syncKey: "jd-order-\(date)",
                externalStatus: .externalConfirmed,
                externalStatusText: "订单完成",
                waitsForExternalConfirmation: false
            )
        }
        let pendingTrades = records.map { record in
            FundPendingTrade(
                id: "pending-\(record.id)",
                recordID: record.id,
                action: .buy,
                code: code,
                mode: .amount,
                amount: 200,
                shares: nil,
                tradeDate: record.tradeDate,
                tradeTimeType: .before15,
                createdAt: createdAt,
                syncSource: .jdFinance,
                syncKey: record.syncKey,
                externalStatus: .externalConfirmed,
                externalStatusText: "订单完成",
                waitsForExternalConfirmation: false
            )
        }
        var snapshot = jdPortfolio(
            funds: [conversionFund(code: code, name: name, shares: 1_000, cost: 5)],
            records: records,
            now: now
        )
        snapshot.pendingTrades = pendingTrades
        snapshot.pendingCount = pendingTrades.count

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(snapshot, into: store, directory: tempDirectory)

        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        let confirmedRecords = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(confirmedRecords.count, 2)
        XCTAssertTrue(confirmedRecords.allSatisfy { $0.status == .confirmed })
        XCTAssertEqual(
            try XCTUnwrap(confirmedRecords.first { $0.acceptedDate == "2026-08-03" }?.price),
            5.2248,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(confirmedRecords.first { $0.acceptedDate == "2026-08-04" }?.price),
            5.3271,
            accuracy: 0.0001
        )

        let historyRequests = MockURLProtocol.responseStore.requests().filter {
            $0.url?.host == "api.fund.eastmoney.com"
        }
        XCTAssertEqual(historyRequests.count, 2)
        XCTAssertEqual(
            Set(historyRequests.compactMap { request in
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first { $0.name == "startDate" }?
                    .value
            }),
            Set(acceptedDates)
        )
        XCTAssertTrue(historyRequests.allSatisfy {
            $0.value(forHTTPHeaderField: "Referer") == "https://fundf10.eastmoney.com/"
        })
    }

    @MainActor
    func testJDFinancePendingConversionUsesNextDayLocalNetValuesInsteadOfExternalStatus() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-conversion-local-confirm-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            ),
            syncMetadata: FundTradeSyncMetadata(
                source: .jdFinance,
                syncKey: "jd-conversion-pending",
                externalStatus: .waitingExternalConfirmation,
                externalStatusText: "处理中",
                waitsForExternalConfirmation: true
            )
        )

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        let sameDayRecords = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertTrue(sameDayRecords.allSatisfy { $0.status == .pending })
        XCTAssertTrue(sameDayRecords.allSatisfy { $0.waitsForExternalConfirmation == true })

        now = try chinaDate("2026-06-23 00:01")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingConversions)
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.status == .confirmed })
        XCTAssertTrue(records.allSatisfy { $0.externalStatus == .externalConfirmed })
        XCTAssertTrue(records.allSatisfy { $0.waitsForExternalConfirmation == false })

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 247.014925, accuracy: 0.000001)
    }

    func testPortfolioCalculatorExcludesSameDayJDPendingBuyEmbeddedInSyncedAmount() throws {
        let now = try chinaDate("2026-07-16 16:00")
        let amount = 10_000.0
        let pendingBuyAmount = 2_000.0
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
                    id: "026210-jd-sync",
                    shares: shares,
                    cost: 1,
                    principal: amount,
                    incomeStartDate: "2026-07-15",
                    positionDate: "2026-07-15",
                    positionTimeType: .before15
                )
            ]
        )
        let baseline = FundTradeRecord(
            id: "jd-baseline-026210",
            kind: .newFund,
            status: .confirmed,
            code: fund.code,
            name: fund.name,
            mode: .amount,
            amount: amount,
            shares: nil,
            confirmedShares: shares,
            price: netValue,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: now,
            confirmedAt: now,
            failureReason: nil,
            syncSource: .jdFinance,
            externalStatus: .externalConfirmed,
            waitsForExternalConfirmation: false,
            isReconciliationBaseline: true
        )
        let pending = FundTradeRecord(
            id: "jd-pending-026210",
            kind: .buy,
            status: .pending,
            code: fund.code,
            name: fund.name,
            mode: .amount,
            amount: pendingBuyAmount,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: now,
            confirmedAt: nil,
            failureReason: nil,
            syncSource: .jdFinance,
            externalStatus: .waitingExternalConfirmation,
            waitsForExternalConfirmation: true
        )
        let snapshot = jdPortfolio(
            funds: [fund],
            records: [baseline, pending],
            now: now
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

        let expectedTodayIncome = (amount - pendingBuyAmount) * quote.growthRate / (100 + quote.growthRate)
        XCTAssertEqual(result.funds[0].currentAmount ?? 0, amount - pendingBuyAmount, accuracy: 0.0001)
        XCTAssertEqual(result.totalAmount, amount - pendingBuyAmount, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncomeRate, quote.growthRate, accuracy: 0.0001)
    }

    @MainActor
    func testPortfolioStorePersistsJDFinancePendingBuyAmountOnAmountSync() async throws {
        let now = try chinaDate("2026-07-16 16:00")
        let amount = 10_000.0
        let netValue = 0.9
        let fund = FundPosition(
            code: "026210",
            name: "平安科技精选混合发起式A",
            dateText: "07-15 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: 0,
            currentAmount: amount,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: amount / netValue,
            migratedCost: 1,
            migratedPrincipal: amount,
            incomeStartDate: "2026-07-15",
            positionMode: .amount,
            positionDate: "2026-07-15",
            positionTimeType: .before15
        )
        let store = PortfolioStore(
            repository: RecordingPortfolioRepository(initialSnapshot: jdPortfolio(
                funds: [fund],
                records: [],
                now: now
            )),
            quoteService: multiTradeQuoteService([
                "026210": (
                    name: fund.name,
                    date: "2026-07-16",
                    netValue: netValue
                )
            ]),
            now: { now }
        )
        store.load()

        try await store.applyAmountPositionSyncUpdates([
            FundAmountPositionSyncUpdate(
                code: fund.code,
                amount: amount,
                holdingIncome: 0,
                syncedPendingBuyAmount: 2_000,
                syncedAt: now
            )
        ])

        let syncedFund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(syncedFund.syncedPendingBuyAmount ?? 0, 2_000, accuracy: 0.0001)
        XCTAssertEqual(syncedFund.syncedPendingBuyDate, "2026-07-16")
        XCTAssertEqual(syncedFund.currentAmount ?? 0, amount - 2_000, accuracy: 0.0001)
    }

    @MainActor
    func testPortfolioStorePersistsPendingBuyMetadataDuringJDFinanceSync() throws {
        let now = try chinaDate("2026-07-16 16:00")
        let fund = FundPosition(
            code: "026210",
            name: "平安科技精选混合发起式A",
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: 0,
            currentAmount: 10_000,
            status: .holding,
            isUpdated: true
        )
        let store = PortfolioStore(
            repository: RecordingPortfolioRepository(initialSnapshot: jdPortfolio(
                funds: [fund],
                records: [],
                now: now
            )),
            now: { now }
        )
        store.load()

        try store.applyJDFinanceSyncMetadata(
            accountTotal: 10_000,
            confirmations: [],
            syncedAt: now,
            syncedPendingBuyAmounts: [fund.code: 2_000],
            syncedTodayIncomes: [fund.code: -647.32]
        )

        XCTAssertEqual(store.snapshot.funds[0].syncedPendingBuyAmount ?? 0, 2_000, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.funds[0].syncedPendingBuyDate, "2026-07-16")
        XCTAssertEqual(store.snapshot.funds[0].syncedTodayIncome ?? 0, -647.32, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.funds[0].syncedTodayIncomeDate, "2026-07-16")
        XCTAssertEqual(store.snapshot.funds[0].currentAmount ?? 0, 10_000, accuracy: 0.0001)

        try store.applyJDFinanceSyncMetadata(
            accountTotal: 10_000,
            confirmations: [],
            syncedAt: now,
            syncedPendingBuyAmounts: [fund.code: nil],
            syncedTodayIncomes: [fund.code: nil]
        )

        XCTAssertNil(store.snapshot.funds[0].syncedPendingBuyAmount)
        XCTAssertNil(store.snapshot.funds[0].syncedPendingBuyDate)
        XCTAssertNil(store.snapshot.funds[0].syncedTodayIncome)
        XCTAssertNil(store.snapshot.funds[0].syncedTodayIncomeDate)
    }

    @MainActor
    func testJDFinanceSyncMetadataConfirmsPendingNewFundCoveredByBaseline() throws {
        let now = try chinaDate("2026-07-16 23:00")
        let name = "富国全球科技互联网股票(QDII)C"
        let fund = FundPosition(
            code: "022184",
            name: name,
            dateText: "07-16 15:00",
            todayIncome: 4.61,
            todayRate: 0.15,
            holdingIncome: 4.61,
            holdingRate: 0.46,
            currentAmount: 1_004.61,
            status: .holding,
            isUpdated: true
        )
        let pendingRecord = FundTradeRecord(
            id: "pending-new-fund-022184",
            kind: .newFund,
            status: .pending,
            code: fund.code,
            name: name,
            mode: .amount,
            amount: 1_000,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: "2026-07-13",
            tradeTimeType: .after15,
            acceptedDate: "2026-07-14",
            createdAt: now.addingTimeInterval(-86_400),
            confirmedAt: nil,
            failureReason: nil,
            syncSource: .jdFinance,
            externalStatus: .waitingExternalConfirmation,
            waitsForExternalConfirmation: true
        )
        let baselineRecord = FundTradeRecord(
            id: "jd-baseline-022184",
            kind: .newFund,
            status: .confirmed,
            code: fund.code,
            name: name,
            mode: .amount,
            amount: 3_004.61,
            shares: nil,
            confirmedShares: 528.18,
            price: 5.6886,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: now,
            confirmedAt: now,
            failureReason: nil,
            syncSource: .jdFinance,
            externalStatus: .externalConfirmed,
            externalStatusText: "京东持仓对账基线",
            waitsForExternalConfirmation: false,
            isReconciliationBaseline: true
        )
        var snapshot = jdPortfolio(
            funds: [fund],
            records: [pendingRecord, baselineRecord],
            now: now
        )
        snapshot.pendingCount = 1
        snapshot.pendingTrades = [
            FundPendingTrade(
                id: "pending-trade-022184",
                recordID: pendingRecord.id,
                action: .buy,
                code: fund.code,
                mode: .amount,
                amount: 1_000,
                shares: nil,
                tradeDate: pendingRecord.tradeDate,
                tradeTimeType: pendingRecord.tradeTimeType,
                createdAt: pendingRecord.createdAt,
                syncSource: .jdFinance,
                externalStatus: .waitingExternalConfirmation,
                waitsForExternalConfirmation: true
            )
        ]
        let store = PortfolioStore(
            repository: RecordingPortfolioRepository(initialSnapshot: snapshot),
            now: { now }
        )
        store.load()

        try store.applyJDFinanceSyncMetadata(
            accountTotal: 3_004.61,
            confirmations: [],
            syncedAt: now,
            syncedPendingBuyAmounts: [fund.code: 2_000]
        )

        let updatedRecord = try XCTUnwrap(
            store.snapshot.tradeRecords?.first(where: { $0.id == pendingRecord.id })
        )
        XCTAssertEqual(updatedRecord.status, .confirmed)
        XCTAssertEqual(updatedRecord.externalStatus, .externalConfirmed)
        XCTAssertEqual(updatedRecord.waitsForExternalConfirmation, false)
        XCTAssertTrue(store.snapshot.pendingTrades?.isEmpty ?? true)
    }
}
