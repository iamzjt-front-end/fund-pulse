import Foundation
import XCTest
@testable import FundPulse

final class JDFinancePerformanceHistoryTests: XCTestCase {
    override func tearDown() {
        PerformanceHistoryURLProtocol.store.reset()
        super.tearDown()
    }

    func testParserReadsSanitizedDailyIncomeFixtureAndSortsByDate() throws {
        let days = try JDFinancePerformanceHistoryParser.parse(
            data: Data(Self.validRangeFixture.utf8)
        )

        XCTAssertEqual(
            days,
            [
                JDFinancePerformanceDay(
                    date: "2026-01-01",
                    incomeAmount: 8.25,
                    incomeRate: nil
                ),
                JDFinancePerformanceDay(
                    date: "2026-01-02",
                    incomeAmount: -12.34,
                    incomeRate: -0.12
                )
            ]
        )
    }

    func testParserTreatsAnEmptyMapAsAValidEmptyHistory() throws {
        let days = try JDFinancePerformanceHistoryParser.parse(
            data: Data(Self.emptyRangeFixture.utf8)
        )

        XCTAssertTrue(days.isEmpty)
    }

    func testParserRejectsMissingMapMalformedAmountAndMismatchedDate() {
        for fixture in [
            Self.missingMapFixture,
            Self.malformedAmountFixture,
            Self.mismatchedDateFixture
        ] {
            XCTAssertThrowsError(
                try JDFinancePerformanceHistoryParser.parse(data: Data(fixture.utf8))
            ) { error in
                XCTAssertEqual(error as? JDFinancePerformanceHistoryError, .invalidResponse)
            }
        }
    }

    func testParserRecognizesOuterAndInnerLoginExpiry() {
        for fixture in [Self.outerLoginExpiredFixture, Self.innerLoginExpiredFixture] {
            XCTAssertThrowsError(
                try JDFinancePerformanceHistoryParser.parse(data: Data(fixture.utf8))
            ) { error in
                XCTAssertEqual(error as? JDFinancePerformanceHistoryError, .notLoggedIn)
            }
        }
    }

    func testRequestRangesSplitAtNaturalYearBoundariesAndNeverExceed366Days() throws {
        let ranges = try JDFinancePerformanceHistoryService.requestRanges(
            from: "2023-12-30",
            through: "2025-01-02"
        )

        XCTAssertEqual(
            ranges,
            [
                JDFinancePerformanceHistoryRange(from: "2023-12-30", through: "2023-12-31"),
                JDFinancePerformanceHistoryRange(from: "2024-01-01", through: "2024-12-31"),
                JDFinancePerformanceHistoryRange(from: "2025-01-01", through: "2025-01-02")
            ]
        )

        for range in ranges {
            let start = try XCTUnwrap(DateOnlyFormatter.parse(range.from))
            let end = try XCTUnwrap(DateOnlyFormatter.parse(range.through))
            let days = Calendar.shanghai.dateComponents([.day], from: start, to: end).day ?? 0
            XCTAssertLessThanOrEqual(days + 1, 366)
            XCTAssertEqual(Calendar.shanghai.component(.year, from: start), Calendar.shanghai.component(.year, from: end))
        }
    }

    func testRequestRangesRejectInvalidOrReversedDates() {
        for (start, end) in [
            ("not-a-date", "2026-01-01"),
            ("2026-01-02", "2026-01-01")
        ] {
            XCTAssertThrowsError(
                try JDFinancePerformanceHistoryService.requestRanges(from: start, through: end)
            ) { error in
                XCTAssertEqual(error as? JDFinancePerformanceHistoryError, .invalidDateRange)
            }
        }
    }

