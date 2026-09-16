import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    func testJDFinanceHoldingsServiceFillsPendingDetailWhenAvailable() async throws {
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: Self.jdFinancePendingDetailResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.action, .buy)
        XCTAssertEqual(detail.amount ?? 0, 7_632.07, accuracy: 0.0001)
        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.statusText, "买入确认中")
    }

    func testJDFinanceHoldingsServicePrefersTodayPendingPaymentOverOlderCompletedSameAmount() async throws {
        let holdingsResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "headAssetsData": {
                "totalAssets": { "text": "20,000.00" },
                "holdIncome": { "text": "0.00" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1022364",
                        "fundCode": "022364",
                        "productName": "永赢科技智选混合发起A",
                        "totalAmount": { "text": "20,000.00" },
                        "transactionTip": { "text": "交易：1笔买入中合计2000.00元" },
                        "jumpData": {
                          "param": {
                            "extJson": "{\\"source\\":\\"pending-detail\\"}"
                          }
                        }
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
        """
        let detailResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "detail": {
                "tradeType": "买入",
                "tradeAmount": "2000.00",
                "tradeStatus": "支付成功"
              }
            }
          }
        }
        """
        let tradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "orderId": "today-pending",
                  "productId": "1022364",
                  "productName": "永赢科技智选混合发起A",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "2000.00",
                  "bizTime": "2026-07-16 10:05:00",
                  "statusCode": "PAY_SUCC",
                  "statusName": "支付成功"
                },
                {
                  "orderId": "older-completed",
                  "productId": "1022364",
                  "productName": "永赢科技智选混合发起A",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "2000.00",
                  "bizTime": "2026-07-13 10:05:00",
                  "statusCode": "COMPLETE",
                  "statusName": "订单完成"
                }
              ]
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: tradeOrderResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.tradeDate, "2026-07-16")
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.matchedTradeRecords.map(\.tradeDate), ["2026-07-16"])
        XCTAssertEqual(detail.matchedTradeRecords.first?.statusText, "支付成功")
        XCTAssertTrue(detail.candidateTradeRecords.isEmpty)
    }

    func testJDFinanceHoldingsServicePrefersPendingPaymentBatchOverAmbiguousCompletedHistory() async throws {
        let holdingsResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "headAssetsData": {
                "totalAssets": { "text": "20,000.00" },
                "holdIncome": { "text": "0.00" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1022184",
                        "fundCode": "022184",
                        "productName": "富国全球科技互联网股票(QDII)C",
                        "totalAmount": { "text": "20,000.00" },
                        "transactionTip": { "text": "交易：4笔买入中合计2000.00元" },
                        "jumpData": {
                          "param": {
                            "extJson": "{\\"source\\":\\"pending-detail\\"}"
                          }
                        }
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
        """
        let detailResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "detail": {
                "tradeType": "买入",
                "tradeAmount": "2000.00",
                "tradeStatus": "支付成功"
              }
            }
          }
        }
        """
        let tradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "orderId": "pending-17-900",
                  "productId": "1022184",
                  "productName": "富国全球科技互联网股票(QDII)C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "900.00",
                  "bizTime": "2026-07-17 10:05:00",
                  "statusCode": "PAY_SUCC",
                  "statusName": "支付成功"
                },
                {
                  "orderId": "pending-17-100",
                  "productId": "1022184",
                  "productName": "富国全球科技互联网股票(QDII)C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "100.00",
                  "bizTime": "2026-07-17 10:06:00",
                  "statusCode": "PAY_SUCC",
                  "statusName": "支付成功"
                },
                {
                  "orderId": "pending-16-900",
                  "productId": "1022184",
                  "productName": "富国全球科技互联网股票(QDII)C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "900.00",
                  "bizTime": "2026-07-16 10:05:00",
                  "statusCode": "PAY_SUCC",
                  "statusName": "支付成功"
                },
                {
                  "orderId": "pending-16-100",
                  "productId": "1022184",
                  "productName": "富国全球科技互联网股票(QDII)C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "100.00",
                  "bizTime": "2026-07-16 10:06:00",
                  "statusCode": "PAY_SUCC",
                  "statusName": "支付成功"
                },
                {
                  "orderId": "completed-15-900",
                  "productId": "1022184",
                  "productName": "富国全球科技互联网股票(QDII)C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "900.00",
                  "bizTime": "2026-07-15 10:05:00",
                  "statusCode": "COMPLETE",
                  "statusName": "订单完成"
                },
                {
                  "orderId": "completed-15-100",
                  "productId": "1022184",
                  "productName": "富国全球科技互联网股票(QDII)C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "100.00",
                  "bizTime": "2026-07-15 10:06:00",
                  "statusCode": "COMPLETE",
                  "statusName": "订单完成"
                }
              ]
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: tradeOrderResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertNil(detail.tradeDate)
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.matchedTradeRecords.count, 4)
        XCTAssertEqual(detail.matchedTradeRecords.map(\.tradeDate), [
            "2026-07-17",
            "2026-07-17",
            "2026-07-16",
            "2026-07-16"
        ])
        XCTAssertTrue(detail.matchedTradeRecords.allSatisfy { $0.effectiveStatus == .pending })
        XCTAssertEqual(detail.matchedTradeRecords.compactMap(\.amount).reduce(0, +), 2_000, accuracy: 0.0001)
        XCTAssertTrue(detail.candidateTradeRecords.isEmpty)
    }

    @MainActor
    func testJDFinanceSyncStoreImportsPendingNoticeAsLocalPendingFund() async throws {
        let now = try chinaDate("2026-07-03 10:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-sync-pending-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: Self.jdFinancePendingDetailResponse,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "011833",
                name: "西部利得人工智能主题指数增强C",
                netValueDate: "2026-07-02",
                netValue: 2,
                estimatedNetValue: 2,
                growthRate: 0,
                estimateTime: "2026-07-02 15:00"
            )
        ]
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: session),
            now: { now }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: FundQuoteService(session: session),
            now: { now }
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), ["011833"])

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: false,
            importPending: true
        )

        let fund = try XCTUnwrap(portfolioStore.snapshot.funds.first { $0.code == "011833" })
        XCTAssertEqual(fund.status, .pending)
        XCTAssertEqual(fund.pendingAmount ?? 0, 7_632.07, accuracy: 0.0001)
        XCTAssertEqual(fund.pendingProfit ?? 0, -88.88, accuracy: 0.0001)
        XCTAssertEqual(fund.positionDate, "2026-07-03")
        XCTAssertEqual(fund.positionTimeType, .before15)
        let record = try XCTUnwrap(portfolioStore.snapshot.tradeRecords?.first { $0.code == "011833" })
        XCTAssertEqual(record.status, .pending)
        XCTAssertEqual(record.amount ?? 0, 7_632.07, accuracy: 0.0001)
        XCTAssertEqual(record.profit ?? 0, -88.88, accuracy: 0.0001)
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), [])
        XCTAssertEqual(syncStore.statusMessage, "已同步 1 项数据")
    }

    @MainActor
    func testJDFinanceSyncStoreImportsQDIIThreePaymentRowsAsTwoPendingBuys() async throws {
        func suggestPrefix(_ key: String) throws -> String {
            var components = try XCTUnwrap(
                URLComponents(string: "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx")
            )
            components.queryItems = [
                URLQueryItem(name: "m", value: "1"),
                URLQueryItem(name: "key", value: key)
            ]
            return try XCTUnwrap(components.url).absoluteString + "&callback="
        }

        let now = try chinaDate("2026-07-15 14:07")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-qdii-split-payment-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fundName = "富国全球科技互联网股票(QDII)C"
        let holdingsResponse = """
        {"success":true,"resultCode":0,"resultData":{"success":true,"resultData":{"headAssetsData":{"totalAssets":{"text":"2,000.00"},"holdIncome":{"text":"0.00"}},"fundData":{"fundList":[{"productList":[{"skuId":"1022184","productName":"\(fundName)","totalAmount":{"text":"2,000.00"},"holdIncome":{"text":"0.00"},"transactionTip":{"text":"交易：3笔买入中合计2000.00元"}}]}]}}}}
        """
        let tradeOrderResponse = """
        {"resultCode":0,"resultData":{"data":{"tradeOrderVoList":[
          {"orderId":"today-card","productId":"1022184","productName":"\(fundName)","tradeTypeCode":"TRANSFER_IN","allAmount":"900.00","bizTime":"2026-07-15 10:05:00","statusCode":"PAY_SUCC","statusName":"支付成功"},
          {"orderId":"today-balance","productId":"1022184","productName":"\(fundName)","tradeTypeCode":"TRANSFER_IN","allAmount":"100.00","bizTime":"2026-07-15 10:05:00","statusCode":"PAY_SUCC","statusName":"支付成功"},
          {"orderId":"yesterday-buy","productId":"1022184","productName":"\(fundName)","tradeTypeCode":"TRANSFER_IN","allAmount":"1000.00","bizTime":"2026-07-13 16:05:00","statusCode":"PAY_SUCC","statusName":"支付成功"}
        ]}}}
        """
        let exactSuggestResponse = """
        FundPulseSuggest_123({"Datas":[{"CODE":"VSS","NAME":"Vanguard FTSE All-World ex-US Small-Cap ETF","CATEGORYDESC":"美股"}]});
        """
        let baseSuggestResponse = """
        FundPulseSuggest_123({"Datas":[
          {"CODE":"100055","NAME":"富国全球科技互联网股票(QDII)A","CATEGORYDESC":"基金"},
          {"CODE":"022184","NAME":"富国全球科技互联网股票(QDII)C","CATEGORYDESC":"基金"},
          {"CODE":"026228","NAME":"富国全球科技互联网股票(QDII)D","CATEGORYDESC":"基金"}
        ]});
        """
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: tradeOrderResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: tradeOrderResponse,
            try suggestPrefix(fundName): exactSuggestResponse,
            try suggestPrefix("富国全球科技互联网股票"): baseSuggestResponse,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "022184",
                name: fundName,
                netValueDate: "2026-07-11",
                netValue: 1,
                estimatedNetValue: 1,
                growthRate: 0,
                estimateTime: "2026-07-15 14:07"
            )
        ]
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: session),
            codeResolver: JDFinanceFundCodeResolver(quoteService: FundQuoteService(session: session)),
            now: { now }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: FundQuoteService(session: session),
            now: { now }
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )

        let notice = try XCTUnwrap(syncStore.preview?.importablePendingNotices.first)
        XCTAssertEqual(notice.code, "022184")
        XCTAssertEqual(notice.tradeCountText, "2 笔")
        XCTAssertEqual(syncStore.preview?.pendingTradeCount, 2)
        XCTAssertEqual(syncStore.preview?.importablePendingTradeCount, 2)
        XCTAssertTrue(syncStore.preview?.unresolvedHoldings.isEmpty == true)

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: false,
            importPending: true
        )

        let records = (portfolioStore.snapshot.tradeRecords ?? [])
            .filter { $0.code == "022184" }
            .sorted { ($0.tradeDate, $0.tradeTimeType.rawValue) < ($1.tradeDate, $1.tradeTimeType.rawValue) }
        XCTAssertEqual(portfolioStore.snapshot.pendingCount, 2)
        XCTAssertEqual(records.map(\.kind), [.newFund, .buy])
        XCTAssertEqual(records.map(\.amount), [1_000, 1_000])
        XCTAssertEqual(records.map(\.tradeDate), ["2026-07-13", "2026-07-15"])
        XCTAssertEqual(records.map(\.tradeTimeType), [.after15, .before15])
        XCTAssertEqual(records.map(\.acceptedDate), ["2026-07-14", "2026-07-15"])
        XCTAssertTrue(records.allSatisfy { $0.status == .pending })
        XCTAssertTrue(records.allSatisfy { $0.syncSource == .jdFinance })
        XCTAssertTrue(records.allSatisfy { $0.waitsForExternalConfirmation == true })
    }

    @MainActor
    func testJDFinanceCombinedAmountAndPendingSyncIsStableForMixedLocalConfirmation() async throws {
        let now = try chinaDate("2026-07-21 16:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-mixed-pending-idempotency-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let code = "022184"
        let name = "富国全球科技互联网股票(QDII)C"
        let remoteAmount = 4_961.25
        let localConfirmedAmount = 4_861.25
        let netValue = 5.3344
        let localPrincipal = 5_000.0
        let localShares = localConfirmedAmount / netValue
        let holdingsResponse = """
        {"success":true,"resultCode":0,"resultData":{"success":true,"resultData":{"headAssetsData":{"totalAssets":{"text":"4,961.25"},"holdIncome":{"text":"-138.75"}},"fundData":{"fundList":[{"productList":[{"skuId":"1022184","fundCode":"022184","productName":"\(name)","totalAmount":{"text":"4,961.25"},"holdIncome":{"text":"-138.75"},"transactionTip":{"text":"交易：2笔买入中合计1100.00元"}}]}]}}}}
        """
        let tradeOrderResponse = """
        {"resultCode":0,"resultData":{"data":{"tradeOrderVoList":[
          {"orderId":"jd-022184-yesterday-1000","fundCode":"022184","productId":"1022184","productName":"\(name)","tradeTypeCode":"TRANSFER_IN","allAmount":"1000.00","bizTime":"2026-07-20 10:00:00","statusCode":"PAY_SUCC","statusName":"支付成功"},
          {"orderId":"jd-022184-today-100","fundCode":"022184","productId":"1022184","productName":"\(name)","tradeTypeCode":"TRANSFER_IN","allAmount":"100.00","bizTime":"2026-07-21 10:00:00","statusCode":"PAY_SUCC","statusName":"支付成功"}
        ]}}}
        """
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: tradeOrderResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: tradeOrderResponse,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: code,
                name: name,
                netValueDate: "2026-07-20",
                netValue: netValue,
                estimatedNetValue: netValue,
                growthRate: 0,
                estimateTime: "2026-07-21 15:00"
            )
        ]
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let quoteService = FundQuoteService(session: session)
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: session),
            codeResolver: JDFinanceFundCodeResolver(quoteService: quoteService),
            now: { now }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: quoteService,
            now: { now }
        )
        let fund = FundPosition(
            code: code,
            name: name,
            dateText: "07-20 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: -138.75,
            holdingRate: -2.775,
            confirmedHoldingIncome: -138.75,
            confirmedHoldingRate: -2.775,
            currentAmount: localConfirmedAmount,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: localShares,
            migratedCost: localPrincipal / localShares,
            migratedPrincipal: localPrincipal,
            incomeStartDate: "2026-07-20",
            positionMode: .amount,
            positionDate: "2026-07-20",
            positionTimeType: .before15,
            lots: [
                FundPositionLot(
                    id: "022184-existing-position",
                    shares: localShares,
                    cost: localPrincipal / localShares,
                    principal: localPrincipal,
                    incomeStartDate: "2026-07-20",
                    positionDate: "2026-07-20",
                    positionTimeType: .before15
                )
            ]
        )
        try seedPortfolio(
            jdPortfolio(funds: [fund], records: [], now: now),
            into: portfolioStore,
            directory: tempDirectory
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )

        XCTAssertEqual(syncStore.preview?.changedHoldings.map(\.code), [code])
        XCTAssertEqual(syncStore.preview?.importablePendingTradeCount, 2)

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: true,
            importPending: true
        )

        let firstAppliedSnapshot = portfolioStore.snapshot
        let syncedFund = try XCTUnwrap(firstAppliedSnapshot.funds.first { $0.code == code })
        XCTAssertEqual(syncedFund.currentAmount ?? 0, localConfirmedAmount, accuracy: 0.01)
        XCTAssertEqual(syncedFund.syncedPendingBuyAmount ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(firstAppliedSnapshot.pendingTrades?.map(\.amount), [100])
        XCTAssertEqual(firstAppliedSnapshot.pendingCount, 1)
        XCTAssertTrue(syncStore.preview?.changedHoldings.isEmpty == true)
        XCTAssertTrue(syncStore.preview?.importablePendingNotices.isEmpty == true)

        let fundRecords = (firstAppliedSnapshot.tradeRecords ?? []).filter { $0.code == code }
        XCTAssertEqual(fundRecords.filter { $0.isReconciliationBaseline == true }.count, 1)
        XCTAssertEqual(fundRecords.filter { $0.status == .pending }.compactMap(\.amount), [100])
        XCTAssertFalse(fundRecords.contains { $0.status == .confirmed && $0.kind == .buy && $0.amount == 1_000 })

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: true,
            importPending: true
        )

        XCTAssertEqual(portfolioStore.snapshot, firstAppliedSnapshot)
        XCTAssertEqual(portfolioStore.snapshot.funds.first?.currentAmount ?? 0, localConfirmedAmount, accuracy: 0.01)
        XCTAssertEqual(portfolioStore.snapshot.pendingTrades?.map(\.amount), [100])
        XCTAssertEqual(remoteAmount - (portfolioStore.snapshot.funds.first?.currentAmount ?? 0), 100, accuracy: 0.01)
    }

    @MainActor
    func testJDFinanceSyncStoreImportsHoldingTransactionTipAsPendingBuyTrade() async throws {
        let now = try chinaDate("2026-07-03 10:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-sync-pending-trade-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: Self.jdFinancePendingDetailResponse,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "011833",
                name: "西部利得人工智能主题指数增强C",
                netValueDate: "2026-07-02",
                netValue: 2,
                estimatedNetValue: 2,
                growthRate: 0,
                estimateTime: "2026-07-02 15:00"
            )
        ]
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: session),
            now: { now }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: FundQuoteService(session: session),
            now: { now }
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 8_000,
            holdingIncome: -200,
            holdingIncomeRate: -2.44,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "011833",
                    name: "西部利得人工智能主题指数增强C",
                    dateText: "07-02 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: -200,
                    holdingRate: -2.44,
                    currentAmount: 8_000,
                    status: .holding,
                    isUpdated: true,
                    migratedShares: 4_000,
                    migratedCost: 2.05,
                    migratedPrincipal: 8_200,
                    lots: [
                        FundPositionLot(
                            id: "011833-initial",
                            shares: 4_000,
                            cost: 2.05,
                            principal: 8_200,
                            incomeStartDate: "2026-07-02",
                            positionDate: "2026-07-02",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil
        )
        try seedPortfolio(localSnapshot, into: portfolioStore, directory: tempDirectory)

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )
        XCTAssertEqual(syncStore.preview?.changedHoldings.map(\.code), ["011833"])
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), ["011833"])
        XCTAssertEqual(syncStore.preview?.pendingNotices.first?.importKind, .trade(.buy))
        XCTAssertEqual(portfolioStore.snapshot.funds.first { $0.code == "011833" }?.status, .holding)

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: false,
            importPending: true
        )

        let fund = try XCTUnwrap(portfolioStore.snapshot.funds.first { $0.code == "011833" })
        XCTAssertEqual(fund.status, .holding)
        XCTAssertEqual(fund.currentAmount ?? 0, 8_000, accuracy: 0.0001)
        let pendingTrade = try XCTUnwrap(portfolioStore.snapshot.pendingTrades?.first { $0.code == "011833" })
        XCTAssertEqual(pendingTrade.action, .buy)
        XCTAssertEqual(pendingTrade.amount ?? 0, 7_632.07, accuracy: 0.0001)
        XCTAssertEqual(pendingTrade.tradeDate, "2026-07-03")
        XCTAssertEqual(pendingTrade.tradeTimeType, .before15)
        let record = try XCTUnwrap(portfolioStore.snapshot.tradeRecords?.first { $0.code == "011833" && $0.kind == .buy })
        XCTAssertEqual(record.status, .pending)
        XCTAssertEqual(record.amount ?? 0, 7_632.07, accuracy: 0.0001)
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), [])
    }

    @MainActor
    func testJDFinanceSyncStoreImportsConversionPendingNotice() async throws {
        let now = try chinaDate("2026-07-07 13:10")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-sync-conversion-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let holdingsResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "success": true,
            "resultCode": 0,
            "resultMsg": "success",
            "resultData": {
              "headAssetsData": { "totalAssets": { "text": "8,000.00" } },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1007818",
                        "fundCode": "007818",
                        "productName": "国泰中证全指通信设备ETF联接C",
                        "totalAmount": { "text": "8,000.00" },
                        "holdIncome": { "text": "0.00" },
                        "transactionTip": { "text": "交易：2笔转换中" }
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
        """
        let tradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "code": "0000",
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "109922",
                  "productName": "转换-国泰中证全指通信设备ETF联接C",
                  "sellProductName": "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                  "tradeTypeName": "转换",
                  "tradeTypeCode": "TRANSFORM",
                  "allAmount": "¥ 971.77",
                  "tradeShare": "971.77",
                  "bizTime": "2026-07-07 15:00前",
                  "statusName": "处理中",
                  "statusCode": "PROCESS"
                },
                {
                  "productId": "109922",
                  "productName": "转换-国泰中证全指通信设备ETF联接C",
                  "sellProductName": "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                  "tradeTypeName": "转换",
                  "tradeTypeCode": "TRANSFORM",
                  "allAmount": "¥ 971.78",
                  "tradeShare": "971.78",
                  "bizTime": "2026-07-07 15:00前",
                  "statusName": "处理中",
                  "statusCode": "PROCESS"
                }
              ]
            }
          }
        }
        """
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: tradeOrderResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: """
            {"resultCode":0,"resultData":{"data":{"tradeOrderVoList":[]}}}
            """,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse([
                CoreQuoteMock(
                    code: "007818",
                    name: "国泰中证全指通信设备ETF联接C",
                    netValueDate: "2026-07-06",
                    netValue: 1,
                    estimatedNetValue: 1,
                    growthRate: 0,
                    estimateTime: "2026-07-07 13:10"
                ),
                CoreQuoteMock(
                    code: "024418",
                    name: "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                    netValueDate: "2026-07-06",
                    netValue: 1,
                    estimatedNetValue: 1,
                    growthRate: 0,
                    estimateTime: "2026-07-07 13:10"
                )
            ])
        ]
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: session),
            now: { now }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: FundQuoteService(session: session),
            now: { now }
        )
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
                    conversionFund(code: "007818", name: "国泰中证全指通信设备ETF联接C", shares: 2_000, cost: 1),
                    conversionFund(code: "024418", name: "华夏上证科创板半导体材料设备主题ETF发起式联接C", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: portfolioStore,
            directory: tempDirectory
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )

        let notice = try XCTUnwrap(syncStore.preview?.pendingNotices.first { $0.code == "007818" })
        XCTAssertEqual(notice.actionTitle, "转换")
        XCTAssertEqual(notice.importKind, .conversion(toCode: "024418", toName: "华夏上证科创板半导体材料设备主题ETF发起式联接C"))
        XCTAssertEqual(notice.matchedTradeRecords.count, 2)
        XCTAssertEqual(notice.matchedTradeRecords.first?.shares ?? 0, 971.77, accuracy: 0.0001)
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), ["007818"])

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: false,
            importPending: true
        )

        let pendingConversions = try XCTUnwrap(portfolioStore.snapshot.pendingConversions)
            .sorted { $0.shares < $1.shares }
        XCTAssertEqual(pendingConversions.count, 2)
        XCTAssertEqual(pendingConversions.map(\.fromCode), ["007818", "007818"])
        XCTAssertEqual(pendingConversions.map(\.toCode), ["024418", "024418"])
        XCTAssertEqual(pendingConversions.map(\.shares), [971.77, 971.78])
        XCTAssertEqual(pendingConversions.map(\.tradeDate), ["2026-07-07", "2026-07-07"])
        XCTAssertEqual(pendingConversions.map(\.tradeTimeType), [.before15, .before15])

        let records = try XCTUnwrap(portfolioStore.snapshot.tradeRecords)
        let outRecords = records.filter { $0.kind == .conversionOut }.sorted { ($0.shares ?? 0) < ($1.shares ?? 0) }
        let inRecords = records.filter { $0.kind == .conversionIn }
        XCTAssertEqual(outRecords.count, 2)
        XCTAssertEqual(inRecords.count, 2)
        XCTAssertEqual(outRecords.map(\.code), ["007818", "007818"])
        XCTAssertEqual(outRecords.map(\.linkedCode), ["024418", "024418"])
        XCTAssertEqual(outRecords.map { $0.shares ?? 0 }, [971.77, 971.78])
        XCTAssertEqual(Set(records.compactMap(\.conversionID)), Set(pendingConversions.map(\.id)))
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), [])
    }

    @MainActor
    func testJDFinanceSyncStoreImportsConversionPendingNoticeWithLookedUpTargetCode() async throws {
        let now = try chinaDate("2026-07-07 13:20")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-sync-conversion-lookup-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let holdingsResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "success": true,
            "resultCode": 0,
            "resultMsg": "success",
            "resultData": {
              "headAssetsData": { "totalAssets": { "text": "18,000.00" } },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1011172",
                        "fundCode": "011172",
                        "productName": "广发利鑫混合C",
                        "totalAmount": { "text": "14,639.00" },
                        "holdIncome": { "text": "0.00" },
                        "transactionTip": { "text": "交易：1笔转换中" }
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
        """
        let tradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "code": "0000",
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "111172",
                  "productName": "转换-广发利鑫混合C",
                  "sellProductName": "易方达上证科创50ETF联接C",
                  "sellProductId": "113284",
                  "tradeTypeName": "转换",
                  "tradeTypeCode": "TRANSFORM",
                  "allAmount": "¥ 2,773.85",
                  "tradeShare": "2773.85",
                  "bizTime": "2026-07-07 15:00前",
                  "statusName": "处理中",
                  "statusCode": "PROCESS"
                }
              ]
            }
          }
        }
        """
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: tradeOrderResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: """
            {"resultCode":0,"resultData":{"data":{"tradeOrderVoList":[]}}}
            """,
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": """
            FundPulseSuggest_123({"Datas":[{"CODE":"011609","NAME":"易方达上证科创板50成份交易型开放式指数证券投资基金联接基金","SHORTNAME":"易方达上证科创50ETF联接C","CATEGORYDESC":"基金"}]});
            """,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse([
                CoreQuoteMock(
                    code: "011172",
                    name: "广发利鑫灵活配置混合C",
                    netValueDate: "2026-07-06",
                    netValue: 1,
                    estimatedNetValue: 1,
                    growthRate: 0,
                    estimateTime: "2026-07-07 13:20"
                ),
                CoreQuoteMock(
                    code: "011609",
                    name: "易方达上证科创50ETF联接C",
                    netValueDate: "2026-07-06",
                    netValue: 1,
                    estimatedNetValue: 1,
                    growthRate: 0,
                    estimateTime: "2026-07-07 13:20"
                ),
                CoreQuoteMock(
                    code: "013284",
                    name: "上银价值增长3个月持有期混合A",
                    netValueDate: "2026-07-06",
                    netValue: 1,
                    estimatedNetValue: 1,
                    growthRate: 0,
                    estimateTime: "2026-07-07 13:20"
                )
            ])
        ]
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: session),
            now: { now }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: FundQuoteService(session: session),
            now: { now }
        )
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
                    conversionFund(code: "011172", name: "广发利鑫灵活配置混合C", shares: 4_000, cost: 1),
                    conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 0, cost: 1)
                ],
                migration: nil
            ),
            into: portfolioStore,
            directory: tempDirectory
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )

        let notice = try XCTUnwrap(syncStore.preview?.pendingNotices.first { $0.code == "011172" })
        XCTAssertEqual(notice.actionTitle, "转换")
        XCTAssertEqual(notice.importKind, .conversion(toCode: "011609", toName: "易方达上证科创50ETF联接C"))
        XCTAssertEqual(notice.matchedTradeRecords.first?.conversionTargetCode, "011609")
        XCTAssertEqual(notice.matchedTradeRecords.first?.shares ?? 0, 2_773.85, accuracy: 0.0001)
        XCTAssertEqual(syncStore.preview?.importablePendingNotices.map(\.code), ["011172"])

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: false,
            importPending: true
        )

        let pendingConversion = try XCTUnwrap(portfolioStore.snapshot.pendingConversions?.first)
        XCTAssertEqual(pendingConversion.fromCode, "011172")
        XCTAssertEqual(pendingConversion.toCode, "011609")
        XCTAssertEqual(pendingConversion.shares, 2_773.85, accuracy: 0.0001)

        let targetFund = try XCTUnwrap(portfolioStore.snapshot.funds.first { $0.code == "011609" })
        XCTAssertEqual(targetFund.name, "易方达上证科创50ETF联接C")
        XCTAssertNil(portfolioStore.snapshot.pendingConversions?.first { $0.toCode == "013284" })
    }

    func testJDFinanceSyncPreviewSeparatesNewChangedMissingAndPendingNotice() throws {
        var remoteSnapshot = try JDFinanceHoldingsParser.parse(data: Data(Self.jdFinanceHoldingsResponse.utf8))
        remoteSnapshot.products.append(
            JDFinanceHoldingProduct(
                skuID: "1008998",
                code: "008998",
                name: "同泰竞争优势混合A",
                totalAmount: 1_234.56,
                yesterdayIncome: 6.78,
                todayIncome: nil,
                holdIncome: 12.34,
                holdRate: 1.01,
                transactionTip: nil
            )
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 2_400,
            holdingIncome: -10,
            holdingIncomeRate: -0.41,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 1,
            funds: [
                FundPosition(
                    code: "024424",
                    name: "永赢先进制造智选混合发起A",
                    dateText: "07-03 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: -500,
                    holdingRate: -2.40,
                    currentAmount: 18_900,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 19_400
                ),
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "07-03 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: 50,
                    holdingRate: 5,
                    currentAmount: 1_050,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 1_000
                ),
                FundPosition(
                    code: "025833",
                    name: "天弘电网设备特高压指数C",
                    dateText: "07-03 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    currentAmount: 0,
                    status: .pending,
                    isUpdated: false,
                    pendingAmount: 5_000
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(preview.newHoldings.map(\.code), ["008998"])
        XCTAssertEqual(preview.changedHoldings.map(\.code), ["024424"])
        XCTAssertEqual(preview.missingLocalHoldings.map(\.code), ["026210"])
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["011833"])

        let draft = try XCTUnwrap(preview.newHoldings.first?.draft(positionDate: "2026-07-04"))
        XCTAssertEqual(draft.code, "008998")
        XCTAssertEqual(draft.positionMode, .amount)
        XCTAssertEqual(draft.positionAmount ?? 0, 1_234.56, accuracy: 0.0001)
        XCTAssertEqual(draft.positionProfit, 12.34, accuracy: 0.0001)
        XCTAssertFalse(draft.requiresTradeConfirmation)
    }

    func testJDFinanceSyncPreviewTreatsLocalPendingFundAsPendingNotice() {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 3_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1025500",
                    code: "025500",
                    name: "东方阿尔法科技智选混合发起C",
                    totalAmount: 3_000,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: 0,
                    holdRate: nil,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：2笔买入中合计3000.00元",
                        action: .buy,
                        tradeCount: 2,
                        totalAmount: 3_000
                    )
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
            pendingCount: 1,
            funds: [
                FundPosition(
                    code: "025500",
                    name: "东方阿尔法科技智选混合发起C",
                    dateText: "07-03 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    currentAmount: 0,
                    status: .pending,
                    isUpdated: false,
                    pendingAmount: 3_000
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertTrue(preview.newHoldings.isEmpty)
        XCTAssertTrue(preview.changedHoldings.isEmpty)
        XCTAssertTrue(preview.missingLocalHoldings.isEmpty)
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["025500"])
        XCTAssertEqual(
            preview.pendingNotices.first?.message,
            "本次同步已完成；京东仍标记为交易处理中，尚未完成基金份额确认。"
        )
        XCTAssertNil(preview.pendingNotices.first?.importKind)
        XCTAssertFalse(preview.pendingNotices.first?.isImportable ?? true)
    }

    func testJDFinanceSyncPreviewMovesHoldingTransactionTipToPendingNotice() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 20_686.71,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: -919.26,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1024424",
                    code: "024424",
                    name: "东方阿尔法科技优选混合发起C",
                    totalAmount: 20_686.71,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: -919.26,
                    holdRate: -4.46,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：1笔买入中合计1000.00元",
                        action: .buy,
                        tradeCount: 1,
                        totalAmount: 1_000
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 19_686.71,
            holdingIncome: -918.99,
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
                    holdingIncome: -918.99,
                    holdingRate: -4.45,
                    currentAmount: 19_686.71,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 20_605.70
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(preview.changedHoldings.map(\.code), ["024424"])
        let difference = try XCTUnwrap(preview.changedHoldings.first)
        XCTAssertEqual(difference.jdAmount, 20_686.71, accuracy: 0.0001)
        XCTAssertEqual(difference.comparableJDAmount, 19_686.71, accuracy: 0.0001)
        XCTAssertEqual(difference.amountDelta, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(difference.localAmount), 19_686.71, accuracy: 0.0001)
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["024424"])
        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertEqual(notice.amount, 1_000, accuracy: 0.0001)
        XCTAssertTrue(notice.requiresManualCompletion)
        XCTAssertFalse(notice.isImportable)
        let manualCompletion = JDFinancePendingManualCompletion(
            tradeDate: "2026-07-03",
            tradeTimeType: .before15
        )
        let draft = try XCTUnwrap(notice.tradeDraft(manualCompletion: manualCompletion))
        XCTAssertEqual(draft.action, .buy)
        XCTAssertEqual(draft.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(draft.tradeDate, "2026-07-03")
    }

    func testJDFinanceSyncPreviewDoesNotTreatEmbeddedPendingBuyAsAmountDifference() throws {
        let now = try chinaDate("2026-07-16 16:00")
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: "026210",
            name: "平安科技精选混合发起式A",
            totalAmount: 26_628.86,
            holdIncome: -6_390.07,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：3笔买入中合计3500.00元",
                action: .buy,
                tradeCount: 3,
                totalAmount: 3_500
            )
        )
        let localFund = FundPosition(
            code: product.code,
            name: product.name,
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: -6_390.07,
            holdingRate: -21.65,
            currentAmount: 23_128.86,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 26_628.86,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: -6_390.07,
                totalIncome: nil,
                products: [product]
            ),
            localSnapshot: jdPortfolio(funds: [localFund], records: [], now: now)
        )

        XCTAssertTrue(preview.changedHoldings.isEmpty)
        XCTAssertEqual(product.syncedPendingBuyAmount ?? 0, 3_500, accuracy: 0.0001)
        XCTAssertEqual(product.comparableHoldingAmount, 23_128.86, accuracy: 0.0001)
    }

    func testJDFinanceSyncPreviewPrefersFullAmountWhenLocalAlreadyIncludesPendingBuy() throws {
        let now = try chinaDate("2026-07-17 00:24")
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: "026210",
            name: "平安科技精选混合发起式A",
            totalAmount: 26_628.86,
            holdIncome: -6_390.07,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：3笔买入中合计3500.00元",
                action: .buy,
                tradeCount: 3,
                totalAmount: 3_500
            )
        )
        let localFund = FundPosition(
            code: product.code,
            name: product.name,
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: -6_390.07,
            holdingRate: -21.65,
            currentAmount: 26_628.86,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 26_628.86,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: -6_390.07,
                totalIncome: nil,
                products: [product]
            ),
            localSnapshot: jdPortfolio(funds: [localFund], records: [], now: now)
        )

        XCTAssertTrue(preview.changedHoldings.isEmpty)
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["026210"])
    }

    func testJDFinanceSyncPreviewKeepsIncomeDifferenceWithoutReintroducingPendingBuyDelta() throws {
        let now = try chinaDate("2026-07-17 00:24")
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: "026210",
            name: "平安科技精选混合发起式A",
            totalAmount: 26_628.86,
            holdIncome: -6_390.07,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：3笔买入中合计3500.00元",
                action: .buy,
                tradeCount: 3,
                totalAmount: 3_500
            )
        )
        let localFund = FundPosition(
            code: product.code,
            name: product.name,
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: -6_300,
            holdingRate: -21.65,
            currentAmount: 26_628.86,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 26_628.86,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: -6_390.07,
                totalIncome: nil,
                products: [product]
            ),
            localSnapshot: jdPortfolio(funds: [localFund], records: [], now: now)
        )

        let difference = try XCTUnwrap(preview.changedHoldings.first)
        XCTAssertEqual(difference.amountDelta, 0, accuracy: 0.0001)
        XCTAssertNil(difference.jdPendingBuyAmount)
        XCTAssertEqual(difference.jdHoldingIncome ?? 0, -6_390.07, accuracy: 0.0001)
        XCTAssertEqual(difference.localHoldingIncome ?? 0, -6_300, accuracy: 0.0001)
    }

    func testJDFinanceSyncPreviewBuildsPendingTradeWhenDetailIsComplete() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 20_686.71,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: -919.26,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1024424",
                    code: "024424",
                    name: "东方阿尔法科技优选混合发起C",
                    totalAmount: 20_686.71,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: -919.26,
                    holdRate: -4.46,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：1笔买入中合计1000.00元",
                        action: .buy,
                        tradeCount: 1,
                        totalAmount: 1_000
                    ),
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .buy,
                        amount: 1_000,
                        shares: nil,
                        tradeDate: "2026-07-03",
                        tradeTimeType: .before15,
                        statusText: "买入确认中"
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 19_686.71,
            holdingIncome: -918.99,
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
                    holdingIncome: -918.99,
                    holdingRate: -4.45,
                    currentAmount: 19_686.71,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 20_605.70
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
        let draft = try XCTUnwrap(notice.tradeDraft())
        XCTAssertEqual(draft.action, .buy)
        XCTAssertEqual(draft.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(draft.tradeDate, "2026-07-03")
        XCTAssertEqual(draft.tradeTimeType, .before15)
    }

    func testJDFinanceSyncPreviewBuildsMultiplePendingTradesFromMatchedRecords() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 3_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: 0,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1025500",
                    code: "025500",
                    name: "东方阿尔法科技智选混合发起C",
                    totalAmount: 3_000,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: 0,
                    holdRate: nil,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：2笔买入中合计3000.00元",
                        action: .buy,
                        tradeCount: 2,
                        totalAmount: 3_000
                    ),
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .buy,
                        amount: 3_000,
                        shares: nil,
                        tradeDate: nil,
                        tradeTimeType: nil,
                        statusText: "匹配交易记录：2 笔",
                        matchedTradeRecords: [
                            JDFinanceTradeOrderRecord(
                                code: "025500",
                                productName: "东方阿尔法科技智选混合发起C",
                                action: .buy,
                                amount: 1_000,
                                shares: nil,
                                tradeDate: "2026-07-03",
                                tradeTimeType: .before15,
                                statusText: "支付成功"
                            ),
                            JDFinanceTradeOrderRecord(
                                code: "025500",
                                productName: "东方阿尔法科技智选混合发起C",
                                action: .buy,
                                amount: 2_000,
                                shares: nil,
                                tradeDate: "2026-07-04",
                                tradeTimeType: .after15,
                                statusText: "支付成功"
                            )
                        ]
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 10_000,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "025500",
                    name: "东方阿尔法科技智选混合发起C",
                    dateText: "07-02 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    currentAmount: 10_000,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 10_000
                )
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )
        let notice = try XCTUnwrap(preview.pendingNotices.first)
        let drafts = try XCTUnwrap(notice.tradeDrafts())

        XCTAssertTrue(notice.isImportable)
        XCTAssertFalse(notice.requiresManualCompletion)
        XCTAssertEqual(notice.matchedTradeRecords.count, 2)
        XCTAssertEqual(drafts.map(\.amount), [1_000, 2_000])
        XCTAssertEqual(drafts.map(\.code), ["025500", "025500"])
        XCTAssertEqual(drafts.map(\.tradeDate), ["2026-07-03", "2026-07-04"])
        XCTAssertEqual(drafts.map(\.tradeTimeType), [.before15, .after15])
    }

    func testJDFinanceNewFundPendingNoticeMergesSplitPaymentsIntoTwoLogicalBuys() throws {
        let name = "富国全球科技互联网股票(QDII)C"
        let matchedRecords = [
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-today-card",
                code: "022184",
                productName: name,
                action: .buy,
                amount: 900,
                shares: nil,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                submittedAt: "2026-07-15 10:05:00",
                status: .pending,
                statusText: "支付成功"
            ),
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-today-balance",
                code: "022184",
                productName: name,
                action: .buy,
                amount: 100,
                shares: nil,
                tradeDate: "2026-07-15",
                tradeTimeType: .before15,
                submittedAt: "2026-07-15 10:05:00",
                status: .pending,
                statusText: "支付成功"
            ),
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-yesterday",
                code: "022184",
                productName: name,
                action: .buy,
                amount: 1_000,
                shares: nil,
                tradeDate: "2026-07-13",
                tradeTimeType: .after15,
                submittedAt: "2026-07-13 16:05:00",
                status: .pending,
                statusText: "支付成功"
            )
        ]
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 2_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: 0,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1022184",
                    code: "022184",
                    name: name,
                    totalAmount: 2_000,
                    yesterdayIncome: nil,
                    todayIncome: nil,
                    holdIncome: 0,
                    holdRate: nil,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：3笔买入中合计2000.00元",
                        action: .buy,
                        tradeCount: 3,
                        totalAmount: 2_000
                    ),
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .buy,
                        amount: 2_000,
                        shares: nil,
                        tradeDate: nil,
                        tradeTimeType: nil,
                        statusText: "匹配交易记录：3 笔",
                        matchedTradeRecords: matchedRecords
                    )
                )
            ],
            tradeOrders: matchedRecords,
            tradeOrderFetchState: .complete
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: .empty
        )
        let notice = try XCTUnwrap(preview.pendingNotices.first)
        let drafts = try XCTUnwrap(notice.tradeDrafts())
        let fundDraft = try XCTUnwrap(notice.fundPositionDraft())

        XCTAssertEqual(notice.importKind, .newFund)
        XCTAssertEqual(notice.tradeCountText, "2 笔")
        XCTAssertEqual(drafts.map(\.amount), [1_000, 1_000])
        XCTAssertEqual(drafts.map(\.tradeDate), ["2026-07-13", "2026-07-15"])
        XCTAssertEqual(drafts.map(\.tradeTimeType), [.after15, .before15])
        XCTAssertEqual(try XCTUnwrap(fundDraft.positionAmount), 1_000, accuracy: 0.0001)
        XCTAssertEqual(fundDraft.positionDate, "2026-07-13")
        XCTAssertEqual(fundDraft.positionTimeType, .after15)
    }

    @MainActor
    func testJDFinanceOrphanedPendingBuyRepairsIndexAndAutoConfirmsOnNextDay() async throws {
        let now = try chinaDate("2026-07-08 09:30")
        let createdAt = try chinaDate("2026-07-07 14:30")
        let service = tradeQuoteService(
            code: "013284",
            name: "上银价值增长3个月持有期混合A",
            date: "2026-07-07",
            netValue: 10
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-waiting-pending-buy-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let syncMetadata = FundTradeSyncMetadata(
            source: .jdFinance,
            syncKey: "trade|buy|013284|2026-07-07|before15|500.00|",
            externalStatus: .waitingExternalConfirmation,
            externalStatusText: "支付成功",
            waitsForExternalConfirmation: true
        )
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 1_000,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)
                ],
                migration: nil,
                pendingTrades: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "initial-record",
                        kind: .newFund,
                        status: .confirmed,
                        code: "013284",
                        name: "上银价值增长3个月持有期混合A",
                        mode: .amount,
                        amount: 1_000,
                        shares: nil,
                        confirmedShares: 100,
                        price: 10,
                        tradeDate: "2026-07-06",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-06",
                        createdAt: createdAt.addingTimeInterval(-60),
                        confirmedAt: createdAt.addingTimeInterval(-60),
                        failureReason: nil
                    ),
                    FundTradeRecord(
                        id: "pending-buy-record",
                        kind: .buy,
                        status: .pending,
                        code: "013284",
                        name: "上银价值增长3个月持有期混合A",
                        mode: .amount,
                        amount: 500,
                        shares: nil,
                        confirmedShares: nil,
                        price: nil,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-07",
                        createdAt: createdAt,
                        confirmedAt: nil,
                        failureReason: nil,
                        syncSource: syncMetadata.source,
                        syncKey: syncMetadata.syncKey,
                        externalStatus: syncMetadata.externalStatus,
                        externalStatusText: syncMetadata.externalStatusText,
                        waitsForExternalConfirmation: syncMetadata.waitsForExternalConfirmation
                    )
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "pending-buy-record" })
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.confirmedShares ?? 0, 50, accuracy: 0.000001)
        XCTAssertEqual(record.externalStatus, .externalConfirmed)
        XCTAssertEqual(record.waitsForExternalConfirmation, false)
        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "013284" })
        XCTAssertEqual(fund.migratedShares ?? 0, 150, accuracy: 0.000001)
        XCTAssertEqual(fund.currentAmount ?? 0, 1_500, accuracy: 0.0001)

        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertEqual(store.snapshot.tradeRecords?.filter { $0.id == "pending-buy-record" }.count, 1)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 150, accuracy: 0.000001)
    }

    func testJDFinancePendingRemoteDoesNotDuplicateLocallyConfirmedTrade() throws {
        let createdAt = try chinaDate("2026-07-08 09:30")
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 1_001,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1013284",
                    code: "013284",
                    name: "上银价值增长3个月持有期混合A",
                    totalAmount: 1_001,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：1笔买入中合计1001.00元",
                        action: .buy,
                        tradeCount: 1,
                        totalAmount: 1_001
                    ),
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .buy,
                        amount: 1_001,
                        shares: 100,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        statusText: "确认中"
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: createdAt,
            totalAmount: 1_000,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)
            ],
            migration: nil,
            tradeRecords: [
                FundTradeRecord(
                    id: "jd-buy-record",
                    kind: .newFund,
                    status: .confirmed,
                    code: "013284",
                    name: "上银价值增长3个月持有期混合A",
                    mode: .amount,
                    amount: 1_000,
                    shares: nil,
                    confirmedShares: 100,
                    price: 10,
                    tradeDate: "2026-07-07",
                    tradeTimeType: .before15,
                    acceptedDate: "2026-07-07",
                    createdAt: createdAt,
                    confirmedAt: createdAt,
                    failureReason: nil,
                    syncSource: .jdFinance,
                    syncKey: "jd-buy",
                    externalStatus: .waitingExternalConfirmation,
                    externalStatusText: "确认中",
                    waitsForExternalConfirmation: true
                )
            ]
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )
        let notice = try XCTUnwrap(preview.pendingNotices.first)

        XCTAssertFalse(notice.isImportable)
        XCTAssertNil(notice.importKind)
        XCTAssertEqual(preview.importablePendingNotices.count, 0)
        if case .localConfirmedJDPending(let difference)? = notice.syncState {
            XCTAssertEqual(difference.amountDelta ?? 0, 1, accuracy: 0.0001)
        } else {
            XCTFail("Expected local confirmed JD pending state")
        }
    }

    func testJDFinancePendingSplitBuyMatchesConfirmedLocalBatch() throws {
        let now = try chinaDate("2026-07-17 00:31")
        let code = "026210"
        let name = "平安科技精选混合发起式A"
        let amounts = [500.0, 1_000, 2_000]
        let remoteOrders = amounts.enumerated().map { index, amount in
            JDFinanceTradeOrderRecord(
                stableOrderKey: "026210-split-\(index)",
                code: code,
                codeResolution: .explicit,
                productName: name,
                action: .buy,
                amount: amount,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                status: .pending,
                statusCode: "PAY_SUCC",
                statusText: "支付成功"
            )
        }
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: code,
            name: name,
            totalAmount: 26_628.86,
            holdIncome: -6_390.07,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：3笔买入中合计3500.00元",
                action: .buy,
                tradeCount: 3,
                totalAmount: 3_500
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 3_500,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                statusText: "匹配交易记录：3 笔",
                matchedTradeRecords: remoteOrders
            )
        )
        let localRecords = amounts.enumerated().map { index, amount in
            FundTradeRecord(
                id: "local-026210-split-\(index)",
                kind: .buy,
                status: .confirmed,
                code: code,
                name: name,
                mode: .amount,
                amount: amount,
                shares: nil,
                confirmedShares: amount / 2,
                price: 2,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                acceptedDate: "2026-07-16",
                createdAt: now,
                confirmedAt: now,
                failureReason: nil,
                syncSource: .jdFinance,
                externalStatus: .externalConfirmed,
                waitsForExternalConfirmation: false
            )
        }
        let localFund = FundPosition(
            code: code,
            name: name,
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: -6_390.07,
            holdingRate: -21.65,
            currentAmount: 26_628.86,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 26_628.86,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: -6_390.07,
                totalIncome: nil,
                products: [product],
                tradeOrders: remoteOrders,
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [localFund], records: localRecords, now: now)
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertFalse(notice.isImportable)
        XCTAssertNil(notice.importKind)
        XCTAssertEqual(preview.importablePendingTradeCount, 0)
        XCTAssertEqual(preview.localConfirmedJDPendingTradeCount, 3)
        XCTAssertEqual(preview.localPendingTradeCount, 0)
        if case .localConfirmedJDPending? = notice.syncState {
            XCTAssertTrue(notice.message.contains("本地已确认"))
        } else {
            XCTFail("Expected the confirmed local split batch to represent the JD aggregate")
        }
    }

    func testJDFinancePendingBuyWithCoveredAmountAndMissingLedgerIsNotImportable() throws {
        let now = try chinaDate("2026-07-17 00:31")
        let code = "026210"
        let name = "平安科技精选混合发起式A"
        let remoteOrder = JDFinanceTradeOrderRecord(
            stableOrderKey: "covered-without-ledger",
            code: code,
            codeResolution: .explicit,
            productName: name,
            action: .buy,
            amount: 1_000,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            status: .pending,
            statusCode: "PAY_SUCC",
            statusText: "支付成功"
        )
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: code,
            name: name,
            totalAmount: 5_000,
            holdIncome: -100,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：1笔买入中合计1000.00元",
                action: .buy,
                tradeCount: 1,
                totalAmount: 1_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 1_000,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                statusText: "支付成功",
                matchedTradeRecords: [remoteOrder]
            )
        )
        let localFund = FundPosition(
            code: code,
            name: name,
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: -100,
            holdingRate: -2,
            currentAmount: 5_000,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 5_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: -100,
                totalIncome: nil,
                products: [product],
                tradeOrders: [remoteOrder],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [localFund], records: [], now: now)
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertFalse(notice.isImportable)
        XCTAssertNil(notice.importKind)
        XCTAssertNil(notice.syncState)
        XCTAssertTrue(notice.message.contains("持仓金额已覆盖"))
        XCTAssertEqual(preview.positionCoveredMissingLedgerTradeCount, 1)
    }

    func testJDFinancePendingBuyWithoutLedgerRemainsImportableWhenHoldingExcludesIt() throws {
        let now = try chinaDate("2026-07-17 00:31")
        let code = "026210"
        let name = "平安科技精选混合发起式A"
        let remoteOrder = JDFinanceTradeOrderRecord(
            stableOrderKey: "missing-and-not-covered",
            code: code,
            codeResolution: .explicit,
            productName: name,
            action: .buy,
            amount: 1_000,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            status: .pending,
            statusCode: "PAY_SUCC",
            statusText: "支付成功"
        )
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: code,
            name: name,
            totalAmount: 5_000,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：1笔买入中合计1000.00元",
                action: .buy,
                tradeCount: 1,
                totalAmount: 1_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 1_000,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                statusText: "支付成功",
                matchedTradeRecords: [remoteOrder]
            )
        )
        let localFund = FundPosition(
            code: code,
            name: name,
            dateText: "07-16 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: 0,
            holdingRate: 0,
            currentAmount: 4_000,
            status: .holding,
            isUpdated: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 5_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [product],
                tradeOrders: [remoteOrder],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [localFund], records: [], now: now)
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertTrue(notice.isImportable)
        XCTAssertEqual(preview.importablePendingTradeCount, 1)
        XCTAssertEqual(preview.positionCoveredMissingLedgerTradeCount, 0)
    }

    func testJDFinancePendingProductStillReportsAmountDifference() throws {
        let createdAt = try chinaDate("2026-07-08 09:30")
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 900,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1013284",
                    code: "013284",
                    name: "上银价值增长3个月持有期混合A",
                    totalAmount: 900,
                    transactionTip: JDFinanceTransactionTip(
                        text: "交易：1笔买入中合计500.00元",
                        action: .buy,
                        tradeCount: 1,
                        totalAmount: 500
                    )
                )
            ]
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: createdAt,
            totalAmount: 1_000,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)
            ],
            migration: nil
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        let difference = try XCTUnwrap(preview.changedHoldings.first)
        XCTAssertEqual(difference.jdAmount, 900, accuracy: 0.0001)
        XCTAssertEqual(difference.localAmount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(preview.pendingNotices.count, 1)
    }

    func testJDFinancePendingOrderIsShownOnlyInsideItsPendingNotice() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let globalOrder = JDFinanceTradeOrderRecord(
            code: "022184",
            codeResolution: .nameMatched,
            productName: "转入-富国全球科技互联网股票(QDII)C",
            action: .buy,
            amount: 1_000,
            tradeDate: "2026-07-13",
            tradeTimeType: .after15,
            submittedAt: "2026-07-13 15:30:00",
            status: .pending,
            statusCode: "PAY_SUCC",
            statusText: "支付成功"
        )
        var nestedOrder = globalOrder
        nestedOrder.code = nil
        nestedOrder.codeResolution = .unresolved
        let product = JDFinanceHoldingProduct(
            skuID: "1022184",
            code: "022184",
            name: "富国全球科技互联网股票(QDII)C",
            totalAmount: 1_000,
            transactionTip: JDFinanceTransactionTip(
                text: "交易中",
                action: .buy,
                tradeCount: 1,
                totalAmount: 1_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 1_000,
                shares: nil,
                tradeDate: "2026-07-13",
                tradeTimeType: .after15,
                statusText: "支付成功",
                matchedTradeRecords: [nestedOrder]
            )
        )
        var local = jdPortfolio(
            funds: [conversionFund(code: "022184", name: product.name, shares: 100, cost: 10)],
            records: [],
            now: now
        )
        local.funds[0].status = .pending
        local.funds[0].currentAmount = 0
        local.funds[0].pendingAmount = 1_000
        local.jdFinanceSyncState = JDFinanceSyncState(
            baselineEstablishedAt: try chinaDate("2026-07-13 00:00")
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 1_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [product],
                tradeOrders: [globalOrder],
                tradeOrderFetchState: .incomplete(["部分接口失败"])
            ),
            localSnapshot: local
        )

        XCTAssertEqual(preview.pendingNotices.count, 1)
        XCTAssertEqual(
            preview.pendingNotices.first?.message,
            "本次同步已完成；京东订单当前为「支付成功」，尚未完成基金份额确认。"
        )
        XCTAssertTrue(preview.informationalOrders.isEmpty)
    }

    func testJDFinancePendingTradeRecordSuppressesDuplicatePendingImport() throws {
        let now = try chinaDate("2026-07-16 16:00")
        let order = JDFinanceTradeOrderRecord(
            code: "026210",
            codeResolution: .explicit,
            productName: "平安科技精选混合发起式A",
            action: .buy,
            amount: 2_000,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            status: .pending,
            statusCode: "PAY_SUCC",
            statusText: "支付成功"
        )
        let product = JDFinanceHoldingProduct(
            skuID: "1026210",
            code: "026210",
            name: "平安科技精选混合发起式A",
            totalAmount: 27_000,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：1笔买入中合计2000.00元",
                action: .buy,
                tradeCount: 1,
                totalAmount: 2_000
            ),
            pendingDetail: JDFinancePendingTransactionDetail(
                action: .buy,
                amount: 2_000,
                tradeDate: "2026-07-16",
                tradeTimeType: .before15,
                statusText: "支付成功",
                matchedTradeRecords: [order]
            )
        )
        let pendingRecord = FundTradeRecord(
            id: "jd-pending-026210",
            kind: .buy,
            status: .pending,
            code: "026210",
            name: product.name,
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
            failureReason: nil,
            syncSource: .jdFinance,
            externalStatus: .waitingExternalConfirmation,
            waitsForExternalConfirmation: true
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 27_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [product]
            ),
            localSnapshot: jdPortfolio(
                funds: [conversionFund(code: "026210", name: product.name, shares: 10_000, cost: 2.5)],
                records: [pendingRecord],
                now: now
            )
        )

        let notice = try XCTUnwrap(preview.pendingNotices.first)
        XCTAssertNil(notice.importKind)
        XCTAssertFalse(notice.isImportable)
    }
}
