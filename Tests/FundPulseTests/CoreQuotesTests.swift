import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    @MainActor
    func testRefreshQuotesPublishesRefreshingState() async throws {
        let now = try chinaDate("2026-06-24 10:00")
        let service = tradeQuoteService(date: "2026-06-23", netValue: 2.5)
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 180_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-refresh-state-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        XCTAssertFalse(store.isRefreshingQuotes)

        let refreshTask = Task {
            await store.refreshQuotes()
        }
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertTrue(store.isRefreshingQuotes)

        await refreshTask.value

        XCTAssertFalse(store.isRefreshingQuotes)
    }

    func testFundThresholdReminderEvaluatorIgnoresLegacyPerFundAndNetValueReminders() throws {
        let date = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-24"))
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(
                    code: "024418",
                    todayRate: 8.2,
                    currentAmount: 2_570.9,
                    shares: 1_000,
                    zdfRange: 5,
                    jzNotice: 2.5
                ),
                thresholdReminderFund(
                    code: "025833",
                    todayRate: -8.2,
                    currentAmount: 2_400,
                    shares: 1_000,
                    zdfRange: 5,
                    jzNotice: 2.5
                )
            ]
        )

        XCTAssertTrue(
            FundThresholdReminderEvaluator.reminders(in: snapshot, settings: AppSettings(), date: date).isEmpty
        )

        let settings = AppSettings(
            dailyGrowthReminderEnabled: true,
            dailyGrowthRiseTiers: [.seven],
            dailyGrowthFallTiers: []
        )
        let reminders = FundThresholdReminderEvaluator.reminders(in: snapshot, settings: settings, date: date)
        XCTAssertEqual(reminders.map(\.code), ["024418"])
        XCTAssertEqual(reminders.map(\.kind), [.dailyGrowth])
    }

    @MainActor
    func testSettingsFallsBackToDefaultMarketIndexWhenStoredValueIsInvalid() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-market-index-invalid-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let settingsURL = tempDirectory.appending(path: "settings.json")
        let settings = """
        {
          "settingsSchemaVersion": 10,
          "showsMarketIndexes": false,
          "defaultMarketIndexID": "hangSengTech"
        }
        """
        try Data(settings.utf8).write(to: settingsURL, options: .atomic)

        let store = AppSettingsStore(dataDirectory: tempDirectory)

        XCTAssertFalse(store.settings.showsMarketIndexes)
        XCTAssertEqual(store.settings.defaultMarketIndexID, .shanghaiComposite)
    }

    func testMarketIndexServiceFetchesEastmoneyBatchIndexQuotes() async throws {
        let service = marketIndexServiceWithMockResponses([
            "https://push2delay.eastmoney.com/api/qt/ulist.np/get": """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38},{"f12":"000300","f14":"沪深300","f2":4969.71,"f3":0.87,"f4":42.79}]}}
            """
        ])

        let quotes = await service.fetchQuotes(for: [.shanghaiComposite, .csi300])

        let shanghaiQuote = try XCTUnwrap(quotes[.shanghaiComposite])
        let csi300Quote = try XCTUnwrap(quotes[.csi300])
        XCTAssertEqual(shanghaiQuote.name, "上证指数")
        XCTAssertEqual(shanghaiQuote.value, 4080.28, accuracy: 0.0001)
        XCTAssertEqual(shanghaiQuote.change, 6.38, accuracy: 0.0001)
        XCTAssertEqual(shanghaiQuote.changeRate, 0.16, accuracy: 0.0001)
        XCTAssertEqual(csi300Quote.name, "沪深300")
        XCTAssertEqual(csi300Quote.value, 4969.71, accuracy: 0.0001)
        XCTAssertEqual(csi300Quote.change, 42.79, accuracy: 0.0001)
        XCTAssertEqual(csi300Quote.changeRate, 0.87, accuracy: 0.0001)
    }

    func testMarketIndexServiceKeepsOnlyIndexesReturnedByBatchEndpoint() async throws {
        let service = marketIndexServiceWithMockResponses([
            "https://push2delay.eastmoney.com/api/qt/ulist.np/get": """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000300","f14":"沪深300","f2":4969.71,"f3":0.87,"f4":42.79}]}}
            """
        ])

        let quotes = await service.fetchQuotes(for: [.shanghaiComposite, .csi300])

        XCTAssertNil(quotes[.shanghaiComposite])
        let csi300Quote = try XCTUnwrap(quotes[.csi300])
        XCTAssertEqual(csi300Quote.name, "沪深300")
        XCTAssertEqual(csi300Quote.value, 4969.71, accuracy: 0.0001)
    }

    func testMarketIndexServiceFallsBackToDelayBatchHostWhenRealtimeBatchHostFails() async throws {
        let service = marketIndexServiceWithMockResponses([
            "https://push2delay.eastmoney.com/api/qt/ulist.np/get": """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38}]}}
            """
        ])

        let quotes = await service.fetchQuotes(for: [.shanghaiComposite])

        let quote = try XCTUnwrap(quotes[.shanghaiComposite])
        XCTAssertEqual(quote.name, "上证指数")
        XCTAssertEqual(quote.value, 4080.28, accuracy: 0.0001)
        XCTAssertEqual(quote.change, 6.38, accuracy: 0.0001)
        XCTAssertEqual(quote.changeRate, 0.16, accuracy: 0.0001)
    }

    func testMarketIndexServiceBypassesURLCacheForRealtimeQuotes() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.marketIndexBatchQuoteEndpoint(): """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38}]}}
            """
        ])

        _ = await service.fetchQuotes(for: [.shanghaiComposite])

        let request = try XCTUnwrap(MockURLProtocol.responseStore.requests().last)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }

    func testMarketIndexServiceFetchesTonghuashunMarketBreadth() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.tonghuashunMarketBreadthEndpoint(): """
            {
              "zdfb_data": {
                "zdfb": [155,267,1030,2354,990,391,149,81,43,57],
                "znum": 693,
                "dnum": 4796
              },
              "zdt_data": {
                "last_zdt": {
                  "ztzs": 34,
                  "dtzs": 45
                }
              }
            }
            """
        ])

        let fetchedBreadth = await service.fetchMarketBreadth()
        let breadth = try XCTUnwrap(fetchedBreadth)

        XCTAssertEqual(breadth.risingCount, 693)
        XCTAssertEqual(breadth.fallingCount, 4796)
        XCTAssertEqual(breadth.activeCount, 5489)
        XCTAssertEqual(breadth.distribution, [155, 267, 1030, 2354, 990, 391, 149, 81, 43, 57])
        XCTAssertEqual(breadth.limitUpCount, 34)
        XCTAssertEqual(breadth.limitDownCount, 45)
    }

    func testMarketIndexServiceFallsBackToEastmoneyMarketBreadthWhenTonghuashunFails() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.tonghuashunMarketBreadthEndpoint(): """
            {"status":"forbidden"}
            """,
            Self.eastmoneyMarketBreadthEndpoint(): """
            {
              "rc": 0,
              "data": {
                "total": 4,
                "diff": [
                  { "f12": "300454", "f14": "深信服", "f3": 20.0 },
                  { "f12": "600000", "f14": "浦发银行", "f3": 1.24 },
                  { "f12": "000001", "f14": "平安银行", "f3": -0.35 },
                  { "f12": "600519", "f14": "贵州茅台", "f3": -10.0 }
                ]
              }
            }
            """
        ])

        let fetchedBreadth = await service.fetchMarketBreadth()
        let breadth = try XCTUnwrap(fetchedBreadth)

        XCTAssertEqual(breadth.risingCount, 2)
        XCTAssertEqual(breadth.fallingCount, 2)
        XCTAssertEqual(breadth.limitUpCount, 1)
        XCTAssertEqual(breadth.limitDownCount, 1)
        XCTAssertEqual(breadth.distribution.reduce(0, +), 4)
    }

    func testMarketIndexServiceFallsBackToRealtimeHostWhenDelayMarketBreadthFails() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.tonghuashunMarketBreadthEndpoint(): """
            {"status":"forbidden"}
            """,
            Self.eastmoneyMarketBreadthEndpoint(host: "push2.eastmoney.com"): """
            {
              "rc": 0,
              "data": {
                "total": 2,
                "diff": [
                  { "f12": "300454", "f14": "深信服", "f3": 20.0 },
                  { "f12": "000001", "f14": "平安银行", "f3": -0.35 }
                ]
              }
            }
            """
        ])

        let fetchedBreadth = await service.fetchMarketBreadth()
        let breadth = try XCTUnwrap(fetchedBreadth)
        let requestedURLs = MockURLProtocol.responseStore.requests().compactMap { $0.url?.absoluteString }

        XCTAssertTrue(requestedURLs.contains { $0.hasPrefix(Self.eastmoneyMarketBreadthEndpoint()) })
        XCTAssertTrue(requestedURLs.contains { $0.hasPrefix(Self.eastmoneyMarketBreadthEndpoint(host: "push2.eastmoney.com")) })
        XCTAssertEqual(breadth.risingCount, 1)
        XCTAssertEqual(breadth.fallingCount, 1)
        XCTAssertEqual(breadth.limitUpCount, 1)
    }

    func testMarketIndexServiceFetchesEastmoneyMarketBreadthAdditionalPages() async throws {
        let pageOnePrefix = Self.eastmoneyMarketBreadthEndpoint() + "?pn=1&"
        let pageTwoPrefix = Self.eastmoneyMarketBreadthEndpoint() + "?pn=2&"
        let service = marketIndexServiceWithMockResponses([
            Self.tonghuashunMarketBreadthEndpoint(): """
            {"status":"forbidden"}
            """,
            pageOnePrefix: """
            {
              "rc": 0,
              "data": {
                "total": 101,
                "diff": [
                  { "f12": "300454", "f14": "深信服", "f3": 20.0 },
                  { "f12": "600000", "f14": "浦发银行", "f3": 1.24 }
                ]
              }
            }
            """,
            pageTwoPrefix: """
            {
              "rc": 0,
              "data": {
                "total": 101,
                "diff": [
                  { "f12": "000001", "f14": "平安银行", "f3": -0.35 },
                  { "f12": "600519", "f14": "贵州茅台", "f3": -10.0 }
                ]
              }
            }
            """
        ])

        let fetchedBreadth = await service.fetchMarketBreadth()
        let breadth = try XCTUnwrap(fetchedBreadth)
        let requestedURLs = MockURLProtocol.responseStore.requests().compactMap { $0.url?.absoluteString }

        XCTAssertTrue(requestedURLs.contains { $0.hasPrefix(pageOnePrefix) })
        XCTAssertTrue(requestedURLs.contains { $0.hasPrefix(pageTwoPrefix) })
        XCTAssertEqual(breadth.risingCount, 2)
        XCTAssertEqual(breadth.fallingCount, 2)
        XCTAssertEqual(breadth.limitUpCount, 1)
        XCTAssertEqual(breadth.limitDownCount, 1)
    }

    @MainActor
    func testMarketIndexStoreMergesPartialRefreshesIntoExistingQuotes() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.marketIndexBatchQuoteEndpoint(): """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38},{"f12":"000300","f14":"沪深300","f2":4969.71,"f3":0.87,"f4":42.79}]}}
            """
        ])
        let store = MarketIndexStore(service: service, minimumRefreshInterval: 0)

        await store.refresh(ids: [.shanghaiComposite, .csi300], force: true)
        MockURLProtocol.responseStore.set([
            Self.marketIndexBatchQuoteEndpoint(): Data("""
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000300","f14":"沪深300","f2":4970.00,"f3":0.87,"f4":43.08}]}}
            """.utf8)
        ])
        await store.refresh(ids: [.shanghaiComposite, .csi300], force: true)

        let shanghaiQuote = try XCTUnwrap(store.quotes[.shanghaiComposite])
        let csi300Quote = try XCTUnwrap(store.quotes[.csi300])
        XCTAssertEqual(shanghaiQuote.value, 4080.28, accuracy: 0.0001)
        XCTAssertEqual(csi300Quote.value, 4970.00, accuracy: 0.0001)
    }

    @MainActor
    func testMarketIndexStoreRefreshesMarketBreadthWithQuotes() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.marketIndexBatchQuoteEndpoint(): """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38}]}}
            """,
            Self.tonghuashunMarketBreadthEndpoint(): """
            {"zdfb_data":{"zdfb":[1,2,3],"znum":704,"dnum":4860},"zdt_data":{"last_zdt":{"ztzs":31,"dtzs":42}}}
            """
        ])
        let store = MarketIndexStore(service: service, minimumRefreshInterval: 0)

        await store.refresh(ids: [.shanghaiComposite], force: true)

        let quote = try XCTUnwrap(store.quotes[.shanghaiComposite])
        XCTAssertEqual(quote.value, 4080.28, accuracy: 0.0001)
        let breadth = try XCTUnwrap(store.marketBreadth)
        XCTAssertEqual(breadth.risingCount, 704)
        XCTAssertEqual(breadth.fallingCount, 4860)
        XCTAssertEqual(breadth.limitUpCount, 31)
        XCTAssertEqual(breadth.limitDownCount, 42)
    }

    @MainActor
    func testMarketIndexStoreRetriesWhenMarketBreadthIsMissing() async throws {
        let now = try chinaDate("2026-07-08 15:20")
        let service = marketIndexServiceWithMockResponses([
            Self.marketIndexBatchQuoteEndpoint(): """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38}]}}
            """
        ])
        let store = MarketIndexStore(service: service, minimumRefreshInterval: 20) {
            now
        }

        await store.refresh()
        XCTAssertNotNil(store.primaryQuote(defaultID: MarketIndexID.shanghaiComposite))
        XCTAssertNil(store.marketBreadth)

        MockURLProtocol.responseStore.set([
            Self.marketIndexBatchQuoteEndpoint(): Data("""
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000001","f14":"上证指数","f2":4080.28,"f3":0.16,"f4":6.38}]}}
            """.utf8),
            Self.tonghuashunMarketBreadthEndpoint(): Data("""
            {"zdfb_data":{"zdfb":[1,2,3],"znum":704,"dnum":4860},"zdt_data":{"last_zdt":{"ztzs":31,"dtzs":42}}}
            """.utf8)
        ])

        await store.refresh()
        let breadth: MarketBreadth = try XCTUnwrap(store.marketBreadth)
        XCTAssertEqual(breadth.risingCount, 704)
        XCTAssertEqual(breadth.fallingCount, 4860)
    }

    @MainActor
    func testMarketIndexStoreDoesNotFallbackWhenDefaultIndexIsMissing() async throws {
        let service = marketIndexServiceWithMockResponses([
            Self.marketIndexBatchQuoteEndpoint(): """
            {"rc":0,"rt":4,"data":{"diff":[{"f12":"000300","f14":"沪深300","f2":4926.92,"f3":1.21,"f4":58.7}]}}
            """
        ])
        let store = MarketIndexStore(service: service, minimumRefreshInterval: 0)

        await store.refresh(ids: [.csi300], force: true)

        XCTAssertNotNil(store.primaryQuote(defaultID: .csi300))
        XCTAssertNil(store.primaryQuote(defaultID: .shanghaiComposite))
    }

    func testEastmoneyCoreSourceUsesBatchQuoteFields() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": """
            {"data":[{"NAV":"--","DWJZ":2.5626,"GZTIME":"2026-06-26 14:17","PTYPE":"F","SHORTNAME":"平安科技精选混合发起式A","QDCODE":"026210","FCODE":"026210","RZDF":4.75,"JZRQ":"--","FSRQ":"2026-06-25","GSZZL":-5.21,"GSZ":2.4292},{"NAV":"--","DWJZ":"2.265","GZTIME":"2026-06-26 14:17","PTYPE":"F","SHORTNAME":"泰信发展主题混合","QDCODE":"290008","FCODE":"290008","RZDF":"-4.35","JZRQ":"--","FSRQ":"2026-06-25","GSZZL":"-5.88","GSZ":"2.1318"}],"errorCode":0,"success":true,"totalCount":2}
            """
        ])

        let quotes = await service.fetchQuotes(codes: ["026210", "290008"])

        let first = try XCTUnwrap(quotes["026210"])
        XCTAssertEqual(first.name, "平安科技精选混合发起式A")
        XCTAssertEqual(first.netValue, 2.5626, accuracy: 0.0001)
        XCTAssertEqual(first.estimatedNetValue, 2.4292, accuracy: 0.0001)
        XCTAssertEqual(first.growthRate, -5.21, accuracy: 0.0001)
        XCTAssertEqual(first.estimateTime, "2026-06-26 14:17")
        XCTAssertEqual(first.netValueDate, "2026-06-25")

        let second = try XCTUnwrap(quotes["290008"])
        XCTAssertEqual(second.name, "泰信发展主题混合")
        XCTAssertEqual(second.netValue, 2.265, accuracy: 0.0001)
        XCTAssertEqual(second.estimatedNetValue, 2.1318, accuracy: 0.0001)
        XCTAssertEqual(second.growthRate, -5.88, accuracy: 0.0001)
    }

    func testEastmoneyCoreSourceBypassesURLCacheForRealtimeQuotes() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": """
            {"data":[{"NAV":"--","DWJZ":2.5626,"GZTIME":"2026-06-26 14:17","PTYPE":"F","SHORTNAME":"平安科技精选混合发起式A","QDCODE":"026210","FCODE":"026210","RZDF":4.75,"JZRQ":"--","FSRQ":"2026-06-25","GSZZL":-5.21,"GSZ":2.4292}],"errorCode":0,"success":true,"totalCount":1}
            """
        ])

        _ = await service.fetchQuotes(codes: ["026210"])

        let request = try XCTUnwrap(MockURLProtocol.responseStore.requests().last)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }

    func testEastmoneyCoreSingleQuoteUsesRealtimeFields() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "026210",
                name: "平安科技精选混合发起式A",
                netValueDate: "2026-06-18",
                netValue: 2.3773,
                estimatedNetValue: 2.5,
                growthRate: 5.16,
                estimateTime: "2026-06-22 14:30"
            )
        ])

        let quote = try await service.fetchQuote(code: "026210")

        XCTAssertEqual(quote.netValue, 2.3773, accuracy: 0.0001)
        XCTAssertEqual(quote.estimatedNetValue, 2.5, accuracy: 0.0001)
        XCTAssertEqual(quote.growthRate, 5.16, accuracy: 0.0001)
        XCTAssertEqual(quote.netValueDate, "2026-06-18")
        XCTAssertEqual(quote.estimateTime, "2026-06-22 14:30")
    }

    func testLookupFundNameUsesEastmoneySuggest() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": """
            FundPulseSuggest_123({"Datas":[{"CODE":"026210","NAME":"平安科技精选混合发起式A","SHORTNAME":"平安科技精选混合发起式A","CATEGORYDESC":"基金"}]});
            """
        ])

        let name = await service.lookupFundName(code: "026210")

        XCTAssertEqual(name, "平安科技精选混合发起式A")
    }

    func testFundDetailSupplementUsesFundBabyTrendAndTopHoldingsSources() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fund.eastmoney.com/pingzhongdata/588760.js": """
            var Data_netWorthTrend = [
              {"x":1718553600000,"y":1.0000,"equityReturn":0,"unitMoney":""},
              {"x":1718640000000,"y":1.0200,"equityReturn":2.00,"unitMoney":""},
              {"x":1718726400000,"y":1.0100,"equityReturn":-0.98,"unitMoney":""}
            ];
            """,
            "https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=588760&topline=10": """
            var apidata={ content:"<table><thead><tr><th>序号</th><th>股票代码</th><th>股票名称</th><th>占净值<br />比例</th></tr></thead><tbody><tr><td>1</td><td><a>688521</a></td><td class='tol'><a>芯原股份</a></td><td class='tor'>10.21%</td></tr><tr><td>2</td><td><a>002230</a></td><td class='tol'><a>科大讯飞</a></td><td class='tor'>5.30%</td></tr></tbody></table>",records:2};
            """,
            "https://qt.gtimg.cn/q=s_sh688521,s_sz002230": """
            v_s_sh688521="1~芯原股份~688521~280.70~6.70~2.45";
            v_s_sz002230="51~科大讯飞~002230~43.61~-1.00~-2.35";
            """
        ])

        let today = try XCTUnwrap(DateOnlyFormatter.parse("2024-06-19"))
        let supplement = await service.fetchFundDetailSupplement(code: "588760", now: today)

        XCTAssertEqual(supplement.trend.count, 3)
        XCTAssertEqual(supplement.history.count, 3)
        XCTAssertEqual(supplement.trend.last?.value, 1.0100)
        XCTAssertEqual(supplement.yesterdayPoint?.equityReturn, 2.00)
        XCTAssertEqual(supplement.topHoldings.count, 2)
        XCTAssertEqual(supplement.topHoldings[0].code, "688521")
        XCTAssertEqual(supplement.topHoldings[0].name, "芯原股份")
        XCTAssertEqual(supplement.topHoldings[0].weight, "10.21%")
        XCTAssertEqual(supplement.topHoldings[0].changeRate, 2.45)
        XCTAssertEqual(supplement.topHoldings[1].changeRate, -2.35)
    }

    func testFundDetailSupplementUsesMobilePositionAndSectorSources() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fund.eastmoney.com/pingzhongdata/290008.js": """
            var Data_netWorthTrend = [
              {"x":1718553600000,"y":2.2100,"equityReturn":0,"unitMoney":""},
              {"x":1718640000000,"y":2.2650,"equityReturn":2.49,"unitMoney":""}
            ];
            """,
            "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNInverstPosition?FCODE=290008": """
            {"Datas":{"fundStocks":[{"GPDM":"300390","GPJC":"天华新能","JZBL":"9.97","PCTNVCHGTYPE":"增持","PCTNVCHG":"1.05","NEWTEXCH":"0","INDEXCODE":"029022","INDEXNAME":"电力设备"},{"GPDM":"002738","GPJC":"中矿资源","JZBL":"9.94","PCTNVCHGTYPE":"增持","PCTNVCHG":"1.14","NEWTEXCH":"0","INDEXCODE":"029004","INDEXNAME":"有色金属"},{"GPDM":"002240","GPJC":"盛新锂能","JZBL":"9.90","PCTNVCHGTYPE":"增持","PCTNVCHG":"1.71","NEWTEXCH":"0","INDEXCODE":"029004","INDEXNAME":"有色金属"}],"fundboods":[]},"ErrCode":0,"Success":true,"TotalCount":1,"Expansion":"2026-03-31"}
            """,
            "https://qt.gtimg.cn/q=s_sz300390,s_sz002738,s_sz002240": """
            v_s_sz300390="51~天华新能~300390~31.00~1.00~3.33";
            v_s_sz002738="51~中矿资源~002738~45.00~-1.00~-2.17";
            v_s_sz002240="51~盛新锂能~002240~12.00~0.30~2.56";
            """,
            "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNSectorAllocation?FCODE=290008": """
            {"Datas":[{"HYMC":"制造业","SZ":"110816.434718","ZJZBL":"62.91","FSRQ":"2026-03-31"},{"HYMC":"采矿业","SZ":"47116.755654","ZJZBL":"26.75","FSRQ":"2026-03-31"},{"HYMC":"合计","SZ":"165150.299572","ZJZBL":"93.76","FSRQ":"2026-03-31"}],"ErrCode":0,"Success":true,"TotalCount":3,"Expansion":"2026-03-31"}
            """,
            "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNAssetAllocationNew?FCODE=290008": """
            {"Datas":[{"FSRQ":"2026-03-31","GP":"93.76","ZQ":"--","HB":"6.91","JZC":"17.614","QT":"0","JJ":"--"}],"ErrCode":0,"Success":true,"TotalCount":1,"Expansion":"2026-03-31"}
            """
        ])

        let today = try XCTUnwrap(DateOnlyFormatter.parse("2024-06-19"))
        let supplement = await service.fetchFundDetailSupplement(code: "290008", now: today)

        XCTAssertEqual(supplement.topHoldings.count, 3)
        XCTAssertEqual(supplement.holdingDisclosureDate, "2026-03-31")
        XCTAssertEqual(supplement.topHoldings[0].code, "300390")
        XCTAssertEqual(supplement.topHoldings[0].industryName, "电力设备")
        XCTAssertEqual(supplement.topHoldings[0].positionChangeType, "增持")
        XCTAssertEqual(supplement.topHoldings[0].positionChangeRate ?? 0, 1.05, accuracy: 0.0001)
        XCTAssertEqual(supplement.topHoldings[0].changeRate, 3.33)

        XCTAssertEqual(supplement.relatedSectors.count, 2)
        XCTAssertEqual(supplement.relatedSectors[0].name, "有色金属")
        XCTAssertEqual(supplement.relatedSectors[0].weight, 19.84, accuracy: 0.0001)
        XCTAssertEqual(supplement.relatedSectors[1].name, "电力设备")
        XCTAssertEqual(supplement.industryAllocation.map(\.name), ["制造业", "采矿业"])
        XCTAssertEqual(supplement.assetAllocation.map(\.name), ["股票", "现金"])
        XCTAssertEqual(supplement.assetAllocation.first?.weight ?? 0, 93.76, accuracy: 0.0001)
    }

    func testFundDetailSupplementUsesLatestHistoryPointAfterMidnight() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fund.eastmoney.com/pingzhongdata/024480.js": """
            var Data_netWorthTrend = [
              {"x":1781712000000,"y":2.6157,"equityReturn":3.35,"unitMoney":""},
              {"x":1782057600000,"y":2.6460,"equityReturn":1.16,"unitMoney":""}
            ];
            """,
            "https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=024480&topline=10": """
            var apidata={ content:"<table></table>",records:0};
            """
        ])
        let afterMidnight = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-23"))

        let supplement = await service.fetchFundDetailSupplement(code: "024480", now: afterMidnight)

        XCTAssertEqual(supplement.yesterdayPoint?.value, 2.6460)
        XCTAssertEqual(supplement.yesterdayPoint?.equityReturn, 1.16)
    }

    func testConfirmedNetValueFallsBackToTrendHistoryWhenJSONHistoryFails() async throws {
        let targetDate = "2026-08-04"
        let targetTimestamp = try timestamp(targetDate)
        let service = quoteServiceWithMockResponses([
            "https://api.fund.eastmoney.com/f10/lsjz": "not-json",
            "https://fund.eastmoney.com/pingzhongdata/022184.js": """
            var Data_netWorthTrend = [
              {"x":\(targetTimestamp),"y":5.3271,"equityReturn":1.96,"unitMoney":""}
            ];
            """
        ])
        let latestQuote = FundQuote(
            code: "022184",
            name: "富国全球科技互联网股票(QDII)C",
            netValue: 5.3627,
            estimatedNetValue: 5.2593,
            growthRate: 0.67,
            estimateTime: "2026-08-07 14:54",
            netValueDate: "2026-08-05"
        )

        let value = await service.fetchConfirmedNetValue(
            code: "022184",
            acceptedDate: targetDate,
            latestQuote: latestQuote
        )

        XCTAssertEqual(try XCTUnwrap(value), 5.3271, accuracy: 0.0001)
        XCTAssertEqual(
            MockURLProtocol.responseStore.requests().compactMap(\.url?.host),
            ["api.fund.eastmoney.com", "fund.eastmoney.com"]
        )
    }

    func testConfirmedNetValueNeverUsesANewerHistoryDateForAnOlderTrade() async throws {
        let newerTimestamp = try timestamp("2026-08-05")
        let service = quoteServiceWithMockResponses([
            "https://api.fund.eastmoney.com/f10/lsjz": """
            {
              "Data": {
                "LSJZList": [
                  {"FSRQ":"2026-08-05","DWJZ":"5.3627"}
                ]
              },
              "ErrCode": 0
            }
            """,
            "https://fund.eastmoney.com/pingzhongdata/022184.js": """
            var Data_netWorthTrend = [
              {"x":\(newerTimestamp),"y":5.3627,"equityReturn":0.67,"unitMoney":""}
            ];
            """
        ])

        let value = await service.fetchConfirmedNetValue(
            code: "022184",
            acceptedDate: "2026-08-04"
        )

        XCTAssertNil(value)
        let currentRequest = try XCTUnwrap(
            MockURLProtocol.responseStore.requests().first { $0.url?.host == "api.fund.eastmoney.com" }
        )
        let queryItems = try XCTUnwrap(
            URLComponents(url: currentRequest.url!, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(queryItems.first { $0.name == "startDate" }?.value, "2026-08-04")
        XCTAssertEqual(queryItems.first { $0.name == "endDate" }?.value, "2026-08-04")
    }

    @MainActor
    func testNewFundAddedTodayWithoutConfirmedNetValueStaysPending() async throws {
        let now = try chinaDate("2026-06-24 14:45")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "024418",
                name: "华夏上证科创板半导体材料设备主题ETF联接A",
                netValueDate: "2026-06-23",
                netValue: 2.5709,
                estimatedNetValue: 2.6000,
                growthRate: 1.13,
                estimateTime: "2026-06-24 14:20"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=024418&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-23</td><td class='tor bold'>2.5709</td><td>2.5709</td><td class='red'>1.13%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-new-fund-unconfirmed-nav-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let draft = FundPositionDraft(
            code: "024418",
            name: "",
            positionMode: .amount,
            positionAmount: 5_000,
            positionProfit: 0,
            shares: nil,
            cost: nil,
            positionDate: "2026-06-24",
            positionTimeType: .before15,
            memo: ""
        )

        try await store.upsertFund(draft)

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024418" })
        XCTAssertEqual(fund.name, "华夏上证科创板半导体材料设备主题ETF联接A")
        XCTAssertEqual(fund.status, .pending)
        XCTAssertEqual(fund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertNil(fund.migratedCost)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(fund.currentAmount ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(fund.holdingIncome ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(fund.todayIncome, 0, accuracy: 0.0001)
        XCTAssertEqual(fund.isIncomeActive, false)
        XCTAssertEqual(store.snapshot.pendingCount, 1)
        XCTAssertEqual(store.snapshot.totalAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.holdingIncome, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.todayIncome, 0, accuracy: 0.0001)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .pending)
        XCTAssertEqual(record.acceptedDate, "2026-06-24")
        XCTAssertEqual(record.amount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertNil(record.confirmedShares)
        XCTAssertNil(record.price)
        XCTAssertNil(record.confirmedAt)
    }

    @MainActor
    func testHistoricalNewFundAddedTodayUsesLatestConfirmedNetValueImmediately() async throws {
        let now = try chinaDate("2026-06-24 14:45")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "024418",
                name: "华夏上证科创板半导体材料设备主题ETF联接A",
                netValueDate: "2026-06-23",
                netValue: 2.5709,
                estimatedNetValue: 2.6000,
                growthRate: 1.13,
                estimateTime: "2026-06-24 14:20"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=024418&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-23</td><td class='tor bold'>2.5709</td><td>2.5709</td><td class='red'>1.13%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-historical-fund-today-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let draft = FundPositionDraft(
            code: "024418",
            name: "",
            positionMode: .amount,
            positionAmount: 5_000,
            positionProfit: 0,
            shares: nil,
            cost: nil,
            positionDate: "2026-06-24",
            positionTimeType: .after15,
            memo: "",
            requiresTradeConfirmation: false
        )

        try await store.upsertFund(draft)

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024418" })
        XCTAssertEqual(fund.status, .holding)
        XCTAssertEqual(fund.positionDate, "2026-06-23")
        XCTAssertEqual(fund.migratedShares ?? 0, 1944.844218, accuracy: 0.000001)
        XCTAssertEqual(((fund.migratedShares ?? 0) * 100).rounded() / 100, 1944.84, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.5709, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.tradeDate, "2026-06-23")
        XCTAssertEqual(record.acceptedDate, "2026-06-23")
        XCTAssertEqual(record.price ?? 0, 2.5709, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 1944.844218, accuracy: 0.000001)
    }

    @MainActor
    func testHistoricalNewFundWithoutNetValueStillBecomesHolding() async throws {
        let now = try chinaDate("2026-06-24 14:45")
        let service = quoteServiceWithMockResponses([:])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-historical-fund-missing-nav-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let draft = FundPositionDraft(
            code: "024418",
            name: "华夏上证科创板半导体材料设备主题ETF联接A",
            positionMode: .amount,
            positionAmount: 5_000,
            positionProfit: 0,
            shares: nil,
            cost: nil,
            positionDate: "2026-06-24",
            positionTimeType: .before15,
            memo: "",
            requiresTradeConfirmation: false
        )

        try await store.upsertFund(draft)

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024418" })
        XCTAssertEqual(fund.status, .holding)
        XCTAssertEqual(fund.currentAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(fund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(fund.isIncomeActive, true)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertEqual(store.snapshot.totalAmount, 5_000, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingTrades)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertNil(record.confirmedShares)
        XCTAssertNil(record.price)
    }

    @MainActor
    func testPendingBuyAfter15UsesNextTradingDayNetValueAndConfirmsOneDayLater() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = tradeQuoteService(date: "2026-06-23", netValue: 3)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-buy-after15-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                        migratedShares: 100,
                        migratedCost: 1,
                        migratedPrincipal: 100,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-17",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "seed", shares: 100, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
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
                code: Self.tradeTestCode,
                mode: .amount,
                amount: 300,
                shares: nil,
                tradeDate: "2026-06-22",
                tradeTimeType: .after15
            )
        )

        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(pendingRecord.acceptedDate, "2026-06-23")
        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 15:30")
        await store.refreshQuotes()

        let stillPendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(stillPendingRecord.status, .pending)
        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.0001)

        now = try chinaDate("2026-06-24 09:30")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.acceptedDate, "2026-06-23")
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 3, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 400, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2, accuracy: 0.0001)
    }

    @MainActor
    func testEditingConfirmedSameDayNewFundTradeStaysHoldingWhenNetValueIsAvailable() async throws {
        let now = try chinaDate("2026-07-08 23:05")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "022485",
                name: "国金中证A500指数增强A",
                netValueDate: "2026-07-08",
                netValue: 1.5051,
                estimatedNetValue: 1.5153,
                growthRate: -1.79,
                estimateTime: "2026-07-08 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=022485&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-07-08</td><td class='tor bold'>1.5051</td><td>1.5051</td><td class='green'>-1.79%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-same-day-new-fund-record-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-07-08 22:55")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 116_552.60,
                holdingIncome: -3_447.40,
                holdingIncomeRate: -2.8728,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "022485",
                        name: "国金中证A500指数增强A",
                        dateText: "07-08 15:00",
                        todayIncome: 0,
                        todayRate: -1.79,
                        holdingRate: -2.8728,
                        status: .holding,
                        isUpdated: true,
                        isIncomeActive: true,
                        migratedShares: 77_438.442628,
                        migratedCost: 1.549618,
                        migratedPrincipal: 120_000,
                        incomeStartDate: "2026-07-08",
                        positionMode: .amount,
                        positionDate: "2026-07-08",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "new-record",
                                shares: 77_438.442628,
                                cost: 1.549618,
                                principal: 120_000,
                                incomeStartDate: "2026-07-08",
                                positionDate: "2026-07-08",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "new-record",
                        kind: .newFund,
                        status: .confirmed,
                        code: "022485",
                        name: "国金中证A500指数增强A",
                        mode: .amount,
                        amount: 116_552.60,
                        shares: nil,
                        confirmedShares: 77_438.442628,
                        price: 1.5051,
                        profit: -3_447.40,
                        tradeDate: "2026-07-08",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-08",
                        createdAt: createdAt,
                        confirmedAt: createdAt,
                        failureReason: nil
                    )
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editTradeRecord(
            id: "new-record",
            with: FundTradeDraft(
                action: .buy,
                code: "022485",
                mode: .amount,
                amount: 122_552.60,
                shares: nil,
                tradeDate: "2026-07-08",
                tradeTimeType: .before15
            )
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "022485" })
        XCTAssertEqual(fund.status, .holding)
        XCTAssertEqual(fund.currentAmount ?? 0, 122_552.60, accuracy: 0.001)
        XCTAssertEqual(fund.pendingAmount ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "new-record" })
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount ?? 0, 122_552.60, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 81_424.888712, accuracy: 0.000001)
        XCTAssertEqual(record.price ?? 0, 1.5051, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

    @MainActor
    func testEditingAmountPositionAllowsNegativeProfitAndUsesLatestNetValue() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "018926",
                name: "南方中证电池ETF联接A",
                netValueDate: "2026-06-18",
                netValue: 1.7394,
                estimatedNetValue: 1.7394,
                growthRate: -1.01,
                estimateTime: "2026-06-18 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=018926&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-18</td><td class='tor bold'>1.7394</td><td>1.7394</td><td class='green'>-1.01%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """,
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=018926&page=1&per=1&sdate=2026-05-15&edate=2026-05-15": """
            var apidata={ content:"<table><tbody><tr><td>2026-05-15</td><td class='tor bold'>1.8218</td><td>1.8218</td><td class='green'>-0.22%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service)
        let seedSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "018926",
                    name: "南方中证电池ETF联接A",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: true,
                    migratedShares: 1,
                    migratedCost: 1,
                    migratedPrincipal: 1
                )
            ],
            migration: nil
        )
        let importURL = tempDirectory.appending(path: "seed.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let seedData = try encoder.encode(seedSnapshot)
        try seedData.write(to: importURL, options: .atomic)
        try store.importPortfolio(from: importURL)

        let draft = FundPositionDraft(
            code: "018926",
            name: "南方中证电池ETF联接A",
            positionMode: .amount,
            positionAmount: 3263.04,
            positionProfit: -236.96,
            shares: nil,
            cost: nil,
            positionDate: "2026-05-15",
            positionTimeType: .before15,
            memo: ""
        )

        try await store.upsertFund(draft, replacing: "018926")

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "018926" })
        XCTAssertEqual(fund.migratedShares ?? 0, 1875.957227, accuracy: 0.000001)
        XCTAssertEqual(((fund.migratedShares ?? 0) * 100).rounded() / 100, 1875.96, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1.8657, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 3500, accuracy: 0.1)
        XCTAssertEqual(fund.status, .holding)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.kind, .newFund)
        XCTAssertEqual(record.amount ?? 0, 3263.04, accuracy: 0.0001)
        XCTAssertEqual(record.profit ?? 0, -236.96, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 1875.957227, accuracy: 0.000001)
        XCTAssertEqual(record.price ?? 0, 1.7394, accuracy: 0.0001)
    }

    @MainActor
    func testEditingAmountFundPreservesManuallyRecordedProfitAfterQuoteRefresh() async throws {
        let now = try chinaDate("2026-06-27 12:20")
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
            .appending(path: "fund-pulse-edit-amount-profit-baseline-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })

        try await store.upsertFund(
            FundPositionDraft(
                code: "007818",
                name: "国泰中证全指通信设备ETF联接C",
                positionMode: .amount,
                positionAmount: 15_455.10,
                positionProfit: -544.90,
                shares: nil,
                cost: nil,
                positionDate: "2026-06-26",
                positionTimeType: .before15,
                memo: ""
            )
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "007818" })
        XCTAssertEqual(fund.currentAmount ?? 0, 15_455.10, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedShares ?? 0, 3243.122443, accuracy: 0.000001)
        XCTAssertEqual(((fund.migratedShares ?? 0) * 100).rounded() / 100, 3243.12, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 4.9335, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 16_000, accuracy: 0.0001)
        XCTAssertEqual(fund.holdingIncome ?? 0, -544.90, accuracy: 0.0001)
        XCTAssertEqual(((fund.currentAmount ?? 0) * 100).rounded() / 100, 15_455.10, accuracy: 0.0001)
        XCTAssertEqual(((fund.holdingIncome ?? 0) * 100).rounded() / 100, -544.90, accuracy: 0.0001)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.code == "007818" })
        XCTAssertEqual(record.profit ?? 0, -544.90, accuracy: 0.0001)
    }

    func testPortfolioCalculatorKeepsHoldingAmountAtOfficialNetValueDuringIntradayEstimate() throws {
        let now = try chinaDate("2026-06-22 10:35")
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
                    code: "024480",
                    name: "财通品质甄选混合A",
                    dateText: "06-18 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    migratedShares: 100,
                    migratedCost: 2,
                    migratedPrincipal: 200,
                    incomeStartDate: "2026-06-21"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "024480",
            name: "财通品质甄选混合A",
            netValue: 2,
            estimatedNetValue: 2.1,
            growthRate: 5,
            estimateTime: "2026-06-22 10:31",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["024480": quote],
            now: now
        )

        XCTAssertEqual(result.todayIncome, 10, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncome, 0, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncomeRate, 0, accuracy: 0.0001)
        XCTAssertEqual(result.totalAmount, 200, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, 10, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].holdingIncome ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].holdingRate ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].currentAmount ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayRate, 5, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].dateText, "06-22 10:31")
        XCTAssertEqual(result.funds[0].isIncomeActive, true)
    }

    func testHoldingIncomeAndAmountUseOfficialNetValueWhileTodayIncomeUsesEstimate() throws {
        let now = try chinaDate("2026-06-22 11:52")
        let shares = 11_518.08
        let cost = 0.8682
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
                    status: .holding,
                    isUpdated: false,
                    migratedShares: shares,
                    migratedCost: cost,
                    migratedPrincipal: shares * cost,
                    incomeStartDate: "2026-06-21"
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "588760",
            name: "科创人工智能ETF广发",
            netValue: 0.9245,
            estimatedNetValue: 0.9066,
            growthRate: -1.98,
            estimateTime: "2026-06-22 11:30",
            netValueDate: "2026-06-18"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["588760": quote],
            now: now
        )

        let expectedTodayIncome = shares * (quote.estimatedNetValue - quote.netValue)
        let expectedHoldingIncome = shares * (quote.netValue - cost)
        let expectedPrincipal = shares * cost
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncome, expectedHoldingIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].holdingIncome ?? 0, expectedHoldingIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].holdingRate ?? 0, expectedHoldingIncome / expectedPrincipal * 100, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].confirmedHoldingIncome ?? 0, expectedHoldingIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].confirmedHoldingRate ?? 0, expectedHoldingIncome / expectedPrincipal * 100, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].currentAmount ?? 0, shares * quote.netValue, accuracy: 0.0001)
        XCTAssertEqual(result.totalAmount, shares * quote.netValue, accuracy: 0.0001)
    }
}
