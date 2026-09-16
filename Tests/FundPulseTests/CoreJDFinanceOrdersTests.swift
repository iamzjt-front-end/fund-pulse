import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
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

    func testJDFinanceTradeOrderEndpointMatchesWebTradeRecordPage() {
        XCTAssertTrue(JDFinanceHoldingsService.tradeOrderListEndpoint.absoluteString.contains("/cfGateway/newna/m/queryTradeOrderList"))
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
    func testJDFinanceTradeOrderURLUsesFundTradeRecordPage() {
        XCTAssertEqual(
            JDFinanceWebSession.tradeOrderURL.absoluteString,
            "https://roma.jd.com/wealth/tradeorder/list?pageShowType=1&businessCode=FUND&pageShowTitle=%E5%9F%BA%E9%87%91%E4%BA%A4%E6%98%93"
        )
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

    func testJDFinanceTradeOrderBatcherDoesNotMergeDifferentSubmissionTimes() {
        var first = jdOrder(
            key: "independent-payment-900",
            code: "022184",
            action: .buy,
            amount: 900,
            shares: nil,
            status: .succeeded
        )
        var second = jdOrder(
            key: "independent-payment-100",
            code: "022184",
            action: .buy,
            amount: 100,
            shares: nil,
            status: .succeeded
        )
        first.submittedAt = "2026-07-13 10:05:00"
        second.submittedAt = "2026-07-13 10:06:00"
        let records = [first, second]

        XCTAssertEqual(JDFinanceTradeOrderBatcher.logicalRecords(records), records)
        XCTAssertNil(JDFinanceTradeOrderBatcher.combinedRecord(records))
    }

    func testJDFinanceTradeOrderBatcherDoesNotMergeMissingSubmissionTimes() {
        var first = jdOrder(
            key: "missing-time-payment-900",
            code: "022184",
            action: .buy,
            amount: 900,
            shares: nil,
            status: .succeeded
        )
        var second = jdOrder(
            key: "missing-time-payment-100",
            code: "022184",
            action: .buy,
            amount: 100,
            shares: nil,
            status: .succeeded
        )
        first.submittedAt = nil
        second.submittedAt = nil
        let records = [first, second]

        XCTAssertEqual(JDFinanceTradeOrderBatcher.logicalRecords(records), records)
        XCTAssertNil(JDFinanceTradeOrderBatcher.combinedRecord(records))
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
}
