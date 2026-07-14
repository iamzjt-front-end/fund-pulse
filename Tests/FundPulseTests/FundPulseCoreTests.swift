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

    func testAppUpdateMenuItemPresentationShowsIdleCheckAction() {
        let presentation = AppUpdateMenuItemPresentation(status: .idle, downloadProgress: 0)

        XCTAssertEqual(presentation.title, "检查更新")
        XCTAssertEqual(presentation.action, .checkForUpdates)
        XCTAssertTrue(presentation.isEnabled)
        XCTAssertNil(presentation.toolTip)
        XCTAssertFalse(presentation.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationShowsUpToDateAsDisabledLatestStatus() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = AppUpdateMenuItemPresentation(status: .upToDate(date), downloadProgress: 0)

        XCTAssertEqual(presentation.title, "已是最新版本")
        XCTAssertNil(presentation.action)
        XCTAssertFalse(presentation.isEnabled)
        XCTAssertNotNil(presentation.toolTip)
        XCTAssertFalse(presentation.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationShowsAvailableVersionAsOpenUpdateAction() throws {
        let info = try appUpdateInfo(version: "1.0.30")
        let presentation = AppUpdateMenuItemPresentation(status: .available(info), downloadProgress: 0)

        XCTAssertEqual(presentation.title, "检测到新版本")
        XCTAssertEqual(presentation.action, .openUpdate)
        XCTAssertTrue(presentation.isEnabled)
        XCTAssertEqual(presentation.toolTip, "v1.0.30 · 点击下载")
        XCTAssertFalse(presentation.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationKeepsTransientAndFailedStates() throws {
        let info = try appUpdateInfo(version: "1.0.30")
        let downloading = AppUpdateMenuItemPresentation(status: .downloading(info), downloadProgress: 0.42)
        let checking = AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 2)
        let failed = AppUpdateMenuItemPresentation(status: .failed("网络异常"), downloadProgress: 0)

        XCTAssertEqual(downloading.title, "正在下载 v1.0.30 · 42%")
        XCTAssertNil(downloading.action)
        XCTAssertFalse(downloading.isEnabled)
        XCTAssertTrue(downloading.isActiveStatus)
        XCTAssertEqual(checking.title, "正在检查更新...")
        XCTAssertNil(checking.action)
        XCTAssertFalse(checking.isEnabled)
        XCTAssertTrue(checking.isActiveStatus)
        XCTAssertEqual(failed.title, "重新检查更新")
        XCTAssertEqual(failed.action, .checkForUpdates)
        XCTAssertEqual(failed.toolTip, "网络异常")
        XCTAssertFalse(failed.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationAnimatesCheckingEllipsis() {
        XCTAssertEqual(
            AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 0).title,
            "正在检查更新."
        )
        XCTAssertEqual(
            AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 1).title,
            "正在检查更新.."
        )
        XCTAssertEqual(
            AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 2).title,
            "正在检查更新..."
        )
    }

    func testAppUpdateStatusContextMenuCheckPolicyPreservesActiveUpdateFlows() throws {
        let info = try appUpdateInfo(version: "1.0.30")
        let package = AppUpdatePackage(
            localURL: try XCTUnwrap(URL(string: "file:///tmp/fund-pulse.zip")),
            stagedAppURL: try XCTUnwrap(URL(string: "file:///tmp/fund-pulse.app")),
            downloadedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(AppUpdateStatus.idle.shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.upToDate(Date()).shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.available(info).shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.failed("网络异常").shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.checking.shouldCheckWhenOpeningContextMenu)
        XCTAssertFalse(AppUpdateStatus.downloading(info).shouldCheckWhenOpeningContextMenu)
        XCTAssertFalse(AppUpdateStatus.downloaded(info, package).shouldCheckWhenOpeningContextMenu)
        XCTAssertFalse(AppUpdateStatus.installing(info).shouldCheckWhenOpeningContextMenu)
    }

    @MainActor
    func testAppUpdateStoreStartAndFinishCheckCanApplyExternalCompletion() {
        let store = AppUpdateStore(service: appUpdateServiceWithMockResponses([:]))
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let request = store.startCheck(currentVersion: "1.0.29", mode: .interactive)

        XCTAssertEqual(store.status, .checking)
        XCTAssertEqual(request?.currentVersion, "1.0.29")
        XCTAssertEqual(request?.mode, .interactive)

        guard let request else {
            return XCTFail("Expected update check request")
        }
        store.finishCheck(request, completion: .success(.upToDate(checkedAt)))

        XCTAssertEqual(store.status, .upToDate(checkedAt))
        XCTAssertNotNil(store.lastCheckedAt)
    }

    @MainActor
    func testAppUpdateStoreExternalCompletionIgnoresStaleGeneration() throws {
        let store = AppUpdateStore(service: appUpdateServiceWithMockResponses([:]))
        let olderRequest = try XCTUnwrap(store.startCheck(currentVersion: "1.0.29", mode: .background))
        let newerRequest = try XCTUnwrap(store.startCheck(currentVersion: "1.0.29", mode: .interactive))
        let staleInfo = try appUpdateInfo(version: "1.0.30")
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.finishCheck(olderRequest, completion: .success(.available(staleInfo)))

        XCTAssertEqual(store.status, .checking)

        store.finishCheck(newerRequest, completion: .success(.upToDate(checkedAt)))

        XCTAssertEqual(store.status, .upToDate(checkedAt))
    }

    func testAppUpdateServiceInteractiveCheckReportsUpToDateFromGitHubAPI() async throws {
        let service = appUpdateServiceWithMockResponses([
            Self.githubLatestReleaseAPIEndpoint(): Self.githubReleaseResponse(version: "1.0.29")
        ])

        let status = try await service.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .upToDate = status else {
            return XCTFail("Expected GitHub API response to report up-to-date, got \(status)")
        }
    }

    func testAppUpdateServiceInteractiveCheckReportsAvailableVersionFromGitHubAPI() async throws {
        let service = appUpdateServiceWithMockResponses([
            Self.githubLatestReleaseAPIEndpoint(): Self.githubReleaseResponse(version: "1.0.30")
        ])

        let status = try await service.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .available(let info) = status else {
            return XCTFail("Expected GitHub API response to report available version, got \(status)")
        }
        XCTAssertEqual(info.version, "1.0.30")
        XCTAssertEqual(info.downloadURL?.absoluteString, Self.githubZipDownloadURL(version: "1.0.30"))
    }

    func testAppUpdateServiceInteractiveCheckFallsBackToMacReleaseFeedWhenAPIFails() async throws {
        let service = appUpdateServiceWithMockResponses(
            [
                Self.githubLatestReleaseWebEndpoint(): "",
                Self.githubMacReleaseFeedEndpoint(version: "1.0.30"): Self.macReleaseFeedResponse(version: "1.0.30")
            ],
            finalURLs: [
                Self.githubLatestReleaseWebEndpoint(): Self.githubReleaseTagURL(version: "1.0.30")
            ]
        )

        let status = try await service.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .available(let info) = status else {
            return XCTFail("Expected interactive check to fallback to mac release feed, got \(status)")
        }
        XCTAssertEqual(info.version, "1.0.30")
        XCTAssertEqual(info.downloadURL?.absoluteString, Self.githubZipDownloadURL(version: "1.0.30"))
    }

    func testAppUpdateServiceInteractiveCheckUsesHardTimeout() async {
        MockURLProtocol.responseStore.set([
            Self.githubLatestReleaseAPIEndpoint(): Data(Self.githubReleaseResponse(version: "1.0.29").utf8)
        ])
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 300_000_000)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            interactiveAPIRequestTimeout: 0.05
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.check(currentVersion: "1.0.29", mode: .interactive)
        } errorHandler: { error in
            XCTAssertEqual(error.localizedDescription, "检查更新超时，请稍后重试")
        }
    }

    @MainActor
    func testAppUpdateStoreInteractiveCheckSupersedesBackgroundChecking() async throws {
        let service = appUpdateServiceWithMockResponses([
            Self.githubLatestReleaseAPIEndpoint(): Self.githubReleaseResponse(version: "1.0.30")
        ])
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 300_000_000)
        let store = AppUpdateStore(service: service)

        let backgroundTask = Task {
            await store.check(currentVersion: "1.0.29", mode: .background)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.status, .checking)

        MockURLProtocol.responseStore.set([
            Self.githubLatestReleaseAPIEndpoint(): Data(Self.githubReleaseResponse(version: "1.0.29").utf8)
        ])
        await store.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .upToDate = store.status else {
            return XCTFail("Expected interactive check to supersede background checking, got \(store.status)")
        }

        await backgroundTask.value
        guard case .upToDate = store.status else {
            return XCTFail("Expected stale background result to be ignored, got \(store.status)")
        }
    }

    func testAppUpdateServiceBackgroundCheckFallsBackToMacReleaseFeedWhenAPIFails() async throws {
        let service = appUpdateServiceWithMockResponses(
            [
                Self.githubLatestReleaseWebEndpoint(): "",
                Self.githubMacReleaseFeedEndpoint(version: "1.0.29"): Self.macReleaseFeedResponse(version: "1.0.29")
            ],
            finalURLs: [
                Self.githubLatestReleaseWebEndpoint(): Self.githubReleaseTagURL(version: "1.0.29")
            ]
        )

        let status = try await service.check(currentVersion: "1.0.29", mode: .background)

        guard case .upToDate = status else {
            return XCTFail("Expected background check to fallback to mac release feed, got \(status)")
        }
    }

    func testFundCodeFormatterDisplaysCodeWithoutHashPrefix() {
        XCTAssertEqual(FundCodeFormatter.display("024418"), "024418")
        XCTAssertEqual(FundCodeFormatter.display("#024418"), "024418")
        XCTAssertEqual(FundCodeFormatter.display("  #024418  "), "024418")
        XCTAssertEqual(FundCodeFormatter.display(""), "--")
    }

    func testJDFinanceFundCodeMapperDoesNotInferJDProductIDs() {
        XCTAssertNil(JDFinanceFundCodeMapper.inferCode(from: "1024424"))
        XCTAssertNil(JDFinanceFundCodeMapper.inferCode(from: "1008998"))
        XCTAssertNil(JDFinanceFundCodeMapper.inferCode(from: "113687"))
        XCTAssertNil(JDFinanceFundCodeMapper.inferCode(from: "1013284"))
        XCTAssertNil(JDFinanceFundCodeMapper.inferCode(from: "109922"))
        XCTAssertEqual(JDFinanceFundCodeMapper.inferCode(from: "024418"), "024418")
    }

    func testJDFinanceHoldingsParserReadsNestedFundHoldGroupResponse() throws {
        let snapshot = try JDFinanceHoldingsParser.parse(data: Data(Self.jdFinanceHoldingsResponse.utf8))

        XCTAssertEqual(snapshot.totalAssets ?? 0, 171_461.84, accuracy: 0.0001)
        XCTAssertEqual(snapshot.holdIncome ?? 0, -9_222.66, accuracy: 0.0001)
        XCTAssertEqual(snapshot.totalIncome ?? 0, -5_425.17, accuracy: 0.0001)
        XCTAssertEqual(snapshot.products.count, 2)

        let first = try XCTUnwrap(snapshot.products.first)
        XCTAssertEqual(first.skuID, "1024424")
        XCTAssertEqual(first.code, "024424")
        XCTAssertEqual(first.codeResolution, .explicit)
        XCTAssertEqual(first.name, "永赢先进制造智选混合发起A")
        XCTAssertEqual(first.totalAmount, 19_907.79, accuracy: 0.0001)
        XCTAssertEqual(first.yesterdayIncome ?? 0, -688.41, accuracy: 0.0001)
        XCTAssertEqual(first.holdIncome ?? 0, -734.13, accuracy: 0.0001)
        XCTAssertEqual(first.holdRate ?? 0, -3.56, accuracy: 0.0001)

        let second = try XCTUnwrap(snapshot.products.last)
        XCTAssertEqual(second.code, "011833")
        XCTAssertEqual(second.transactionTipText, "买入确认中")
    }

    func testJDFinanceHoldingsParserPrefersExplicitFundCodeOverSkuID() throws {
        let response = """
        {"success":true,"resultData":{"success":true,"resultData":{"headAssetsData":{},"fundData":{"fundList":[{"productList":[{"skuId":"113687","fundCode":"011833","productName":"西部利得人工智能主题指数增强C","totalAmount":"7632.07"}]}]}}}}
        """

        let snapshot = try JDFinanceHoldingsParser.parse(data: Data(response.utf8))

        XCTAssertEqual(snapshot.products.first?.skuID, "113687")
        XCTAssertEqual(snapshot.products.first?.code, "011833")
    }

    func testJDFinanceHoldingsParserMarksProductWithoutExplicitCodeAsUnresolved() throws {
        let response = """
        {"success":true,"resultData":{"success":true,"resultData":{"headAssetsData":{},"fundData":{"fundList":[{"productList":[{"skuId":"113387","productName":"华商均衡成长混合C","totalAmount":"14019.17","holdIncome":"-1980.83"}]}]}}}}
        """

        let snapshot = try JDFinanceHoldingsParser.parse(data: Data(response.utf8))
        let product = try XCTUnwrap(snapshot.products.first)

        XCTAssertEqual(product.skuID, "113387")
        XCTAssertEqual(product.code, "")
        XCTAssertEqual(product.codeResolution, .unresolved)
        XCTAssertFalse(product.isCodeResolved)
        XCTAssertEqual(product.name, "华商均衡成长混合C")
    }

    func testJDFinanceHoldingsParserReadsTransactionTipObjectAndDetailRequest() throws {
        let snapshot = try JDFinanceHoldingsParser.parse(data: Data(Self.jdFinancePendingHoldingsResponse.utf8))
        let product = try XCTUnwrap(snapshot.products.first)

        XCTAssertNil(product.yesterdayIncome)
        XCTAssertEqual(product.yesterdayIncomeNotice, "预计08日更新")
        XCTAssertEqual(product.transactionTip?.text, "交易：1笔买入中合计7632.07元")
        XCTAssertEqual(product.transactionTip?.action, .buy)
        XCTAssertEqual(product.transactionTip?.tradeCount, 1)
        XCTAssertEqual(product.transactionTip?.totalAmount ?? 0, 7_632.07, accuracy: 0.0001)
        XCTAssertEqual(product.detailRequest?.extJSON, #"{"source":"pending-detail"}"#)
    }

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

    func testJDFinanceTradeOrderParserDoesNotTreatProductIDAsFundCode() throws {
        let response = """
        {
          "resultCode": 0,
          "resultData": {
            "code": "0000",
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "1024424",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "BUY",
                  "allAmount": "¥ 1,000.00",
                  "bizTime": "2026-07-03 14:35:12",
                  "statusName": "买入确认中",
                  "orderId": "secret-order"
                }
              ]
            }
          }
        }
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))
        let record = try XCTUnwrap(records.first)

        XCTAssertNil(record.code)
        XCTAssertEqual(record.productName, "东方阿尔法科技优选混合发起C")
        XCTAssertEqual(record.action, .buy)
        XCTAssertEqual(record.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(record.tradeDate, "2026-07-03")
        XCTAssertEqual(record.tradeTimeType, .before15)
        XCTAssertEqual(record.submittedAt, "2026-07-03 14:35:12")
        XCTAssertEqual(record.effectiveStatus, .pending)
        XCTAssertNotNil(record.stableOrderKey)
        XCTAssertFalse(record.stableOrderKey?.contains("secret-order") ?? true)
        XCTAssertEqual(record.statusText, "买入确认中")
    }

    func testJDFinanceTradeOrderStatusOnlyAllowsConfirmedFundStatesToSucceed() {
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("确认成功"), .succeeded)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("订单完成"), .succeeded)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("赎回成功"), .succeeded)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify(statusCode: "REDEEM_SUCC", statusText: "转出完成"), .succeeded)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("支付成功"), .pending)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("PAY_SUCCESS"), .pending)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify(statusCode: "PAY_SUCC", statusText: "支付成功"), .pending)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("处理中"), .pending)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("退款完成"), .cancelled)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify(statusCode: "REFUND_SUCC", statusText: "退款完成"), .cancelled)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("交易失败"), .failed)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify("新的未知状态"), .unknown)
        XCTAssertEqual(JDFinanceTradeOrderStatus.classify(nil), .unknown)
    }

    func testJDFinanceTradeOrderParserKeepsSameValueOrdersWithDifferentOrderIDs() throws {
        let response = """
        {"resultCode":0,"resultData":{"data":{"orderList":[
          {"orderId":"order-a","productCode":"013284","fundName":"上银价值增长3个月持有期混合A","tradeTypeCode":"TRANSFER_IN","applyAmount":"1,000.00","orderCreateTime":"2026-07-13 10:00:00","statusName":"确认成功"},
          {"orderId":"order-b","productCode":"013284","fundName":"上银价值增长3个月持有期混合A","tradeTypeCode":"TRANSFER_IN","applyAmount":"1,000.00","orderCreateTime":"2026-07-13 10:00:00","statusName":"确认成功"}
        ]}}}
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.compactMap(\.stableOrderKey)).count, 2)
        XCTAssertTrue(records.allSatisfy { record in
            guard let key = record.stableOrderKey,
                  key.hasPrefix("jd-order-")
            else {
                return false
            }
            return key.dropFirst("jd-order-".count).allSatisfy(\.isHexDigit)
        })
    }

    func testJDFinanceTradeOrderParserNormalizesMinutePrecisionSubmissionTime() throws {
        let response = """
        {"resultCode":0,"resultData":{"data":{"orderList":[
          {"productCode":"013284","fundName":"上银价值增长3个月持有期混合A","tradeTypeCode":"TRANSFER_IN","applyAmount":"1,000.00","orderCreateTime":"2026-07-13 10:05","statusName":"确认成功"}
        ]}}}
        """

        let record = try XCTUnwrap(JDFinanceTradeOrderParser.parse(data: Data(response.utf8)).first)

        XCTAssertEqual(record.submittedAt, "2026-07-13 10:05:00")
    }

    func testJDFinanceTradeOrderParserCombinesSplitTradeDateAndTime() throws {
        let response = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "1024424",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "BUY",
                  "allAmount": "¥ 1,000.00",
                  "tradeDate": "2026-07-03",
                  "tradeTime": "14点35分",
                  "statusName": "买入确认中"
                }
              ]
            }
          }
        }
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))
        let record = try XCTUnwrap(records.first)

        XCTAssertNil(record.code)
        XCTAssertEqual(record.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(record.tradeDate, "2026-07-03")
        XCTAssertEqual(record.tradeTimeType, .before15)
    }

    func testJDFinanceTradeOrderParserReadsRowsFromStringWrappedResultData() throws {
        let embedded = #"""
        {"data":{"tradeOrderVoList":[{"productId":"1024424","productName":"东方阿尔法科技优选混合发起C","tradeTypeCode":"BUY","allAmount":"1000.00元","bizTime":"2026-07-03 14:35:12","statusName":"买入确认中"}]}}
        """#
        let response = """
        {
          "resultCode": 0,
          "resultData": \(try jsonStringLiteral(embedded))
        }
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))
        let record = try XCTUnwrap(records.first)

        XCTAssertNil(record.code)
        XCTAssertEqual(record.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(record.tradeDate, "2026-07-03")
        XCTAssertEqual(record.tradeTimeType, .before15)
    }

    func testJDFinanceTradeOrderEndpointMatchesWebTradeRecordPage() {
        XCTAssertTrue(JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString.contains("/cfGateway/newna/m/queryTradeOrderList"))
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

    func testJDFinanceTradeOrderProductScopedPayloadMatchesWebTradeRecordPage() throws {
        let product = JDFinanceHoldingProduct(
            skuID: "1025500",
            code: "025500",
            name: "东方阿尔法科技智选混合发起C",
            totalAmount: 3_000,
            transactionTip: JDFinanceTransactionTip(
                text: "交易：2笔买入中合计3000.00元",
                action: .buy,
                tradeCount: 2,
                totalAmount: 3_000
            )
        )
        let now = try chinaDate("2026-07-06 11:49")

        let payload = try JDFinanceHoldingsService.tradeOrderRequestPayload(
            page: 1,
            now: now,
            product: product
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["businessCode"] as? String, "FUND")
        XCTAssertEqual(object["pageNo"] as? Int, 1)
        XCTAssertEqual(object["busProductId"] as? String, "1025500")
        XCTAssertEqual(object["productId"] as? String, "1025500")
        XCTAssertEqual(object["productCode"] as? String, "025500")
        XCTAssertEqual(object["fundCode"] as? String, "025500")
    }

    func testJDFinanceTradeOrderProductScopedPayloadOmitsUnresolvedFundCode() throws {
        let product = JDFinanceHoldingProduct(
            skuID: "113387",
            code: "",
            codeResolution: .unresolved,
            name: "华商均衡成长混合C",
            totalAmount: 14_019.17
        )

        let payload = try JDFinanceHoldingsService.tradeOrderRequestPayload(
            page: 1,
            now: try chinaDate("2026-07-08 14:38"),
            product: product
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["busProductId"] as? String, "113387")
        XCTAssertEqual(object["productId"] as? String, "113387")
        XCTAssertNil(object["productCode"])
        XCTAssertNil(object["fundCode"])
    }

    func testJDFinanceTradeOrderPayloadUsesNinetyDaysAndCanTraceOlderWaitingRecord() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let defaultPayload = try JDFinanceHoldingsService.tradeOrderRequestPayload(page: 1, now: now)
        let defaultObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(defaultPayload.utf8)) as? [String: Any]
        )
        XCTAssertEqual(defaultObject["clientType"] as? String, "h5")
        XCTAssertEqual(defaultObject["clientVersion"] as? String, "999.999.999")
        XCTAssertEqual(defaultObject["orderCreateStartDate"] as? String, "2026-04-15 00:00:00")

        let tracedPayload = try JDFinanceHoldingsService.tradeOrderRequestPayload(
            page: 1,
            now: now,
            startDate: "2025-12-01"
        )
        let tracedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(tracedPayload.utf8)) as? [String: Any]
        )
        XCTAssertEqual(tracedObject["orderCreateStartDate"] as? String, "2025-12-01 00:00:00")
    }

    func testJDFinanceTradeOrderParserReadsGenericTradeRows() throws {
        let response = """
        {
          "success": true,
          "resultData": {
            "data": {
              "orderList": [
                {
                  "productCode": "025500",
                  "fundName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "applyAmount": "¥ 3,000.00",
                  "orderCreateTime": "2026/07/03 14:12:59",
                  "statusName": "支付成功"
                }
              ]
            }
          }
        }
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.code, "025500")
        XCTAssertEqual(record.productName, "东方阿尔法科技智选混合发起C")
        XCTAssertEqual(record.action, .buy)
        XCTAssertEqual(record.amount ?? 0, 3_000, accuracy: 0.0001)
        XCTAssertEqual(record.tradeDate, "2026-07-03")
        XCTAssertEqual(record.tradeTimeType, .before15)
        XCTAssertEqual(record.statusText, "支付成功")
    }

    func testJDFinanceTradeOrderParserReadsConversionRows() throws {
        let response = """
        {
          "success": true,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "109922",
                  "productCode": "009922",
                  "productName": "转换-国泰中证全指通信设备ETF联接C",
                  "sellProductName": "华夏上证科创板半导体材料设备主题ETF发起式联接C",
                  "sellProductId": "113284",
                  "tradeTypeName": "转换",
                  "tradeTypeCode": "TRANSFORM",
                  "allAmount": "¥ 971.77",
                  "bizTime": "2026-07-07 15:00前",
                  "statusName": "处理中"
                }
              ]
            }
          }
        }
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.code, "009922")
        XCTAssertEqual(record.productName, "转换-国泰中证全指通信设备ETF联接C")
        XCTAssertNil(record.conversionTargetCode)
        XCTAssertEqual(record.conversionTargetName, "华夏上证科创板半导体材料设备主题ETF发起式联接C")
        XCTAssertEqual(record.action, .conversion)
        XCTAssertEqual(record.amount ?? 0, 971.77, accuracy: 0.0001)
        XCTAssertNil(record.shares)
        XCTAssertEqual(record.tradeDate, "2026-07-07")
        XCTAssertEqual(record.tradeTimeType, .before15)
        XCTAssertEqual(record.statusText, "处理中")
    }

    func testJDFinanceTradeOrderParserDoesNotTreatRedeemAmountAsSharesWhenShareFieldIsMissing() throws {
        let response = """
        {
          "success": true,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "1008998",
                  "productCode": "008998",
                  "productName": "转出-同泰竞争优势混合C",
                  "tradeTypeName": "卖出",
                  "tradeTypeCode": "TRANSFER_OUT",
                  "allAmount": "¥ 7,171.54",
                  "bizTime": "2026-07-07 15:00前",
                  "statusName": "转出中"
                }
              ]
            }
          }
        }
        """

        let records = try JDFinanceTradeOrderParser.parse(data: Data(response.utf8))
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.code, "008998")
        XCTAssertEqual(record.productName, "转出-同泰竞争优势混合C")
        XCTAssertEqual(record.action, .sell)
        XCTAssertEqual(record.amount ?? 0, 7_171.54, accuracy: 0.0001)
        XCTAssertNil(record.shares)
        XCTAssertEqual(record.tradeDate, "2026-07-07")
        XCTAssertEqual(record.tradeTimeType, .before15)
        XCTAssertEqual(record.statusText, "转出中")
    }

    func testJDFinanceHoldingsServiceFillsPendingTimeFromTradeOrderList() async throws {
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
              "headAssetsData": {
                "totalAssets": { "text": "20,686.71" },
                "holdIncome": { "text": "-919.26" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1024424",
                        "fundCode": "024424",
                        "productName": "东方阿尔法科技优选混合发起C",
                        "totalAmount": { "text": "20,686.71" },
                        "yesterdayIncome": { "text": "预计08日更新" },
                        "holdIncome": { "text": "-919.26" },
                        "transactionTip": { "text": "交易：1笔买入中合计1000.00元" },
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
                "tradeAmount": "1000.00",
                "tradeStatus": "买入确认中"
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
                  "productId": "113387",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "1000.00",
                  "bizTime": "2026-07-02 14:35:12",
                  "statusName": "退款完成"
                },
                {
                  "productId": "113387",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 1,000.00",
                  "bizTime": "2026.07.03 14:35:12",
                  "statusName": "支付成功"
                },
                {
                  "productId": "1024424",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "BUY",
                  "allAmount": "2000.00",
                  "bizTime": "2026-07-02 14:35:12",
                  "statusName": "买入确认中"
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

        XCTAssertEqual(detail.action, .buy)
        XCTAssertEqual(detail.amount ?? 0, 1_000, accuracy: 0.0001)
        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
    }

    func testJDFinanceHoldingsServiceFallsBackToLegacyTradeOrderEndpoint() async throws {
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
              "headAssetsData": {
                "totalAssets": { "text": "20,686.71" },
                "holdIncome": { "text": "-919.26" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1024424",
                        "fundCode": "024424",
                        "productName": "东方阿尔法科技优选混合发起C",
                        "totalAmount": { "text": "20,686.71" },
                        "yesterdayIncome": { "text": "预计08日更新" },
                        "holdIncome": { "text": "-919.26" },
                        "transactionTip": { "text": "交易：1笔买入中合计1000.00元" },
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
                "tradeAmount": "1000.00",
                "tradeStatus": "买入确认中"
              }
            }
          }
        }
        """
        let emptyTradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": []
            }
          }
        }
        """
        let legacyTradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "1024424",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 1,000.00",
                  "bizTime": "2026-07-03 14:35:12",
                  "statusName": "支付成功"
                }
              ]
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: holdingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: emptyTradeOrderResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: legacyTradeOrderResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
    }

    func testJDFinanceHoldingsServiceMergesLegacyTradeOrderWhenNewEndpointHasOtherRecords() async throws {
        let detailResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "detail": {
                "tradeType": "买入",
                "tradeAmount": "7632.07",
                "tradeStatus": "买入确认中"
              }
            }
          }
        }
        """
        let newTradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "1024424",
                  "productName": "东方阿尔法科技优选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 1,000.00",
                  "bizTime": "2026-07-03 14:35:12",
                  "statusName": "支付成功"
                }
              ]
            }
          }
        }
        """
        let legacyTradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productName": "西部利得人工智能主题指数增强C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 7,632.07",
                  "bizTime": "2026-07-03 14:35:12",
                  "statusName": "支付成功"
                }
              ]
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
            JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse,
            JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: newTradeOrderResponse,
            JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: legacyTradeOrderResponse
        ])

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.matchedTradeRecords.count, 1)
    }

    func testJDFinanceHoldingsServiceFillsPendingTimeFromProductScopedTradeOrderList() async throws {
        let detailResponse = """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "resultData": {
              "detail": {
                "tradeType": "买入",
                "tradeAmount": "7632.07",
                "tradeStatus": "买入确认中"
              }
            }
          }
        }
        """
        let emptyTradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": []
            }
          }
        }
        """
        let productScopedTradeOrderResponse = """
        {
          "resultCode": 0,
          "resultData": {
            "data": {
              "tradeOrderVoList": [
                {
                  "productId": "113687",
                  "productName": "西部利得人工智能主题指数增强C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 7,632.07",
                  "bizTime": "2026-07-03 14:35:12",
                  "statusName": "支付成功"
                }
              ]
            }
          }
        }
        """
        let service = jdFinanceServiceWithMockResponses(
            [
                JDFinanceHoldingsService.endpoint.absoluteString: Self.jdFinancePendingHoldingsResponse,
                JDFinanceHoldingsService.detailEndpoint.absoluteString: detailResponse,
                JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString: emptyTradeOrderResponse,
                JDFinanceHoldingsService.legacyTradeOrderListEndpoint.absoluteString: emptyTradeOrderResponse
            ],
            bodyResponses: [
                MockBodyResponseRule(
                    urlPrefix: JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString,
                    bodyContains: "productId",
                    data: Data(productScopedTradeOrderResponse.utf8)
                )
            ]
        )

        let snapshot = try await service.fetchSnapshot(cookieHeader: "pt_key=abc; pt_pin=test")
        let detail = try XCTUnwrap(snapshot.products.first?.pendingDetail)

        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.matchedTradeRecords.count, 1)
    }

    func testJDFinanceHoldingsServiceFillsPendingTimeFromGroupedTradeOrderList() async throws {
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
              "headAssetsData": {
                "totalAssets": { "text": "3,000.00" },
                "holdIncome": { "text": "0.00" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1025500",
                        "fundCode": "025500",
                        "productName": "东方阿尔法科技智选混合发起C",
                        "totalAmount": { "text": "3,000.00" },
                        "yesterdayIncome": { "text": "预计08日更新" },
                        "holdIncome": { "text": "0.00" },
                        "transactionTip": { "text": "交易：2笔买入中合计3000.00元" },
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
                "tradeAmount": "3000.00",
                "tradeStatus": "买入确认中"
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
                  "productId": "1025500",
                  "productName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 1,000.00",
                  "bizTime": "2026-07-03 14:21:12",
                  "statusName": "支付成功"
                },
                {
                  "productId": "1025500",
                  "productName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 2,000.00",
                  "bizTime": "2026-07-03 14:35:12",
                  "statusName": "支付成功"
                },
                {
                  "productId": "1025500",
                  "productName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 3,000.00",
                  "bizTime": "2026-07-02 10:35:12",
                  "statusName": "退款完成"
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

        XCTAssertEqual(detail.action, .buy)
        XCTAssertEqual(detail.amount ?? 0, 3_000, accuracy: 0.0001)
        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.statusText, "匹配交易记录：2 笔，2026-07-03 15:00前")
    }

    func testJDFinanceHoldingsServiceFillsPendingTimeFromAggregateTradeOrderRecord() async throws {
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
              "headAssetsData": {
                "totalAssets": { "text": "3,000.00" },
                "holdIncome": { "text": "0.00" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1025500",
                        "fundCode": "025500",
                        "productName": "东方阿尔法科技智选混合发起C",
                        "totalAmount": { "text": "3,000.00" },
                        "yesterdayIncome": { "text": "预计08日更新" },
                        "holdIncome": { "text": "0.00" },
                        "transactionTip": { "text": "交易：2笔买入中合计3000.00元" },
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
                "tradeAmount": "3000.00",
                "tradeStatus": "买入确认中"
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
                  "productId": "1025500",
                  "productName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 3,000.00",
                  "bizTime": "2026-07-03 14:18:12",
                  "statusName": "支付成功"
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

        XCTAssertEqual(detail.action, .buy)
        XCTAssertEqual(detail.amount ?? 0, 3_000, accuracy: 0.0001)
        XCTAssertEqual(detail.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.tradeTimeType, .before15)
        XCTAssertEqual(detail.statusText, "买入确认中")
    }

    func testJDFinanceHoldingsServiceKeepsMultipleMatchedTradeOrderRecordsWhenTimesDiffer() async throws {
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
              "headAssetsData": {
                "totalAssets": { "text": "3,000.00" },
                "holdIncome": { "text": "0.00" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1025500",
                        "fundCode": "025500",
                        "productName": "东方阿尔法科技智选混合发起C",
                        "totalAmount": { "text": "3,000.00" },
                        "yesterdayIncome": { "text": "预计08日更新" },
                        "holdIncome": { "text": "0.00" },
                        "transactionTip": { "text": "交易：2笔买入中合计3000.00元" },
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
                "tradeAmount": "3000.00",
                "tradeStatus": "买入确认中"
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
                  "productId": "1025500",
                  "productName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 1,000.00",
                  "bizTime": "2026-07-03 14:18:12",
                  "statusName": "支付成功"
                },
                {
                  "productId": "1025500",
                  "productName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "allAmount": "¥ 2,000.00",
                  "bizTime": "2026-07-04 15:18:12",
                  "statusName": "支付成功"
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
        XCTAssertNil(detail.tradeTimeType)
        XCTAssertEqual(detail.statusText, "匹配交易记录：2 笔")
        XCTAssertEqual(detail.matchedTradeRecords.count, 2)
        XCTAssertEqual(detail.matchedTradeRecords.map(\.tradeDate), ["2026-07-03", "2026-07-04"])
        XCTAssertEqual(detail.matchedTradeRecords.map(\.tradeTimeType), [.before15, .after15])
        XCTAssertEqual(detail.matchedTradeRecords.compactMap(\.amount).reduce(0, +), 3_000, accuracy: 0.0001)
    }

    func testJDFinanceHoldingsServiceExplainsUnmatchedGroupedTradeOrderList() async throws {
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
              "headAssetsData": {
                "totalAssets": { "text": "3,000.00" },
                "holdIncome": { "text": "0.00" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "skuId": "1025500",
                        "fundCode": "025500",
                        "productName": "东方阿尔法科技智选混合发起C",
                        "totalAmount": { "text": "3,000.00" },
                        "yesterdayIncome": { "text": "预计08日更新" },
                        "holdIncome": { "text": "0.00" },
                        "transactionTip": { "text": "交易：2笔买入中合计3000.00元" },
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
                "tradeAmount": "3000.00",
                "tradeStatus": "买入确认中"
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
              "orderList": [
                {
                  "productCode": "025500",
                  "fundName": "东方阿尔法科技智选混合发起C",
                  "tradeTypeCode": "TRANSFER_IN",
                  "applyAmount": "¥ 1,000.00",
                  "orderCreateTime": "2026-07-03 14:21:12",
                  "statusName": "支付成功"
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
        XCTAssertNil(detail.tradeTimeType)
        XCTAssertTrue(detail.statusText?.contains("已查交易记录") ?? false)
        XCTAssertTrue(detail.statusText?.contains("未匹配到 2 笔") ?? false)
        XCTAssertEqual(detail.candidateTradeRecords.count, 1)
        XCTAssertEqual(detail.candidateTradeRecords.first?.tradeDate, "2026-07-03")
        XCTAssertEqual(detail.candidateTradeRecords.first?.tradeTimeType, .before15)
        XCTAssertEqual(detail.candidateTradeRecords.first?.amount ?? 0, 1_000, accuracy: 0.0001)
    }

    @MainActor
    func testJDFinanceNetworkProbeRedactsSensitiveFields() throws {
        let probe = JDFinanceNetworkProbe()
        let url = try XCTUnwrap(URL(
            string: "https://ms.jr.jd.com/gw/generic/jj/newna/m/getNewFundPositionDetail?reqData=secret-ext-json"
        ))
        let response = """
        {
          "token": "secret-token",
          "cookie": "pt_key=secret-cookie",
          "orderId": "secret-order",
          "resultData": {
            "fundCode": "024424",
            "tradeAmount": "1000.00",
            "applyTime": "2026-07-03 14:35:12",
            "tradeStatus": "买入确认中",
            "extJson": "{\\"orderId\\":\\"secret\\"}"
          }
        }
        """

        probe.recordURLSession(
            endpoint: "getNewFundPositionDetail",
            url: url,
            statusCode: 200,
            data: Data(response.utf8)
        )

        let entry = try XCTUnwrap(probe.entries.first)
        let joined = ([entry.path] + entry.topLevelKeys + entry.fieldSummaries).joined(separator: " ")

        XCTAssertEqual(entry.statusCode, 200)
        XCTAssertFalse(entry.path.contains("reqData"))
        XCTAssertFalse(joined.contains("secret-token"))
        XCTAssertFalse(joined.contains("secret-cookie"))
        XCTAssertFalse(joined.contains("secret-order"))
        XCTAssertFalse(joined.lowercased().contains("extjson"))
        XCTAssertTrue(joined.contains("024424"))
        XCTAssertTrue(joined.contains("1,000.00") || joined.contains("1000.00"))
        XCTAssertTrue(joined.contains("2026-07-03"))
        XCTAssertTrue(joined.contains("15:00前"))
    }

    @MainActor
    func testJDFinanceNetworkProbePrioritizesAccountTotalAssets() throws {
        let probe = JDFinanceNetworkProbe()
        let url = try XCTUnwrap(URL(string: "https://ms.jr.jd.com/gw/generic/base/h5/m/fundHoldGroup"))
        let response = """
        {
          "success": true,
          "resultData": {
            "resultData": {
              "headAssetsData": {
                "totalAssets": { "amt": 306651.24, "text": "306,651.24" },
                "holdIncome": { "text": "-15,289.46" },
                "todayIncome": { "text": "5,400.02" }
              },
              "fundData": {
                "fundList": [
                  {
                    "productList": [
                      {
                        "productName": "国金中证A500指数增强A",
                        "totalAmount": { "text": "118,674.41" }
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
        """

        probe.recordURLSession(
            endpoint: "fundHoldGroup",
            url: url,
            statusCode: 200,
            data: Data(response.utf8)
        )

        let entry = try XCTUnwrap(probe.entries.first)
        let joined = entry.fieldSummaries.joined(separator: " ")
        XCTAssertTrue(joined.contains("账户总金额"))
        XCTAssertTrue(joined.contains("306,651.24"))
        XCTAssertTrue(joined.contains("账户持有收益"))
        XCTAssertTrue(joined.contains("账户今日收益"))
    }

    @MainActor
    func testJDFinanceNetworkProbeCapturesTradeOrderListFields() throws {
        let probe = JDFinanceNetworkProbe()
        let payload: [String: Any] = [
            "url": "https://ms.jr.jd.com/gw2/generic/cfGateway/newna/m/queryTradeOrderList",
            "method": "POST",
            "status": 200,
            "body": """
            {
              "success": true,
              "data": {
                "tradeOrderVoList": [
                  {
                    "bizTime": "2026-07-02 10:35:12",
                    "productName": "无关基金A",
                    "allAmount": "999.00",
                    "statusName": "支付成功",
                    "tradeTypeCode": "TRANSFER_IN"
                  },
                  {
                    "bizTime": "2026-07-03 14:35:12",
                    "currentTime": "07-03 14:35:12",
                    "productId": "1025500",
                    "productCode": "025500",
                    "productName": "东方阿尔法科技智选混合发起C",
                    "allAmount": "1000.00",
                    "statusName": "支付成功",
                    "tradeTypeCode": "TRANSFER_IN",
                    "orderId": "secret-order"
                  },
                  {
                    "bizTime": "2026-07-03 14:42:12",
                    "productId": "1025500",
                    "productCode": "025500",
                    "productName": "东方阿尔法科技智选混合发起C",
                    "allAmount": "2000.00",
                    "statusName": "支付成功",
                    "tradeTypeCode": "TRANSFER_IN"
                  }
                ]
              }
            }
            """
        ]

        probe.setTargets([
            JDFinanceNetworkProbeTarget(code: "025500", name: "东方阿尔法科技智选混合发起C", amount: 3_000)
        ])
        probe.recordWebViewPayload(payload)

        let entry = try XCTUnwrap(probe.entries.first)
        let joined = ([entry.path] + entry.topLevelKeys + entry.fieldSummaries).joined(separator: " ")

        XCTAssertEqual(entry.method, "POST")
        XCTAssertEqual(entry.statusCode, 200)
        XCTAssertTrue(entry.isVisibleInCapturePanel)
        XCTAssertTrue(entry.isTradeOrderEndpoint)
        XCTAssertTrue(joined.contains("queryTradeOrderList"))
        XCTAssertTrue(joined.contains("025500"))
        XCTAssertTrue(joined.contains("东方阿尔法科技智选混合发起C"))
        XCTAssertTrue(joined.contains("1,000.00") || joined.contains("1000.00"))
        XCTAssertTrue(joined.contains("2,000.00") || joined.contains("2000.00"))
        XCTAssertTrue(joined.contains("2026-07-03"))
        XCTAssertTrue(joined.contains("15:00前"))
        XCTAssertTrue(joined.contains("支付成功"))
        XCTAssertTrue(joined.contains("TRANSFER_IN"))
        XCTAssertFalse(joined.contains("无关基金A"))
        XCTAssertFalse(joined.contains("secret-order"))
        XCTAssertFalse(joined.lowercased().contains("orderid"))
    }

    @MainActor
    func testJDFinanceNetworkProbeCapturesTradeOrderRequestFields() throws {
        let probe = JDFinanceNetworkProbe()
        let requestBody = try XCTUnwrap("""
        reqData={"businessCode":"FUND","pageNo":1,"pageType":"na","busProductId":"1025500","productId":"1025500","productCode":"025500","fundCode":"025500","orderCreateStartDate":"2016-07-06 00:00:00","orderCreateEndDate":"2026-07-06 23:59:59","token":"secret-token","orderId":"secret-order"}
        """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))
        let payload: [String: Any] = [
            "url": "https://ms.jr.jd.com/gw2/generic/cfGateway/newna/m/queryTradeOrderList",
            "method": "POST",
            "status": 200,
            "requestBody": requestBody,
            "body": #"{"resultCode":0,"data":{"tradeOrderVoList":[]}}"#
        ]

        probe.recordWebViewPayload(payload)

        let entry = try XCTUnwrap(probe.entries.first)
        let joined = ([entry.path] + entry.topLevelKeys + entry.fieldSummaries).joined(separator: " ")

        XCTAssertTrue(joined.contains("请求.businessCode: FUND"))
        XCTAssertTrue(joined.contains("请求.pageNo: 1"))
        XCTAssertTrue(joined.contains("请求.busProductId: 1025500"))
        XCTAssertTrue(joined.contains("请求.productId: 1025500"))
        XCTAssertTrue(joined.contains("请求.productCode: 025500"))
        XCTAssertTrue(joined.contains("请求.fundCode: 025500"))
        XCTAssertTrue(joined.contains("请求.orderCreateStartDate: 2016-07-06"))
        XCTAssertTrue(joined.contains("请求.orderCreateEndDate: 2026-07-06"))
        XCTAssertFalse(joined.contains("secret-token"))
        XCTAssertFalse(joined.contains("secret-order"))
        XCTAssertFalse(joined.lowercased().contains("orderid"))
    }

    @MainActor
    func testJDFinanceNetworkProbeIgnoresKeyOnlyNoise() throws {
        let probe = JDFinanceNetworkProbe()
        let url = try XCTUnwrap(URL(
            string: "https://ms.jr.jd.com/gw/generic/jj/newna/m/getNewFundPositionDetail"
        ))
        let response = """
        {"resultCode":"0","resultMsg":"success","success":true}
        """

        probe.recordURLSession(
            endpoint: "getNewFundPositionDetail",
            url: url,
            statusCode: 200,
            data: Data(response.utf8)
        )

        XCTAssertTrue(probe.entries.isEmpty)
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

        XCTAssertEqual(portfolioStore.snapshot.totalAmount, 200)
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
    func testJDFinanceSyncStoreResolvesMissingCodeByExactFundName() async throws {
        let response = """
        {"success":true,"resultCode":0,"resultMsg":"success","resultData":{"success":true,"resultData":{"headAssetsData":{"totalAssets":{"text":"14,019.17"},"holdIncome":{"text":"-1,980.83"}},"fundData":{"fundList":[{"productList":[{"skuId":"113387","productName":"华商均衡成长混合C","totalAmount":{"text":"14,019.17"},"holdIncome":{"text":"-1,980.83"}}]}]}}}}
        """
        let service = jdFinanceServiceWithMockResponses([
            JDFinanceHoldingsService.endpoint.absoluteString: response
        ])
        let syncStore = JDFinanceHoldingsSyncStore(
            service: service,
            codeResolver: JDFinanceFundCodeResolver { name in
                name == "华商均衡成长混合C" ? "011370" : nil
            }
        )
        let portfolioStore = PortfolioStore(
            dataDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        await syncStore.synchronize(
            portfolioStore: portfolioStore,
            cookieHeader: "pt_key=abc; pt_pin=test"
        )

        let preview = try XCTUnwrap(syncStore.preview)
        XCTAssertEqual(preview.remoteSnapshot.products.map(\.code), ["011370"])
        XCTAssertEqual(preview.remoteSnapshot.products.map(\.codeResolution), [.nameMatched])
        XCTAssertEqual(preview.newHoldings.map(\.code), ["011370"])
        XCTAssertTrue(preview.unresolvedHoldings.isEmpty)
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
        XCTAssertEqual(portfolioStore.snapshot.totalAmount, 171_461.84, accuracy: 0.0001)
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
        XCTAssertEqual(portfolioStore.snapshot.totalAmount, 171_461.84, accuracy: 0.0001)
        XCTAssertEqual(syncStore.preview?.changedHoldings.map(\.code), [])
        XCTAssertEqual(syncStore.statusMessage, "已同步 1 项数据")
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

    @MainActor
    func testJDFinanceLoginURLUsesDirectMobileLoginPage() {
        XCTAssertEqual(
            JDFinanceWebSession.loginURL.absoluteString,
            "https://plogin.m.jd.com/login/login?qqlogin=false&wxlogin=false&appid=2508&source=JDJR_PC&returnurl=https%3A%2F%2Fjdjr.jd.com%2F"
        )
    }

    @MainActor
    func testJDFinanceTradeOrderURLUsesFundTradeRecordPage() {
        XCTAssertEqual(
            JDFinanceWebSession.tradeOrderURL.absoluteString,
            "https://roma.jd.com/wealth/tradeorder/list?pageShowType=1&businessCode=FUND&pageShowTitle=%E5%9F%BA%E9%87%91%E4%BA%A4%E6%98%93"
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

    func testJDFinanceHoldingsParserAcceptsValidEmptyProductListAndZeroTotal() throws {
        let response = """
        {"success":true,"resultData":{"success":true,"resultData":{"headAssetsData":{"totalAssets":"0.00"},"fundData":{"fundList":[{"productList":[]}]}}}}
        """

        let snapshot = try JDFinanceHoldingsParser.parse(data: Data(response.utf8))

        XCTAssertTrue(snapshot.products.isEmpty)
        XCTAssertEqual(snapshot.totalAssets, 0)
    }

    func testJDFinanceHoldingsParserRejectsMissingFundListStructure() {
        let response = """
        {"success":true,"resultData":{"success":true,"resultData":{"headAssetsData":{"totalAssets":"0.00"}}}}
        """

        XCTAssertThrowsError(try JDFinanceHoldingsParser.parse(data: Data(response.utf8))) { error in
            XCTAssertEqual(error as? JDFinanceHoldingsError, .invalidResponse)
        }
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

    func testJDFinanceSyncPreviewMatchesLocalHoldingByExplicitFundCode() throws {
        let remoteSnapshot = try JDFinanceHoldingsParser.parse(data: Data(Self.jdFinanceHoldingsResponse.utf8))
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
                    currentAmount: 8_888.88,
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

        XCTAssertFalse(preview.missingLocalHoldings.contains { $0.code == "011833" })
        XCTAssertTrue(preview.pendingNotices.contains { $0.code == "011833" })
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
        XCTAssertEqual(preview.pendingNotices.map(\.code), ["022485"])
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

    @MainActor
    func testJDFinanceWaitingPendingBuyDoesNotAutoConfirmOnRefresh() async throws {
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
                pendingCount: 1,
                funds: [
                    conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)
                ],
                migration: nil,
                pendingTrades: [
                    FundPendingTrade(
                        id: "pending-buy",
                        recordID: "pending-buy-record",
                        action: .buy,
                        code: "013284",
                        mode: .amount,
                        amount: 500,
                        shares: nil,
                        tradeDate: "2026-07-07",
                        tradeTimeType: .before15,
                        createdAt: createdAt,
                        syncSource: syncMetadata.source,
                        syncKey: syncMetadata.syncKey,
                        externalStatus: syncMetadata.externalStatus,
                        externalStatusText: syncMetadata.externalStatusText,
                        waitsForExternalConfirmation: syncMetadata.waitsForExternalConfirmation
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

        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "pending-buy-record" })
        XCTAssertEqual(record.status, .pending)
        XCTAssertNil(record.confirmedShares)
        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "013284" })
        XCTAssertEqual(fund.migratedShares ?? 0, 100, accuracy: 0.000001)
        XCTAssertEqual(fund.currentAmount ?? 0, 1_000, accuracy: 0.0001)
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

    @MainActor
    func testJDFinanceFinalTradeOrderOverwritesMatchedLocalBuyRecord() async throws {
        let now = try chinaDate("2026-07-08 09:30")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-final-buy-reconcile-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let service = tradeQuoteService(
            code: "013284",
            name: "上银价值增长3个月持有期混合A",
            date: "2026-07-07",
            netValue: 9.90099
        )
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
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
                        createdAt: now,
                        confirmedAt: now,
                        failureReason: nil,
                        syncSource: .jdFinance,
                        syncKey: "jd-buy",
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
                    totalAmount: 1_000,
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .buy,
                        statusText: "已拉取京东交易流水用于对账",
                        candidateTradeRecords: [
                            JDFinanceTradeOrderRecord(
                                code: "013284",
                                productName: "上银价值增长3个月持有期混合A",
                                action: .buy,
                                amount: 1_000,
                                shares: 101,
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

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "jd-buy-record" })
        XCTAssertEqual(record.confirmedShares ?? 0, 101, accuracy: 0.000001)
        XCTAssertEqual(record.price ?? 0, 9.9010, accuracy: 0.0001)
        XCTAssertEqual(record.externalStatus, .externalConfirmed)
        XCTAssertEqual(record.waitsForExternalConfirmation, false)
        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "013284" })
        XCTAssertEqual(fund.migratedShares ?? 0, 101, accuracy: 0.000001)
    }

    @MainActor
    func testJDFinanceFinalTradeOrderOverwritesMatchedLocalSellRecord() async throws {
        let now = try chinaDate("2026-07-08 09:30")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-final-sell-reconcile-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let service = tradeQuoteService(
            code: "008998",
            name: "同泰竞争优势混合C",
            date: "2026-07-07",
            netValue: 1
        )
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 900,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: "008998", name: "同泰竞争优势混合C", shares: 900, cost: 1)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "source-initial",
                        kind: .newFund,
                        status: .confirmed,
                        code: "008998",
                        name: "同泰竞争优势混合C",
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
                        id: "jd-sell-record",
                        kind: .sell,
                        status: .confirmed,
                        code: "008998",
                        name: "同泰竞争优势混合C",
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
                        syncSource: .jdFinance,
                        syncKey: "jd-sell",
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
            totalAssets: 900,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(
                    skuID: "1008998",
                    code: "008998",
                    name: "同泰竞争优势混合C",
                    totalAmount: 900,
                    pendingDetail: JDFinancePendingTransactionDetail(
                        action: .sell,
                        statusText: "已拉取京东交易流水用于对账",
                        candidateTradeRecords: [
                            JDFinanceTradeOrderRecord(
                                code: "008998",
                                productName: "同泰竞争优势混合C",
                                action: .sell,
                                amount: 99,
                                shares: 100,
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

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "jd-sell-record" })
        XCTAssertEqual(record.amount ?? 0, 99, accuracy: 0.0001)
        XCTAssertEqual(record.confirmedShares ?? 0, 100, accuracy: 0.000001)
        XCTAssertEqual(record.price ?? 0, 0.99, accuracy: 0.0001)
        XCTAssertEqual(record.externalStatus, .externalConfirmed)
        let fund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "008998" })
        XCTAssertEqual(fund.migratedShares ?? 0, 900, accuracy: 0.000001)
    }

    func testJDFinanceFinalTradeOrderConflictWhenNoFinalRecordExists() throws {
        let createdAt = try chinaDate("2026-07-08 09:30")
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
        let notice = try XCTUnwrap(preview.reconciliationNotices.first)

        XCTAssertFalse(notice.isOverwritable)
        if case .conflict(let message) = notice.state {
            XCTAssertEqual(message, "缺少京东最终流水，不能安全覆盖流水")
        } else {
            XCTFail("Expected sync conflict")
        }
    }

    func testJDFinanceFinalTradeOrderWithEqualValuesPlansAutomaticConfirmation() throws {
        let now = try chinaDate("2026-07-14 10:00")
        let localRecord = jdWaitingRecord(
            id: "equal-buy",
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
                jdOrder(
                    key: "jd-order-equal-buy",
                    code: "013284",
                    action: .buy,
                    amount: 1_000,
                    shares: 100,
                    status: .succeeded
                )
            ],
            tradeOrderFetchState: .complete
        )
        let localSnapshot = jdPortfolio(
            funds: [conversionFund(code: "013284", name: "上银价值增长3个月持有期混合A", shares: 100, cost: 10)],
            records: [localRecord],
            now: now
        )

        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot
        )

        XCTAssertEqual(preview.automaticConfirmations.map(\.recordIDs), [["equal-buy"]])
        XCTAssertTrue(preview.reconciliationNotices.isEmpty)
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

    func testJDFinanceFinalTradeOrderClosesPendingLocalExternalWait() throws {
        let now = try chinaDate("2026-07-14 10:00")
        var localRecord = jdWaitingRecord(
            id: "pending-buy",
            kind: .buy,
            code: "013284",
            amount: 1_000,
            shares: nil,
            now: now
        )
        localRecord.status = .pending
        localRecord.confirmedShares = nil
        localRecord.price = nil
        let preview = JDFinanceHoldingsSyncPlanner.preview(
            remoteSnapshot: JDFinanceHoldingsSnapshot(
                totalAssets: 1_000,
                yesterdayIncome: nil,
                todayIncome: nil,
                holdIncome: nil,
                totalIncome: nil,
                products: [],
                tradeOrders: [
                    jdOrder(
                        key: "pending-buy-order",
                        code: "013284",
                        action: .buy,
                        amount: 1_000,
                        shares: nil,
                        status: .succeeded
                    )
                ],
                tradeOrderFetchState: .complete
            ),
            localSnapshot: jdPortfolio(funds: [], records: [localRecord], now: now)
        )

        XCTAssertEqual(preview.automaticConfirmations.map(\.recordIDs), [["pending-buy"]])
        XCTAssertTrue(preview.unrecordedOrders.isEmpty)
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

        XCTAssertEqual(first, second)
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

    func testJDFinanceDuplicateRemoteFundCodesAreAggregatedWithoutCrash() {
        let remoteSnapshot = JDFinanceHoldingsSnapshot(
            totalAssets: 300,
            yesterdayIncome: nil,
            todayIncome: nil,
            holdIncome: nil,
            totalIncome: nil,
            products: [
                JDFinanceHoldingProduct(skuID: "a", code: "013284", name: "测试基金A", totalAmount: 100, holdIncome: 1),
                JDFinanceHoldingProduct(skuID: "b", code: "013284", name: "测试基金A", totalAmount: 200, holdIncome: 2)
            ],
            tradeOrderFetchState: .complete
        )
        let localSnapshot = PortfolioSnapshot(
            updateTime: .now,
            totalAmount: 300,
            holdingIncome: 3,
            holdingIncomeRate: 1,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [
                FundPosition(
                    code: "013284",
                    name: "测试基金A",
                    dateText: "07-14 10:00",
                    todayIncome: 0,
                    todayRate: 0,
                    holdingIncome: 3,
                    holdingRate: 1,
                    currentAmount: 300,
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

        XCTAssertTrue(preview.changedHoldings.isEmpty)
        XCTAssertEqual(preview.remoteSnapshot.products.count, 1)
        XCTAssertEqual(preview.remoteSnapshot.products[0].totalAmount, 300)
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
        XCTAssertEqual(store.snapshot.totalAmount, 456)
    }

    @MainActor
    func testJDFinanceTradeOrderStartDateTracesOldestWaitingLocalRecord() throws {
        let now = try chinaDate("2026-07-14 10:00")
        var record = jdWaitingRecord(
            id: "old-buy",
            kind: .buy,
            code: "013284",
            amount: 1_000,
            shares: 100,
            now: now
        )
        record.tradeDate = "2026-01-03"
        let snapshot = jdPortfolio(funds: [], records: [record], now: now)
        let repository = RecordingPortfolioRepository(initialSnapshot: snapshot)
        let store = PortfolioStore(repository: repository, now: { now })

        store.load()

        XCTAssertEqual(store.jdFinanceTradeOrderStartDate(now: now), "2026-01-03")
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
        XCTAssertEqual(
            MenuBarStatusFormatter.text(amount: 12.3, rate: 1.23, mode: .hidden),
            ""
        )
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

    private func sortTestFund(
        code: String,
        name: String,
        todayIncome: Double,
        todayRate: Double
    ) -> FundPosition {
        FundPosition(
            code: code,
            name: name,
            dateText: "07-08 15:00",
            todayIncome: todayIncome,
            todayRate: todayRate,
            holdingIncome: todayIncome,
            holdingRate: todayRate,
            currentAmount: 10_000,
            status: .holding,
            isUpdated: true,
            isIncomeActive: true,
            migratedShares: 10_000,
            migratedCost: 1,
            migratedPrincipal: 10_000,
            incomeStartDate: "2026-07-08",
            positionMode: .amount,
            positionDate: "2026-07-08",
            positionTimeType: .before15
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
            FundPulseSuggest_123({"Datas":[{"CODE":"026210","NAME":"平安科技精选混合发起式A","SHORTNAME":"平安科技精选混合发起式A","CATEGORYDESC":"基金"}]});
            """
        ])

        let name = await service.lookupFundName(code: "026210")

        XCTAssertEqual(name, "平安科技精选混合发起式A")
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
        XCTAssertTrue(FundListDisplayRules.isDisplayedHolding(sourceFund, tradeRecords: records))
        XCTAssertFalse(FundListDisplayRules.isDisplayedPending(sourceFund, tradeRecords: records))
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

    func testPendingHeaderImpactExcludesConversionsFromSubscriptionAndRedemptionAmounts() throws {
        let impact = try XCTUnwrap(PendingHeaderImpact.make(activities: [
            makePendingHeaderActivity(id: "buy-1", kind: .buy, displayAmount: 51_112),
            makePendingHeaderActivity(id: "sell-1", kind: .sell, displayAmount: 9_986.45),
            makePendingHeaderActivity(
                id: "conversion-1-out",
                kind: .conversionOut,
                displayAmount: 11_565.75,
                conversionID: "conversion-1"
            ),
            makePendingHeaderActivity(
                id: "conversion-2-out",
                kind: .conversionOut,
                displayAmount: 4_033.11,
                conversionID: "conversion-2"
            )
        ]))

        XCTAssertEqual(impact.count, 4)
        XCTAssertEqual(impact.buyAmount, 51_112, accuracy: 0.0001)
        XCTAssertEqual(impact.sellAmount, 9_986.45, accuracy: 0.0001)
        XCTAssertEqual(impact.conversionCount, 2)
        XCTAssertEqual(impact.netAmount, 41_125.55, accuracy: 0.0001)
    }

    func testPendingHeaderImpactKeepsConversionOnlyActivitiesVisibleWithoutCashFlow() throws {
        let impact = try XCTUnwrap(PendingHeaderImpact.make(activities: [
            makePendingHeaderActivity(
                id: "conversion-out",
                kind: .conversionOut,
                displayAmount: 11_565.75,
                conversionID: "conversion-1"
            ),
            makePendingHeaderActivity(
                id: "conversion-in",
                kind: .conversionIn,
                displayAmount: 11_565.75,
                conversionID: "conversion-1"
            )
        ]))

        XCTAssertEqual(impact.count, 2)
        XCTAssertEqual(impact.buyAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(impact.sellAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(impact.conversionCount, 1)
        XCTAssertEqual(impact.netAmount, 0, accuracy: 0.0001)
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
    func testDeletingFundRemovesLinkedConversionRecordsAndRebuildsOtherFund() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-delete-linked-conversion-fund-test-\(UUID().uuidString)", directoryHint: .isDirectory)
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

        try await store.deleteFund(code: "290008")

        XCTAssertFalse(store.snapshot.funds.contains { $0.code == "290008" })
        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.code == "290008" || $0.linkedCode == "290008" || $0.conversionID == conversionID } ?? false)
        XCTAssertNil(store.snapshot.pendingConversions)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
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
                        body: "现在可以检查基金估值，按计划处理加仓、减仓或继续持有。"
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

    func testPortfolioCalculatorPreservesSyncedAccountTotalDuringQuoteRefresh() throws {
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

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: ["022485": quote],
            now: now
        )

        XCTAssertEqual(result.funds[0].currentAmount ?? 0, 110, accuracy: 0.0001)
        XCTAssertEqual(result.totalAmount, 306_651.24, accuracy: 0.0001)
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
    func testPendingConversionKeepsPublishedSnapshotWhenPersistenceFails() async throws {
        let tempDirectory = temporaryPortfolioDirectory(prefix: "conversion-transaction")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let store = PortfolioStore(dataDirectory: tempDirectory)
        try seedPortfolio(transactionTestSnapshot(), into: store, directory: tempDirectory)
        let originalSnapshot = store.snapshot
        try makePortfolioStorageUnwritable(for: store)

        do {
            try await store.convertFundPosition(
                FundConversionDraft(
                    fromCode: Self.tradeTestCode,
                    toCode: "290008",
                    toName: "测试转换目标基金",
                    shares: 10,
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

    private func makePendingHeaderActivity(
        id: String,
        kind: FundTradeKind,
        displayAmount: Double?,
        conversionID: String? = nil
    ) -> PendingTradeActivity {
        PendingTradeActivity(
            id: id,
            recordID: id,
            conversionID: conversionID,
            kind: kind,
            code: kind == .conversionIn ? "290008" : Self.tradeTestCode,
            name: kind.title,
            linkedCode: nil,
            linkedName: nil,
            mode: kind == .sell || kind == .conversionOut ? .share : .amount,
            amount: nil,
            shares: nil,
            tradeDate: "2026-07-07",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-07",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            displayAmount: displayAmount.map {
                PendingActivityAmount(value: $0, source: .enteredAmount, price: nil, shares: nil)
            },
            fund: nil
        )
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

    private func temporaryPortfolioDirectory(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @MainActor
    private func makePortfolioStorageUnwritable(for store: PortfolioStore) throws {
        try FileManager.default.removeItem(at: store.dataFileURL)
        try FileManager.default.createDirectory(at: store.dataFileURL, withIntermediateDirectories: false)
    }

    private func transactionTestSnapshot() -> PortfolioSnapshot {
        let fund = FundPosition(
            code: Self.tradeTestCode,
            name: Self.tradeTestName,
            dateText: "07-09 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingIncome: 0,
            holdingRate: 0,
            confirmedHoldingIncome: 0,
            confirmedHoldingRate: 0,
            currentAmount: 2_000,
            status: .holding,
            isUpdated: true,
            isIncomeActive: true,
            migratedShares: 1_000,
            migratedCost: 2,
            migratedPrincipal: 2_000,
            incomeStartDate: "2026-07-09",
            positionMode: .share,
            positionDate: "2026-07-09",
            positionTimeType: .before15,
            lots: [
                FundPositionLot(
                    id: "transaction-lot",
                    shares: 1_000,
                    cost: 2,
                    principal: 2_000,
                    incomeStartDate: "2026-07-09",
                    positionDate: "2026-07-09",
                    positionTimeType: .before15
                )
            ]
        )
        return PortfolioSnapshot(
            updateTime: Date(timeIntervalSince1970: 1_783_587_600),
            totalAmount: 2_000,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [fund],
            migration: nil,
            tradeRecords: [
                FundTradeRecord(
                    id: "transaction-initial-record",
                    kind: .newFund,
                    status: .confirmed,
                    code: Self.tradeTestCode,
                    name: Self.tradeTestName,
                    mode: .share,
                    amount: nil,
                    shares: 1_000,
                    confirmedShares: 1_000,
                    price: 2,
                    tradeDate: "2026-07-09",
                    tradeTimeType: .before15,
                    acceptedDate: "2026-07-09",
                    createdAt: Date(timeIntervalSince1970: 1_783_587_600),
                    confirmedAt: Date(timeIntervalSince1970: 1_783_587_600),
                    failureReason: nil
                )
            ]
        )
    }

    @MainActor
    private func refreshConcurrencyTestStore(prefix: String) throws -> PortfolioStore {
        let now = try chinaDate("2026-07-10 10:00")
        let response = Self.coreQuoteResponse([
            CoreQuoteMock(
                code: Self.tradeTestCode,
                name: Self.tradeTestName,
                netValueDate: "2026-07-09",
                netValue: 2,
                estimatedNetValue: 2.02,
                growthRate: 1,
                estimateTime: "2026-07-10 10:00"
            ),
            CoreQuoteMock(
                code: "290008",
                name: "测试新增基金",
                netValueDate: "2026-07-09",
                netValue: 1,
                estimatedNetValue: 1.01,
                growthRate: 1,
                estimateTime: "2026-07-10 10:00"
            )
        ])
        let tempDirectory = temporaryPortfolioDirectory(prefix: prefix)
        let store = PortfolioStore(
            dataDirectory: tempDirectory,
            quoteService: quoteServiceWithMockResponses([
                "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew": response
            ]),
            now: { now }
        )
        try seedPortfolio(transactionTestSnapshot(), into: store, directory: tempDirectory)
        MockURLProtocol.responseStore.clearRecordedRequests()
        return store
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

    private func appUpdateInfo(version: String) throws -> AppUpdateInfo {
        AppUpdateInfo(
            version: version,
            releaseName: "fund-pulse \(version)",
            releaseNotes: "",
            publishedAt: nil,
            htmlURL: try XCTUnwrap(URL(string: "https://example.com/releases/tag/v\(version)")),
            downloadURL: try XCTUnwrap(URL(string: "https://example.com/fund-pulse-\(version).zip"))
        )
    }

    private func appUpdateServiceWithMockResponses(
        _ responses: [String: String],
        finalURLs: [String: String] = [:]
    ) -> AppUpdateService {
        MockURLProtocol.responseStore.set(
            responses.mapValues { Data($0.utf8) },
            finalURLs: finalURLs.compactMapValues(URL.init(string:))
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AppUpdateService(session: URLSession(configuration: configuration))
    }

    private static func githubLatestReleaseAPIEndpoint() -> String {
        "https://api.github.com/repos/iamzjt-front-end/fund-pulse/releases/latest"
    }

    private static func githubLatestReleaseWebEndpoint() -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/latest"
    }

    private static func githubReleaseTagURL(version: String) -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/tag/v\(version)"
    }

    private static func githubMacReleaseFeedEndpoint(version: String) -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/download/v\(version)/latest-mac.yml"
    }

    private static func githubZipDownloadURL(version: String) -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/download/v\(version)/fund-pulse-\(version)-arm64.zip"
    }

    private static func githubReleaseResponse(version: String) -> String {
        """
        {
          "tag_name": "v\(version)",
          "name": "fund-pulse v\(version)",
          "body": "",
          "html_url": "\(githubReleaseTagURL(version: version))",
          "published_at": "2026-07-03T08:00:00Z",
          "assets": [
            {
              "name": "fund-pulse-\(version)-arm64.zip",
              "browser_download_url": "\(githubZipDownloadURL(version: version))"
            }
          ]
        }
        """
    }

    private static func macReleaseFeedResponse(version: String) -> String {
        """
        version: \(version)
        files:
          - url: fund-pulse-\(version)-arm64.zip
        releaseDate: '2026-07-03T08:00:00.000Z'
        """
    }

    private static func jdFinanceEmptyHoldingsResponse(total: Double) -> String {
        """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "success": true,
            "resultData": {
              "headAssetsData": {
                "totalAssets": { "amt": \(total), "text": "\(total)" }
              },
              "fundData": { "fundList": [] }
            }
          }
        }
        """
    }

    private static let jdFinanceHoldingsResponse = """
    {
      "success": true,
      "resultCode": 0,
      "resultMsg": "success",
      "resultData": {
        "success": true,
        "resultCode": 0,
        "resultMsg": "success",
        "resultData": {
          "headAssetsData": {
            "totalAssets": { "amt": 171461.84, "text": "171,461.84" },
            "yesterdayIncome": { "amt": -16259.99, "text": "-16,259.99" },
            "todayIncome": { "text": "0.00" },
            "holdIncome": { "amt": -9222.66, "text": "-9,222.66" },
            "totalIncome": { "text": "-5,425.17" }
          },
          "fundData": {
            "fundList": [
              {
                "productList": [
                  {
                    "skuId": "1024424",
                    "fundCode": "024424",
                    "productName": "永赢先进制造智选混合发起A",
                    "totalAmount": { "amt": 19907.79, "text": "19,907.79" },
                    "yesterdayIncome": { "text": "-688.41" },
                    "todayIncome": { "text": "--" },
                    "holdIncome": { "amt": -734.13, "text": "-734.13" },
                    "holdRate": { "text": "-3.56%" }
                  },
                  {
                    "skuId": "113687",
                    "fundCode": "011833",
                    "productName": "鹏华中证光伏产业ETF联接A",
                    "totalAmount": { "text": "8,888.88" },
                    "yesterdayIncome": { "text": "+12.34" },
                    "holdIncome": { "text": "-88.88" },
                    "holdRate": { "text": "-0.99%" },
                    "transactionTip": "买入确认中"
                  }
                ]
              }
            ]
          }
        }
      }
    }
    """

    private static let jdFinancePendingHoldingsResponse = """
    {
      "success": true,
      "resultCode": 0,
      "resultMsg": "success",
      "resultData": {
        "success": true,
        "resultCode": 0,
        "resultMsg": "success",
        "resultData": {
          "headAssetsData": {
            "totalAssets": { "text": "7,632.07" },
            "holdIncome": { "text": "-88.88" }
          },
          "fundData": {
            "fundList": [
              {
                "productList": [
                  {
                    "skuId": "113687",
                    "fundCode": "011833",
                    "productName": "西部利得人工智能主题指数增强C",
                    "totalAmount": { "text": "7,632.07" },
                    "yesterdayIncome": { "text": "预计08日更新" },
                    "holdIncome": { "text": "-88.88" },
                    "transactionTip": { "text": "交易：1笔买入中合计7632.07元" },
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

    private static let jdFinancePendingDetailResponse = """
    {
      "success": true,
      "resultCode": 0,
      "resultMsg": "success",
      "resultData": {
        "resultData": {
          "orderDetail": {
            "tradeType": "买入",
            "tradeAmount": "7,632.07",
            "tradeDate": "2026-07-03",
            "tradeTime": "2026-07-03 10:00:00",
            "tradeStatus": "买入确认中"
          }
        }
      }
    }
    """

    private func jdFinanceServiceWithMockResponses(_ responses: [String: String]) -> JDFinanceHoldingsService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return JDFinanceHoldingsService(session: URLSession(configuration: configuration))
    }

    private func jdFinanceServiceWithMockResponses(
        _ responses: [String: String],
        bodyResponses: [MockBodyResponseRule]
    ) -> JDFinanceHoldingsService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        MockURLProtocol.responseStore.setBodyResponses(bodyResponses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return JDFinanceHoldingsService(session: URLSession(configuration: configuration))
    }

    private func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    private func quoteServiceWithMockResponses(_ responses: [String: String]) -> FundQuoteService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return FundQuoteService(session: URLSession(configuration: configuration))
    }

    private func marketIndexServiceWithMockResponses(_ responses: [String: String]) -> MarketIndexService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return MarketIndexService(session: URLSession(configuration: configuration))
    }

    private static func marketIndexBatchQuoteEndpoint(
        host: String = "push2.eastmoney.com"
    ) -> String {
        "https://\(host)/api/qt/ulist.np/get"
    }

    private static func tonghuashunMarketBreadthEndpoint() -> String {
        "https://q.10jqka.com.cn/api.php?t=indexflash"
    }

    private static func eastmoneyMarketBreadthEndpoint(
        host: String = "push2delay.eastmoney.com"
    ) -> String {
        "https://\(host)/api/qt/clist/get"
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

    private func jdWaitingRecord(
        id: String,
        kind: FundTradeKind,
        code: String,
        amount: Double?,
        shares: Double?,
        now: Date
    ) -> FundTradeRecord {
        let price: Double? = if let amount, let shares, shares > 0 {
            amount / shares
        } else {
            nil
        }
        return FundTradeRecord(
            id: id,
            kind: kind,
            status: .confirmed,
            code: code,
            name: code == "008998" ? "同泰竞争优势混合C" : "上银价值增长3个月持有期混合A",
            mode: kind == .sell || kind == .conversionOut ? .share : .amount,
            amount: amount,
            shares: kind == .sell || kind == .conversionOut ? shares : nil,
            confirmedShares: shares,
            price: price,
            tradeDate: "2026-07-13",
            tradeTimeType: .before15,
            acceptedDate: "2026-07-13",
            createdAt: now,
            confirmedAt: now,
            failureReason: nil,
            syncSource: .jdFinance,
            syncKey: "legacy-\(id)",
            externalStatus: .waitingExternalConfirmation,
            externalStatusText: "确认中",
            waitsForExternalConfirmation: true
        )
    }

    private func jdOrder(
        key: String,
        code: String,
        action: JDFinancePendingTradeAction,
        amount: Double?,
        shares: Double?,
        status: JDFinanceTradeOrderStatus
    ) -> JDFinanceTradeOrderRecord {
        JDFinanceTradeOrderRecord(
            stableOrderKey: key,
            code: code,
            productName: code == "008998" ? "同泰竞争优势混合C" : "上银价值增长3个月持有期混合A",
            action: action,
            amount: amount,
            shares: shares,
            tradeDate: "2026-07-13",
            tradeTimeType: .before15,
            submittedAt: "2026-07-13 10:00:00",
            status: status,
            statusText: status == .succeeded ? "确认成功" : status.rawValue
        )
    }

    private func jdPortfolio(
        funds: [FundPosition],
        records: [FundTradeRecord],
        now: Date
    ) -> PortfolioSnapshot {
        PortfolioSnapshot(
            updateTime: now,
            totalAmount: funds.compactMap(\.currentAmount).reduce(0, +),
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: funds,
            migration: nil,
            tradeRecords: records,
            jdFinanceSyncState: JDFinanceSyncState(baselineEstablishedAt: now)
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

@MainActor
private func makeOperationReminderNotificationScheduler(
    center: OperationReminderNotificationCenterFake
) -> OperationReminderNotificationScheduler {
    OperationReminderNotificationScheduler(
        maximumRemovalAttempts: 5,
        pendingRequests: { center.pendingRequests },
        removePendingRequests: { center.removePendingRequests(withIdentifiers: $0) },
        deliveredNotifications: { center.deliveredNotifications },
        removeDeliveredNotifications: { center.removeDeliveredNotifications(withIdentifiers: $0) },
        requestAuthorization: { center.requestAuthorization() },
        addRequest: { try await center.add($0) },
        waitAfterRemovalAttempt: { await center.waitAfterRemovalAttempt() }
    )
}

@MainActor
private final class OperationReminderNotificationCenterFake {
    private(set) var pendingRequests: [OperationReminderNotificationCandidate]
    private(set) var deliveredNotifications: [OperationReminderNotificationCandidate]
    private(set) var addedRequests: [OperationReminderNotificationRequest] = []
    private(set) var removePendingCallCount = 0
    private(set) var waitCallCount = 0
    private(set) var authorizationRequestCount = 0
    private(set) var didAddBeforePendingRequestsWereRemoved = false

    private let removalWaitCount: Int
    private var remainingRemovalWaitCount: Int?
    private var pendingRemovalIdentifiers: Set<String> = []

    init(
        pendingRequests: [OperationReminderNotificationCandidate] = [],
        deliveredNotifications: [OperationReminderNotificationCandidate] = [],
        removalWaitCount: Int = 0
    ) {
        self.pendingRequests = pendingRequests
        self.deliveredNotifications = deliveredNotifications
        self.removalWaitCount = removalWaitCount
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingCallCount += 1
        pendingRemovalIdentifiers.formUnion(identifiers)

        if removalWaitCount == 0 {
            finishPendingRemoval()
        } else if remainingRemovalWaitCount == nil {
            remainingRemovalWaitCount = removalWaitCount
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        let identifierSet = Set(identifiers)
        deliveredNotifications.removeAll { identifierSet.contains($0.identifier) }
    }

    func requestAuthorization() -> Bool {
        authorizationRequestCount += 1
        return true
    }

    func add(_ request: OperationReminderNotificationRequest) async throws {
        if !pendingRequests.isEmpty {
            didAddBeforePendingRequestsWereRemoved = true
        }
        addedRequests.append(request)
        pendingRequests.append(
            OperationReminderNotificationCandidate(
                identifier: request.identifier,
                title: request.title,
                body: request.body
            )
        )
    }

    func waitAfterRemovalAttempt() async {
        waitCallCount += 1
        if let remainingRemovalWaitCount {
            let nextCount = remainingRemovalWaitCount - 1
            self.remainingRemovalWaitCount = nextCount
            if nextCount == 0 {
                finishPendingRemoval()
            }
        }
        await Task.yield()
    }

    private func finishPendingRemoval() {
        pendingRequests.removeAll { pendingRemovalIdentifiers.contains($0.identifier) }
        pendingRemovalIdentifiers.removeAll()
        remainingRemovalWaitCount = nil
    }
}

private final class MockResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var bodyStorage: [MockBodyResponseRule] = []
    private var finalURLStorage: [String: URL] = [:]
    private var requestStorage: [URLRequest] = []
    private var delayNanoseconds: UInt64 = 0
    private var concurrentRequestCount = 0
    private var maximumConcurrentRequests = 0

    func set(_ responses: [String: Data], finalURLs: [String: URL] = [:]) {
        lock.lock()
        storage = responses
        bodyStorage = []
        finalURLStorage = finalURLs
        lock.unlock()
    }

    func setBodyResponses(_ responses: [MockBodyResponseRule]) {
        lock.lock()
        bodyStorage = responses
        lock.unlock()
    }

    func setResponseDelay(nanoseconds: UInt64) {
        lock.lock()
        delayNanoseconds = nanoseconds
        lock.unlock()
    }

    func reset() {
        lock.lock()
        storage = [:]
        bodyStorage = []
        finalURLStorage = [:]
        requestStorage = []
        delayNanoseconds = 0
        concurrentRequestCount = 0
        maximumConcurrentRequests = 0
        lock.unlock()
    }

    func appendRequest(_ request: URLRequest) {
        lock.lock()
        requestStorage.append(request)
        lock.unlock()
    }

    func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestStorage
    }

    func clearRecordedRequests() {
        lock.lock()
        requestStorage = []
        concurrentRequestCount = 0
        maximumConcurrentRequests = 0
        lock.unlock()
    }

    func beginRequest() {
        lock.lock()
        concurrentRequestCount += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, concurrentRequestCount)
        lock.unlock()
    }

    func finishRequest() {
        lock.lock()
        concurrentRequestCount = max(0, concurrentRequestCount - 1)
        lock.unlock()
    }

    func maximumConcurrentRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumConcurrentRequests
    }

    func response(for url: String, body: String? = nil) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let body,
           let bodyMatch = bodyStorage
            .filter({ url.hasPrefix($0.urlPrefix) && body.contains($0.bodyContains) })
            .max(by: { lhs, rhs in
                lhs.urlPrefix.count + lhs.bodyContains.count < rhs.urlPrefix.count + rhs.bodyContains.count
            })
        {
            return bodyMatch.data
        }
        return storage
            .filter { url.hasPrefix($0.key) }
            .max { lhs, rhs in lhs.key.count < rhs.key.count }?
            .value
    }

    func finalURL(for url: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return finalURLStorage
            .filter { url.hasPrefix($0.key) }
            .max { lhs, rhs in lhs.key.count < rhs.key.count }?
            .value
    }

    func responseDelayNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return delayNanoseconds
    }
}

private struct MockBodyResponseRule {
    var urlPrefix: String
    var bodyContains: String
    var data: Data
}

private extension Double {
    var roundedMoneyForTest: Double {
        (self * 100).rounded() / 100
    }
}

private final class RecordingPortfolioRepository: PortfolioRepository {
    let dataDirectory = FileManager.default.temporaryDirectory
        .appending(path: "fund-pulse-recording-repository", directoryHint: .isDirectory)
    var dataFileURL: URL {
        dataDirectory.appending(path: "portfolio.json")
    }
    private let initialSnapshot: PortfolioSnapshot?
    private(set) var savedSnapshots: [PortfolioSnapshot] = []

    init(initialSnapshot: PortfolioSnapshot?) {
        self.initialSnapshot = initialSnapshot
    }

    func load() throws -> PortfolioSnapshot? {
        initialSnapshot
    }

    func save(_ snapshot: PortfolioSnapshot) throws {
        savedSnapshots.append(snapshot)
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
        Self.responseStore.appendRequest(request)
        Self.responseStore.beginRequest()
        defer { Self.responseStore.finishRequest() }
        guard let url = request.url?.absoluteString,
              let data = Self.responseStore.response(
                for: url,
                body: Self.bodyText(for: request)
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let delayNanoseconds = Self.responseStore.responseDelayNanoseconds()
        if delayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(delayNanoseconds) / 1_000_000_000)
        }

        let responseURL = Self.responseStore.finalURL(for: url) ?? request.url!
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyText(for request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8)
    }
}
