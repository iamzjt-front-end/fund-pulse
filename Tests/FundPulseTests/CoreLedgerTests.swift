import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    func testFundCodeFormatterDisplaysCodeWithoutHashPrefix() {
        XCTAssertEqual(FundCodeFormatter.display("024418"), "024418")
        XCTAssertEqual(FundCodeFormatter.display("#024418"), "024418")
        XCTAssertEqual(FundCodeFormatter.display("  #024418  "), "024418")
        XCTAssertEqual(FundCodeFormatter.display(""), "--")
    }

    @MainActor
    func testStalePendingBuyDoesNotDuplicateExistingConfirmedInitialRecordOnRefresh() async throws {
        let now = try chinaDate("2026-07-08 09:30")
        let service = tradeQuoteService(
            code: "013284",
            name: "上银价值增长3个月持有期混合A",
            date: "2026-07-07",
            netValue: 1.3465
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-stale-pending-buy-dedupe-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-07-07 14:30")
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 20_000,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 1,
                funds: [
                    FundPosition(
                        code: "013284",
                        name: "上银价值增长3个月持有期混合A",
                        dateText: "07-07 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: 0,
                        currentAmount: 20_000,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 14_853.323431,
                        migratedCost: 1.3465,
                        migratedPrincipal: 20_000,
                        incomeStartDate: "2026-07-07",
                        positionMode: .amount,
                        positionDate: "2026-07-07",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(
                                id: "initial",
                                shares: 14_853.323431,
                                cost: 1.3465,
                                principal: 20_000,
                                incomeStartDate: "2026-07-07",
                                positionDate: "2026-07-07",
                                positionTimeType: .before15
                            )
                        ]
                    )
                ],
                migration: nil,
                pendingTrades: [
                    FundPendingTrade(
                        id: "stale-pending-buy",
                        recordID: "missing-pending-record",
                        action: .buy,
                        code: "013284",
                        mode: .amount,
                        amount: 20_000,
                        shares: nil,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        createdAt: createdAt
                    )
                ],
                tradeRecords: [
                    FundTradeRecord(
                        id: "initial-record",
                        kind: .newFund,
                        status: .confirmed,
                        code: "013284",
                        name: "上银价值增长3个月持有期混合A",
                        mode: .amount,
                        amount: 20_000,
                        shares: nil,
                        confirmedShares: 14_853.323431,
                        price: 1.3465,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-07",
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

        let records = store.snapshot.tradeRecords?.filter { $0.code == "013284" } ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .newFund)
        XCTAssertNil(store.snapshot.pendingTrades)
    }

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

    func testDefaultAutoRefreshIntervalsUseMarketOpenAndClosedDefaults() throws {
        let settings = AppSettings()

        XCTAssertEqual(settings.autoRefreshInterval, .fiveSeconds)
        XCTAssertEqual(settings.marketClosedAutoRefreshInterval, .tenMinutes)
        XCTAssertEqual(settings.autoRefreshInterval.seconds, 5)
        XCTAssertEqual(settings.marketClosedAutoRefreshInterval.seconds, 10 * 60)
        XCTAssertEqual(settings.effectiveAutoRefreshInterval(for: .open), .fiveSeconds)
        XCTAssertEqual(settings.effectiveAutoRefreshInterval(for: .middayBreak), .tenMinutes)
        XCTAssertEqual(settings.effectiveAutoRefreshInterval(for: .closed), .tenMinutes)
        XCTAssertEqual(settings.effectiveAutoRefreshInterval(now: try chinaDate("2026-06-22 10:35")), .fiveSeconds)
        XCTAssertEqual(settings.effectiveAutoRefreshInterval(now: try chinaDate("2026-06-22 12:00")), .tenMinutes)
        XCTAssertEqual(settings.effectiveAutoRefreshInterval(now: try chinaDate("2026-06-22 15:01")), .tenMinutes)
        XCTAssertEqual(AutoRefreshInterval.twoSeconds.seconds, 2)
        XCTAssertEqual(AutoRefreshInterval.fiveSeconds.seconds, 5)
        XCTAssertEqual(AutoRefreshInterval.tenMinutes.seconds, 10 * 60)
        XCTAssertEqual(AutoRefreshInterval.thirtyMinutes.seconds, 30 * 60)
        XCTAssertEqual(
            AutoRefreshInterval.marketOpenIntervals,
            [.twoSeconds, .fiveSeconds, .tenSeconds, .thirtySeconds, .oneMinute, .threeMinutes, .fiveMinutes]
        )
        XCTAssertEqual(
            AutoRefreshInterval.marketClosedIntervals,
            [.oneMinute, .threeMinutes, .fiveMinutes, .tenMinutes, .thirtyMinutes]
        )
        XCTAssertEqual(Array(AutoRefreshInterval.allCases.prefix(3)), [.twoSeconds, .fiveSeconds, .tenSeconds])
        XCTAssertEqual(AutoRefreshInterval.interval(atSliderIndex: 0), .twoSeconds)
        XCTAssertEqual(AutoRefreshInterval.interval(atSliderIndex: 1), .fiveSeconds)
        XCTAssertEqual(AutoRefreshInterval.interval(atSliderIndex: 2), .tenSeconds)
        XCTAssertEqual(
            AutoRefreshInterval.interval(atSliderIndex: 0, in: AutoRefreshInterval.marketClosedIntervals),
            .oneMinute
        )
        XCTAssertEqual(
            AutoRefreshInterval.interval(atSliderIndex: 4, in: AutoRefreshInterval.marketClosedIntervals),
            .thirtyMinutes
        )
        XCTAssertEqual(
            AppSettings(autoRefreshInterval: .thirtyMinutes).autoRefreshInterval,
            .fiveSeconds
        )
        XCTAssertEqual(
            AppSettings(marketClosedAutoRefreshInterval: .twoSeconds).marketClosedAutoRefreshInterval,
            .tenMinutes
        )
        XCTAssertEqual(settings.menuBarDisplayMode, .color)
        XCTAssertTrue(settings.menuBarDisplayMode.usesGrowthColor)
        XCTAssertEqual(MenuBarDisplayMode.allCases.map(\.title), ["红绿", "单色"])
        XCTAssertEqual(settings.menuBarContentMode, .amount)
        XCTAssertEqual(MenuBarContentMode.allCases.map(\.title), ["金额", "百分比", "都显示", "都不显示"])
        XCTAssertEqual(settings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(settings.operationReminderEnabled)
        XCTAssertEqual(settings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(settings.operationReminderTimeText, "14:30")
        XCTAssertEqual(settings.thresholdReminderInterval, .thirtyMinutes)
        XCTAssertEqual(settings.thresholdReminderInterval.seconds, 30 * 60)
        XCTAssertFalse(settings.dailyGrowthReminderEnabled)
        XCTAssertTrue(settings.dailyGrowthRiseTiers.isEmpty)
        XCTAssertTrue(settings.dailyGrowthFallTiers.isEmpty)
        XCTAssertEqual(FundGrowthReminderTier.allCases.map(\.title), ["2%", "3%", "5%", "7%", "10%"])
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertEqual(AppAppearanceMode.allCases.map(\.title), ["跟随系统", "浅色", "深色"])
        XCTAssertTrue(settings.showsMarketIndexes)
        XCTAssertEqual(settings.defaultMarketIndexID, .shanghaiComposite)
        XCTAssertFalse(settings.betaFeaturesEnabled)
        XCTAssertFalse(MarketIndexID.allCases.map(\.title).contains("恒生科技"))
    }

    @MainActor
    func testConcurrentRefreshesNeverOverlapNetworkPasses() async throws {
        let store = try refreshConcurrencyTestStore(prefix: "single-flight")
        defer { try? FileManager.default.removeItem(at: store.dataDirectory) }
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 180_000_000)

        let firstRefresh = Task { await store.refreshQuotes() }
        try await Task.sleep(nanoseconds: 30_000_000)
        let secondRefresh = Task { await store.refreshQuotes() }
        await firstRefresh.value
        await secondRefresh.value

        XCTAssertEqual(MockURLProtocol.responseStore.requests().count, 2)
        XCTAssertEqual(MockURLProtocol.responseStore.maximumConcurrentRequestCount(), 1)
    }

    @MainActor
    func testRefreshRequestsDuringActivePassCoalesceIntoOneTrailingPass() async throws {
        let store = try refreshConcurrencyTestStore(prefix: "trailing-pass")
        defer { try? FileManager.default.removeItem(at: store.dataDirectory) }
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 180_000_000)

        let firstRefresh = Task { await store.refreshQuotes() }
        try await Task.sleep(nanoseconds: 30_000_000)
        let secondRefresh = Task { await store.refreshQuotes() }
        let thirdRefresh = Task { await store.refreshQuotes() }
        try await Task.sleep(nanoseconds: 190_000_000)

        XCTAssertTrue(store.isRefreshingQuotes)

        await firstRefresh.value
        await secondRefresh.value
        await thirdRefresh.value
        XCTAssertFalse(store.isRefreshingQuotes)
        XCTAssertEqual(MockURLProtocol.responseStore.requests().count, 2)
        XCTAssertEqual(MockURLProtocol.responseStore.maximumConcurrentRequestCount(), 1)
    }

    @MainActor
    func testTrailingRefreshUsesLatestFundCodes() async throws {
        let store = try refreshConcurrencyTestStore(prefix: "latest-codes")
        defer { try? FileManager.default.removeItem(at: store.dataDirectory) }
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 180_000_000)

        let firstRefresh = Task { await store.refreshQuotes() }
        try await Task.sleep(nanoseconds: 30_000_000)
        var updatedSnapshot = store.snapshot
        updatedSnapshot.funds.append(
            conversionFund(code: "290008", name: "测试新增基金", shares: 100, cost: 1)
        )
        let importURL = store.dataDirectory.appending(path: "latest-codes.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(updatedSnapshot).write(to: importURL, options: .atomic)
        try store.importPortfolio(from: importURL)
        let trailingRefresh = Task { await store.refreshQuotes() }

        await firstRefresh.value
        await trailingRefresh.value

        let batches = MockURLProtocol.responseStore.requests().compactMap { request -> Set<String>? in
            guard let url = request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let codes = components.queryItems?.first(where: { $0.name == "FCODES" })?.value
            else { return nil }
            return Set(codes.split(separator: ",").map(String.init))
        }
        XCTAssertEqual(batches, [[Self.tradeTestCode], [Self.tradeTestCode, "290008"]])
    }

    func testMissingEditedRecordRedirectsToLiveTradeRecords() {
        let snapshot = transactionTestSnapshot()
        let route = ChildPanelRoute.editTradeRecord(
            fundCode: Self.tradeTestCode,
            recordID: "missing-record"
        )

        XCTAssertEqual(
            ChildPanelRouteResolver.disposition(for: route, in: snapshot),
            .redirect(.tradeRecords(fundCode: Self.tradeTestCode))
        )
    }

    func testEditedRouteStaysAvailableWhenRecordValuesRefresh() {
        var snapshot = transactionTestSnapshot()
        let recordID = snapshot.tradeRecords?[0].id ?? ""
        let route = ChildPanelRoute.editTradeRecord(
            fundCode: Self.tradeTestCode,
            recordID: recordID
        )
        snapshot.tradeRecords?[0].status = .failed

        XCTAssertEqual(ChildPanelRouteResolver.disposition(for: route, in: snapshot), .available)
        XCTAssertEqual(ChildPanelRouteResolver.record(for: route, in: snapshot)?.status, .failed)
    }

    func testMissingRoutedFundClosesChildPanel() {
        let route = ChildPanelRoute.fundDetail(fundCode: "missing-fund")

        XCTAssertEqual(
            ChildPanelRouteResolver.disposition(for: route, in: transactionTestSnapshot()),
            .close
        )
    }

    func testFundThresholdReminderEvaluatorUsesGlobalDailyGrowthTiers() throws {
        let date = try XCTUnwrap(DateOnlyFormatter.parse("2026-06-24"))
        let settings = AppSettings(
            dailyGrowthReminderEnabled: true,
            dailyGrowthRiseTiers: [.two, .three, .five, .seven],
            dailyGrowthFallTiers: [.three, .five, .ten]
        )
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(code: "024418", todayRate: 5.41),
                thresholdReminderFund(code: "024424", todayRate: -5.2),
                thresholdReminderFund(code: "025833", todayRate: 1.99),
                thresholdReminderFund(code: "026210", todayRate: -2.99)
            ]
        )

        let reminders = FundThresholdReminderEvaluator.reminders(in: snapshot, settings: settings, date: date)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.code), ["024418", "024424"])
        XCTAssertEqual(reminders.map(\.kind), [.dailyGrowth, .dailyGrowth])
        XCTAssertEqual(reminders.map(\.direction), [.rise, .fall])
        XCTAssertEqual(reminders.map(\.threshold), [5, 5])
        XCTAssertEqual(reminders[0].title, "测试基金024418")
        XCTAssertEqual(reminders[0].body, "涨跌幅提醒：当前涨幅 +5.41%，已达 5.00%档。")
        XCTAssertEqual(reminders[1].title, "测试基金024424")
        XCTAssertEqual(reminders[1].body, "涨跌幅提醒：当前跌幅 -5.20%，已达 5.00%档。")
    }

    func testFundThresholdReminderEvaluatorOnlySendsOncePerDay() throws {
        let now = try chinaDate("2026-06-24 13:30")
        let nextDay = try chinaDate("2026-06-25 09:45")
        let settings = AppSettings(
            dailyGrowthReminderEnabled: true,
            dailyGrowthRiseTiers: [.three, .five, .seven],
            dailyGrowthFallTiers: []
        )
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(code: "024418", todayRate: 5.41)
            ]
        )
        let reminder = try XCTUnwrap(
            FundThresholdReminderEvaluator.reminders(in: snapshot, settings: settings, date: now).first
        )

        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                settings: settings,
                now: now,
                lastSentAt: [reminder.dedupeKey: try chinaDate("2026-06-24 09:31")]
            ).isEmpty
        )
        XCTAssertEqual(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                settings: settings,
                now: nextDay,
                lastSentAt: [reminder.dedupeKey: try chinaDate("2026-06-24 14:55")]
            ).count,
            1
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: thresholdReminderSnapshot(funds: [thresholdReminderFund(code: "024418", todayRate: 3.41)]),
                settings: settings,
                now: now,
                lastSentAt: [reminder.dedupeKey: try chinaDate("2026-06-24 09:31")]
            ).isEmpty
        )
        XCTAssertEqual(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: thresholdReminderSnapshot(funds: [thresholdReminderFund(code: "024418", todayRate: 7.41)]),
                settings: settings,
                now: now,
                lastSentAt: [reminder.dedupeKey: try chinaDate("2026-06-24 09:31")]
            ).first?.threshold,
            7
        )
    }

    func testFundThresholdReminderEvaluatorOnlyRunsWhileMarketIsOpen() throws {
        let settings = AppSettings(
            dailyGrowthReminderEnabled: true,
            dailyGrowthRiseTiers: [.five],
            dailyGrowthFallTiers: []
        )
        let snapshot = thresholdReminderSnapshot(
            funds: [
                thresholdReminderFund(code: "024418", todayRate: 5.41)
            ]
        )

        XCTAssertEqual(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                settings: settings,
                now: try chinaDate("2026-06-24 10:30"),
                lastSentAt: [:]
            ).count,
            1
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                settings: settings,
                now: try chinaDate("2026-06-24 12:00"),
                lastSentAt: [:]
            ).isEmpty
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                settings: settings,
                now: try chinaDate("2026-06-24 15:01"),
                lastSentAt: [:]
            ).isEmpty
        )
        XCTAssertTrue(
            FundThresholdReminderEvaluator.eligibleReminders(
                in: snapshot,
                settings: settings,
                now: try chinaDate("2026-06-21 10:30"),
                lastSentAt: [:]
            ).isEmpty
        )
    }

    @MainActor
    func testSettingsMigrationClampsRefreshIntervalsToSessionOptions() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-refresh-interval-clamp-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let settingsURL = tempDirectory.appending(path: "settings.json")
        let settings = """
        {
          "settingsSchemaVersion": 10,
          "autoRefreshInterval": "30m",
          "marketClosedAutoRefreshInterval": "2s"
        }
        """
        try Data(settings.utf8).write(to: settingsURL, options: .atomic)

        let store = AppSettingsStore(dataDirectory: tempDirectory)

        XCTAssertEqual(store.settings.autoRefreshInterval, .fiveSeconds)
        XCTAssertEqual(store.settings.marketClosedAutoRefreshInterval, .tenMinutes)
    }

    func testLookupFundCodeUsesEastmoneySuggest() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": """
            FundPulseSuggest_123({"Datas":[{"CODE":"011609","NAME":"易方达上证科创板50成份交易型开放式指数证券投资基金联接基金","SHORTNAME":"易方达上证科创50ETF联接C","CATEGORYDESC":"基金"}]});
            """
        ])

        let code = await service.lookupFundCode(name: "易方达上证科创50ETF联接C")

        XCTAssertEqual(code, "011609")
    }

    func testLookupFundCodeIgnoresNonFundSuggestResults() async throws {
        let service = quoteServiceWithMockResponses([
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": """
            FundPulseSuggest_123({"Datas":[{"CODE":"300496","NAME":"中科创达","CATEGORYDESC":"深市"},{"CODE":"011609","NAME":"易方达上证科创50联接C","CATEGORYDESC":"基金"}]});
            """
        ])

        let code = await service.lookupFundCode(name: "易方达上证科创50ETF联接C")

        XCTAssertEqual(code, "011609")
    }

    func testLookupFundCodeRetriesQDIIBaseNameAndStillMatchesExactShareClass() async throws {
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

        let fullName = "富国全球科技互联网股票(QDII)C"
        let baseName = "富国全球科技互联网股票"
        let service = quoteServiceWithMockResponses([
            try suggestPrefix(fullName): """
            FundPulseSuggest_123({"Datas":[{"CODE":"VSS","NAME":"Vanguard FTSE All-World ex-US Small-Cap ETF","CATEGORYDESC":"美股"}]});
            """,
            try suggestPrefix(baseName): """
            FundPulseSuggest_123({"Datas":[
              {"CODE":"100055","NAME":"富国全球科技互联网股票(QDII)A","SHORTNAME":"富国全球科技互联网股票(QDII)A","CATEGORYDESC":"基金"},
              {"CODE":"022184","NAME":"富国全球科技互联网股票(QDII)C","SHORTNAME":"富国全球科技互联网股票(QDII)C","CATEGORYDESC":"基金"},
              {"CODE":"026228","NAME":"富国全球科技互联网股票(QDII)D","SHORTNAME":"富国全球科技互联网股票(QDII)D","CATEGORYDESC":"基金"}
            ]});
            """
        ])

        let code = await service.lookupFundCode(name: fullName)
        let requestedKeys = MockURLProtocol.responseStore.requests().compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?
                .first(where: { $0.name == "key" })?
                .value
        }

        XCTAssertEqual(code, "022184")
        XCTAssertTrue(requestedKeys.contains(fullName))
        XCTAssertTrue(requestedKeys.contains(baseName))
    }

    func testLookupFundCodeRejectsAmbiguousExactQDIIShareClassMatches() async throws {
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

        let fullName = "富国全球科技互联网股票(QDII)C"
        let baseName = "富国全球科技互联网股票"
        let ambiguousResponse = """
        FundPulseSuggest_123({"Datas":[
          {"CODE":"022184","NAME":"\(fullName)","CATEGORYDESC":"基金"},
          {"CODE":"999999","NAME":"\(fullName)","CATEGORYDESC":"基金"}
        ]});
        """
        let service = quoteServiceWithMockResponses([
            try suggestPrefix(fullName): ambiguousResponse,
            try suggestPrefix(baseName): ambiguousResponse
        ])

        let code = await service.lookupFundCode(name: fullName)

        XCTAssertNil(code)
    }

    func testLookupFundCodeRetriesConservativeETFLinkAliasAfterExistingLookupsFail() async throws {
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

        let jdName = "广发中证全指电力ETF发起式联接C"
        let alias = "广发电力ETF联接C"
        let unrelatedResponse = """
        FundPulseSuggest_123({"Datas":[{"CODE":"000537","NAME":"绿发电力","CATEGORYDESC":"深市"}]});
        """
        let service = quoteServiceWithMockResponses([
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": unrelatedResponse,
            try suggestPrefix(alias): """
            FundPulseSuggest_123({"Datas":[{"CODE":"016186","NAME":"广发电力ETF联接C","SHORTNAME":"广发电力ETF联接C","CATEGORYDESC":"基金"}]});
            """
        ])

        let code = await service.lookupFundCode(name: jdName)
        let requestedKeys = MockURLProtocol.responseStore.requests().compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?
                .first(where: { $0.name == "key" })?
                .value
        }

        XCTAssertEqual(code, "016186")
        XCTAssertEqual(requestedKeys.last, alias)
        XCTAssertTrue(requestedKeys.contains(jdName))
    }

    func testLookupFundCodeRejectsAmbiguousConservativeETFLinkAlias() async throws {
        let jdName = "广发中证全指电力ETF发起式联接C"
        let service = quoteServiceWithMockResponses([
            "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx": """
            FundPulseSuggest_123({"Datas":[
              {"CODE":"016186","NAME":"广发电力ETF联接C","CATEGORYDESC":"基金"},
              {"CODE":"999999","NAME":"广发电力ETF联接C","CATEGORYDESC":"基金"}
            ]});
            """
        ])

        let code = await service.lookupFundCode(name: jdName)
        let requestedKeys = MockURLProtocol.responseStore.requests().compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?
                .first(where: { $0.name == "key" })?
                .value
        }

        XCTAssertNil(code)
        XCTAssertTrue(requestedKeys.contains("广发电力ETF联接C"))
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

    func testPendingActivityNoticeStaysDismissedWhileCurrentActivitiesOnlyRefreshOrResolve() {
        let dismissedIDs: Set<String> = ["pending-a", "pending-b"]

        XCTAssertFalse(PendingActivityNoticePolicy.shouldShow(
            activityIDs: ["pending-a", "pending-b"],
            dismissedActivityIDs: dismissedIDs
        ))
        XCTAssertFalse(PendingActivityNoticePolicy.shouldShow(
            activityIDs: ["pending-a"],
            dismissedActivityIDs: dismissedIDs
        ))
        XCTAssertEqual(
            PendingActivityNoticePolicy.normalizedDismissedActivityIDs(
                activityIDs: ["pending-a"],
                dismissedActivityIDs: dismissedIDs
            ),
            dismissedIDs
        )
    }

    func testPendingActivityBuilderListsPendingTradesMatchingHeaderCount() throws {
        let now = try chinaDate("2026-07-08 23:39")
        let buyCreatedAt = try chinaDate("2026-07-08 15:08")
        let funds = [
            FundPosition(
                code: "011833",
                name: "西部利得人工智能主题指数增强C",
                dateText: "07-08 15:00",
                todayIncome: 82.15,
                todayRate: 0.96,
                holdingIncome: -360.23,
                holdingRate: -4.00,
                currentAmount: 8_639.77,
                status: .holding,
                isUpdated: true,
                isIncomeActive: true,
                migratedShares: 4_310.832252,
                migratedCost: 2.087764,
                migratedPrincipal: 9_000,
                incomeStartDate: "2026-07-08",
                positionMode: .amount,
                positionDate: "2026-07-08",
                positionTimeType: .before15,
                lots: [
                    FundPositionLot(id: "011833-new", shares: 4_310.832252, cost: 2.087764, principal: 9_000, incomeStartDate: "2026-07-08", positionDate: "2026-07-08", positionTimeType: .before15)
                ]
            ),
            FundPosition(
                code: "011370",
                name: "华商均衡成长混合C",
                dateText: "07-08 15:00",
                todayIncome: -468.24,
                todayRate: -3.34,
                holdingIncome: -2_449,
                holdingRate: -15.31,
                currentAmount: 13_551,
                status: .holding,
                isUpdated: true,
                isIncomeActive: true,
                migratedShares: 3_370.560143,
                migratedCost: 4.746985,
                migratedPrincipal: 16_000,
                incomeStartDate: "2026-07-08",
                positionMode: .amount,
                positionDate: "2026-07-08",
                positionTimeType: .before15,
                lots: [
                    FundPositionLot(id: "011370-new", shares: 3_370.560143, cost: 4.746985, principal: 16_000, incomeStartDate: "2026-07-08", positionDate: "2026-07-08", positionTimeType: .before15)
                ]
            ),
            FundPosition(
                code: "026210",
                name: "平安科技精选混合发起式A",
                dateText: "07-08 15:00",
                todayIncome: -466.41,
                todayRate: -2.19,
                holdingIncome: -4_688.08,
                holdingRate: -18.37,
                currentAmount: 20_830.85,
                status: .holding,
                isUpdated: true,
                isIncomeActive: true,
                migratedShares: 10_466.711888,
                migratedCost: 2.438104,
                migratedPrincipal: 25_518.93,
                incomeStartDate: "2026-07-08",
                positionMode: .amount,
                positionDate: "2026-07-08",
                positionTimeType: .before15,
                lots: [
                    FundPositionLot(id: "026210-new", shares: 10_466.711888, cost: 2.438104, principal: 25_518.93, incomeStartDate: "2026-07-08", positionDate: "2026-07-08", positionTimeType: .before15)
                ]
            ),
            FundPosition(
                code: "008989",
                name: "大成科技创新混合C",
                dateText: "07-08 15:00",
                todayIncome: -688.40,
                todayRate: -3.17,
                holdingIncome: -3_970.20,
                holdingRate: -15.88,
                currentAmount: 21_027.80,
                status: .holding,
                isUpdated: true,
                isIncomeActive: true,
                migratedShares: 3_845.540499,
                migratedCost: 6.500517,
                migratedPrincipal: 24_998,
                incomeStartDate: "2026-07-08",
                positionMode: .amount,
                positionDate: "2026-07-08",
                positionTimeType: .before15,
                lots: [
                    FundPositionLot(id: "008989-new", shares: 3_845.540499, cost: 6.500517, principal: 24_998, incomeStartDate: "2026-07-08", positionDate: "2026-07-08", positionTimeType: .before15)
                ]
            ),
            FundPosition(
                code: "022485",
                name: "国金中证A500指数增强A",
                dateText: "07-08 15:00",
                todayIncome: -2_124.32,
                todayRate: -1.79,
                holdingIncome: -3_447.40,
                holdingRate: -2.87,
                currentAmount: 116_552.60,
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
                    FundPositionLot(id: "022485-new", shares: 77_438.442628, cost: 1.549618, principal: 120_000, incomeStartDate: "2026-07-08", positionDate: "2026-07-08", positionTimeType: .before15)
                ]
            )
        ]
        let pendingTrades = [
            FundPendingTrade(id: "pending-022485", recordID: "buy-022485", action: .buy, code: "022485", mode: .amount, amount: 6_000, shares: nil, tradeDate: "2026-07-08", tradeTimeType: .before15, createdAt: buyCreatedAt),
            FundPendingTrade(id: "pending-008989", recordID: "buy-008989", action: .buy, code: "008989", mode: .amount, amount: 1_000, shares: nil, tradeDate: "2026-07-08", tradeTimeType: .before15, createdAt: buyCreatedAt.addingTimeInterval(11)),
            FundPendingTrade(id: "pending-026210", recordID: "buy-026210", action: .buy, code: "026210", mode: .amount, amount: 1_000, shares: nil, tradeDate: "2026-07-08", tradeTimeType: .before15, createdAt: buyCreatedAt.addingTimeInterval(22)),
            FundPendingTrade(id: "pending-011370", recordID: "buy-011370", action: .buy, code: "011370", mode: .amount, amount: 1_000, shares: nil, tradeDate: "2026-07-08", tradeTimeType: .before15, createdAt: buyCreatedAt.addingTimeInterval(37))
        ]
        let records = pendingTrades.map { pendingTrade in
            FundTradeRecord(
                id: pendingTrade.recordID ?? pendingTrade.id,
                kind: .buy,
                status: .pending,
                code: pendingTrade.code,
                name: funds.first { $0.code == pendingTrade.code }?.name ?? pendingTrade.code,
                mode: pendingTrade.mode,
                amount: pendingTrade.amount,
                shares: nil,
                confirmedShares: nil,
                price: nil,
                tradeDate: pendingTrade.tradeDate,
                tradeTimeType: pendingTrade.tradeTimeType,
                acceptedDate: "2026-07-08",
                createdAt: pendingTrade.createdAt,
                confirmedAt: nil,
                failureReason: nil,
                buyFeeRate: 0
            )
        }
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 301_436.77,
            holdingIncome: -14_834.48,
            holdingIncomeRate: -4.69,
            todayIncome: -2_106.08,
            todayIncomeRate: -0.69,
            pendingCount: 4,
            funds: funds,
            migration: nil,
            pendingTrades: pendingTrades,
            tradeRecords: records
        )

        let activities = PendingTradeActivityBuilder.make(from: snapshot)
        let impact = try XCTUnwrap(PendingHeaderImpact.make(activities: activities))

        XCTAssertEqual(activities.count, snapshot.pendingCount)
        XCTAssertEqual(impact.count, snapshot.pendingCount)
        XCTAssertEqual(activities.map(\.code), ["011370", "026210", "008989", "022485"])
        XCTAssertEqual(activities.map(\.amount), [1_000, 1_000, 1_000, 6_000])
        XCTAssertEqual(impact.buyAmount, 9_000, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingLegacyPendingFundWithoutTradeRecordRemovesFund() async throws {
        let now = try chinaDate("2026-07-08 14:15")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-delete-legacy-pending-fund-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: quoteServiceWithMockResponses([:]), now: { now })
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
                        code: "588760",
                        name: "科创人工智能ETF广发",
                        dateText: "07-08 15:00前确认",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingIncome: 0,
                        holdingRate: 0,
                        currentAmount: 0,
                        status: .pending,
                        isUpdated: false,
                        migratedShares: 0
                    )
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteFund(code: "588760")

        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertNil(store.snapshot.tradeRecords)
        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertNil(store.snapshot.pendingConversions)
    }

    @MainActor
    func testDeletingLastFundClearsHeaderAggregatesAndSyncedTotal() async throws {
        let now = try chinaDate("2026-07-08 14:30")
        let syncedAt = try chinaDate("2026-07-08 14:20")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-delete-last-fund-clears-aggregates-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: quoteServiceWithMockResponses([:]), now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: syncedAt,
                totalAmount: 100,
                holdingIncome: -0.0000002,
                holdingIncomeRate: -0.0000002,
                todayIncome: 0.73,
                todayIncomeRate: 0.73,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "588760",
                        name: "科创人工智能ETF广发",
                        dateText: "07-08 15:00前确认",
                        todayIncome: 0.73,
                        todayRate: 0.73,
                        holdingIncome: 0,
                        holdingRate: 0,
                        currentAmount: 100,
                        status: .holding,
                        isUpdated: false,
                        migratedShares: 100,
                        migratedCost: 1
                    )
                ],
                migration: nil,
                syncedAccountTotal: PortfolioSyncedAccountTotal(source: .jdFinance, amount: 100, syncedAt: syncedAt)
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteFund(code: "588760")

        XCTAssertEqual(store.snapshot.updateTime, now)
        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertEqual(store.snapshot.totalAmount, 0)
        XCTAssertEqual(store.snapshot.holdingIncome, 0)
        XCTAssertEqual(store.snapshot.holdingIncomeRate, 0)
        XCTAssertEqual(store.snapshot.todayIncome, 0)
        XCTAssertEqual(store.snapshot.todayIncomeRate, 0)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertNil(store.snapshot.syncedAccountTotal)

        let reloadedStore = PortfolioStore(dataDirectory: tempDirectory, quoteService: quoteServiceWithMockResponses([:]), now: { now })
        reloadedStore.load()
        XCTAssertTrue(reloadedStore.snapshot.funds.isEmpty)
        XCTAssertEqual(reloadedStore.snapshot.totalAmount, 0)
        XCTAssertEqual(reloadedStore.snapshot.todayIncome, 0)
        XCTAssertNil(reloadedStore.snapshot.syncedAccountTotal)
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
    func testEditingFundPreservesSameDayIntradayHistory() async throws {
        let now = try chinaDate("2026-07-08 13:32")
        let service = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "011833",
                name: "西部利得人工智能主题指数增强C",
                netValueDate: "2026-07-07",
                netValue: 1.9824,
                estimatedNetValue: 2.0250,
                growthRate: 2.15,
                estimateTime: "2026-07-08 13:32"
            ),
            "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=011833&page=1&per=1": """
            var apidata={ content:"<table><tbody><tr><td>2026-07-07</td><td class='tor bold'>1.9824</td><td>1.9824</td><td class='red'>0.42%</td></tr></tbody></table>",records:1,pages:1,curpage:1};
            """
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-edit-intraday-history-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let morningPoint = FundIntradayRatePoint(
            timestamp: Int64(try chinaDate("2026-07-08 09:35").timeIntervalSince1970 * 1000),
            rate: 3.21,
            estimateTime: "2026-07-08 09:35"
        )
        let snapshot = PortfolioSnapshot(
            updateTime: try chinaDate("2026-07-08 09:35"),
            totalAmount: 8_000,
            holdingIncome: -500,
            holdingIncomeRate: -5.88,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "011833",
                    name: "西部利得人工智能主题指数增强C",
                    dateText: "07-08 09:35",
                    todayIncome: 0,
                    todayRate: 3.21,
                    holdingIncome: -500,
                    holdingRate: -5.88,
                    currentAmount: 8_000,
                    status: .holding,
                    isUpdated: false,
                    isIncomeActive: true,
                    migratedShares: 4_000,
                    migratedCost: 2.125,
                    migratedPrincipal: 8_500,
                    incomeStartDate: "2026-07-07",
                    positionMode: .amount,
                    positionDate: "2026-07-07",
                    positionTimeType: .before15,
                    zdfRange: 5,
                    jzNotice: 2.5,
                    lots: [
                        FundPositionLot(
                            id: "existing-lot",
                            shares: 4_000,
                            cost: 2.125,
                            principal: 8_500,
                            incomeStartDate: "2026-07-07",
                            positionDate: "2026-07-07",
                            positionTimeType: .before15
                        )
                    ],
                    intradayRateDate: "2026-07-08",
                    intradayRateHistory: [morningPoint]
                )
            ],
            migration: nil
        )
        try seedPortfolio(snapshot, into: store, directory: tempDirectory)

        try await store.upsertFund(
            FundPositionDraft(
                code: "011833",
                name: "西部利得人工智能主题指数增强C",
                positionMode: .amount,
                positionAmount: 8_557.86,
                positionProfit: -442.14,
                shares: nil,
                cost: nil,
                positionDate: "2026-07-07",
                positionTimeType: .before15,
                memo: ""
            ),
            replacing: "011833"
        )

        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "011833" })
        let points = try XCTUnwrap(fund.intradayRateHistory)
        XCTAssertEqual(fund.intradayRateDate, "2026-07-08")
        XCTAssertEqual(points.map(\.estimateTime), ["2026-07-08 09:35", "2026-07-08 13:32"])
        XCTAssertEqual(points.map(\.rate), [3.21, 2.15])
        XCTAssertNil(fund.zdfRange)
        XCTAssertNil(fund.jzNotice)
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
    func testPendingTradeKeepsPublishedSnapshotWhenPersistenceFails() async throws {
        let tempDirectory = temporaryPortfolioDirectory(prefix: "trade-transaction")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let store = PortfolioStore(dataDirectory: tempDirectory)
        try seedPortfolio(transactionTestSnapshot(), into: store, directory: tempDirectory)
        let originalSnapshot = store.snapshot
        try makePortfolioStorageUnwritable(for: store)

        do {
            try await store.adjustFundPosition(
                FundTradeDraft(
                    action: .buy,
                    code: Self.tradeTestCode,
                    mode: .amount,
                    amount: 100,
                    shares: nil,
                    tradeDate: "2026-07-10",
                    tradeTimeType: .before15
                )
            )
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(store.snapshot, originalSnapshot)
        }
    }

    @MainActor
    func testRefreshKeepsPublishedSnapshotWhenPersistenceFails() async throws {
        let tempDirectory = temporaryPortfolioDirectory(prefix: "refresh-transaction")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let response = Self.coreQuoteResponse(
            code: Self.tradeTestCode,
            name: Self.tradeTestName,
            netValueDate: "2026-07-09",
            netValue: 2.2,
            estimatedNetValue: 2.3,
            growthRate: 1.5,
            estimateTime: "2026-07-10 10:30"
        )
        let store = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: quoteServiceWithMockResponses([
                "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": response
            ])
        )
        try seedPortfolio(transactionTestSnapshot(), into: store, directory: tempDirectory)
        let originalSnapshot = store.snapshot
        try makePortfolioStorageUnwritable(for: store)

        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot, originalSnapshot)
        guard case .failed = store.loadState else {
            return XCTFail("Expected refresh persistence failure, got \(store.loadState)")
        }
    }

    @MainActor
    func testSuccessfulPortfolioMutationPublishesPersistedSnapshot() throws {
        let repository = RecordingPortfolioRepository(initialSnapshot: transactionTestSnapshot())
        let store = PortfolioStore(repository: repository)
        store.load()

        try store.clearAllHoldings()

        XCTAssertEqual(repository.savedSnapshots.last, store.snapshot)
        XCTAssertTrue(store.snapshot.funds.isEmpty)
    }

    @MainActor
    func testMissingPortfolioDoesNotWriteSampleDuringRefresh() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-missing-data-refresh-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: quoteServiceWithMockResponses([:]))

        store.load()
        guard case .missingPlainData(let hasLegacyStore) = store.loadState else {
            return XCTFail("Expected missing plain data state, got \(store.loadState)")
        }
        XCTAssertFalse(hasLegacyStore)
        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.dataFileURL.path))

        await store.refreshQuotes()

        guard case .missingPlainData = store.loadState else {
            return XCTFail("Expected missing plain data state after refresh, got \(store.loadState)")
        }
        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.dataFileURL.path))
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
}
