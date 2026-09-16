import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    func testJDFinanceHoldingsServiceReportsNotLoggedIn() async {
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: """
            {"success":false,"resultCode":3,"resultMsg":"请先登录您的京东账号","channelEncrypt":0}
            """
        ])

        await XCTAssertThrowsErrorAsync {
            _ = try await service.fetchSnapshot(cookieHeader: nil)
        } errorHandler: { error in
            XCTAssertEqual(error as? JDFinanceHoldingsError, .notLoggedIn)
        }
    }

    func testJDFinanceHoldingsServiceParsesApplyTimeAsBefore15TradeTime() async throws {
        let detailResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "detail": {
                "tradeType": "买入",
                "tradeAmount": "1000.00",
                "applyTime": "2026-07-03 14:35:12",
                "tradeStatus": "买入确认中"
              }
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.action, .buy)
        XCTAssertEqual(detail.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
    }

    func testJDFinanceHoldingsServiceDoesNotInferTradeTimeFromExpectedUpdate() async throws {
        let detailResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "detail": {
                "tradeType": "买入",
                "tradeAmount": "1000.00",
                "updateTime": "2026-07-08 09:00:00",
                "expectedUpdateText": "预计08日更新",
                "tradeStatus": "买入确认中"
              }
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.action, .buy)
        XCTAssertEqual(detail.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertNil(detail.tradeDate)
        XCTAssertNil(detail.tradeTimeType)
    }

    func testJDFinanceWebTradeEndpointLoginFailureDoesNotMarkSuccessfulH5FlowIncomplete() async throws {
        let nativeLoginResponse = """
        {"success":false,"resultCode":3,"resultMsg":"请先登录京东账号"}
        """
        let webSuccessResponse = """
        {"success":true,"resultCode":0,"resultData":{"data":{"tradeOrderVoList":[]}}}
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinanceEmptyHoldingsResponse(total: 0),
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: nativeLoginResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: webSuccessResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")

        XCTAssertEqual(snapshot.tradeOrderFetchState, .complete)
        XCTAssertTrue(snapshot.tradeOrders.isEmpty)
    }

    @MainActor
    func testJDFinanceSyncStoreRecordsNotLoggedInForLoginPrompt() async {
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: """
            {"success":false,"resultCode":3,"resultMsg":"请先登录您的京东账号","channelEncrypt":0}
            """
        ])
        let syncStore = JDFinanceHoldingsSyncStore(service: service)
        let portfolioStore = PortfolioStore(
            dataDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        await syncStore.synchronize(portfolioStore: portfolioStore, cookieHeader: nil)

        XCTAssertEqual(syncStore.lastError, .notLoggedIn)
        XCTAssertEqual(syncStore.errorMessage, JDFinanceHoldingsError.notLoggedIn.localizedDescription)
        XCTAssertNil(syncStore.preview)
    }

    @MainActor
    func testJDFinanceHoldingsSyncRejectsDifferentPerformanceAccountBeforeRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-cross-account-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let establishedAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=history-account")
        )
        try performanceStore.replace(
            PortfolioPerformanceSnapshot(
                jdFinanceSync: .init(
                    accountKey: establishedAccount,
                    coveredFrom: "2026-01-01",
                    coveredThrough: "2026-07-14",
                    lastSyncedAt: .now,
                    isComplete: true
                )
            )
        )
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinanceHoldingsResponse
        ])
        let syncStore = JDFinanceHoldingsSyncStore(service: service)
        let portfolioStore = PortfolioStore(
            dataDirectory: directory,
            performanceStore: performanceStore
        )
        portfolioStore.load()

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=session; pt_pin=different-account"
        )

        XCTAssertEqual(MockURLProtocol.responseStore.requests().count, 0)
        XCTAssertNil(syncStore.preview)
        XCTAssertNil(portfolioStore.snapshot.jdFinanceSyncState)
        XCTAssertNil(portfolioStore.snapshot.syncedAccountTotal)
        XCTAssertEqual(syncStore.errorMessage, PortfolioStoreError.jdFinanceAccountMismatch.localizedDescription)
    }

    @MainActor
    func testJDFinanceHoldingsSyncRechecksPerformanceAccountAfterRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-account-race-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        MockURLProtocol.responseStore.set([
            JDFinanceHoldingsService.endpoint.absoluteString: Data(Self.jdFinanceHoldingsResponse.utf8)
        ])
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 120_000_000)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        let portfolioStore = PortfolioStore(
            dataDirectory: directory,
            performanceStore: performanceStore
        )
        portfolioStore.load()
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: URLSession(configuration: configuration))
        )
        let differentAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=different-history-account")
        )

        let syncTask = Task { @MainActor in
            await syncStore.synchronize(
                portfolioStore: portfolioStore,
                cookieHeader: "pt_key=session; pt_pin=request-account"
            )
        }
        try await Task.sleep(for: .milliseconds(30))
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
        await syncTask.value

        XCTAssertNil(portfolioStore.snapshot.jdFinanceSyncState)
        XCTAssertNil(portfolioStore.snapshot.syncedAccountTotal)
        XCTAssertNil(syncStore.preview)
        XCTAssertEqual(syncStore.errorMessage, PortfolioStoreError.jdFinanceAccountMismatch.localizedDescription)
    }

    @MainActor
    func testJDFinanceHoldingsSyncRejectsUnidentifiedCookieWhenAccountIsEstablished() async throws {
        let establishedAccount = try XCTUnwrap(
            JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=established-account")
        )
        var snapshot = PortfolioSnapshot.empty
        snapshot.jdFinanceSyncState = JDFinanceSyncState(
            accountKey: establishedAccount,
            baselineEstablishedAt: .now
        )
        let portfolioStore = PortfolioStore(
            repository: RecordingPortfolioRepository(initialSnapshot: snapshot)
        )
        portfolioStore.load()
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinanceHoldingsResponse
        ])
        let syncStore = JDFinanceHoldingsSyncStore(service: service)

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=session-without-account-id"
        )

        XCTAssertEqual(MockURLProtocol.responseStore.requests().count, 0)
        XCTAssertNil(syncStore.preview)
        XCTAssertEqual(syncStore.errorMessage, PortfolioStoreError.jdFinanceAccountUnidentified.localizedDescription)
        XCTAssertEqual(portfolioStore.snapshot.jdFinanceSyncState?.accountKey, establishedAccount)
    }

    @MainActor
    func testJDFinanceSyncStoreIgnoresOlderRequestCompletion() async throws {
        let emptyOrders = #"{"resultCode":0,"resultData":{"data":{"orderList":[]}}}"#
        MockURLProtocol.responseStore.set([
            JDFinanceHoldingsService.endpoint.absoluteString: Data(Self.jdFinanceEmptyHoldingsResponse(total: 100).utf8),
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: Data(emptyOrders.utf8),
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: Data(emptyOrders.utf8)
        ])
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 120_000_000)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: URLSession(configuration: configuration))
        )
        let repository = RecordingPortfolioRepository(initialSnapshot: .empty)
        let portfolioStore = PortfolioStore(repository: repository)
        portfolioStore.load()

        let olderTask = Task { @MainActor in
            await syncStore.synchronize(
                portfolioStore: portfolioStore,
                cookieHeader: "pt_key=old; pt_pin=test"
            )
        }
        try await Task.sleep(for: .milliseconds(30))
        MockURLProtocol.responseStore.set([
            JDFinanceHoldingsService.endpoint.absoluteString: Data(Self.jdFinanceEmptyHoldingsResponse(total: 200).utf8),
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: Data(emptyOrders.utf8),
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: Data(emptyOrders.utf8)
        ])
        let newerTask = Task { @MainActor in
            await syncStore.synchronize(
                portfolioStore: portfolioStore,
                cookieHeader: "pt_key=new; pt_pin=test"
            )
        }

        await olderTask.value
        await newerTask.value

        XCTAssertEqual(portfolioStore.snapshot.totalAmount, 0)
        XCTAssertEqual(portfolioStore.snapshot.syncedAccountTotal?.amount, 200)
        XCTAssertEqual(repository.savedSnapshots.count, 1)
        XCTAssertFalse(syncStore.isSyncing)
    }

    @MainActor
    func testJDFinanceSyncStoreImportsSelectedUnrecordedSuccessfulOrder() async throws {
        let now = try chinaDate("2026-07-14 10:00")
        let holdingsResponse = """
        {"success":true,"resultCode":0,"resultMsg":"success","resultData":{"success":true,"resultData":{"headAssetsData":{"totalAssets":{"text":"1,000.00"}},"fundData":{"fundList":[{"productList":[{"skuId":"1013284","fundCode":"013284","productName":"上银价值增长3个月持有期混合A","totalAmount":{"text":"1,000.00"},"holdIncome":{"text":"0.00"}}]}]}}}}
        """
        let orderResponse = """
        {"resultCode":0,"resultData":{"data":{"orderList":[{"orderId":"raw-order-must-not-persist","productCode":"013284","fundName":"上银价值增长3个月持有期混合A","tradeTypeCode":"TRANSFER_IN","applyAmount":"1,000.00","confirmShare":"100.00","orderCreateTime":"2026-07-13 10:00:00","statusName":"确认成功"}]}}}
        """
        let quoteResponse = Self.coreQuoteResponse(
            code: "013284",
            name: "上银价值增长3个月持有期混合A",
            netValueDate: "2026-07-13",
            netValue: 10,
            estimateTime: "2026-07-14 10:00"
        )
        MockURLProtocol.responseStore.set([
            JDFinanceHoldingsService.endpoint.absoluteString: Data(holdingsResponse.utf8),
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: Data(orderResponse.utf8),
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: Data(orderResponse.utf8),
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Data(quoteResponse.utf8)
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let repository = RecordingPortfolioRepository(initialSnapshot: jdPortfolio(
            funds: [conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)],
            records: [],
            now: now
        ))
        let portfolioStore = PortfolioStore(
            repository: repository,
            quoteService: FundQuoteService(session: URLSession(configuration: configuration)),
            now: { now }
        )
        portfolioStore.load()
        let syncStore = JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(session: URLSession(configuration: configuration)),
            now: { now }
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )
        XCTAssertEqual(syncStore.preview?.importableUnrecordedOrders.count, 1)

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: false,
            importPending: false,
            reconcileConfirmed: false,
            importUnrecorded: true
        )

        XCTAssertNil(syncStore.errorMessage)
        let imported = try XCTUnwrap(portfolioStore.snapshot.tradeRecords?.last)
        XCTAssertEqual(imported.externalStatus, .externalConfirmed)
        XCTAssertEqual(imported.waitsForExternalConfirmation, false)
        XCTAssertTrue(imported.syncKey?.hasPrefix("jd-order-") == true)
        XCTAssertFalse(imported.syncKey?.contains("raw-order-must-not-persist") == true)
        XCTAssertTrue(syncStore.preview?.unrecordedOrders.isEmpty == true)
    }

    @MainActor
    func testJDFinanceSyncStoreAppliesSelectedChangedHoldings() async throws {
        let now = try chinaDate("2026-07-03 16:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-sync-apply-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let responses = [
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinanceHoldingsResponse,
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "024424",
                name: "永赢先进制造智选混合发起A",
                netValueDate: "2026-07-03",
                netValue: 2,
                estimatedNetValue: 2,
                growthRate: 0,
                estimateTime: "2026-07-03 15:00"
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
            totalAmount: 18_900,
            holdingIncome: -500,
            holdingIncomeRate: -2.58,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "024424",
                    name: "永赢先进制造智选混合发起A",
                    dateText: "07-03 15:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: -500,
                    holdingRate: -2.58,
                    currentAmount: 18_900,
                    status: .holding,
                    isUpdated: true,
                    migratedPrincipal: 19_400
                )
            ],
            migration: nil
        )
        try seedPortfolio(localSnapshot, into: portfolioStore, directory: tempDirectory)

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )
        XCTAssertEqual(portfolioStore.snapshot.totalAmount, 18_900, accuracy: 0.0001)
        XCTAssertEqual(portfolioStore.snapshot.syncedAccountTotal?.source, .jdFinance)
        XCTAssertEqual(portfolioStore.snapshot.syncedAccountTotal?.amount ?? 0, 171_461.84, accuracy: 0.0001)
        XCTAssertEqual(syncStore.preview?.changedHoldings.map(\.code), ["024424"])

        await syncStore.applySelectedHoldings(
            to: portfolioStore,
            importNew: false,
            updateChanged: true,
            importPending: false
        )

        let fund = try XCTUnwrap(portfolioStore.snapshot.funds.first { $0.code == "024424" })
        XCTAssertEqual(fund.currentAmount ?? 0, 19_907.79, accuracy: 0.01)
        XCTAssertEqual(fund.holdingIncome ?? 0, -734.13, accuracy: 0.01)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 20_641.92, accuracy: 0.01)
        XCTAssertEqual(portfolioStore.snapshot.totalAmount, 19_907.79, accuracy: 0.01)
        XCTAssertEqual(syncStore.preview?.changedHoldings.map(\.code), [])
        XCTAssertEqual(syncStore.statusMessage, "已同步 1 项数据")
    }

    @MainActor
    func testJDFinanceLoginURLUsesDirectMobileLoginPage() {
        XCTAssertEqual(
            JDFinanceWebSession.loginURL.absoluteString,
            "https://plogin.m.jd.com/login/login?qqlogin=false&wxlogin=false&appid=2508&source=JDJR_PC&returnurl=https%3A%2F%2Fjdjr.jd.com%2F"
        )
    }

    @MainActor
    func testJDFinanceLoginCompletionRequiresJDFinanceReturnURLAndCookie() throws {
        let returnURL = try XCTUnwrap(URL(string: "https://jdjr.jd.com/"))

        XCTAssertTrue(
            JDFinanceWebSession.didCompleteLoginNavigation(
                url: returnURL,
                cookieHeader: "pt_key=abc; pt_pin=test"
            )
        )
    }

    @MainActor
    func testJDFinanceLoginCompletionIgnoresLoginPageURL() {
        XCTAssertFalse(
            JDFinanceWebSession.didCompleteLoginNavigation(
                url: JDFinanceWebSession.loginURL,
                cookieHeader: "pt_key=abc; pt_pin=test"
            )
        )
    }

    @MainActor
    func testJDFinanceLoginCompletionRequiresAuthenticatedCookieHeader() throws {
        let returnURL = try XCTUnwrap(URL(string: "https://jdjr.jd.com/"))

        XCTAssertFalse(
            JDFinanceWebSession.didCompleteLoginNavigation(
                url: returnURL,
                cookieHeader: nil
            )
        )
        XCTAssertFalse(
            JDFinanceWebSession.didCompleteLoginNavigation(
                url: returnURL,
                cookieHeader: "   "
            )
        )
        XCTAssertFalse(
            JDFinanceWebSession.didCompleteLoginNavigation(
                url: returnURL,
                cookieHeader: "__jdu=visitor; mba_muid=tracking"
            )
        )
    }

    @MainActor
    func testJDFinanceUsableCookieHeaderRequiresAuthenticationCookie() {
        XCTAssertFalse(JDFinanceWebSession.hasUsableCookieHeader(nil))
        XCTAssertFalse(JDFinanceWebSession.hasUsableCookieHeader("   "))
        XCTAssertFalse(JDFinanceWebSession.hasUsableCookieHeader("__jdu=visitor; mba_muid=tracking"))
        XCTAssertFalse(JDFinanceWebSession.hasUsableCookieHeader("pt_pin=test"))
        XCTAssertFalse(JDFinanceWebSession.hasUsableCookieHeader("pt_key=; pt_pin=test"))
        XCTAssertTrue(JDFinanceWebSession.hasUsableCookieHeader("pt_key=abc; pt_pin=test"))
        XCTAssertTrue(JDFinanceWebSession.hasUsableCookieHeader("thor=abc; pin=test"))
    }

    @MainActor
    func testJDFinanceCookieCleanupDeletesOnlyJDDomains() throws {
        func cookie(name: String, domain: String) throws -> HTTPCookie {
            try XCTUnwrap(
                HTTPCookie(properties: [
                    .name: name,
                    .value: "value",
                    .domain: domain,
                    .path: "/"
                ])
            )
        }

        let storage = InMemoryJDFinanceCookieStorage(cookies: [
            try cookie(name: "jd-root", domain: ".jd.com"),
            try cookie(name: "jd-subdomain", domain: "api.jd.com"),
            try cookie(name: "legacy-jd", domain: ".360buy.com"),
            try cookie(name: "jd-pay", domain: "cashier.jdpay.com"),
            try cookie(name: "similar-domain", domain: "notjd.com"),
            try cookie(name: "suffix-trap", domain: "jd.com.example.com"),
            try cookie(name: "unrelated", domain: "example.com")
        ])

        JDFinanceWebSession.clearJDCookies(in: storage)

        XCTAssertEqual(
            Set(storage.deletedCookies.map(\.name)),
            ["jd-root", "jd-subdomain", "legacy-jd", "jd-pay"]
        )
        XCTAssertEqual(
            Set((storage.cookies ?? []).map(\.name)),
            ["similar-domain", "suffix-trap", "unrelated"]
        )
        XCTAssertTrue(JDFinanceWebSession.isJDDomain(".JD.com."))
        XCTAssertFalse(JDFinanceWebSession.isJDDomain("jd.com.example.com"))
    }

    func testJDFinanceCookieHeaderOnlyForwardsRootDomainAuthenticationCookies() throws {
        func cookie(
            name: String,
            value: String,
            domain: String,
            path: String = "/"
        ) throws -> HTTPCookie {
            try XCTUnwrap(
                HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: path
                ])
            )
        }

        let header = JDFinanceCookieHeaderFilter.scopedHeader(from: [
            try cookie(name: "pt_key", value: "auth", domain: ".jd.com"),
            try cookie(name: "pt_key", value: "stale-duplicate", domain: ".jd.com"),
            try cookie(name: "pt_pin", value: "user", domain: ".jd.com"),
            try cookie(name: "payment_token", value: "private", domain: ".jd.com"),
            try cookie(name: "pt_key", value: "payment-auth", domain: ".jdpay.com"),
            try cookie(name: "thor", value: "subdomain-only", domain: "jdjr.jd.com"),
            try cookie(name: "wskey", value: "wrong-path", domain: ".jd.com", path: "/login")
        ])

        XCTAssertEqual(header, "pt_key=auth; pt_pin=user")
    }

    func testJDFinanceCookieHeaderSelectionDoesNotMixWebKitAndSharedStores() throws {
        func cookie(name: String, value: String) throws -> HTTPCookie {
            try XCTUnwrap(
                HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: ".jd.com",
                    .path: "/"
                ])
            )
        }

        let header = JDFinanceCookieHeaderFilter.preferredScopedHeader(
            webKitCookies: [try cookie(name: "pt_key", value: "web-auth")],
            sharedCookies: [try cookie(name: "pt_pin", value: "shared-account")]
        )

        XCTAssertNil(header)
    }

    func testJDFinanceCookieHeaderSelectionFallsBackToCompleteSharedStore() throws {
        func cookie(name: String, value: String) throws -> HTTPCookie {
            try XCTUnwrap(
                HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: ".jd.com",
                    .path: "/"
                ])
            )
        }

        let header = JDFinanceCookieHeaderFilter.preferredScopedHeader(
            webKitCookies: [try cookie(name: "pt_key", value: "incomplete-web-auth")],
            sharedCookies: [
                try cookie(name: "pt_key", value: "shared-auth"),
                try cookie(name: "pt_pin", value: "shared-account")
            ]
        )

        XCTAssertEqual(header, "pt_key=shared-auth; pt_pin=shared-account")
    }

    func testJDFinanceCookieHeaderSelectionPrefersCompleteWebKitStore() throws {
        func cookie(name: String, value: String) throws -> HTTPCookie {
            try XCTUnwrap(
                HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: ".jd.com",
                    .path: "/"
                ])
            )
        }

        let header = JDFinanceCookieHeaderFilter.preferredScopedHeader(
            webKitCookies: [
                try cookie(name: "pt_key", value: "web-auth"),
                try cookie(name: "pt_pin", value: "web-account")
            ],
            sharedCookies: [
                try cookie(name: "pt_key", value: "shared-auth"),
                try cookie(name: "pt_pin", value: "shared-account")
            ]
        )

        XCTAssertEqual(header, "pt_key=web-auth; pt_pin=web-account")
    }

    @MainActor
    func testJDFinanceImportedBuyDoesNotDuplicateExistingInitialRecord() async throws {
        let now = try chinaDate("2026-07-08 09:30")
        let service = tradeQuoteService(
            code: "013284",
            name: "上银价值增长3个月持有期混合A",
            date: "2026-07-07",
            netValue: 1.3465
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-sync-idempotent-buy-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                pendingCount: 0,
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

        try await store.importTradeIfNeeded(
            FundTradeDraft(
                action: .buy,
                code: "013284",
                mode: .amount,
                amount: 20_000,
                shares: nil,
                tradeDate: "2026-07-07",
                tradeTimeType: .before15
            )
        )

        let records = store.snapshot.tradeRecords?.filter { $0.code == "013284" } ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .newFund)
    }

    @MainActor
    func testJDFinanceOrphanedQDIIBuyRepairsIndexButWaitsForAcceptedDateNAV() async throws {
        let now = try chinaDate("2026-07-17 00:10")
        let createdAt = try chinaDate("2026-07-16 14:30")
        let code = "022184"
        let name = "富国全球科技互联网股票(QDII)C"
        let service = tradeQuoteService(
            code: code,
            name: name,
            date: "2026-07-15",
            netValue: 5.6886
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-orphaned-qdii-buy-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let pendingRecord = FundTradeRecord(
            id: "orphaned-qdii-buy",
            kind: .buy,
            status: .pending,
            code: code,
            name: name,
            mode: .amount,
            amount: 1_000,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: createdAt,
            confirmedAt: nil,
            failureReason: nil,
            syncSource: .jdFinance,
            externalStatus: .waitingExternalConfirmation,
            externalStatusText: "支付成功",
            waitsForExternalConfirmation: true
        )
        try seedPortfolio(
            jdPortfolio(
                funds: [conversionFund(code: code, name: name, shares: 100, cost: 5.6886)],
                records: [pendingRecord],
                now: now
            ),
            into: store,
            directory: tempDirectory
        )

        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.pendingTrades?.first?.recordID, pendingRecord.id)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.status, .pending)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.000001)

        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.tradeRecords?.filter { $0.id == pendingRecord.id }.count, 1)
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares ?? 0, 100, accuracy: 0.000001)
    }

    func testJDFinanceFinalSplitPaymentsConfirmOneLogicalLocalBuy() throws {
        let now = try chinaDate("2026-07-15 16:00")
        let localRecord = jdWaitingRecord(
            id: "split-payment-buy",
            kind: .buy,
            code: "022184",
            amount: 1_000,
            shares: nil,
            now: now
        )
        let orders = [
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-split-900",
                code: "022184",
                productName: "富国全球科技互联网股票(QDII)C",
                action: .buy,
                amount: 900,
                shares: nil,
                tradeDate: "2026-07-13",
                tradeTimeType: .before15,
                submittedAt: "2026-07-13 10:05:00",
                status: .succeeded,
                statusText: "订单完成"
            ),
            JDFinanceTradeOrderRecord(
                stableOrderKey: "jd-order-split-100",
                code: "022184",
                productName: "富国全球科技互联网股票(QDII)C",
                action: .buy,
                amount: 100,
                shares: nil,
                tradeDate: "2026-07-13",
                tradeTimeType: .before15,
                submittedAt: "2026-07-13 10:05:00",
                status: .succeeded,
                statusText: "订单完成"
            )
        ]
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 1_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: orders,
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [], records: [localRecord], now: now)
        )

        XCTAssertEqual(preview.automaticConfirmations.map(\.recordIDs), [["split-payment-buy"]])
        XCTAssertEqual(
            preview.automaticConfirmations.first?.representedOrderKeys,
            ["jd-order-split-100", "jd-order-split-900"]
        )
        XCTAssertTrue(preview.reconciliationNotices.isEmpty)
        XCTAssertTrue(preview.unrecordedOrders.isEmpty)
    }

    func testJDFinanceOrderCompletedWithoutSharesPlansAutomaticConfirmation() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let localRecord = jdWaitingRecord(
            id: "order-completed-buy",
            kind: .buy,
            code: "022364",
            amount: 2_000,
            shares: nil,
            now: now
        )
        let completedOrder = JDFinanceTradeOrderRecord(
            stableOrderKey: "jd-order-completed-buy",
            code: "022364",
            productName: "永赢科技智选混合发起A",
            action: .buy,
            amount: 2_000,
            shares: nil,
            tradeDate: "2026-07-13",
            tradeTimeType: .before15,
            submittedAt: "2026-07-13 10:00:00",
            status: nil,
            statusText: "订单完成"
        )
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 2_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: [completedOrder],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [], records: [localRecord], now: now)
        )

        XCTAssertEqual(completedOrder.effectiveStatus, .succeeded)
        XCTAssertEqual(preview.automaticConfirmations.map(\.recordIDs), [["order-completed-buy"]])
        XCTAssertTrue(preview.overwritableReconciliationNotices.isEmpty)
        XCTAssertTrue(preview.unrecordedOrders.isEmpty)
        XCTAssertTrue(preview.informationalOrders.isEmpty)
    }

    func testJDFinanceFinalSellCanReconcileAfterProductLeavesHoldingsList() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let sellRecord = jdWaitingRecord(
            id: "full-sell",
            kind: .sell,
            code: "008998",
            amount: 1_000,
            shares: 1_000,
            now: now
        )
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 0,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [],
            tradeOrders: [
                jdOrder(
                    key: "full-sell-order",
                    code: "008998",
                    action: .sell,
                    amount: 990,
                    shares: 1_000,
                    status: .succeeded
                )
            ],
            tradeOrderFetchState: .complete
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: jdPortfolio(
                funds: [conversionFund(code: "008998", name: "同泰竞争优势混合C", shares: 1_000, cost: 1)],
                records: [sellRecord],
                now: now
            )
        )

        let notice = try XCTUnwrap(preview.overwritableReconciliationNotices.first)
        XCTAssertEqual(notice.id, "full-sell")
        XCTAssertEqual(notice.jdAmount, 990)
    }

    func testJDFinanceSuccessfulUnmatchedOrderIsExposedForManualImport() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 1_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [],
            tradeOrders: [
                jdOrder(
                    key: "unrecorded-buy",
                    code: "013284",
                    action: .buy,
                    amount: 1_000,
                    shares: 100,
                    status: .succeeded
                )
            ],
            tradeOrderFetchState: .complete
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [],
                migration: nil,
                jdFinanceSyncState: JDFinanceSyncState(baselineEstablishedAt: .distantPast)
            )
        )

        XCTAssertEqual(preview.unrecordedOrders.map(\.id), ["unrecorded-buy"])
        XCTAssertTrue(preview.unrecordedOrders[0].isImportable)
    }

    func testJDFinanceDistinctSuccessfulPaymentRowsRemainSeparateInUnrecordedQueue() throws {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 1_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [],
            tradeOrders: [
                jdOrder(
                    key: "successful-payment-900",
                    code: "022184",
                    action: .buy,
                    amount: 900,
                    shares: nil,
                    status: .succeeded
                ),
                jdOrder(
                    key: "successful-payment-100",
                    code: "022184",
                    action: .buy,
                    amount: 100,
                    shares: nil,
                    status: .succeeded
                )
            ],
            tradeOrderFetchState: .complete
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: PortfolioSnapshot(
                updateTime: .now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [],
                migration: nil,
                jdFinanceSyncState: JDFinanceSyncState(baselineEstablishedAt: .distantPast)
            )
        )

        XCTAssertEqual(
            Set(preview.unrecordedOrders.map(\.id)),
            Set(["successful-payment-900", "successful-payment-100"])
        )
    }

    func testJDFinanceNewPaymentRowIsNotHiddenByRepresentedRowInSameTradeBucket() throws {
        let representedKey = "represented-payment"
        let newKey = "new-payment"
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 1_000,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [],
            tradeOrders: [
                jdOrder(
                    key: representedKey,
                    code: "022184",
                    action: .buy,
                    amount: 900,
                    shares: nil,
                    status: .succeeded
                ),
                jdOrder(
                    key: newKey,
                    code: "022184",
                    action: .buy,
                    amount: 100,
                    shares: nil,
                    status: .succeeded
                )
            ],
            tradeOrderFetchState: .complete
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
            migration: nil,
            jdFinanceSyncState: JDFinanceSyncState(
                baselineEstablishedAt: .distantPast,
                representedOrderKeys: [representedKey]
            )
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(preview.unrecordedOrders.map(\.id), [newKey])
    }

    func testJDFinanceFirstSyncTreatsHistoricalSuccessAsCurrentHoldingBaseline() {
        let order = jdOrder(
            key: "historical-buy",
            code: "013284",
            action: .buy,
            amount: 1_000,
            shares: 100,
            status: .succeeded
        )
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 1_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: [order],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: .empty
        )

        XCTAssertTrue(preview.unrecordedOrders.isEmpty)
        XCTAssertEqual(preview.baselineRepresentedCount, 1)
        XCTAssertEqual(preview.baselineOrderKeys, ["historical-buy"])
    }

    @MainActor
    func testJDFinanceResolverFillsOrderCodeFromCanonicalTransferName() async {
        let resolver = JDFinanceFundCodeResolver(lookup: { _ in nil })
        let local = conversionFund(
            code: "022364",
            name: "永赢科技智选混合发起A",
            shares: 100,
            cost: 1
        )
        let snapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 100,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [],
            tradeOrders: [
                JDFinanceTradeOrderRecord(
                    productName: "转入-永赢科技智选混合发起A",
                    action: .buy,
                    amount: 100,
                    tradeDate: "2026-07-14",
                    tradeTimeType: .before15,
                    status: .succeeded
                )
            ]
        )

        let resolved = await resolver.resolve(
            snapshot: snapshot,
            localSnapshot: jdPortfolio(funds: [local], records: [], now: .now)
        )

        XCTAssertEqual(resolved.tradeOrders.first?.code, "022364")
        XCTAssertEqual(resolved.tradeOrders.first?.codeResolution, .nameMatched)
    }

    func testPortfolioCalculatorPreservesJDFinanceSyncStateAcrossRefresh() throws {
        let establishedAt = try chinaDate("2026-07-14 09:00")
        var snapshot = PortfolioSnapshot.empty
        snapshot.jdFinanceSyncState = JDFinanceSyncState(
            accountKey: "account",
            baselineEstablishedAt: establishedAt,
            representedOrderKeys: ["one"]
        )

        let refreshed = PortfolioCalculator.applyingQuotes(to: snapshot, quotes: [:], now: establishedAt)

        XCTAssertEqual(refreshed.jdFinanceSyncState, snapshot.jdFinanceSyncState)
    }

    @MainActor
    func testJDFinanceFullClearanceUsesAllLocalSharesAndKeepsAuditRecords() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let fund = conversionFund(code: "008998", name: "同泰竞争优势混合C", shares: 1_000, cost: 1)
        let initial = jdPortfolio(funds: [fund], records: [], now: now)
        let store = PortfolioStore(repository: RecordingPortfolioRepository(initialSnapshot: initial), now: { now })
        store.load()
        let order = jdOrder(
            key: "full-clear-order",
            code: "008998",
            action: .sell,
            amount: 990,
            shares: nil,
            status: .succeeded
        )
        let candidate = JDFinanceMissingLocalHolding(
            code: "008998",
            name: fund.name,
            localAmount: fund.currentAmount,
            finalOutflowOrder: order
        )

        try store.applyJDFinanceFullClearance(candidate, syncedAt: now)

        let clearedFund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(clearedFund.status, .watch)
        XCTAssertEqual(clearedFund.currentAmount, 0)
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertTrue(records.contains { $0.isReconciliationBaseline == true })
        let sell = try XCTUnwrap(records.last { $0.kind == .sell })
        XCTAssertEqual(sell.confirmedShares, 1_000)
        XCTAssertEqual(sell.syncKey, "full-clear-order")
    }

    func testJDFinanceAccountIdentityIsHashedAndStable() {
        let first = JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_key=secret; pt_pin=test-user")
        let second = JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=test-user; pt_key=changed")
        let preferredFirst = JDFinanceSyncFingerprint.accountKey(cookieHeader: "pin=alternate; pt_pin=test-user")
        let preferredSecond = JDFinanceSyncFingerprint.accountKey(cookieHeader: "pt_pin=test-user; pin=alternate")

        XCTAssertEqual(first, second)
        XCTAssertEqual(preferredFirst, preferredSecond)
        XCTAssertEqual(first, preferredFirst)
        XCTAssertTrue(first?.hasPrefix("jd-account-") == true)
        XCTAssertFalse(first?.contains("test-user") == true)
    }

    func testJDFinanceAmbiguousLegacyOrdersNeverReuseOneOrderForMultipleLocalRecords() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let records = ["legacy-a", "legacy-b"].map {
            jdWaitingRecord(
                id: $0,
                kind: .buy,
                code: "013284",
                amount: 1_000,
                shares: 100,
                now: now
            )
        }
        let ambiguousOrder = JDFinanceTradeOrderRecord(
            code: "013284",
            productName: "上银价值增长3个月持有期混合A",
            action: .buy,
            amount: 1_000,
            shares: 100,
            tradeDate: "2026-07-13",
            tradeTimeType: .before15,
            submittedAt: "2026-07-13 10:00:00",
            status: .succeeded,
            statusText: "确认成功"
        )
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 2_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: [ambiguousOrder, ambiguousOrder],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [], records: records, now: now)
        )

        XCTAssertTrue(preview.automaticConfirmations.isEmpty)
        XCTAssertEqual(preview.reconciliationNotices.count, 2)
        XCTAssertTrue(preview.reconciliationNotices.allSatisfy {
            if case .conflict(let message) = $0.state {
                return message.contains("多笔京东流水")
            }
            return false
        })
    }

    func testJDFinanceTwoStableOrdersConsumeOneExistingLocalRecordOnlyOnce() throws {
        let now = try chinaDate("2026-07-14 10:00")
        var localRecord = jdWaitingRecord(
            id: "already-recorded",
            kind: .buy,
            code: "013284",
            amount: 1_000,
            shares: 100,
            now: now
        )
        localRecord.syncKey = "stable-a"
        localRecord.externalStatus = .externalConfirmed
        localRecord.waitsForExternalConfirmation = false
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 2_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: [
                    jdOrder(key: "stable-a", code: "013284", action: .buy, amount: 1_000, shares: 100, status: .succeeded),
                    jdOrder(key: "stable-b", code: "013284", action: .buy, amount: 1_000, shares: 100, status: .succeeded)
                ],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [], records: [localRecord], now: now)
        )

        XCTAssertEqual(preview.unrecordedOrders.map(\.id), ["stable-b"])
    }

    func testJDFinanceIncompleteFlowDoesNotTreatMissingOrderAsDefinitive() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let localRecord = jdWaitingRecord(
            id: "waiting-buy",
            kind: .buy,
            code: "013284",
            amount: 1_000,
            shares: 100,
            now: now
        )
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 1_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: [],
                tradeOrderFetchState: .incomplete(["部分接口失败"])
            ),
            localSnapshot: jdPortfolio(funds: [], records: [localRecord], now: now)
        )

        let notice = try XCTUnwrap(preview.reconciliationNotices.first)
        if case .conflict(let message) = notice.state {
            XCTAssertTrue(message.contains("拉取不完整"))
        } else {
            XCTFail("Expected incomplete-flow conflict notice")
        }
        XCTAssertEqual(preview.warnings, ["部分接口失败"])
    }

    func testJDFinanceDuplicateRemoteCodeWithConflictingNamesIsReadOnly() {
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 300,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [
                    JDFinanceHoldingProduct(skuID: "sku-a", code: "013284", name: "测试基金A", totalAmount: 100),
                    JDFinanceHoldingProduct(skuID: "sku-b", code: "013284", name: "完全不同基金B", totalAmount: 200)
                ],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: .empty
        )

        XCTAssertTrue(preview.newHoldings.isEmpty)
        XCTAssertTrue(preview.changedHoldings.isEmpty)
        XCTAssertEqual(preview.unresolvedHoldings.count, 2)
        XCTAssertTrue(preview.warnings.contains { $0.contains("名称不一致") })
    }

    func testJDFinanceMissingAccountTotalPreservesValueWithWarning() {
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: nil,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: .empty
        )

        XCTAssertTrue(preview.warnings.contains { $0.contains("保留本地旧值") })
    }

    @MainActor
    func testJDFinanceMetadataApplyAcceptsZeroTotalAndConfirmsWithoutChangingTradeValues() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let record = jdWaitingRecord(
            id: "equal-buy",
            kind: .buy,
            code: "013284",
            amount: 1_000,
            shares: 100,
            now: now
        )
        var initial = jdPortfolio(
            funds: [conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)],
            records: [record],
            now: now
        )
        initial.pendingTrades = [
            FundPendingTrade(
                id: "pending-equal-buy",
                recordID: record.id,
                action: .buy,
                code: record.code,
                mode: .amount,
                amount: record.amount,
                shares: nil,
                tradeDate: record.tradeDate,
                tradeTimeType: record.tradeTimeType,
                createdAt: now,
                syncSource: .jdFinance,
                syncKey: record.syncKey,
                externalStatus: .waitingExternalConfirmation,
                externalStatusText: "确认中",
                waitsForExternalConfirmation: true
            )
        ]
        let repository = RecordingPortfolioRepository(initialSnapshot: initial)
        let store = PortfolioStore(repository: repository, now: { now })
        store.load()

        try store.applyJDFinanceSyncMetadata(
            accountTotal: 0,
            confirmations: [
                JDFinanceAutomaticConfirmation(
                    id: record.id,
                    recordIDs: [record.id],
                    syncKey: "jd-order-confirmed",
                    statusText: "确认成功"
                )
            ],
            syncedAt: now
        )

        XCTAssertEqual(repository.savedSnapshots.count, 1)
        XCTAssertEqual(store.snapshot.totalAmount, 0)
        XCTAssertEqual(store.snapshot.syncedAccountTotal?.amount, 0)
        let confirmed = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(confirmed.amount, 1_000)
        XCTAssertEqual(confirmed.confirmedShares, 100)
        XCTAssertEqual(confirmed.syncKey, "jd-order-confirmed")
        XCTAssertEqual(confirmed.externalStatus, .externalConfirmed)
        XCTAssertEqual(confirmed.waitsForExternalConfirmation, false)
        XCTAssertEqual(store.snapshot.pendingTrades?.first?.externalStatus, .externalConfirmed)
        XCTAssertEqual(store.snapshot.pendingTrades?.first?.waitsForExternalConfirmation, false)
    }

    @MainActor
    func testJDFinanceAtomicMutationRollsBackAndCommitsOnlyOnce() async throws {
        let now = try chinaDate("2026-07-14 10:00")
        let initial = jdPortfolio(funds: [], records: [], now: now)
        let repository = RecordingPortfolioRepository(initialSnapshot: initial)
        let store = PortfolioStore(repository: repository, now: { now })
        store.load()

        do {
            try await store.performJDFinanceAtomicMutation { stagingStore in
                try stagingStore.applyJDFinanceSyncMetadata(
                    accountTotal: 123,
                    confirmations: [],
                    syncedAt: now
                )
                throw PortfolioStoreError.invalidCode
            }
            XCTFail("Expected staged mutation to fail")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .invalidCode)
        }

        XCTAssertEqual(repository.savedSnapshots.count, 0)
        XCTAssertEqual(store.snapshot, initial)

        try await store.performJDFinanceAtomicMutation { stagingStore in
            try stagingStore.applyJDFinanceSyncMetadata(
                accountTotal: 456,
                confirmations: [],
                syncedAt: now
            )
        }

        XCTAssertEqual(repository.savedSnapshots.count, 1)
        XCTAssertEqual(store.snapshot.totalAmount, 0)
        XCTAssertEqual(store.snapshot.syncedAccountTotal?.amount, 456)
    }

    @MainActor
    func testJDFinanceAtomicMutationDefersQuoteRefreshUntilAfterCommit() async throws {
        var now = try chinaDate("2026-07-21 13:11")
        let refreshedAt = try chinaDate("2026-07-21 13:12")
        let initial = jdPortfolio(funds: [], records: [], now: now)
        let repository = RecordingPortfolioRepository(initialSnapshot: initial)
        let store = PortfolioStore(repository: repository, now: { now })
        let gate = AsyncTestGate()
        let committedSyncState = JDFinanceSyncState(
            baselineEstablishedAt: now,
            representedOrderKeys: ["staged-order"]
        )
        store.load()

        let mutationTask = Task { @MainActor in
            try await store.performJDFinanceAtomicMutation { stagingStore in
                try stagingStore.applyJDFinanceSyncMetadata(
                    accountTotal: nil,
                    confirmations: [],
                    syncedAt: now,
                    syncState: committedSyncState
                )
                await gate.wait()
            }
        }

        await gate.waitUntilWaiting()
        now = refreshedAt
        await store.refreshQuotes()
        await gate.open()
        try await mutationTask.value

        XCTAssertEqual(store.snapshot.jdFinanceSyncState, committedSyncState)
        XCTAssertEqual(store.snapshot.updateTime, refreshedAt)
        XCTAssertEqual(repository.savedSnapshots.count, 2)
    }

    @MainActor
    func testJDFinanceAtomicMutationStillRejectsBusinessModification() async throws {
        let now = try chinaDate("2026-07-21 13:11")
        let initial = jdPortfolio(funds: [], records: [], now: now)
        let repository = RecordingPortfolioRepository(initialSnapshot: initial)
        let store = PortfolioStore(repository: repository, now: { now })
        let gate = AsyncTestGate()
        let stagedSyncState = JDFinanceSyncState(
            baselineEstablishedAt: now,
            representedOrderKeys: ["staged-order"]
        )
        let concurrentSyncState = JDFinanceSyncState(
            baselineEstablishedAt: now,
            representedOrderKeys: ["concurrent-order"]
        )
        store.load()

        let mutationTask = Task { @MainActor in
            try await store.performJDFinanceAtomicMutation { stagingStore in
                try stagingStore.applyJDFinanceSyncMetadata(
                    accountTotal: nil,
                    confirmations: [],
                    syncedAt: now,
                    syncState: stagedSyncState
                )
                await gate.wait()
            }
        }

        await gate.waitUntilWaiting()
        try store.applyJDFinanceSyncMetadata(
            accountTotal: nil,
            confirmations: [],
            syncedAt: now,
            syncState: concurrentSyncState
        )
        await gate.open()

        do {
            try await mutationTask.value
            XCTFail("Expected a real concurrent portfolio modification to be rejected")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .concurrentModification)
        }
        XCTAssertEqual(store.snapshot.jdFinanceSyncState, concurrentSyncState)
    }

    @MainActor
    func testJDFinanceAtomicMutationDoesNotWriteRealPerformanceHistoryBeforeCommit() async throws {
        let now = try chinaDate("2026-07-15 14:30")
        let directory = temporaryPortfolioDirectory(prefix: "jd-atomic-performance")
        defer { try? FileManager.default.removeItem(at: directory) }

        let initial = jdPortfolio(
            funds: [
                conversionFund(
                    code: "013284",
                    name: "华夏中证细分食品饮料产业主题ETF发起式联接C",
                    shares: 100,
                    cost: 1
                )
            ],
            records: [],
            now: now
        )
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        try repository.save(initial)

        let performanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        try performanceStore.replace(
            PortfolioPerformanceSnapshot(
                trackingStartDate: "2026-07-14",
                localRecordingStartDate: "2026-07-14",
                days: [
                    PortfolioPerformanceDay(
                        date: "2026-07-14",
                        profit: 8,
                        returnRate: 0.8,
                        status: .confirmed,
                        updatedAt: try chinaDate("2026-07-14 21:00")
                    )
                ]
            )
        )
        let expectedPerformance = performanceStore.snapshot
        let expectedPerformanceData = try Data(contentsOf: performanceStore.dataFileURL)
        let quoteService = quoteServiceWithMockResponses([
            "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": Self.coreQuoteResponse(
                code: "013284",
                name: "华夏中证细分食品饮料产业主题ETF发起式联接C",
                netValueDate: "2026-07-14",
                netValue: 1,
                estimatedNetValue: 1.02,
                growthRate: 2,
                estimateTime: "2026-07-15 14:30"
            )
        ])
        let store = PortfolioStore(
            repository: repository,
            quoteService: quoteService,
            performanceStore: performanceStore,
            now: { now }
        )
        store.load()

        do {
            try await store.performJDFinanceAtomicMutation { stagingStore in
                await stagingStore.refreshQuotes()
                XCTAssertEqual(
                    stagingStore.performanceStore.snapshot.days.map(\.date),
                    ["2026-07-14", "2026-07-15"]
                )
                throw PortfolioStoreError.invalidCode
            }
            XCTFail("Expected staged mutation to fail")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .invalidCode)
        }

        XCTAssertEqual(store.snapshot, initial)
        XCTAssertEqual(try Data(contentsOf: performanceStore.dataFileURL), expectedPerformanceData)
        let reloadedPerformanceStore = PortfolioPerformanceStore(dataDirectory: directory)
        XCTAssertEqual(reloadedPerformanceStore.snapshot, expectedPerformance)
    }

    @MainActor
    func testJDFinanceFinalConversionOrderOverwritesLinkedRecords() async throws {
        let now = try chinaDate("2026-07-08 09:30")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-final-conversion-reconcile-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let service = multiTradeQuoteService([
            "007818": (name: "国泰中证全指通信设备ETF联接C", date: "2026-07-07", netValue: 1),
            "024418": (name: "华夏上证科创板半导体材料设备主题ETF发起式联接C", date: "2026-07-07", netValue: 0.5)
        ])
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 1_100,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: "007818", name: "国泰中证全指通信设备ETF联接C", shares: 900, cost: 1),
                    conversionFund(code: "024418", name: "华夏上证科创板半导体材料设备主题ETF发起式联接C", shares: 200, cost: 0.5)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "source-initial",
                        kind: .newFund,
                        status: .confirmed,
                        code: "007818",
                        name: "国泰中证全指通信设备ETF联接C",
                        mode: .amount,
                        amount: 1_000,
                        shares: nil,
                        confirmedShares: 1_000,
                        price: 1,
                        tradeDate: "2026-07-06",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-06",
                        createdAt: now.addingTimeInterval(-100),
                        confirmedAt: now.addingTimeInterval(-100),
                        failureReason: nil
                    ),
                    FundTradeRecord(
                        id: "conversion-out",
                        kind: .conversionOut,
                        status: .confirmed,
                        code: "007818",
                        name: "国泰中证全指通信设备ETF联接C",
                        mode: .share,
                        amount: 100,
                        shares: 100,
                        confirmedShares: 100,
                        price: 1,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-07",
                        createdAt: now,
                        confirmedAt: now,
                        failureReason: nil,
                        conversionID: "conversion-1",
                        linkedCode: "024418",
                        linkedName: "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                        syncSource: .jdFinance,
                        syncKey: "jd-conversion",
                        externalStatus: .waitingExternalConfirmation,
                        externalStatusText: "确认中",
                        waitsForExternalConfirmation: true
                    ),
                    FundTradeRecord(
                        id: "conversion-in",
                        kind: .conversionIn,
                        status: .confirmed,
                        code: "024418",
                        name: "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                        mode: .amount,
                        amount: 100,
                        shares: nil,
                        confirmedShares: 200,
                        price: 0.5,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-07-07",
                        createdAt: now,
                        confirmedAt: now,
                        failureReason: nil,
                        conversionID: "conversion-1",
                        linkedCode: "007818",
                        linkedName: "国泰中证全指通信设备ETF联接C",
                        syncSource: .jdFinance,
                        syncKey: "jd-conversion",
                        externalStatus: .waitingExternalConfirmation,
                        externalStatusText: "确认中",
                        waitsForExternalConfirmation: true
                    )
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 1_100,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1007818",
                    code: "007818",
                    name: "国泰中证全指通信设备ETF联接C",
                    totalAmount: 880,
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .conversion,
                        statusText: "已拉取京东交易流水用于对账",
                        candidateTradeRecords: [
                            JDFinanceTradeOrderRecord(
                                code: "007818",
                                productName: "转换-国泰中证全指通信设备ETF联接C",
                                conversionTargetCode: "024418",
                                conversionTargetName: "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                                action: .conversion,
                                amount: 120,
                                shares: 120,
                                tradeDate: "2026-07-07",
                                tradeTimeType: .before15,
                                statusText: "确认成功"
                            )
                        ]
                    )
                )
            ]
        )
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: store.snapshot
        )
        let notice = try XCTUnwrap(preview.overwritableReconciliationNotices.first)

        try await store.applyJDFinanceReconciliation(notice)

        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "conversion-out" })
        let inRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "conversion-in" })
        XCTAssertEqual(outRecord.amount ?? 0, 120, accuracy: 0.0001)
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 120, accuracy: 0.000001)
        XCTAssertEqual(outRecord.externalStatus, .externalConfirmed)
        XCTAssertEqual(inRecord.externalStatus, .externalConfirmed)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "007818" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 880, accuracy: 0.000001)
    }

    func testPortfolioCalculatorPreservesJDFinanceSyncedManualAmount() throws {
        let now = try chinaDate("2026-07-08 15:09")
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
                    code: "011370",
                    name: "华商均衡成长混合C",
                    dateText: "07-08 14:38",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingRate: nil,
                    status: .holding,
                    isUpdated: false,
                    isIncomeActive: true,
                    migratedShares: 10_000,
                    migratedCost: 1.6,
                    migratedPrincipal: 16_000,
                    incomeStartDate: "2026-07-08",
                    positionMode: .amount,
                    positionDate: "2026-07-08",
                    positionTimeType: .before15,
                    pendingAmount: 14_019.17,
                    pendingProfit: -1_980.83,
                    memo: "京东金融同步持仓金额修复",
                    lots: [
                        FundPositionLot(
                            id: "011370-amount-backfill",
                            shares: 10_000,
                            cost: 1.6,
                            principal: 16_000,
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
            code: "011370",
            name: "华商均衡成长混合C",
            netValue: 1.2345,
            estimatedNetValue: 1.2345,
            growthRate: 3.21,
            estimateTime: "2026-07-08 15:00",
            netValueDate: "2026-07-07"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["011370": quote],
            now: now
        )

        let fund = result.funds[0]
        XCTAssertEqual(fund.status, .holding)
        XCTAssertEqual(fund.currentAmount ?? 0, 14_019.17, accuracy: 0.0001)
        XCTAssertEqual(fund.holdingIncome ?? 0, -1_980.83, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedPrincipal ?? 0, 16_000, accuracy: 0.0001)
        XCTAssertEqual(fund.migratedShares ?? 0, 10_000, accuracy: 0.000001)
        XCTAssertEqual(fund.migratedCost ?? 0, 1.6, accuracy: 0.0001)
        XCTAssertEqual(fund.lots?.first?.shares ?? 0, 10_000, accuracy: 0.000001)
        XCTAssertEqual(fund.pendingAmount ?? 0, 14_019.17, accuracy: 0.0001)
        XCTAssertEqual(fund.pendingProfit ?? 0, -1_980.83, accuracy: 0.0001)
        XCTAssertEqual(fund.todayRate, 3.21, accuracy: 0.0001)
        XCTAssertEqual(fund.todayIncome, 14_019.17 * 3.21 / 100, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, 14_019.17 * 3.21 / 100, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncomeRate, 3.21, accuracy: 0.0001)
    }

    func testPortfolioCalculatorIgnoresSameDayJDFinanceTodayIncomeAndUsesLocalQuote() throws {
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
            syncedTodayIncome: -647.32,
            syncedTodayIncomeDate: "2026-07-16",
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
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: amount,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [fund],
            migration: nil
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
        XCTAssertEqual(result.funds[0].syncedTodayIncome ?? 0, -647.32, accuracy: 0.0001)
    }

    func testPortfolioCalculatorCalculatesRealtimeIncomeForJDSyncedManualAmountWhenSyncedIncomeIsZero() throws {
        let now = try chinaDate("2026-07-16 14:30")
        let syncedAmount = 591.01
        let pendingBuyAmount = 100.0
        let growthRate = 5.83
        let fund = FundPosition(
            code: "022365",
            name: "永赢科技智选混合发起C",
            dateText: "07-16 14:20",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: 0,
            holdingRate: 0,
            currentAmount: syncedAmount,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: 165.23,
            migratedCost: 3.5769,
            migratedPrincipal: syncedAmount,
            incomeStartDate: "2026-07-15",
            positionMode: .amount,
            positionDate: "2026-07-15",
            positionTimeType: .before15,
            pendingAmount: syncedAmount,
            syncedPendingBuyAmount: pendingBuyAmount,
            syncedPendingBuyDate: "2026-07-16",
            syncedTodayIncome: 0,
            syncedTodayIncomeDate: "2026-07-16",
            memo: "京东金融同步导入",
            lots: [
                FundPositionLot(
                    id: "022365-jd-sync",
                    shares: 165.23,
                    cost: 3.5769,
                    principal: syncedAmount,
                    incomeStartDate: "2026-07-15",
                    positionDate: "2026-07-15",
                    positionTimeType: .before15
                )
            ]
        )
        let snapshot = jdPortfolio(funds: [fund], records: [], now: now)
        let quote = FundQuote(
            code: fund.code,
            name: fund.name,
            netValue: 3.5769,
            estimatedNetValue: 3.7854,
            growthRate: growthRate,
            estimateTime: "2026-07-16 14:20",
            netValueDate: "2026-07-15"
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: [fund.code: quote],
            now: now
        )

        let confirmedAmount = syncedAmount - pendingBuyAmount
        let expectedTodayIncome = confirmedAmount * growthRate / 100
        XCTAssertEqual(result.funds[0].currentAmount ?? 0, confirmedAmount, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncome, expectedTodayIncome, accuracy: 0.0001)
        XCTAssertEqual(result.todayIncomeRate, growthRate, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].todayRate, growthRate, accuracy: 0.0001)
        XCTAssertEqual(result.funds[0].syncedTodayIncome ?? -1, 0, accuracy: 0.0001)
    }

    @MainActor
    func testJDFinanceAmountSyncReplacesFundHistoryWithSingleBaseline() async throws {
        let firstSyncAt = try chinaDate("2026-07-18 16:00")
        let secondSyncAt = try chinaDate("2026-07-18 16:30")
        let code = "026210"
        let name = "平安科技精选混合发起式A"
        let unrelatedCode = "008998"
        let unrelatedName = "同泰竞争优势混合C"
        let fund = FundPosition(
            code: code,
            name: name,
            dateText: "07-18 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: 0,
            currentAmount: 25_000,
            status: .holding,
            isUpdated: true,
            isIncomeActive: true,
            migratedShares: 12_500,
            migratedCost: 2,
            migratedPrincipal: 25_000,
            incomeStartDate: "2026-07-16",
            positionMode: .amount,
            positionDate: "2026-07-16",
            positionTimeType: .before15,
            lots: [
                FundPositionLot(
                    id: "old-initial",
                    shares: 12_500,
                    cost: 2,
                    principal: 25_000,
                    incomeStartDate: "2026-07-16",
                    positionDate: "2026-07-16",
                    positionTimeType: .before15
                )
            ]
        )
        let unrelatedFund = FundPosition(
            code: unrelatedCode,
            name: unrelatedName,
            dateText: "07-18 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: 0,
            currentAmount: 3_000,
            status: .holding,
            isUpdated: true,
            isIncomeActive: true,
            migratedShares: 3_000,
            migratedCost: 1,
            migratedPrincipal: 3_000,
            incomeStartDate: "2026-07-16",
            positionMode: .amount,
            positionDate: "2026-07-16",
            positionTimeType: .before15,
            lots: [
                FundPositionLot(
                    id: "unrelated-initial",
                    shares: 3_000,
                    cost: 1,
                    principal: 3_000,
                    incomeStartDate: "2026-07-16",
                    positionDate: "2026-07-16",
                    positionTimeType: .before15
                )
            ]
        )
        let oldInitial = FundTradeRecord(
            id: "old-initial",
            kind: .newFund,
            status: .confirmed,
            code: code,
            name: name,
            mode: .amount,
            amount: 23_500,
            shares: nil,
            confirmedShares: 11_750,
            price: 2,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: firstSyncAt.addingTimeInterval(-172_800),
            confirmedAt: firstSyncAt.addingTimeInterval(-172_800),
            failureReason: nil
        )
        let oldBuy = FundTradeRecord(
            id: "old-buy",
            kind: .buy,
            status: .confirmed,
            code: code,
            name: name,
            mode: .amount,
            amount: 1_000,
            shares: nil,
            confirmedShares: 500,
            price: 2,
            tradeDate: "2026-07-17",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-17",
            createdAt: firstSyncAt.addingTimeInterval(-86_400),
            confirmedAt: firstSyncAt.addingTimeInterval(-86_400),
            failureReason: nil
        )
        let oldPendingBuy = FundTradeRecord(
            id: "old-pending-buy",
            kind: .buy,
            status: .pending,
            code: code,
            name: name,
            mode: .amount,
            amount: 500,
            shares: nil,
            confirmedShares: nil,
            price: nil,
            tradeDate: "2026-07-18",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-18",
            createdAt: firstSyncAt.addingTimeInterval(-3_600),
            confirmedAt: nil,
            failureReason: nil
        )
        let unrelatedInitial = FundTradeRecord(
            id: "unrelated-initial",
            kind: .newFund,
            status: .confirmed,
            code: unrelatedCode,
            name: unrelatedName,
            mode: .amount,
            amount: 3_000,
            shares: nil,
            confirmedShares: 3_000,
            price: 1,
            tradeDate: "2026-07-16",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-16",
            createdAt: firstSyncAt.addingTimeInterval(-172_800),
            confirmedAt: firstSyncAt.addingTimeInterval(-172_800),
            failureReason: nil
        )
        var snapshot = jdPortfolio(
            funds: [fund, unrelatedFund],
            records: [oldInitial, oldBuy, oldPendingBuy, unrelatedInitial],
            now: firstSyncAt
        )
        snapshot.pendingCount = 1
        snapshot.pendingTrades = [
            FundPendingTrade(
                id: "pending-old-buy",
                recordID: oldPendingBuy.id,
                action: .buy,
                code: code,
                mode: .amount,
                amount: oldPendingBuy.amount,
                shares: nil,
                tradeDate: oldPendingBuy.tradeDate,
                tradeTimeType: oldPendingBuy.tradeTimeType,
                createdAt: oldPendingBuy.createdAt
            )
        ]
        let store = PortfolioStore(
            repository: RecordingPortfolioRepository(initialSnapshot: snapshot),
            quoteService: multiTradeQuoteService([
                code: (name: name, date: "2026-07-18", netValue: 1.8363),
                unrelatedCode: (name: unrelatedName, date: "2026-07-18", netValue: 1)
            ]),
            now: { secondSyncAt }
        )
        store.load()

        try await store.applyAmountPositionSyncUpdates([
            FundAmountPositionSyncUpdate(
                code: code,
                amount: 26_628.86,
                holdingIncome: 1_100,
                syncedPendingBuyAmount: nil,
                syncedAt: firstSyncAt
            )
        ])
        try await store.applyAmountPositionSyncUpdates([
            FundAmountPositionSyncUpdate(
                code: code,
                amount: 26_628.87,
                holdingIncome: 1_100.01,
                syncedPendingBuyAmount: nil,
                syncedAt: secondSyncAt
            )
        ])

        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        let fundRecords = records.filter { $0.code == code }
        XCTAssertEqual(fundRecords.count, 1)
        let baseline = try XCTUnwrap(fundRecords.first)
        XCTAssertEqual(baseline.kind, .newFund)
        XCTAssertEqual(baseline.status, .confirmed)
        XCTAssertEqual(baseline.amount ?? 0, 26_628.87, accuracy: 0.0001)
        XCTAssertEqual(baseline.profit ?? 0, 1_100.01, accuracy: 0.0001)
        XCTAssertEqual(baseline.createdAt, secondSyncAt)
        XCTAssertEqual(baseline.syncSource, .jdFinance)
        XCTAssertEqual(baseline.isReconciliationBaseline, true)
        XCTAssertFalse(records.contains { ["old-initial", "old-buy", "old-pending-buy"].contains($0.id) })
        XCTAssertEqual(records.filter { $0.code == unrelatedCode }.map(\.id), ["unrelated-initial"])
        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
    }
}