    func testServiceFetchesYearBatchesAndPreservesExistingDaysNotReturnedByJD() async throws {
        PerformanceHistoryURLProtocol.store.setDefaultResponse(.json(Self.fixture(days: [
            ("2025-12-31", "3.50", "0.03"),
            ("2026-01-01", "4.50", nil),
            ("2026-01-02", "5.50", "0.05")
        ])))
        let existing = JDFinancePerformanceHistory(
            days: [
                JDFinancePerformanceDay(date: "2025-12-30", incomeAmount: 1, incomeRate: 0.01),
                JDFinancePerformanceDay(date: "2026-01-01", incomeAmount: 999, incomeRate: nil)
            ],
            coveredFrom: "2025-12-30",
            coveredThrough: "2026-01-01",
            isComplete: false
        )
        let service = Self.service()

        let history = try await service.fetchHistory(
            cookieHeader: Self.cookieHeader,
            from: "2025-12-31",
            through: "2026-01-02",
            existing: existing
        )

        XCTAssertEqual(history.coveredFrom, "2025-12-31")
        XCTAssertEqual(history.coveredThrough, "2026-01-02")
        XCTAssertTrue(history.isComplete)
        XCTAssertEqual(history.days.map(\.date), ["2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02"])
        XCTAssertEqual(history.days.first(where: { $0.date == "2025-12-30" })?.incomeAmount, 1)
        XCTAssertEqual(history.days.first(where: { $0.date == "2026-01-01" })?.incomeAmount, 4.5)

        let requests = PerformanceHistoryURLProtocol.store.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url, JDFinancePerformanceHistoryService.endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), JDFinancePerformanceHistoryService.referer)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=UTF-8")
        }
    }

    func testRequestUsesExpectedRangePayloadAndBrowserHeaders() throws {
        let request = try JDFinancePerformanceHistoryService.request(
            for: JDFinancePerformanceHistoryRange(
                from: "2026-07-01",
                through: "2026-07-14"
            ),
            cookieHeader: "pt_key=fixture-auth; pt_pin=fixture-user; payment_token=must-not-leave-app; wskey=fixture-mobile"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, JDFinancePerformanceHistoryService.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), JDFinancePerformanceHistoryService.referer)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), JDFinancePerformanceHistoryService.origin)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=UTF-8")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cookie"),
            "pt_key=fixture-auth; pt_pin=fixture-user; wskey=fixture-mobile"
        )

        let payload = try Self.requestPayload(from: request)
        XCTAssertEqual(payload["risk_type"] as? String, "")
        XCTAssertEqual(payload["rf_type"] as? String, "fund")
        XCTAssertEqual(payload["rateType"] as? String, "most")
        XCTAssertEqual(payload["rateFlag"] as? String, "1")
        XCTAssertEqual(payload["incomeDateDimension"] as? String, "day")
        XCTAssertEqual(payload["dateFrom"] as? String, "2026-07-01")
        XCTAssertEqual(payload["dateTo"] as? String, "2026-07-14")
    }

    func testServiceDefaultsThroughDateToYesterdayInShanghai() async throws {
        PerformanceHistoryURLProtocol.store.setDefaultResponse(.json(Self.emptyRangeFixture))
        let service = Self.service()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T02:00:00Z"))

        let history = try await service.fetchHistory(
            cookieHeader: Self.cookieHeader,
            from: "2026-07-13",
            now: now
        )

        XCTAssertEqual(history.coveredFrom, "2026-07-13")
        XCTAssertEqual(history.coveredThrough, "2026-07-14")
    }

    func testServicePropagatesOuterAndInnerLoginExpiry() async {
        for fixture in [Self.outerLoginExpiredFixture, Self.innerLoginExpiredFixture] {
            PerformanceHistoryURLProtocol.store.reset()
            PerformanceHistoryURLProtocol.store.setDefaultResponse(.json(fixture))

            do {
                _ = try await Self.service().fetchHistory(
                    cookieHeader: Self.cookieHeader,
                    from: "2026-07-01",
                    through: "2026-07-02"
                )
                XCTFail("Expected login expiry")
            } catch {
                XCTAssertEqual(error as? JDFinancePerformanceHistoryError, .notLoggedIn)
            }
        }
    }

    func testServiceMapsCancellationToCancellationError() async {
        PerformanceHistoryURLProtocol.store.setDefaultResponse(
            .json(Self.emptyRangeFixture, delay: 0.5)
        )
        let service = Self.service()
        let cookieHeader = Self.cookieHeader
        let task = Task {
            try await service.fetchHistory(
                cookieHeader: cookieHeader,
                from: "2026-07-01",
                through: "2026-07-02"
            )
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testServiceRejectsNonSuccessfulHTTPResponse() async {
        PerformanceHistoryURLProtocol.store.setDefaultResponse(
            PerformanceHistoryHTTPStub(statusCode: 503, data: Data("{}".utf8), delay: 0)
        )

        do {
            _ = try await Self.service().fetchHistory(
                cookieHeader: Self.cookieHeader,
                from: "2026-07-01",
                through: "2026-07-02"
            )
            XCTFail("Expected network error")
        } catch let error as JDFinancePerformanceHistoryError {
            guard case .network = error else {
                return XCTFail("Expected network error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServiceTreatsUnauthorizedAndHTMLResponsesAsExpiredLogin() async {
        let responses = [
            PerformanceHistoryHTTPStub(statusCode: 401, data: Data(), delay: 0),
            PerformanceHistoryHTTPStub(
                statusCode: 200,
                data: Data("<html><body>login</body></html>".utf8),
                delay: 0,
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )
        ]

        for response in responses {
            PerformanceHistoryURLProtocol.store.reset()
            PerformanceHistoryURLProtocol.store.setDefaultResponse(response)

            do {
                _ = try await Self.service().fetchHistory(
                    cookieHeader: Self.cookieHeader,
                    from: "2026-07-01",
                    through: "2026-07-02"
                )
                XCTFail("Expected an expired login")
            } catch {
                XCTAssertEqual(error as? JDFinancePerformanceHistoryError, .notLoggedIn)
            }
        }
    }

    private static func service() -> JDFinancePerformanceHistoryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PerformanceHistoryURLProtocol.self]
        return JDFinancePerformanceHistoryService(session: URLSession(configuration: configuration))
    }

    private static let cookieHeader = "pt_key=fixture-auth; pt_pin=fixture-user"

    private static func requestPayload(from request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        let components = try XCTUnwrap(URLComponents(string: "?\(body)"))
        let reqData = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "reqData" })?.value)
        let jsonData = try XCTUnwrap(reqData.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
    }

    private static func fixture(days: [(String, String, String?)]) -> String {
        let rows = days.map { date, amount, rate in
            let rateJSON = rate.map { ", \"incomeRate\": \"\($0)\"" } ?? ""
            return "\"\(date)\": { \"incomeDate\": \"\(date)\", \"incomeAmount\": \"\(amount)\"\(rateJSON) }"
        }.joined(separator: ",")
        return """
        {
          "success": true,
          "resultCode": 0,
          "resultMsg": "success",
          "resultData": {
            "code": "0000",
            "success": true,
            "message": "success",
            "data": {
              "incomeFlag": "1",
              "rateFlag": "1",
              "incomeRateVoMap": { \(rows) }
            }
          }
        }
        """
    }

    private static let validRangeFixture = """
    {
      "success": true,
      "resultCode": 0,
      "resultMsg": "success",
      "resultData": {
        "code": "0000",
        "success": true,
        "message": "success",
        "data": {
          "incomeFlag": "1",
          "rateFlag": "1",
          "incomeRateVoMap": {
            "2026-01-02": {
              "incomeAmount": "-12.34",
              "incomeDate": "2026-01-02",
              "incomeRate": "-0.12",
              "index": 2,
              "weekNumber": 1,
              "currentWeek": false,
              "crossMonth": false
            },
            "2026-01-01": {
              "incomeAmount": 8.25,
              "incomeDate": "2026-01-01"
            }
          }
        }
      }
    }
    """

    private static let emptyRangeFixture = fixture(days: [])

    private static let missingMapFixture = """
    {"success":true,"resultCode":0,"resultData":{"code":"0000","success":true,"data":{}}}
    """

    private static let malformedAmountFixture = """
    {"success":true,"resultCode":0,"resultData":{"code":"0000","success":true,"data":{"incomeRateVoMap":{"2026-01-01":{"incomeDate":"2026-01-01","incomeAmount":"not-money"}}}}}
    """

    private static let mismatchedDateFixture = """
    {"success":true,"resultCode":0,"resultData":{"code":"0000","success":true,"data":{"incomeRateVoMap":{"2026-01-01":{"incomeDate":"2026-01-02","incomeAmount":"1.00"}}}}}
    """

    private static let outerLoginExpiredFixture = """
    {"success":false,"resultCode":3,"resultMsg":"请先登录您的京东账号"}
    """

    private static let innerLoginExpiredFixture = """
    {"success":true,"resultCode":0,"resultData":{"code":"1003","success":false,"message":"登录状态已失效","data":null}}
    """
}

