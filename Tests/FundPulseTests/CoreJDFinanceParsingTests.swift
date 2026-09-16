import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
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
        XCTAssertTrue(joined.contains("账户持仓收益"))
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
}
