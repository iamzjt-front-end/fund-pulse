import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
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
        XCTAssertEqual(
            MenuBarStatusFormatter.text(amount: 12.3, rate: 1.23, mode: .hidden),
            ""
        )
    }

    func testChildPanelRouteCarriesStableIdentifiers() {
        XCTAssertEqual(
            ChildPanelRoute.fundDetail(fundCode: Self.tradeTestCode).selectedFundCode,
            Self.tradeTestCode
        )
        XCTAssertEqual(
            ChildPanelRoute.editConversion(
                sourceFundCode: Self.tradeTestCode,
                recordID: "conversion-record",
                returnFundCode: "290008"
            ).selectedFundCode,
            Self.tradeTestCode
        )
        XCTAssertNil(ChildPanelRoute.settings.selectedFundCode)
    }

    func testMetricChildPanelsUseStandardSize() {
        XCTAssertEqual(
            PopoverLayout.portfolioBreakdownSize.height,
            PopoverLayout.standardChildPanelHeight
        )
        XCTAssertEqual(
            PopoverLayout.todayIncomeRankingSize.height,
            PopoverLayout.standardChildPanelHeight
        )
        XCTAssertEqual(
            PopoverLayout.portfolioBreakdownSize.width,
            PopoverLayout.standardChildPanelWidth
        )
        XCTAssertEqual(
            PopoverLayout.todayIncomeRankingSize.width,
            PopoverLayout.standardChildPanelWidth
        )
    }

    func testChildPanelRouteResolverReadsLatestSnapshotValues() throws {
        let route = ChildPanelRoute.tradeRecords(fundCode: Self.tradeTestCode)
        let originalSnapshot = transactionTestSnapshot()
        var updatedSnapshot = originalSnapshot
        updatedSnapshot.funds[0].name = "刷新后的基金名称"
        updatedSnapshot.tradeRecords?[0].status = .failed

        XCTAssertEqual(
            ChildPanelRouteResolver.fund(for: route, in: updatedSnapshot)?.name,
            "刷新后的基金名称"
        )
        XCTAssertEqual(
            try XCTUnwrap(ChildPanelRouteResolver.tradeRecords(for: route, in: updatedSnapshot)).first?.status,
            .failed
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
        XCTAssertEqual(store.settings.marketClosedAutoRefreshInterval, .tenMinutes)
        XCTAssertEqual(store.settings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(store.settings.operationReminderEnabled)
        XCTAssertEqual(store.settings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(store.settings.thresholdReminderInterval, .thirtyMinutes)
        XCTAssertFalse(store.settings.dailyGrowthReminderEnabled)
        XCTAssertTrue(store.settings.dailyGrowthRiseTiers.isEmpty)
        XCTAssertTrue(store.settings.dailyGrowthFallTiers.isEmpty)
        XCTAssertEqual(store.settings.appearanceMode, .system)
        XCTAssertTrue(store.settings.showsMarketIndexes)
        XCTAssertEqual(store.settings.defaultMarketIndexID, .shanghaiComposite)
        XCTAssertFalse(store.settings.betaFeaturesEnabled)

        let savedData = try Data(contentsOf: settingsURL)
        let savedSettings = try JSONDecoder().decode(AppSettings.self, from: savedData)
        XCTAssertEqual(savedSettings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        XCTAssertEqual(savedSettings.menuBarDisplayMode, .sign)
        XCTAssertEqual(savedSettings.menuBarContentMode, .amount)
        XCTAssertEqual(savedSettings.autoRefreshInterval, .thirtySeconds)
        XCTAssertEqual(savedSettings.marketClosedAutoRefreshInterval, .tenMinutes)
        XCTAssertEqual(savedSettings.mainPanelHeight, AppSettings.defaultMainPanelHeight)
        XCTAssertTrue(savedSettings.operationReminderEnabled)
        XCTAssertEqual(savedSettings.operationReminderTimeMinutes, 14 * 60 + 30)
        XCTAssertEqual(savedSettings.thresholdReminderInterval, .thirtyMinutes)
        XCTAssertFalse(savedSettings.dailyGrowthReminderEnabled)
        XCTAssertTrue(savedSettings.dailyGrowthRiseTiers.isEmpty)
        XCTAssertTrue(savedSettings.dailyGrowthFallTiers.isEmpty)
        XCTAssertEqual(savedSettings.appearanceMode, .system)
        XCTAssertTrue(savedSettings.showsMarketIndexes)
        XCTAssertEqual(savedSettings.defaultMarketIndexID, .shanghaiComposite)
        XCTAssertFalse(savedSettings.betaFeaturesEnabled)
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
        store.setDailyGrowthReminderEnabled(true)
        XCTAssertTrue(store.settings.dailyGrowthReminderEnabled)
        store.setDailyGrowthRiseTiers([.five, .two, .five, .ten])
        XCTAssertEqual(store.settings.dailyGrowthRiseTiers, [.two, .five, .ten])
        XCTAssertTrue(store.settings.dailyGrowthFallTiers.isEmpty)
        store.setDailyGrowthFallTiers([.seven, .three, .seven])
        XCTAssertEqual(store.settings.dailyGrowthRiseTiers, [.two, .five, .ten])
        XCTAssertEqual(store.settings.dailyGrowthFallTiers, [.three, .seven])
        store.setAppearanceMode(.dark)
        XCTAssertEqual(store.settings.appearanceMode, .dark)
        store.setMenuBarContentMode(.both)
        XCTAssertEqual(store.settings.menuBarContentMode, .both)
        store.setMenuBarDisplayMode(.sign)
        XCTAssertEqual(store.settings.menuBarDisplayMode, .sign)
        XCTAssertFalse(store.settings.menuBarDisplayMode.usesGrowthColor)

        store.setAutoRefreshInterval(.twoSeconds)
        store.setMarketClosedAutoRefreshInterval(.threeMinutes)
        XCTAssertEqual(store.settings.autoRefreshInterval, .twoSeconds)
        XCTAssertEqual(store.settings.marketClosedAutoRefreshInterval, .threeMinutes)
        store.setShowsMarketIndexes(false)
        store.setDefaultMarketIndexID(.csi300)
        store.setBetaFeaturesEnabled(true)
        XCTAssertFalse(store.settings.showsMarketIndexes)
        XCTAssertEqual(store.settings.defaultMarketIndexID, .csi300)
        XCTAssertTrue(store.settings.betaFeaturesEnabled)

        let refreshedData = try Data(contentsOf: tempDirectory.appending(path: "settings.json"))
        let refreshedSettings = try JSONDecoder().decode(AppSettings.self, from: refreshedData)
        XCTAssertEqual(refreshedSettings.autoRefreshInterval, .twoSeconds)
        XCTAssertEqual(refreshedSettings.marketClosedAutoRefreshInterval, .threeMinutes)
        XCTAssertTrue(refreshedSettings.dailyGrowthReminderEnabled)
        XCTAssertEqual(refreshedSettings.dailyGrowthRiseTiers, [.two, .five, .ten])
        XCTAssertEqual(refreshedSettings.dailyGrowthFallTiers, [.three, .seven])
        XCTAssertFalse(refreshedSettings.showsMarketIndexes)
        XCTAssertEqual(refreshedSettings.defaultMarketIndexID, .csi300)
        XCTAssertTrue(refreshedSettings.betaFeaturesEnabled)
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

    func testPendingActivityPresentationSeparatesOrderTimeFromWaitingReason() {
        var activity = makePendingHeaderActivity(id: "new-fund", kind: .newFund, displayAmount: 1_000)
        activity.code = "022184"
        activity.name = "富国全球科技互联网股票(QDII)C"
        activity.tradeDate = "2026-07-14"
        activity.tradeTimeType = .before15
        activity.acceptedDate = "2026-07-14"

        let presentation = PendingActivityPresentation(activity: activity)

        XCTAssertEqual(presentation.orderText, "022184 · 07-14 15:00前下单")
        XCTAssertEqual(presentation.waitingText, "次日检查确认 · 净值就绪后自动更新")
    }

    func testPendingActivityPresentationUsesNextAcceptedDateForAfter15Order() {
        var activity = makePendingHeaderActivity(id: "after-15", kind: .buy, displayAmount: 1_000)
        activity.code = "022184"
        activity.tradeDate = "2026-07-14"
        activity.tradeTimeType = .after15
        activity.acceptedDate = "2026-07-15"

        let presentation = PendingActivityPresentation(activity: activity)

        XCTAssertEqual(presentation.orderText, "022184 · 07-14 15:00后下单")
        XCTAssertEqual(presentation.waitingText, "次日检查确认 · 净值就绪后自动更新")
    }

    func testPendingActivityPresentationDoesNotDistinguishExternalConfirmationWait() {
        var activity = makePendingHeaderActivity(id: "jd-waiting", kind: .buy, displayAmount: 1_000)
        activity.waitsForExternalConfirmation = true

        let presentation = PendingActivityPresentation(activity: activity)

        XCTAssertEqual(presentation.waitingText, "次日检查确认 · 净值就绪后自动更新")
    }

    func testPendingActivityPresentationFallsBackWhenAcceptedDateIsMalformed() {
        var activity = makePendingHeaderActivity(id: "legacy", kind: .newFund, displayAmount: 1_000)
        activity.acceptedDate = ""

        XCTAssertEqual(
            PendingActivityPresentation(activity: activity).waitingText,
            "次日检查确认 · 净值就绪后自动更新"
        )
    }

    func testPendingActivityPresentationNoticeExplainsDelayedQDIIConfirmation() {
        XCTAssertEqual(
            PendingActivityPresentation.noticeText,
            "系统会在受理日次日持续检查正式净值，净值就绪后自动确认；\nQDII 等基金净值发布较晚，继续待确认通常正常。"
        )
    }

    func testPendingActivityNoticeReappearsForANewActivityAndResetsAfterAllResolve() {
        let dismissedIDs: Set<String> = ["pending-a", "pending-b"]

        XCTAssertTrue(PendingActivityNoticePolicy.shouldShow(
            activityIDs: ["pending-a", "pending-c"],
            dismissedActivityIDs: dismissedIDs
        ))
        XCTAssertTrue(PendingActivityNoticePolicy.normalizedDismissedActivityIDs(
            activityIDs: ["pending-a", "pending-c"],
            dismissedActivityIDs: dismissedIDs
        ).isEmpty)
        XCTAssertTrue(PendingActivityNoticePolicy.normalizedDismissedActivityIDs(
            activityIDs: [],
            dismissedActivityIDs: dismissedIDs
        ).isEmpty)
    }

    func testMarketSessionStateUsesTradingHoursAfterDragonBoatHoliday() throws {
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 10:35")), .open)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 12:00")), .middayBreak)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-22 15:01")), .closed)
        XCTAssertEqual(TradingCalendar.marketSessionState(now: try chinaDate("2026-06-21 10:35")), .closed)
        XCTAssertEqual(
            TradingCalendar.nextMarketSessionBoundary(after: try chinaDate("2026-06-22 12:59")),
            try chinaDate("2026-06-22 13:00")
        )
        XCTAssertEqual(
            TradingCalendar.nextMarketSessionBoundary(after: try chinaDate("2026-06-22 15:01")),
            try chinaDate("2026-06-23 09:30")
        )
        XCTAssertEqual(
            TradingCalendar.nextMarketSessionBoundary(after: try chinaDate("2026-06-26 15:01")),
            try chinaDate("2026-06-29 09:30")
        )
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

    func testOperationReminderCleanupAlwaysIncludesLegacyRepeatingIdentifier() {
        XCTAssertEqual(
            StatusBarController.operationReminderNotificationIdentifiersToClear(
                from: [
                    "fund-pulse.operation-reminder.2026-07-01",
                    "other.notification"
                ]
            ),
            [
                "fund-pulse.operation-reminder",
                "fund-pulse.operation-reminder.2026-07-01"
            ]
        )
    }

    func testOperationReminderCleanupClearsLegacyContentWithUnknownIdentifier() {
        XCTAssertEqual(
            StatusBarController.operationReminderNotificationIdentifiersToClear(
                from: [
                    OperationReminderNotificationCandidate(
                        identifier: "legacy.daily-reminder",
                        title: "基金操作提醒",
                        body: "现在可以检查基金估值，按计划处理加仓、减仓或继续持仓。"
                    ),
                    OperationReminderNotificationCandidate(
                        identifier: "fund-pulse.test-reminder.1",
                        title: "fund-pulse 测试提醒",
                        body: "如果你看到这条通知，说明系统通知权限正常。"
                    ),
                    OperationReminderNotificationCandidate(
                        identifier: "other.notification",
                        title: "基金操作提醒",
                        body: "别的内容"
                    )
                ]
            ),
            [
                "fund-pulse.operation-reminder",
                "legacy.daily-reminder"
            ]
        )
    }

    @MainActor
    func testOperationReminderSchedulerWaitsUntilDuplicateRequestsAreRemovedBeforeAdding() async throws {
        let reminderDate = try chinaDate("2026-07-14 14:30")
        let request = OperationReminderNotificationRequest(
            identifier: "fund-pulse.operation-reminder.2026-07-14",
            title: OperationReminderNotificationContent.title,
            body: OperationReminderNotificationContent.body,
            fireDate: reminderDate
        )
        let duplicateCandidate = OperationReminderNotificationCandidate(
            identifier: request.identifier,
            title: request.title,
            body: request.body
        )
        let notificationCenter = OperationReminderNotificationCenterFake(
            pendingRequests: [duplicateCandidate, duplicateCandidate],
            removalWaitCount: 2
        )
        let scheduler = makeOperationReminderNotificationScheduler(center: notificationCenter)

        scheduler.configure(isEnabled: true, requests: [request])
        await scheduler.waitUntilIdle()

        XCTAssertFalse(notificationCenter.didAddBeforePendingRequestsWereRemoved)
        XCTAssertEqual(notificationCenter.addedRequests, [request])
        XCTAssertEqual(
            notificationCenter.pendingRequests.filter { $0.identifier == request.identifier }.count,
            1
        )
        XCTAssertGreaterThanOrEqual(notificationCenter.removePendingCallCount, 1)
        XCTAssertEqual(notificationCenter.waitCallCount, 2)
    }

    @MainActor
    func testOperationReminderSchedulerKeepsOnlyLatestConsecutiveConfiguration() async throws {
        let firstRequest = OperationReminderNotificationRequest(
            identifier: "fund-pulse.operation-reminder.2026-07-14",
            title: OperationReminderNotificationContent.title,
            body: OperationReminderNotificationContent.body,
            fireDate: try chinaDate("2026-07-14 14:30")
        )
        let latestRequest = OperationReminderNotificationRequest(
            identifier: "fund-pulse.operation-reminder.2026-07-15",
            title: OperationReminderNotificationContent.title,
            body: OperationReminderNotificationContent.body,
            fireDate: try chinaDate("2026-07-15 14:30")
        )
        let notificationCenter = OperationReminderNotificationCenterFake()
        let scheduler = makeOperationReminderNotificationScheduler(center: notificationCenter)

        scheduler.configure(isEnabled: true, requests: [firstRequest])
        scheduler.configure(isEnabled: true, requests: [latestRequest])
        await scheduler.waitUntilIdle()

        XCTAssertEqual(notificationCenter.authorizationRequestCount, 1)
        XCTAssertEqual(notificationCenter.addedRequests, [latestRequest])
    }

    func testOperationReminderPresentationGateSuppressesConsecutiveDuplicateBanners() async throws {
        let gate = OperationReminderNotificationPresentationGate(duplicateWindow: 60)
        let candidate = OperationReminderNotificationCandidate(
            identifier: "fund-pulse.operation-reminder.2026-07-14",
            title: OperationReminderNotificationContent.title,
            body: OperationReminderNotificationContent.body
        )
        let firstDelivery = try chinaDate("2026-07-14 14:30")
        let shouldPresentFirst = await gate.shouldPresent(candidate, at: firstDelivery)
        let shouldPresentDuplicate = await gate.shouldPresent(
            candidate,
            at: firstDelivery.addingTimeInterval(1)
        )
        let shouldPresentAfterWindow = await gate.shouldPresent(
            candidate,
            at: firstDelivery.addingTimeInterval(61)
        )

        XCTAssertTrue(shouldPresentFirst)
        XCTAssertFalse(shouldPresentDuplicate)
        XCTAssertTrue(shouldPresentAfterWindow)
    }

    func testOperationReminderPresentationGateDoesNotSuppressOtherNotifications() async throws {
        let gate = OperationReminderNotificationPresentationGate(duplicateWindow: 60)
        let testReminder = OperationReminderNotificationCandidate(
            identifier: "fund-pulse.test-reminder.1",
            title: "fund-pulse 测试提醒",
            body: "如果你看到这条通知，说明系统通知权限正常。"
        )
        let deliveryDate = try chinaDate("2026-07-14 14:30")
        let shouldPresentFirst = await gate.shouldPresent(testReminder, at: deliveryDate)
        let shouldPresentSecond = await gate.shouldPresent(testReminder, at: deliveryDate)

        XCTAssertTrue(shouldPresentFirst)
        XCTAssertTrue(shouldPresentSecond)
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

    func testIntradayRateHistoryPausesOutsideOpenAndRestartsNextTradingDay() throws {
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
        let middayQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.04,
            growthRate: 1.65,
            estimateTime: "2026-06-24 11:30",
            netValueDate: "2026-06-23"
        )
        let afternoonQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.05,
            growthRate: 1.80,
            estimateTime: "2026-06-24 13:01",
            netValueDate: "2026-06-23"
        )
        let closeQuote = FundQuote(
            code: "026210",
            name: "平安科技精选混合发起式A",
            netValue: 2,
            estimatedNetValue: 2.06,
            growthRate: 1.95,
            estimateTime: "2026-06-24 15:00",
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
            quotes: ["026210": middayQuote],
            now: try chinaDate("2026-06-24 12:00")
        )
        let middayPoints = try XCTUnwrap(middayBreak.funds[0].intradayRateHistory)
        XCTAssertEqual(middayPoints.map(\.rate), [1.12])
        XCTAssertEqual(middayPoints.map(\.estimateTime), ["2026-06-24 10:58"])

        let afternoonOpen = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: middayBreak,
            quotes: ["026210": afternoonQuote],
            now: try chinaDate("2026-06-24 13:01")
        )
        let afternoonPoints = try XCTUnwrap(afternoonOpen.funds[0].intradayRateHistory)
        XCTAssertEqual(afternoonPoints.map(\.rate), [1.12, 1.80])
        XCTAssertEqual(
            afternoonPoints.map(\.estimateTime),
            ["2026-06-24 10:58", "2026-06-24 13:01"]
        )

        let afterClose = FundIntradayRateHistoryRecorder.applyingQuotes(
            to: afternoonOpen,
            quotes: ["026210": closeQuote],
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
}
