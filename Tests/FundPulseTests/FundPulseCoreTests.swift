import XCTest
@testable import FundPulse

final class FundPulseCoreTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responseStore.reset()
        super.tearDown()
    }

    func testVersionComparatorHandlesTagsAndPatchVersions() {
        XCTAssertTrue(VersionComparator.isVersion("0.0.13", newerThan: "0.0.12"))
        XCTAssertTrue(VersionComparator.isVersion("v0.1.0", newerThan: "0.0.99"))
        XCTAssertFalse(VersionComparator.isVersion("v0.0.12", newerThan: "0.0.12"))
        XCTAssertFalse(VersionComparator.isVersion("0.0.11", newerThan: "0.0.12"))
    }

    func testDefaultAutoRefreshIntervalIsTenSeconds() {
        let settings = AppSettings()

        XCTAssertEqual(settings.autoRefreshInterval, .tenSeconds)
        XCTAssertEqual(settings.autoRefreshInterval.seconds, 10)
        XCTAssertEqual(settings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(settings.operationReminderEnabled)
        XCTAssertEqual(settings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(settings.operationReminderTimeText, "14:30")
    }

    @MainActor
    func testSettingsMigrationKeepsExistingValuesAndAddsReminderDefaults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-settings-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let settingsURL = tempDirectory.appending(path: "settings.json")
        let legacySettings = """
        {
          "settingsSchemaVersion": 3,
          "menuBarDisplayMode": "sign",
          "autoRefreshInterval": "30s"
        }
        """
        try Data(legacySettings.utf8).write(to: settingsURL, options: .atomic)

        let store = AppSettingsStore(dataDirectory: tempDirectory)

        XCTAssertEqual(store.settings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        XCTAssertEqual(store.settings.menuBarDisplayMode, .sign)
        XCTAssertEqual(store.settings.autoRefreshInterval, .thirtySeconds)
        XCTAssertEqual(store.settings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(store.settings.operationReminderEnabled)
        XCTAssertEqual(store.settings.operationReminderTimeMinutes, 14 * 60 + 30)

        let savedData = try Data(contentsOf: settingsURL)
        let savedSettings = try JSONDecoder().decode(AppSettings.self, from: savedData)
        XCTAssertEqual(savedSettings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        XCTAssertEqual(savedSettings.menuBarDisplayMode, .sign)
        XCTAssertEqual(savedSettings.autoRefreshInterval, .thirtySeconds)
        XCTAssertEqual(savedSettings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(savedSettings.operationReminderEnabled)
        XCTAssertEqual(savedSettings.operationReminderTimeMinutes, 14 * 60 + 30)
    }

    @MainActor
    func testMainPanelHeightPersistsLocally() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-height-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = AppSettingsStore(dataDirectory: tempDirectory)

        store.setMainPanelHeight(780)

        XCTAssertEqual(store.settings.mainPanelHeight, 780)

        let savedData = try Data(contentsOf: tempDirectory.appending(path: "settings.json"))
        let savedSettings = try JSONDecoder().decode(AppSettings.self, from: savedData)
        XCTAssertEqual(savedSettings.mainPanelHeight, 780)

        let reloadedStore = AppSettingsStore(dataDirectory: tempDirectory)
        XCTAssertEqual(reloadedStore.settings.mainPanelHeight, 780)

        store.setMainPanelHeight(777)
        XCTAssertEqual(store.settings.mainPanelHeight, 777)
    }

    func testEastmoneySourceUsesF10OfficialNetValueWhenFundGZOfficialIsStale() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-17","dwjz":"2.2871","gsz":"2.3511","gszzl":"2.80","gztime":"2026-06-18 15:00"});
            """,
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-18</td><td class='tor bold'>2.3773</td><td>2.3773</td><td class='red'>3.94%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])

        let quote = try await service.fetchQuote(code: "026210", source: .eastmoneyFundGZ)

        XCTAssertEqual(quote.netValue, 2.3773, accuracy: 0.0001)
        XCTAssertEqual(quote.estimatedNetValue, 2.3773, accuracy: 0.0001)
        XCTAssertEqual(quote.growthRate, 3.94, accuracy: 0.0001)
        XCTAssertEqual(quote.netValueDate, "2026-06-18")
        XCTAssertEqual(quote.estimateTime, "")
    }

    func testEastmoneySourceKeepsIntradayEstimateWhenItIsNewerThanOfficialNetValue() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-18","dwjz":"2.3773","gsz":"2.5000","gszzl":"5.16","gztime":"2026-06-22 14:30"});
            """,
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=026210&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-18</td><td class='tor bold'>2.3773</td><td>2.3773</td><td class='red'>3.94%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])

        let quote = try await service.fetchQuote(code: "026210", source: .eastmoneyFundGZ)

        XCTAssertEqual(quote.netValue, 2.3773, accuracy: 0.0001)
        XCTAssertEqual(quote.estimatedNetValue, 2.5, accuracy: 0.0001)
        XCTAssertEqual(quote.growthRate, 5.16, accuracy: 0.0001)
        XCTAssertEqual(quote.netValueDate, "2026-06-18")
        XCTAssertEqual(quote.estimateTime, "2026-06-22 14:30")
    }

    func testLookupFundNameUsesEastmoneySuggest() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": """
            FundPulseSuggest_123({"Datas":[{"CODE":"026210","NAME":"平安科技精选混合发起式A","SHORTNAME":"平安科技精选混合发起式A"}]});
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

    @MainActor
    func testAmountPositionDerivesSharesAndCostLikeFundBaby() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-18","dwjz":"2.3773","gsz":"2.3773","gszzl":"3.94","gztime":"2026-06-18 15:00"});
            """,
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
            zdfRange: nil,
            jzNotice: nil,
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
        XCTAssertEqual(record.confirmedShares ?? 0, 1000, accuracy: 0.0001)
    }

    @MainActor
    func testNewFundAddedTodayStaysPendingAfterNetValueUpdatesUntilNextDay() async throws {
        var now = try chinaDate("2026-06-23 21:48")
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/025833.js": """
            jsonpgz({"fundcode":"025833","name":"天弘电网设备特高压指数C","jzrq":"2026-06-23","dwjz":"1.5130","gsz":"1.5130","gszzl":"-2.76","gztime":"2026-06-23 15:00"});
            """,
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=025833&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-06-23</td><td class='tor bold'>1.5130</td><td>1.5130</td><td class='green'>-2.76%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-new-fund-same-day-pending-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let draft = FundPositionDraft(
            code: "025833",
            name: "",
            positionMode: .amount,
            positionAmount: 5_000,
            positionProfit: 0,
            shares: nil,
            cost: nil,
            positionDate: "2026-06-23",
            positionTimeType: .before15,
            zdfRange: nil,
            jzNotice: nil,
            memo: ""
        )

        try await store.upsertFund(draft)

        let pendingFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(pendingFund.name, "天弘电网设备特高压指数C")
        XCTAssertEqual(pendingFund.status, .pending)
        XCTAssertEqual(pendingFund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(pendingFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 1)
        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(pendingRecord.kind, .newFund)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertNil(pendingRecord.confirmedShares)
        XCTAssertNil(pendingRecord.price)

        await store.refreshQuotes()

        let stillPendingFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(stillPendingFund.status, .pending)
        XCTAssertEqual(stillPendingFund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(stillPendingFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.status, .pending)

        now = try chinaDate("2026-06-24 09:30")
        await store.refreshQuotes()

        let confirmedFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(confirmedFund.status, .holding)
        XCTAssertEqual(confirmedFund.pendingAmount ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(confirmedFund.migratedShares ?? 0, 3304.69, accuracy: 0.0001)
        XCTAssertEqual(confirmedFund.migratedCost ?? 0, 1.5130, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 3304.69, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 1.5130, accuracy: 0.0001)
    }

    @MainActor
    func testPrematureSameDayNewFundConfirmationIsRestoredToPending() async throws {
        let now = try chinaDate("2026-06-23 21:48")
        let createdAt = try chinaDate("2026-06-23 15:41")
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/025833.js": """
            jsonpgz({"fundcode":"025833","name":"天弘电网设备特高压指数C","jzrq":"2026-06-23","dwjz":"1.5130","gsz":"1.5130","gszzl":"-2.76","gztime":"2026-06-23 15:00"});
            """,
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
        XCTAssertEqual(restoredFund.status, .pending)
        XCTAssertEqual(restoredFund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(restoredFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 1)
        let restoredRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(restoredRecord.status, .pending)
        XCTAssertNil(restoredRecord.confirmedShares)
        XCTAssertNil(restoredRecord.price)
        XCTAssertNil(restoredRecord.confirmedAt)
    }

    @MainActor
    func testConfirmedBuyTradeCreatesRecordAndUpdatesWeightedCost() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-18","dwjz":"2.3773","gsz":"2.3773","gszzl":"3.94","gztime":"2026-06-18 15:00"});
            """,
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
    func testPendingBuyTradeWaitsUntilNextDayBeforeUpdatingHolding() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-18","dwjz":"2.3773","gsz":"2.5000","gszzl":"5.16","gztime":"2026-06-22 14:30"});
            """,
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
            "https://fundgz.1234567.com.cn/js/026210.js": Data("""
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-22","dwjz":"2.5000","gsz":"2.5000","gszzl":"5.16","gztime":"2026-06-22 15:00"});
            """.utf8),
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
    func testPendingSellTradeWaitsUntilNextDayBeforeReducingHolding() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-22","dwjz":"2.5000","gsz":"2.5000","gszzl":"5.16","gztime":"2026-06-22 15:00"});
            """,
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
                mode: .amount,
                amount: 250,
                shares: nil,
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
    func testEditingConfirmedBuyTradeRecalculatesHolding() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-22","dwjz":"2.5000","gsz":"2.5000","gszzl":"5.16","gztime":"2026-06-22 15:00"});
            """,
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
    func testDeletingConfirmedSellTradeRecalculatesHolding() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/026210.js": """
            jsonpgz({"fundcode":"026210","name":"平安科技精选混合发起式A","jzrq":"2026-06-22","dwjz":"2.5000","gsz":"2.5000","gszzl":"5.16","gztime":"2026-06-22 15:00"});
            """,
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
    func testEditingAmountPositionAllowsNegativeProfitAndUsesLatestNetValue() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundgz.1234567.com.cn/js/018926.js": """
            jsonpgz({"fundcode":"018926","name":"南方中证电池ETF联接A","jzrq":"2026-06-18","dwjz":"1.7394","gsz":"1.7394","gszzl":"-1.01","gztime":"2026-06-18 15:00"});
            """,
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
            zdfRange: nil,
            jzNotice: nil,
            memo: ""
        )

        try await store.upsertFund(draft, replacing: "018926")

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "018926" })
        XCTAssertEqual(fund.migratedShares ?? 0, 1875.96, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1.8657, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 3500, accuracy: 0.1)
        XCTAssertEqual(fund.status, .holding)
    }

    func testTradingCalendarAcceptedTradeDateSkipsDragonBoatHoliday() {
        XCTAssertEqual(
            TradingCalendar.acceptedTradeDate(positionDate: "2026-06-18", timeType: .before15),
            "2026-06-18"
        )
        XCTAssertEqual(
            TradingCalendar.acceptedTradeDate(positionDate: "2026-06-18", timeType: .after15),
            "2026-06-22"
        )
    }

    func testMarketSessionStateUsesTradingHoursAfterDragonBoatHoliday() throws {
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 10:35")), .open)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 12:00")), .middayBreak)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 15:01")), .closed)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-21 10:35")), .closed)
    }

    func testPortfolioCalculatorUsesOfficialValueForHoldingAmountAndRealtimeForTodayIncome() throws {
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
                    incomeStartDate: "2026-06-22"
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
        XCTAssertEqual(result.funds[0].holdingRate ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayRate, 5, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].dateText, "06-22 10:31")
        XCTAssertEqual(result.funds[0].isIncomeActive, true)
    }

    func testHoldingIncomeUsesOfficialNetValueWhileTodayIncomeUsesRealtimeEstimate() throws {
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
                    incomeStartDate: "2026-06-22"
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
        let expectedConfirmedHoldingIncome = shares * (quote.netValue - cost)
        let expectedPrincipal = shares * cost
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.holdingIncome, expectedHoldingIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].holdingIncome ?? 0, expectedHoldingIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].holdingRate ?? 0, expectedHoldingIncome / expectedPrincipal * 100, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].confirmedHoldingIncome ?? 0, expectedConfirmedHoldingIncome, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].confirmedHoldingRate ?? 0, expectedConfirmedHoldingIncome / expectedPrincipal * 100, accuracy: 0.0001)
        XCTAssertEqual(result.totalAmount, shares * quote.netValue, accuracy: 0.0001)
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
    func testPortfolioImportExportPreservesEnteredFundConfiguration() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-import-export-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let importedDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-imported-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            try? FileManager.default.removeItem(at: importedDirectory)
        }

        let createdAt = try chinaDate("2026-06-23 15:41")
        let confirmedAt = try chinaDate("2026-06-24 09:30")
        let snapshot = PortfolioSnapshot(
            updateTime: createdAt,
            totalAmount: 1_250,
            holdingIncome: 50,
            holdingIncomeRate: 4.17,
            todayIncome: 12.5,
            todayIncomeRate: 1,
            pendingCount: 1,
            funds: [
                FundPosition(
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    dateText: "06-23 15:00",
                    todayIncome: 12.5,
                    todayRate: 1,
                    holdingIncome: 50,
                    holdingRate: 4.17,
                    confirmedHoldingIncome: 50,
                    confirmedHoldingRate: 4.17,
                    currentAmount: 1_250,
                    status: .holding,
                    isUpdated: true,
                    isIncomeActive: true,
                    migratedShares: 500,
                    migratedCost: 2.4,
                    migratedPrincipal: 1_200,
                    incomeStartDate: "2026-06-23",
                    positionMode: .amount,
                    positionDate: "2026-06-23",
                    positionTimeType: .before15,
                    pendingAmount: nil,
                    pendingProfit: nil,
                    zdfRange: 3.2,
                    jzNotice: 1.1,
                    memo: "核心仓",
                    lots: [
                        FundPositionLot(
                            id: "lot-1",
                            shares: 500,
                            cost: 2.4,
                            incomeStartDate: "2026-06-23",
                            positionDate: "2026-06-23",
                            positionTimeType: .before15
                        )
                    ]
                )
            ],
            migration: nil,
            pendingTrades: [
                FundPendingTrade(
                    id: "pending-buy",
                    recordID: "record-buy",
                    action: .buy,
                    code: "026210",
                    mode: .amount,
                    amount: 300,
                    shares: nil,
                    tradeDate: "2026-06-23",
                    tradeTimeType: .after15,
                    createdAt: createdAt
                )
            ],
            tradeRecords: [
                FundTradeRecord(
                    id: "record-new",
                    kind: .newFund,
                    status: .confirmed,
                    code: "026210",
                    name: "平安科技精选混合发起式A",
                    mode: .amount,
                    amount: 1_200,
                    shares: nil,
                    confirmedShares: 500,
                    price: 2.4,
                    tradeDate: "2026-06-23",
                    tradeTimeType: .before15,
                    acceptedDate: "2026-06-23",
                    createdAt: createdAt,
                    confirmedAt: confirmedAt,
                    failureReason: nil
                )
            ]
        )
        let store = PortfolioStore(dataDirectory: tempDirectory)
        try seedPortfolio(snapshot, into: store, directory: tempDirectory)

        let exportURL = tempDirectory.appending(path: "fund-config.json")
        try store.exportPortfolio(to: exportURL)

        let exportedJSON = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exportedJSON.contains("\"funds\""))
        XCTAssertTrue(exportedJSON.contains("\"positionDate\""))
        XCTAssertTrue(exportedJSON.contains("\"pendingTrades\""))
        XCTAssertTrue(exportedJSON.contains("\"tradeRecords\""))
        XCTAssertTrue(exportedJSON.contains("\"createdAt\""))

        let importedStore = PortfolioStore(dataDirectory: importedDirectory)
        try importedStore.importPortfolio(from: exportURL)

        XCTAssertEqual(importedStore.snapshot, snapshot)
        XCTAssertEqual(importedStore.snapshot.funds.first?.positionDate, "2026-06-23")
        XCTAssertEqual(importedStore.snapshot.pendingTrades?.first?.createdAt, createdAt)
        XCTAssertEqual(importedStore.snapshot.tradeRecords?.first?.confirmedAt, confirmedAt)
    }

    @MainActor
    private func seedPortfolio(
        _ snapshot: PortfolioSnapshot,
        into store: PortfolioStore,
        directory: URL
    ) throws {
        let importURL = directory.appending(path: "seed.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let seedData = try encoder.encode(snapshot)
        try seedData.write(to: importURL, options: .atomic)
        try store.importPortfolio(from: importURL)
    }

    private func quoteServiceWithMockResponses(_ responses: [String: String]) -> FundQuoteService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return FundQuoteService(session: URLSession(configuration: configuration))
    }

    private func chinaDate(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: value))
    }
}

private final class MockResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func set(_ responses: [String: Data]) {
        lock.lock()
        storage = responses
        lock.unlock()
    }

    func reset() {
        lock.lock()
        storage = [:]
        lock.unlock()
    }

    func response(for url: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage
            .filter { url.hasPrefix($0.key) }
            .max { lhs, rhs in lhs.key.count < rhs.key.count }?
            .value
    }
}

private final class MockURLProtocol: URLProtocol {
    static let responseStore = MockResponseStore()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url?.absoluteString,
              let data = Self.responseStore.response(for: url)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
