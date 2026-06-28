import XCTest
@testable import FundPulse
#if canImport(AppKit)
import AppKit
#endif

final class FundPulseCoreTests: XCTestCase {
    private static let tradeTestCode = "026210"
    private static let tradeTestName = "平安科技精选混合发起式A"

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

    func testFundCodeFormatterDisplaysCodeWithoutHashPrefix() {
        XCTAssertEqual(FundCodeFormatter.display("024418"), "024418")
        XCTAssertEqual(FundCodeFormatter.display("#024418"), "024418")
        XCTAssertEqual(FundCodeFormatter.display("  #024418  "), "024418")
        XCTAssertEqual(FundCodeFormatter.display(""), "--")
    }

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

    func testStatusBarToneIntensityUsesTodayRateThresholds() {
        XCTAssertEqual(StatusBarTone.intensity(forRate: 0), .neutral)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 0.10), .neutral)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 0.11), .subtle)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 1.00), .normal)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 2.00), .clear)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 3.00), .strong)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 4.00), .extreme)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 5.00), .extreme)
        XCTAssertEqual(StatusBarTone.intensity(forRate: 5.01), .maximum)
        XCTAssertEqual(StatusBarTone.intensity(forRate: -4.00), .extreme)
        XCTAssertEqual(StatusBarTone.intensity(forRate: -5.00), .extreme)
        XCTAssertEqual(StatusBarTone.intensity(forRate: -5.01), .maximum)
    }

    func testMenuBarStatusFormatterUsesConfiguredContentMode() {
        XCTAssertEqual(
            MenuBarStatusFormatter.text(amount: 12.3, rate: 1.23, mode: .amount),
            "+12.30"
        )
        XCTAssertEqual(
            MenuBarStatusFormatter.text(amount: 12.3, rate: 1.23, mode: .rate),
            "+1.23%"
        )
        XCTAssertEqual(
            MenuBarStatusFormatter.text(amount: 12.3, rate: 1.23, mode: .both),
            "+12.30 | +1.23%"
        )
        XCTAssertEqual(
            MenuBarStatusFormatter.text(amount: -8, rate: -0.56, mode: .both),
            "-8.00 | -0.56%"
        )
    }

    #if canImport(AppKit)
    func testStatusBarToneMenuBarColorsUseFundBabyStyleDepth() throws {
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 0)), "#8E8E93")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 0.50)), "#FF9F9A")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 1.50)), "#E1827D")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 2.50)), "#C46562")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 3.50)), "#A74847")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 4.50)), "#8A2B2D")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: 5.50)), "#6E0714")

        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: -0.50)), "#8EDDA2")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: -1.50)), "#72BA87")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: -2.50)), "#57986C")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: -3.50)), "#3C7753")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: -4.50)), "#23583B")
        XCTAssertEqual(try rgbHex(StatusBarTone.menuBarColor(forRate: -5.50)), "#073B24")
    }
    #endif

    func testDefaultAutoRefreshIntervalIsTenSeconds() {
        let settings = AppSettings()

        XCTAssertEqual(settings.autoRefreshInterval, .tenSeconds)
        XCTAssertEqual(settings.autoRefreshInterval.seconds, 10)
        XCTAssertEqual(AutoRefreshInterval.twoSeconds.seconds, 2)
        XCTAssertEqual(AutoRefreshInterval.fiveSeconds.seconds, 5)
        XCTAssertEqual(Array(AutoRefreshInterval.allCases.prefix(3)), [.twoSeconds, .fiveSeconds, .tenSeconds])
        XCTAssertEqual(AutoRefreshInterval.interval(atSliderIndex: 0), .twoSeconds)
        XCTAssertEqual(AutoRefreshInterval.interval(atSliderIndex: 1), .fiveSeconds)
        XCTAssertEqual(AutoRefreshInterval.interval(atSliderIndex: 2), .tenSeconds)
        XCTAssertEqual(settings.menuBarDisplayMode, .color)
        XCTAssertTrue(settings.menuBarDisplayMode.usesGrowthColor)
        XCTAssertEqual(MenuBarDisplayMode.allCases.map(\.title), ["红绿", "单色"])
        XCTAssertEqual(settings.menuBarContentMode, .amount)
        XCTAssertEqual(MenuBarContentMode.allCases.map(\.title), ["金额", "百分比", "都显示"])
        XCTAssertEqual(settings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(settings.operationReminderEnabled)
        XCTAssertEqual(settings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(settings.operationReminderTimeText, "14:30")
        XCTAssertEqual(settings.thresholdReminderInterval, .thirtyMinutes)
        XCTAssertEqual(settings.thresholdReminderInterval.seconds, 30 * 60)
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertEqual(AppAppearanceMode.allCases.map(\.title), ["跟随系统", "浅色", "深色"])
    }

    func testFundThresholdReminderEvaluatorTriggersDailyGrowthRange() throws {
        let date = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-24"))
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(code: "024418", todayRate: 5.41, zdfRange: 5),
                thresholdReminderFund(code: "024424", todayRate: -5.2, zdfRange: 5),
                thresholdReminderFund(code: "025833", todayRate: 4.99, zdfRange: 5)
            ]
        )

        let reminders = FundThresholdReminderEvaluator.reminders(in: snapshot, date: date)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.code), ["024418", "024424"])
        XCTAssertEqual(reminders.map(\.kind), [.dailyGrowth, .dailyGrowth])
        XCTAssertEqual(reminders[0].title, "测试基金024418")
        XCTAssertEqual(reminders[0].body, "涨跌幅提醒：当前涨幅 +5.41%。")
        XCTAssertEqual(reminders[1].title, "测试基金024424")
        XCTAssertEqual(reminders[1].body, "涨跌幅提醒：当前跌幅 -5.20%。")
    }

    func testFundThresholdReminderEvaluatorTriggersNetValueTarget() throws {
        let date = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-24"))
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(
                    code: "024418",
                    todayRate: 1.2,
                    currentAmount: 2_570.9,
                    shares: 1_000,
                    jzNotice: 2.5
                ),
                thresholdReminderFund(
                    code: "025833",
                    todayRate: 1.2,
                    currentAmount: 2_400,
                    shares: 1_000,
                    jzNotice: 2.5
                )
            ]
        )

        let reminders = FundThresholdReminderEvaluator.reminders(in: snapshot, date: date)

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.code, "024418")
        XCTAssertEqual(reminders.first?.kind, .netValue)
        XCTAssertEqual(reminders.first?.title, "测试基金024418")
        XCTAssertEqual(reminders.first?.body, "净值提醒：当前净值 2.5709，目标 2.5000。")
    }

    func testFundThresholdReminderEvaluatorOnlySendsOncePerDay() throws {
        let now = try chinaDate("2026-06-24 13:30")
        let nextDay = try chinaDate("2026-06-25 09:45")
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(code: "024418", todayRate: 5.41, zdfRange: 5)
            ]
        )
        let reminder = try XCTUnwrap(FundThresholdReminderEvaluator.reminders(in: snapshot, date: now).first)

        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                now: now,
                lastSentAt: [reminder.dedupeKey: try chinaDate("2026-06-24 09:31")]
            ).isEmpty
        )
        XCTAssertEqual(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                now: nextDay,
                lastSentAt: [reminder.dedupeKey: try chinaDate("2026-06-24 14:55")]
            ).count,
            1
        )
    }

    func testFundThresholdReminderEvaluatorOnlyRunsWhileMarketIsOpen() throws {
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(code: "024418", todayRate: 5.41, zdfRange: 5)
            ]
        )

        XCTAssertEqual(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                now: try chinaDate("2026-06-24 10:30"),
                lastSentAt: [:]
            ).count,
            1
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                now: try chinaDate("2026-06-24 12:00"),
                lastSentAt: [:]
            ).isEmpty
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                now: try chinaDate("2026-06-24 15:01"),
                lastSentAt: [:]
            ).isEmpty
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                now: try chinaDate("2026-06-21 10:30"),
                lastSentAt: [:]
            ).isEmpty
        )
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
        XCTAssertEqual(store.settings.menuBarContentMode, .amount)
        XCTAssertEqual(store.settings.autoRefreshInterval, .thirtySeconds)
        XCTAssertEqual(store.settings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(store.settings.operationReminderEnabled)
        XCTAssertEqual(store.settings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(store.settings.thresholdReminderInterval, .thirtyMinutes)
        XCTAssertEqual(store.settings.appearanceMode, .system)

        let savedData = try Data(contentsOf: settingsURL)
        let savedSettings = try JSONDecoder().decode(AppSettings.self, from: savedData)
        XCTAssertEqual(savedSettings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        XCTAssertEqual(savedSettings.menuBarDisplayMode, .sign)
        XCTAssertEqual(savedSettings.menuBarContentMode, .amount)
        XCTAssertEqual(savedSettings.autoRefreshInterval, .thirtySeconds)
        XCTAssertEqual(savedSettings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(savedSettings.operationReminderEnabled)
        XCTAssertEqual(savedSettings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(savedSettings.thresholdReminderInterval, .thirtyMinutes)
        XCTAssertEqual(savedSettings.appearanceMode, .system)
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
        store.setThresholdReminderInterval(.twoHours)
        XCTAssertEqual(store.settings.thresholdReminderInterval, .twoHours)
        store.setAppearanceMode(.dark)
        XCTAssertEqual(store.settings.appearanceMode, .dark)
        store.setMenuBarContentMode(.both)
        XCTAssertEqual(store.settings.menuBarContentMode, .both)
        store.setMenuBarDisplayMode(.sign)
        XCTAssertEqual(store.settings.menuBarDisplayMode, .sign)
        XCTAssertFalse(store.settings.menuBarDisplayMode.usesGrowthColor)
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

    func testEastmoneyCoreUsesOfficialGrowthRateAfterNavDateCatchesEstimateDate() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": """
            {"data":[{"NAV":"--","DWJZ":2.4712,"GZTIME":"2026-06-26 15:00","PTYPE":"F","SHORTNAME":"平安科技精选混合发起式A","QDCODE":"026210","FCODE":"026210","RZDF":-3.57,"JZRQ":"--","FSRQ":"2026-06-26","GSZZL":-5.65,"GSZ":2.4177}],"errorCode":0,"success":true,"totalCount":1}
            """
        ])

        let quote = try await service.fetchQuote(code: "026210")

        XCTAssertEqual(quote.netValue, 2.4712, accuracy: 0.0001)
        XCTAssertEqual(quote.estimatedNetValue, 2.4177, accuracy: 0.0001)
        XCTAssertEqual(quote.growthRate, -3.57, accuracy: 0.0001)
        XCTAssertEqual(quote.netValueDate, "2026-06-26")
        XCTAssertEqual(quote.estimateTime, "2026-06-26 15:00")
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
        XCTAssertEqual(record.amount ?? 0, 2377.30, accuracy: 0.0001)
        XCTAssertEqual(record.profit ?? 0, 177.30, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 1000, accuracy: 0.0001)
        XCTAssertEqual(record.price ?? 0, 2.3773, accuracy: 0.0001)
    }

    @MainActor
    func testNewFundAddedBefore15WaitsUntilNextDayToConfirm() async throws {
        var now = try chinaDate("2026-06-23 21:48")
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

        let createdFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(createdFund.name, "天弘电网设备特高压指数C")
        XCTAssertEqual(createdFund.status, .pending)
        XCTAssertEqual(createdFund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(createdFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 1)
        let createdRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(createdRecord.kind, .newFund)
        XCTAssertEqual(createdRecord.status, .pending)
        XCTAssertEqual(createdRecord.amount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertNil(createdRecord.confirmedShares)
        XCTAssertNil(createdRecord.price)

        await store.refreshQuotes()

        let refreshedFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(refreshedFund.status, .pending)
        XCTAssertEqual(refreshedFund.pendingAmount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(refreshedFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.status, .pending)

        now = try chinaDate("2026-06-24 09:30")
        await store.refreshQuotes()

        let confirmedFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "025833" })
        XCTAssertEqual(confirmedFund.status, .holding)
        XCTAssertEqual(confirmedFund.pendingAmount ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(confirmedFund.migratedShares ?? 0, 3304.692664, accuracy: 0.000001)
        XCTAssertEqual(((confirmedFund.migratedShares ?? 0) * 100).rounded() / 100, 3304.69, accuracy: 0.0001)
        XCTAssertEqual(confirmedFund.migratedCost ?? 0, 1.5130, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.amount ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 3304.692664, accuracy: 0.000001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 1.5130, accuracy: 0.0001)
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
            zdfRange: nil,
            jzNotice: nil,
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
    func testDeletingPendingNewFundRecordRemovesPendingFund() async throws {
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
            .appending(path: "fund-pulse-delete-pending-new-fund-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try await store.upsertFund(
            FundPositionDraft(
                code: "024418",
                name: "",
                positionMode: .amount,
                positionAmount: 5_000,
                positionProfit: 0,
                shares: nil,
                cost: nil,
                positionDate: "2026-06-24",
                positionTimeType: .before15,
                zdfRange: nil,
                jzNotice: nil,
                memo: ""
            )
        )

        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(pendingRecord.kind, .newFund)
        XCTAssertEqual(pendingRecord.status, .pending)

        try await store.deleteTradeRecord(id: pendingRecord.id)

        XCTAssertFalse(store.snapshot.funds.contains { $0.code == "024418" })
        XCTAssertNil(store.snapshot.tradeRecords)
        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertNil(store.snapshot.pendingConversions)
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
            zdfRange: nil,
            jzNotice: nil,
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
    func testPrematureSameDayNewFundConfirmationIsRestoredToPending() async throws {
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
    func testPendingBuyTradeAppliesBuyFeeRateLikeFundBaby() async throws {
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
            .appending(path: "fund-pulse-buy-fee-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                amount: 252.5,
                shares: nil,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                buyFeeRate: 1
            )
        )

        let pendingRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(pendingRecord.status, .pending)
        XCTAssertEqual(pendingRecord.buyFeeRate ?? 0, 1, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingTrades)
        let confirmedRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(confirmedRecord.status, .confirmed)
        XCTAssertEqual(confirmedRecord.amount ?? 0, 252.5, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.buyFeeRate ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(confirmedRecord.price ?? 0, 2.5, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 352.5, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1.7625, accuracy: 0.0001)
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
    func testPendingConversionCreatesLinkedRecordsWithoutMutatingHoldings() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-pending-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            )
        )

        let pendingConversion = try XCTUnwrap(store.snapshot.pendingConversions?.first)
        XCTAssertEqual(pendingConversion.fromCode, Self.tradeTestCode)
        XCTAssertEqual(pendingConversion.toCode, "290008")
        XCTAssertEqual(pendingConversion.shares, 100, accuracy: 0.0001)
        XCTAssertEqual(pendingConversion.acceptedDate, "2026-06-22")

        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.kind)), [.conversionOut, .conversionIn])
        XCTAssertEqual(Set(records.compactMap(\.conversionID)), [pendingConversion.id])
        XCTAssertTrue(records.allSatisfy { $0.status == .pending })

        let outRecord = try XCTUnwrap(records.first { $0.kind == .conversionOut })
        XCTAssertEqual(outRecord.id, pendingConversion.outRecordID)
        XCTAssertEqual(outRecord.code, Self.tradeTestCode)
        XCTAssertEqual(outRecord.linkedCode, "290008")
        XCTAssertEqual(outRecord.shares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(outRecord.sellFeeMode, .rate)
        XCTAssertEqual(outRecord.sellFeeValue ?? 0, 1, accuracy: 0.0001)

        let inRecord = try XCTUnwrap(records.first { $0.kind == .conversionIn })
        XCTAssertEqual(inRecord.id, pendingConversion.inRecordID)
        XCTAssertEqual(inRecord.code, "290008")
        XCTAssertEqual(inRecord.linkedCode, Self.tradeTestCode)
        XCTAssertEqual(inRecord.buyFeeRate ?? 0, 0.5, accuracy: 0.0001)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingPendingConversionRecordCancelsLinkedRecordsWithoutMutatingHoldings() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-pending-conversion-delete-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            )
        )

        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionOut })
        let conversionID = try XCTUnwrap(outRecord.conversionID)

        try await store.deleteTradeRecord(id: outRecord.id)

        XCTAssertNil(store.snapshot.pendingConversions)
        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.conversionID == conversionID } ?? false)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedCost ?? 0, 1, accuracy: 0.0001)
    }

    @MainActor
    func testPendingConversionConfirmsAfterBothNetValuesAndAppliesFees() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-confirm-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            )
        )

        XCTAssertNil(store.snapshot.pendingConversions)
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 2)

        let outRecord = try XCTUnwrap(records.first { $0.kind == .conversionOut })
        let inRecord = try XCTUnwrap(records.first { $0.kind == .conversionIn })
        XCTAssertEqual(outRecord.status, .confirmed)
        XCTAssertEqual(inRecord.status, .confirmed)
        XCTAssertEqual(outRecord.price ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(outRecord.amount ?? 0, 250, accuracy: 0.0001)
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(outRecord.feeAmount ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(inRecord.price ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(inRecord.amount ?? 0, 247.5, accuracy: 0.0001)
        XCTAssertEqual(inRecord.confirmedShares ?? 0, 197.014925, accuracy: 0.000001)
        XCTAssertEqual(((inRecord.confirmedShares ?? 0) * 100).rounded() / 100, 197.01, accuracy: 0.0001)
        XCTAssertEqual(inRecord.feeAmount ?? 0, 1.23, accuracy: 0.01)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedPrincipal ?? 0, 100, accuracy: 0.0001)

        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(targetFund.migratedShares ?? 0, 247.014925, accuracy: 0.000001)
        XCTAssertEqual(targetFund.migratedPrincipal ?? 0, 297.5, accuracy: 0.01)
        XCTAssertEqual(targetFund.migratedCost ?? 0, 1.2044, accuracy: 0.0001)
    }

    @MainActor
    func testPendingConversionDoesNotWaitForNextTradingDayAfterNetValuesConfirmed() async throws {
        let now = try chinaDate("2026-06-18 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-18", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-18", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-next-trading-day-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                tradeDate: "2026-06-18",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertNil(store.snapshot.pendingConversions)
        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionOut })
        let inRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionIn })
        XCTAssertEqual(outRecord.status, .confirmed)
        XCTAssertEqual(inRecord.status, .confirmed)
        let sourceAfterExecution = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetAfterExecution = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceAfterExecution.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(targetAfterExecution.migratedShares ?? 0, 247.014925, accuracy: 0.000001)
    }

    @MainActor
    func testFullConversionOutDoesNotBecomePendingNewFund() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-full-conversion-out-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let createdAt = try chinaDate("2026-06-22 15:00")
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "initial-source",
                        kind: .newFund,
                        status: .confirmed,
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        mode: .share,
                        amount: 100,
                        shares: 100,
                        confirmedShares: 100,
                        price: 1,
                        tradeDate: "2026-06-22",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-06-22",
                        createdAt: createdAt,
                        confirmedAt: createdAt,
                        failureReason: nil
                    )
                ]
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
                tradeTimeType: .before15
            )
        )

        XCTAssertNil(store.snapshot.pendingConversions)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertFalse(records.contains { $0.status == .pending && $0.kind == .newFund && $0.code == Self.tradeTestCode })
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertTrue(PendingFundDisplayRules.isClosedZeroPosition(sourceFund, tradeRecords: records))
    }

    @MainActor
    func testFullConversionAllowsDisplayedShareRoundingAboveStoredShares() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-rounded-full-conversion-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 2_615.35765, cost: 1),
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
                shares: 2_615.36,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertNil(store.snapshot.pendingConversions)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionOut })
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 2_615.36, accuracy: 0.0001)
    }

    @MainActor
    func testPendingConversionWaitsWhenEitherConfirmedNetValueIsMissing() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-missing-nav-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                tradeTimeType: .before15
            )
        )

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        XCTAssertEqual(store.snapshot.tradeRecords?.filter { $0.status == .pending }.count, 2)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
    }

    @MainActor
    func testConversionToNewFundConfirmsIntoHoldingWhenNetValuesAreAvailable() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "024480": ("永赢先进制造智选混合发起A", "2026-06-22", 1.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-new-target-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "024480",
                toName: "永赢先进制造智选混合发起A",
                shares: 60,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024480" })
        XCTAssertEqual(targetFund.status, .holding)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedPrincipal ?? 0, 150, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingConversions)
    }

    @MainActor
    func testPendingConversionToNewFundCountsAsSinglePendingItem() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-pending-count-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "024480",
                toName: "永赢先进制造智选混合发起A",
                shares: 60,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        XCTAssertEqual(store.snapshot.pendingCount, 1)
    }

    @MainActor
    func testPendingConversionWithInsufficientSharesKeepsLinkedRecordsPendingWithFailureReason() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-insufficient-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "pending-conversion-1"
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 80, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil,
                pendingConversions: [
                    FundPendingConversion(
                        id: conversionID,
                        outRecordID: "conversion-out",
                        inRecordID: "conversion-in",
                        fromCode: Self.tradeTestCode,
                        toCode: "290008",
                        toName: "泰信发展主题混合",
                        shares: 100,
                        tradeDate: "2026-06-22",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-06-22",
                        createdAt: createdAt
                    )
                ],
                tradeRecords: [
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .pending, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: nil, shares: 100, confirmedShares: nil, price: nil, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: nil, failureReason: nil, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合"),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .pending, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: nil, shares: nil, confirmedShares: nil, price: nil, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: nil, failureReason: nil, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        let pendingConversion = try XCTUnwrap(store.snapshot.pendingConversions?.first)
        XCTAssertEqual(pendingConversion.failureReason, "可转换份额不足")
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.filter { $0.status == .pending }.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.failureReason == "可转换份额不足" })

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingOneConversionRecordDeletesLinkedLegAndRecalculatesBothFunds() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-delete-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "conversion-1"
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 247.01, cost: 1.2044)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "source-new", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 200, shares: 200, confirmedShares: 200, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "target-new", kind: .newFund, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .share, amount: 50, shares: 50, confirmedShares: 50, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, sellFeeMode: .rate, sellFeeValue: 1, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合", feeAmount: 2.5),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 247.5, shares: nil, confirmedShares: 197.01, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, buyFeeRate: 0.5, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName, feeAmount: 1.23)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteTradeRecord(id: "conversion-out")

        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.conversionID == conversionID } ?? true)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedCost ?? 0, 1, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingConfirmedConversionRestoresLegacySourceWithoutCreatingInitialRecord() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            "024424": ("东方阿尔法科技优选混合发起C", "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-delete-legacy-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "legacy-conversion-1"
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
                        code: "024424",
                        name: "东方阿尔法科技优选混合发起C",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 2,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "legacy-remaining", shares: 100, cost: 2, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    ),
                    FundPosition(
                        code: "290008",
                        name: "泰信发展主题混合",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1.25,
                        migratedPrincipal: 250,
                        incomeStartDate: "2026-06-22",
                        positionMode: .amount,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "conversion-target", shares: 200, cost: 1.25, incomeStartDate: "2026-06-22", positionDate: "2026-06-22", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: "024424", name: "东方阿尔法科技优选混合发起C", mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合"),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 250, shares: nil, confirmedShares: 200, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: "024424", linkedName: "东方阿尔法科技优选混合发起C")
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteTradeRecord(id: "conversion-out")

        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.conversionID == conversionID } ?? false)
        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.code == "024424" && $0.kind == .newFund } ?? false)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024424" })
        XCTAssertEqual(sourceFund.status, .holding)
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedPrincipal ?? 0, 400, accuracy: 0.0001)

        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(targetFund.status, .pending)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 0, accuracy: 0.0001)
    }

    @MainActor
    func testEditingConfirmedConversionRecalculatesBothFunds() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-edit-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "conversion-1"
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 250, cost: 1.2)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "source-new", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 200, shares: 200, confirmedShares: 200, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "target-new", kind: .newFund, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .share, amount: 50, shares: 50, confirmedShares: 50, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合"),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 250, shares: nil, confirmedShares: 200, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editConversion(
            id: conversionID,
            with: FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 80,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertNil(store.snapshot.pendingConversions)
        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "conversion-out" })
        let inRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "conversion-in" })
        XCTAssertEqual(outRecord.status, .confirmed)
        XCTAssertEqual(inRecord.status, .confirmed)
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(outRecord.amount ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(inRecord.confirmedShares ?? 0, 160, accuracy: 0.0001)
        XCTAssertEqual(inRecord.amount ?? 0, 200, accuracy: 0.0001)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 120, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 210, accuracy: 0.0001)
    }

    @MainActor
    func testConversionRejectsInvalidDrafts() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-invalid-conversion-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
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
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        await XCTAssertThrowsErrorAsync {
            try await store.convertFundPosition(
                FundConversionDraft(fromCode: Self.tradeTestCode, toCode: Self.tradeTestCode, shares: 10, tradeDate: "2026-06-22", tradeTimeType: .before15)
            )
        } errorHandler: { error in
            XCTAssertEqual(error as? PortfolioStoreError, .invalidConversionTarget)
        }

        await XCTAssertThrowsErrorAsync {
            try await store.convertFundPosition(
                FundConversionDraft(fromCode: Self.tradeTestCode, toCode: "290008", shares: 0, tradeDate: "2026-06-22", tradeTimeType: .before15)
            )
        } errorHandler: { error in
            XCTAssertEqual(error as? PortfolioStoreError, .invalidPosition)
        }

        await XCTAssertThrowsErrorAsync {
            try await store.convertFundPosition(
                FundConversionDraft(fromCode: Self.tradeTestCode, toCode: "290008", shares: 120, tradeDate: "2026-06-22", tradeTimeType: .before15)
            )
        } errorHandler: { error in
            XCTAssertEqual(error as? PortfolioStoreError, .insufficientShares)
        }
    }

    func testConversionEditorPrimaryActionRequiresConfirmationBeforeSaving() {
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: false, isSaving: false, isConfirming: false),
            .ignore
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: true, isSaving: true, isConfirming: false),
            .ignore
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: true, isSaving: false, isConfirming: false),
            .showConfirmation
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: true, isSaving: false, isConfirming: true),
            .save
        )
    }

    func testConversionEditorPresentationUsesConfirmationCopy() {
        XCTAssertEqual(
            FundConversionEditorPresentation.headerTitle(isEditing: false, isConfirming: false),
            "基金转换"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: false, isConfirming: false, isSaving: false),
            "转换确认"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.headerTitle(isEditing: false, isConfirming: true),
            "转换确认"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.headerSubtitle(isEditing: false, isConfirming: true),
            "确认后写入两条转换记录，净值更新后自动完成"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.cancelTitle(isConfirming: true),
            "返回修改"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: false, isConfirming: true, isSaving: false),
            "确认转换"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: true, isConfirming: false, isSaving: false),
            "保存确认"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: true, isConfirming: true, isSaving: false),
            "确认保存"
        )
    }

    func testConversionConfirmationSummaryIncludesBothFundsFeesAndAcceptedDate() {
        let summary = FundConversionConfirmationSummary.make(
            sourceFund: conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
            targetCode: "290008",
            targetName: "泰信发展主题混合",
            shares: 100,
            sellFeeMode: .rate,
            sellFeeValue: 1,
            buyFeeRate: 0.5,
            tradeDate: "2026-06-22",
            tradeTimeType: .after15
        )
        let rows = Dictionary(uniqueKeysWithValues: summary.rows.map { ($0.title, $0.value) })

        XCTAssertEqual(rows["转出基金"], "\(Self.tradeTestName) \(Self.tradeTestCode)")
        XCTAssertEqual(rows["转入基金"], "泰信发展主题混合 290008")
        XCTAssertEqual(rows["转出份额"], "100.00 份")
        XCTAssertEqual(rows["转出费率/费用"], "1.00%")
        XCTAssertEqual(rows["转入费率"], "0.50%")
        XCTAssertEqual(rows["交易日期"], "2026-06-22")
        XCTAssertEqual(rows["交易时段"], PositionTimeType.after15.title)
        XCTAssertEqual(rows["确认净值日"], "2026-06-23")
        XCTAssertEqual(summary.footnote, "*净值未取到时会先进入待确认，净值更新后自动完成转换")
    }

    func testConversionAmountProjectionUsesEstimateUntilBothNetValuesConfirmed() throws {
        let projection = try XCTUnwrap(
            FundConversionAmountProjection.make(
                sourceFund: conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                targetFund: nil,
                sourceQuote: FundQuote(
                    code: Self.tradeTestCode,
                    name: Self.tradeTestName,
                    netValue: 1,
                    estimatedNetValue: 1.05,
                    growthRate: 5,
                    estimateTime: "2026-06-26 14:30",
                    netValueDate: "2026-06-25"
                ),
                targetQuote: FundQuote(
                    code: "290008",
                    name: "泰信发展主题混合",
                    netValue: 2,
                    estimatedNetValue: 1.9,
                    growthRate: -5,
                    estimateTime: "2026-06-26 14:30",
                    netValueDate: "2026-06-25"
                ),
                sourceReferenceNetValue: nil,
                sourceReferenceNetValueDate: nil,
                targetReferenceNetValue: nil,
                targetReferenceNetValueDate: nil,
                acceptedDate: "2026-06-26",
                shares: 100,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertFalse(projection.isFullyConfirmed)
        XCTAssertEqual(projection.sourcePrice.value, 1.05, accuracy: 0.0001)
        XCTAssertFalse(projection.sourcePrice.isConfirmed)
        XCTAssertEqual(projection.targetPrice.value, 1.9, accuracy: 0.0001)
        XCTAssertFalse(projection.targetPrice.isConfirmed)
        XCTAssertEqual(projection.grossAmount, 105, accuracy: 0.0001)
        XCTAssertEqual(projection.sellFee, 1.05, accuracy: 0.0001)
        XCTAssertEqual(projection.transferAmount, 103.95, accuracy: 0.0001)
        XCTAssertEqual(projection.buyFee, 0.52, accuracy: 0.01)
        XCTAssertEqual(projection.targetShares, 54.44, accuracy: 0.01)
    }

    func testConversionAmountProjectionUsesConfirmedReferenceValuesWhenUpdated() throws {
        let projection = try XCTUnwrap(
            FundConversionAmountProjection.make(
                sourceFund: conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                targetFund: conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1),
                sourceQuote: nil,
                targetQuote: nil,
                sourceReferenceNetValue: 2.5,
                sourceReferenceNetValueDate: "2026-06-22",
                targetReferenceNetValue: 1.25,
                targetReferenceNetValueDate: "2026-06-22",
                acceptedDate: "2026-06-22",
                shares: 100,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertTrue(projection.isFullyConfirmed)
        XCTAssertEqual(projection.grossAmount, 250, accuracy: 0.0001)
        XCTAssertEqual(projection.transferAmount, 247.5, accuracy: 0.0001)
        XCTAssertEqual(projection.buyFee, 1.23, accuracy: 0.01)
        XCTAssertEqual(projection.targetShares, 197.01, accuracy: 0.01)
    }

    @MainActor
    func testEditingConfirmedSellTradeReappliesFIFOLots() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = tradeQuoteService(date: "2026-06-22", netValue: 2.5)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-sell-fifo-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let newRecordDate = try chinaDate("2026-06-17 15:00")
        let buyRecordDate = try chinaDate("2026-06-21 15:00")
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
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 150,
                        migratedCost: 2,
                        migratedPrincipal: 300,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "new-record", shares: 50, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15),
                            FundPositionLot(id: "buy-record", shares: 100, cost: 2.5, incomeStartDate: "2026-06-21", positionDate: "2026-06-21", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "new-record", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 100, shares: 100, confirmedShares: 100, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: newRecordDate, confirmedAt: newRecordDate, failureReason: nil),
                    FundTradeRecord(id: "buy-record", kind: .buy, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .amount, amount: 250, shares: nil, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-21", tradeTimeType: .before15, acceptedDate: "2026-06-21", createdAt: buyRecordDate, confirmedAt: buyRecordDate, failureReason: nil),
                    FundTradeRecord(id: "sell-record", kind: .sell, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: nil, shares: 50, confirmedShares: 50, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: sellRecordDate, confirmedAt: sellRecordDate, failureReason: nil, sellFeeMode: .rate, sellFeeValue: 0.5)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editTradeRecord(
            id: "sell-record",
            with: FundTradeDraft(
                action: .sell,
                code: Self.tradeTestCode,
                mode: .share,
                amount: nil,
                shares: 150,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .amount,
                sellFeeValue: 2
            )
        )

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "sell-record" })
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.confirmedShares ?? 0, 150, accuracy: 0.0001)
        XCTAssertEqual(record.sellFeeMode, .amount)
        XCTAssertEqual(record.sellFeeValue ?? 0, 2, accuracy: 0.0001)

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(fund.migratedShares ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 125, accuracy: 0.0001)
        XCTAssertEqual(fund.lots?.count, 1)
        XCTAssertEqual(fund.lots?.first?.id, "buy-record")
        XCTAssertEqual(fund.lots?.first?.shares ?? 0, 50, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingTrades)
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
    func testEditingFundResetsHistoryAndUsesNewBaselineForFutureTrades() async throws {
        let now = try chinaDate("2026-06-24 09:30")
        let service = tradeQuoteService(date: "2026-06-23", netValue: 2.5)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-fund-reset-baseline-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let firstRecordDate = try chinaDate("2026-06-17 15:00")
        let oldBuyDate = try chinaDate("2026-06-20 15:00")
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
                        dateText: "06-20 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 2,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-20",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "old-new", shares: 50, cost: 1, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15),
                            FundPositionLot(id: "old-buy", shares: 50, cost: 3, incomeStartDate: "2026-06-20", positionDate: "2026-06-20", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "old-new", kind: .newFund, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .share, amount: 50, shares: 50, confirmedShares: 50, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: firstRecordDate, confirmedAt: firstRecordDate, failureReason: nil),
                    FundTradeRecord(id: "old-buy", kind: .buy, status: .confirmed, code: "026210", name: "平安科技精选混合发起式A", mode: .amount, amount: 150, shares: nil, confirmedShares: 50, price: 3, tradeDate: "2026-06-20", tradeTimeType: .before15, acceptedDate: "2026-06-20", createdAt: oldBuyDate, confirmedAt: oldBuyDate, failureReason: nil)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.upsertFund(
            FundPositionDraft(
                code: "026210",
                name: "平安科技精选混合发起式A",
                positionMode: .share,
                positionAmount: nil,
                positionProfit: 0,
                shares: 200,
                cost: 2,
                positionDate: "2026-06-22",
                positionTimeType: .before15,
                zdfRange: nil,
                jzNotice: nil,
                memo: ""
            ),
            replacing: "026210"
        )

        var records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records.contains { $0.id == "old-new" || $0.id == "old-buy" })

        let resetBaseline = try XCTUnwrap(records.first { $0.code == "026210" && $0.kind == .newFund })
        XCTAssertEqual(resetBaseline.tradeDate, "2026-06-22")
        XCTAssertEqual(resetBaseline.confirmedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(resetBaseline.price ?? 0, 2, accuracy: 0.0001)

        try await store.adjustFundPosition(
            FundTradeDraft(
                action: .buy,
                code: "026210",
                mode: .amount,
                amount: 250,
                shares: nil,
                tradeDate: "2026-06-23",
                tradeTimeType: .before15
            )
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "026210" })
        XCTAssertEqual(fund.migratedShares ?? 0, 300, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 650, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedCost ?? 0, 2.1667, accuracy: 0.0001)

        records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 2)
        XCTAssertFalse(records.contains { $0.id == "old-new" || $0.id == "old-buy" })
        XCTAssertEqual(records.filter { $0.kind == .newFund }.count, 1)
        XCTAssertEqual(records.filter { $0.kind == .buy }.count, 1)

        let latestBaseline = try XCTUnwrap(records
            .filter { $0.code == "026210" && $0.kind == .newFund }
            .sorted { $0.createdAt < $1.createdAt }
            .last)
        XCTAssertEqual(latestBaseline.tradeDate, "2026-06-22")
        XCTAssertEqual(latestBaseline.confirmedShares ?? 0, 200, accuracy: 0.0001)
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
            zdfRange: nil,
            jzNotice: nil,
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
                zdfRange: nil,
                jzNotice: nil,
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

    func testTradingCalendarAcceptedTradeDateSkipsDragonBoatHoliday() {
        XCTAssertEqual(
            TradingCalendar.acceptedTradeDate(positionDate: "2026-06-18", timeType: .before15),
            "2026-06-18"
        )
        XCTAssertEqual(
            TradingCalendar.acceptedTradeDate(positionDate: "2026-06-18", timeType: .after15),
            "2026-06-22"
        )
        XCTAssertEqual(
            TradingCalendar.nextFundTradingDate(after: "2026-06-18"),
            "2026-06-22"
        )
    }

    func testMarketSessionStateUsesTradingHoursAfterDragonBoatHoliday() throws {
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 10:35")), .open)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 12:00")), .middayBreak)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 15:01")), .closed)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-21 10:35")), .closed)
    }

    func testOperationReminderDatesOnlyUseMarketOpenTradingDays() throws {
        XCTAssertEqual(
            TradingCalendar.nextMarketOpenReminderDates(
                minutes: 14 * 60 + 30,
                from: try chinaDate("2026-06-22 15:01"),
                limit: 2
            ).map(DateOnlyFormatter.string),
            ["2026-06-23", "2026-06-24"]
        )
        XCTAssertEqual(
            TradingCalendar.nextMarketOpenReminderDates(
                minutes: 15 * 60 + 1,
                from: try chinaDate("2026-06-22 10:00"),
                limit: 2
            ).count,
            0
        )
        XCTAssertEqual(
            TradingCalendar.nextMarketOpenReminderDates(
                minutes: 12 * 60,
                from: try chinaDate("2026-06-22 10:00"),
                limit: 2
            ).count,
            0
        )
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

    private func thresholdReminderSnapshot(funds: [FundPosition]) -> PortfolioSnapshot {
        PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: funds,
            migration: nil
        )
    }

    private func thresholdReminderFund(
        code: String,
        todayRate: Double,
        currentAmount: Double? = nil,
        shares: Double? = nil,
        zdfRange: Double? = nil,
        jzNotice: Double? = nil
    ) -> FundPosition {
        FundPosition(
            code: code,
            name: "测试基金\(code)",
            dateText: "06-24 13:30",
            todayIncome: 0,
            todayRate: todayRate,
            holdingRate: nil,
            currentAmount: currentAmount,
            status: .holding,
            isUpdated: false,
            migratedShares: shares,
            zdfRange: zdfRange,
            jzNotice: jzNotice
        )
    }

    private struct CoreQuoteMock {
        var code: String
        var name: String
        var netValueDate: String
        var netValue: Double
        var estimatedNetValue: Double
        var growthRate: Double
        var officialGrowthRate: Double?
        var estimateTime: String
    }

    private static func coreQuoteResponse(
        code: String,
        name: String,
        netValueDate: String,
        netValue: Double,
        estimatedNetValue: Double? = nil,
        growthRate: Double = 0,
        officialGrowthRate: Double? = nil,
        estimateTime: String = ""
    ) -> String {
        coreQuoteResponse([
            CoreQuoteMock(
                code: code,
                name: name,
                netValueDate: netValueDate,
                netValue: netValue,
                estimatedNetValue: estimatedNetValue ?? netValue,
                growthRate: growthRate,
                officialGrowthRate: officialGrowthRate,
                estimateTime: estimateTime
            )
        ])
    }

    private static func coreQuoteResponse(_ quotes: [CoreQuoteMock]) -> String {
        let rows = quotes.map { quote in
            let netValueText = String(format: "%.4f", quote.netValue)
            let estimatedValueText = String(format: "%.4f", quote.estimatedNetValue)
            let growthRateText = String(format: "%.2f", quote.growthRate)
            let officialGrowthRateText = String(format: "%.2f", quote.officialGrowthRate ?? quote.growthRate)
            return """
            {"NAV":"--","DWJZ":\(netValueText),"GZTIME":"\(quote.estimateTime)","PTYPE":"F","SHORTNAME":"\(quote.name)","QDCODE":"\(quote.code)","FCODE":"\(quote.code)","RZDF":\(officialGrowthRateText),"JZRQ":"--","FSRQ":"\(quote.netValueDate)","GSZZL":\(growthRateText),"GSZ":\(estimatedValueText)}
            """
        }
        .joined(separator: ",")
        return """
        {"data":[\(rows)],"errorCode":0,"success":true,"totalCount":\(quotes.count)}
        """
    }

    private func quoteServiceWithMockResponses(_ responses: [String: String]) -> FundQuoteService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return FundQuoteService(session: URLSession(configuration: configuration))
    }

    private func tradeQuoteService(
        code: String = FundPulseCoreTests.tradeTestCode,
        name: String = FundPulseCoreTests.tradeTestName,
        date: String,
        netValue: Double
    ) -> FundQuoteService {
        let valueText = String(format: "%.4f", netValue)
        let responses = [
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: code,
                name: name,
                netValueDate: date,
                netValue: netValue,
                estimatedNetValue: netValue,
                growthRate: 0,
                estimateTime: "\(date) 15:00"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(code)&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>\(date)</td><td class='tor bold'>\(valueText)</td><td>\(valueText)</td><td class='red'>0.00%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """,
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(code)&page=1&per=1&sdate=\(date)&edate=\(date)": """
            var apidata={ content:"<table><tbody><tr><td>\(date)</td><td class='tor bold'>\(valueText)</td><td>\(valueText)</td><td class='red'>0.00%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ]
        return quoteServiceWithMockResponses(responses)
    }

    private func multiTradeQuoteService(
        _ quotes: [String: (name: String, date: String, netValue: Double)]
    ) -> FundQuoteService {
        var responses: [String: String] = [:]
        let coreRows = quotes
            .sorted { $0.key < $1.key }
            .map { code, quote in
                let valueText = String(format: "%.4f", quote.netValue)
                return """
                {"NAV":"--","DWJZ":\(valueText),"GZTIME":"\(quote.date) 15:00","PTYPE":"F","SHORTNAME":"\(quote.name)","QDCODE":"\(code)","FCODE":"\(code)","RZDF":0.00,"JZRQ":"--","FSRQ":"\(quote.date)","GSZZL":0.00,"GSZ":\(valueText)}
                """
            }
            .joined(separator: ",")
        responses["https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew"] = """
        {"data":[\(coreRows)],"errorCode":0,"success":true,"totalCount":\(quotes.count)}
        """

        for (code, quote) in quotes {
            let valueText = String(format: "%.4f", quote.netValue)
            responses["https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(code)&page=1&per=1"] = """
            var apidata={ content:"<table><tbody><tr><td>\(quote.date)</td><td class='tor bold'>\(valueText)</td><td>\(valueText)</td><td class='red'>0.00%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
            responses["https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(code)&page=1&per=1&sdate=\(quote.date)&edate=\(quote.date)"] = """
            var apidata={ content:"<table><tbody><tr><td>\(quote.date)</td><td class='tor bold'>\(valueText)</td><td>\(valueText)</td><td class='red'>0.00%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        }

        return quoteServiceWithMockResponses(responses)
    }

    private func conversionFund(
        code: String,
        name: String,
        shares: Double,
        cost: Double
    ) -> FundPosition {
        FundPosition(
            code: code,
            name: name,
            dateText: "06-17 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: nil,
            status: shares > 0 ? .holding : .pending,
            isUpdated: true,
            migratedShares: shares,
            migratedCost: shares > 0 ? cost : 0,
            migratedPrincipal: shares * cost,
            incomeStartDate: "2026-06-17",
            positionMode: .share,
            positionDate: "2026-06-17",
            positionTimeType: .before15,
            lots: shares > 0
                ? [
                    FundPositionLot(
                        id: "\(code)-seed",
                        shares: shares,
                        cost: cost,
                        incomeStartDate: "2026-06-17",
                        positionDate: "2026-06-17",
                        positionTimeType: .before15
                    )
                ]
                : []
        )
    }

    func testIntradayRateHistoryRecordsEveryOpenRefresh() throws {
        let firstNow = try chinaDate("2026-06-24 09:35")
        let secondNow = try chinaDate("2026-06-24 09:36")
        let snapshot = PortfolioSnapshot(
            updateTime: firstNow,
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
                    isUpdated: false
                )
            ],
            migration: nil
        )
        let firstQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.03,
            growthRate: 1.25,
            estimateTime: "2026-06-24 09:35",
            netValueDate: "2026-06-23"
        )
        let secondQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.04,
            growthRate: 1.40,
            estimateTime: "2026-06-24 09:36",
            netValueDate: "2026-06-23"
        )

        let first = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: snapshot,
            quotes: ["026210": firstQuote],
            now: firstNow
        )
        let second = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: first,
            quotes: ["026210": secondQuote],
            now: secondNow
        )

        let points = try XCTUnwrap(second.funds[0].intradayRateHistory)
        XCTAssertEqual(second.funds[0].intradayRateDate, "2026-06-24")
        XCTAssertEqual(points.map(\.rate), [1.25, 1.40])
        XCTAssertEqual(points.map(\.estimateTime), ["2026-06-24 09:35", "2026-06-24 09:36"])
    }

    func testIntradayRateHistoryDeduplicatesStoredEstimateTimes() throws {
        let duplicateTimestamp = Int64(try chinaDate("2026-06-24 11:11").timeIntervalSince1970 * 1000)
        let duplicateEarlier = FundIntradayRatePoint(
            timestamp: duplicateTimestamp,
            rate: -4.46,
            estimateTime: "2026-06-24 11:11"
        )
        let duplicateLater = FundIntradayRatePoint(
            timestamp: duplicateTimestamp,
            rate: -4.65,
            estimateTime: "2026-06-24 11:11"
        )
        let snapshot = PortfolioSnapshot(
            updateTime: try chinaDate("2026-06-24 13:30"),
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
                    dateText: "06-24 13:30",
                    todayIncome: 0,
                    todayRate: -4.65,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    intradayRateDate: "2026-06-24",
                    intradayRateHistory: [duplicateEarlier, duplicateLater]
                )
            ],
            migration: nil
        )
        let quote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 1.9,
            growthRate: -5.16,
            estimateTime: "2026-06-24 13:32",
            netValueDate: "2026-06-23"
        )

        let result = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: snapshot,
            quotes: ["026210": quote],
            now: try chinaDate("2026-06-24 13:32")
        )

        let points = try XCTUnwrap(result.funds[0].intradayRateHistory)
        XCTAssertEqual(points.map(\.estimateTime), ["2026-06-24 11:11", "2026-06-24 13:32"])
        XCTAssertEqual(points.map(\.rate), [-4.65, -5.16])
    }

    func testIntradayRateHistoryRecordsLatestEstimateOutsideOpenAndRestartsNextTradingDay() throws {
        let sameDayPoint = FundIntradayRatePoint(
            timestamp: Int64(try chinaDate("2026-06-24 10:58").timeIntervalSince1970 * 1000),
            rate: 1.12,
            estimateTime: "2026-06-24 10:58"
        )
        let snapshot = PortfolioSnapshot(
            updateTime: try chinaDate("2026-06-24 10:58"),
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
                    dateText: "06-24 10:58",
                    todayIncome: 0,
                    todayRate: 1.12,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    intradayRateDate: "2026-06-24",
                    intradayRateHistory: [sameDayPoint]
                )
            ],
            migration: nil
        )
        let sameDayQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.04,
            growthRate: 1.65,
            estimateTime: "2026-06-24 11:30",
            netValueDate: "2026-06-23"
        )
        let nextDayQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.05,
            growthRate: 2.00,
            estimateTime: "2026-06-25 09:31",
            netValueDate: "2026-06-24"
        )

        let middayBreak = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: snapshot,
            quotes: ["026210": sameDayQuote],
            now: try chinaDate("2026-06-24 12:00")
        )
        let middayPoints = try XCTUnwrap(middayBreak.funds[0].intradayRateHistory)
        XCTAssertEqual(middayPoints.map(\.rate), [1.12, 1.65])
        XCTAssertEqual(
            middayPoints.last?.timestamp,
            Int64(try chinaDate("2026-06-24 11:30").timeIntervalSince1970 * 1000)
        )

        let afterClose = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: middayBreak,
            quotes: ["026210": sameDayQuote],
            now: try chinaDate("2026-06-24 15:10")
        )
        XCTAssertEqual(afterClose.funds[0].intradayRateHistory?.count, 2)

        let beforeOpenNextDay = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: afterClose,
            quotes: ["026210": nextDayQuote],
            now: try chinaDate("2026-06-25 08:50")
        )
        XCTAssertEqual(beforeOpenNextDay.funds[0].intradayRateDate, "2026-06-25")
        XCTAssertTrue(beforeOpenNextDay.funds[0].intradayRateHistory?.isEmpty ?? true)

        let openNextDay = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: beforeOpenNextDay,
            quotes: ["026210": nextDayQuote],
            now: try chinaDate("2026-06-25 09:31")
        )
        let points = try XCTUnwrap(openNextDay.funds[0].intradayRateHistory)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].rate, 2.00)
        XCTAssertEqual(openNextDay.funds[0].intradayRateDate, "2026-06-25")
    }

    func testIntradayRateHistoryIgnoresStaleEstimateDuringMarketOpen() throws {
        let now = try chinaDate("2026-06-24 10:00")
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
                    isUpdated: false
                )
            ],
            migration: nil
        )
        let staleQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.01,
            growthRate: 0.50,
            estimateTime: "2026-06-23 14:30",
            netValueDate: "2026-06-23"
        )

        let result = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: snapshot,
            quotes: ["026210": staleQuote],
            now: now
        )

        XCTAssertEqual(result.funds[0].intradayRateDate, "2026-06-24")
        XCTAssertTrue(result.funds[0].intradayRateHistory?.isEmpty ?? true)
    }

    private func chinaDate(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: value))
    }

    private func timestamp(_ dateText: String) throws -> Int64 {
        let date = try chinaDate("\(dateText) 00:00")
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

#if canImport(AppKit)
private func rgbHex(_ color: NSColor) throws -> String {
    let converted = try XCTUnwrap(color.usingColorSpace(.sRGB))
    let red = Int(round(converted.redComponent * 255))
    let green = Int(round(converted.greenComponent * 255))
    let blue = Int(round(converted.blueComponent * 255))
    return String(format: "#%02X%02X%02X", red, green, blue)
}
#endif

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line,
    errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
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

private extension Double {
    var roundedMoneyForTest: Double {
        (self * 100).rounded() / 100
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