private extension Calendar {
    static var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
}

private struct PerformanceHistoryHTTPStub: Sendable {
    var statusCode: Int
    var data: Data
    var delay: TimeInterval
    var headerFields: [String: String] = [:]

    static func json(_ value: String, statusCode: Int = 200, delay: TimeInterval = 0) -> Self {
        Self(
            statusCode: statusCode,
            data: Data(value.utf8),
            delay: delay,
            headerFields: ["Content-Type": "application/json"]
        )
    }
}

private final class PerformanceHistoryResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var defaultResponse: PerformanceHistoryHTTPStub?
    private var requests: [URLRequest] = []

    func reset() {
        lock.lock()
        defaultResponse = nil
        requests = []
        lock.unlock()
    }

    func setDefaultResponse(_ response: PerformanceHistoryHTTPStub) {
        lock.lock()
        defaultResponse = response
        lock.unlock()
    }

    func response(for request: URLRequest) -> PerformanceHistoryHTTPStub? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return defaultResponse
    }

    func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

}

private final class PerformanceHistoryURLProtocol: URLProtocol {
    static let store = PerformanceHistoryResponseStore()

    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.store.response(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        if stub.delay > 0 {
            Thread.sleep(forTimeInterval: stub.delay)
        }
        guard !isStopped else { return }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: stub.headerFields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }
}
