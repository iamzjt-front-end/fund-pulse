import XCTest
@testable import FundPulse
#if canImport(AppKit)
import AppKit
#endif

final class FundPulseCoreTests: XCTestCase {
    static let tradeTestCode = "026210"
    static let tradeTestName = "平安科技精选混合发起式A"

    override func tearDown() {
        MockURLProtocol.responseStore.reset()
        super.tearDown()
    }

    func sortTestFund(
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

    func makePendingHeaderActivity(
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
    func seedPortfolio(
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

    func temporaryPortfolioDirectory(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @MainActor
    func makePortfolioStorageUnwritable(for store: PortfolioStore) throws {
        try FileManager.default.removeItem(at: store.dataFileURL)
        try FileManager.default.createDirectory(at: store.dataFileURL, withIntermediateDirectories: false)
    }

    func transactionTestSnapshot() -> PortfolioSnapshot {
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
    func refreshConcurrencyTestStore(prefix: String) throws -> PortfolioStore {
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

    func thresholdReminderSnapshot(funds: [FundPosition]) -> PortfolioSnapshot {
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

    func thresholdReminderFund(
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

    struct CoreQuoteMock {
        var code: String
        var name: String
        var netValueDate: String
        var netValue: Double
        var estimatedNetValue: Double
        var growthRate: Double
        var officialGrowthRate: Double?
        var estimateTime: String
    }

    static func coreQuoteResponse(
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

    static func coreQuoteResponse(_ quotes: [CoreQuoteMock]) -> String {
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

    func appUpdateInfo(version: String) throws -> AppUpdateInfo {
        AppUpdateInfo(
            version: version,
            releaseName: "fund-pulse \(version)",
            releaseNotes: "",
            publishedAt: nil,
            htmlURL: try XCTUnwrap(URL(string: "https://example.com/releases/tag/v\(version)")),
            downloadURL: try XCTUnwrap(URL(string: "https://example.com/fund-pulse-\(version).zip"))
        )
    }

    func appUpdateServiceWithMockResponses(
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

    static func githubLatestReleaseAPIEndpoint() -> String {
        "https://api.github.com/repos/iamzjt-front-end/fund-pulse/releases/latest"
    }

    static func githubLatestReleaseWebEndpoint() -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/latest"
    }

    static func githubReleaseTagURL(version: String) -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/tag/v\(version)"
    }

    static func githubMacReleaseFeedEndpoint(version: String) -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/download/v\(version)/latest-mac.yml"
    }

    static func githubZipDownloadURL(version: String) -> String {
        "https://github.com/iamzjt-front-end/fund-pulse/releases/download/v\(version)/fund-pulse-\(version)-arm64.zip"
    }

    static func githubReleaseResponse(version: String) -> String {
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

    static func macReleaseFeedResponse(version: String) -> String {
        """
        version: \(version)
        files:
          - url: fund-pulse-\(version)-arm64.zip
        releaseDate: '2026-07-03T08:00:00.000Z'
        """
    }

    static func jdFinanceEmptyHoldingsResponse(total: Double) -> String {
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

    static let jdFinanceHoldingsResponse = """
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

    static let jdFinancePendingHoldingsResponse = """
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

    static let jdFinancePendingDetailResponse = """
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

    func jdFinanceServiceWithMockResponses(_ responses: [String: String]) -> JDFinanceHoldingsService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return JDFinanceHoldingsService(session: URLSession(configuration: configuration))
    }

    func jdFinanceServiceWithMockResponses(
        _ responses: [String: String],
        bodyResponses: [MockBodyResponseRule]
    ) -> JDFinanceHoldingsService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        MockURLProtocol.responseStore.setBodyResponses(bodyResponses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return JDFinanceHoldingsService(session: URLSession(configuration: configuration))
    }

    func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    func quoteServiceWithMockResponses(_ responses: [String: String]) -> FundQuoteService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return FundQuoteService(session: URLSession(configuration: configuration))
    }

    func marketIndexServiceWithMockResponses(_ responses: [String: String]) -> MarketIndexService {
        MockURLProtocol.responseStore.set(responses.mapValues { Data($0.utf8) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return MarketIndexService(session: URLSession(configuration: configuration))
    }

    static func marketIndexBatchQuoteEndpoint(
        host: String = "push2.eastmoney.com"
    ) -> String {
        "https://\(host)/api/qt/ulist.np/get"
    }

    static func tonghuashunMarketBreadthEndpoint() -> String {
        "https://q.10jqka.com.cn/api.php?t=indexflash"
    }

    static func eastmoneyMarketBreadthEndpoint(
        host: String = "push2delay.eastmoney.com"
    ) -> String {
        "https://\(host)/api/qt/clist/get"
    }

    func tradeQuoteService(
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

    func multiTradeQuoteService(
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

    func conversionFund(
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

    func jdWaitingRecord(
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

    func jdOrder(
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

    func jdPortfolio(
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

    func chinaDate(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: value))
    }

    func timestamp(_ dateText: String) throws -> Int64 {
        let date = try chinaDate("\(dateText) 00:00")
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

#if canImport(AppKit)
func rgbHex(_ color: NSColor) throws -> String {
    let converted = try XCTUnwrap(color.usingColorSpace(.sRGB))
    let red = Int(round(converted.redComponent * 255))
    let green = Int(round(converted.greenComponent * 255))
    let blue = Int(round(converted.blueComponent * 255))
    return String(format: "#%02X%02X%02X", red, green, blue)
}
#endif

@MainActor
func XCTAssertThrowsErrorAsync(
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
func makeOperationReminderNotificationScheduler(
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
final class OperationReminderNotificationCenterFake {
    private(set) var pendingRequests: [OperationReminderNotificationCandidate]
    private(set) var deliveredNotifications: [OperationReminderNotificationCandidate]
    private(set) var addedRequests: [OperationReminderNotificationRequest] = []
    private(set) var removePendingCallCount = 0
    private(set) var waitCallCount = 0
    private(set) var authorizationRequestCount = 0
    private(set) var didAddBeforePendingRequestsWereRemoved = false

    let removalWaitCount: Int
    var remainingRemovalWaitCount: Int?
    var pendingRemovalIdentifiers: Set<String> = []

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

    func finishPendingRemoval() {
        pendingRequests.removeAll { pendingRemovalIdentifiers.contains($0.identifier) }
        pendingRemovalIdentifiers.removeAll()
        remainingRemovalWaitCount = nil
    }
}

final class MockResponseStore: @unchecked Sendable {
    let lock = NSLock()
    var storage: [String: Data] = [:]
    var bodyStorage: [MockBodyResponseRule] = []
    var finalURLStorage: [String: URL] = [:]
    var requestStorage: [URLRequest] = []
    var delayNanoseconds: UInt64 = 0
    var concurrentRequestCount = 0
    var maximumConcurrentRequests = 0

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

struct MockBodyResponseRule {
    var urlPrefix: String
    var bodyContains: String
    var data: Data
}

extension Double {
    var roundedMoneyForTest: Double {
        (self * 100).rounded() / 100
    }
}

final class InMemoryJDFinanceCookieStorage: JDFinanceCookieStorage {
    private(set) var cookies: [HTTPCookie]?
    private(set) var deletedCookies: [HTTPCookie] = []

    init(cookies: [HTTPCookie]) {
        self.cookies = cookies
    }

    func deleteCookie(_ cookie: HTTPCookie) {
        deletedCookies.append(cookie)
        cookies?.removeAll {
            $0.name == cookie.name
                && $0.domain == cookie.domain
                && $0.path == cookie.path
        }
    }
}

final class RecordingPortfolioRepository: PortfolioRepository {
    let dataDirectory = FileManager.default.temporaryDirectory
        .appending(path: "fund-pulse-recording-repository", directoryHint: .isDirectory)
    var dataFileURL: URL {
        dataDirectory.appending(path: "portfolio.json")
    }
    let initialSnapshot: PortfolioSnapshot?
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

actor AsyncTestGate {
    var isWaiting = false
    var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilWaiting() async {
        while !isWaiting {
            await Task.yield()
        }
    }

    func open() {
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}

final class MockURLProtocol: URLProtocol {
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

    static func bodyText(for request: URLRequest) -> String? {
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
