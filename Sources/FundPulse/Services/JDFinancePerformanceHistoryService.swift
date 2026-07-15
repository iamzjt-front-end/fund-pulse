import Foundation

struct JDFinancePerformanceHistoryService: Sendable {
    static let endpoint = URL(
        string: "https://ms.jr.jd.com/gw2/generic/cfGateway/h5/m/getIncomeDateDetailRange"
    )!
    static let referer = "https://mix.jd.com/mix/asset-mark/home/?conditionType=fund"
    static let origin = "https://mix.jd.com"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchHistory(
        cookieHeader: String?,
        from startDate: String,
        through endDate: String? = nil,
        existing: JDFinancePerformanceHistory = .empty,
        now: Date = .now
    ) async throws -> JDFinancePerformanceHistory {
        guard let cookieHeader = JDFinanceCookieHeaderFilter.scopedHeader(from: cookieHeader)
        else {
            throw JDFinancePerformanceHistoryError.notLoggedIn
        }

        let resolvedEndDate: String
        if let endDate {
            resolvedEndDate = endDate
        } else {
            guard let yesterday = Self.calendar.date(byAdding: .day, value: -1, to: now) else {
                throw JDFinancePerformanceHistoryError.invalidDateRange
            }
            resolvedEndDate = DateOnlyFormatter.string(from: yesterday)
        }

        let ranges = try Self.requestRanges(from: startDate, through: resolvedEndDate)
        var daysByDate: [String: JDFinancePerformanceDay] = [:]
        for day in existing.days {
            daysByDate[day.date] = day
        }

        do {
            for range in ranges {
                try Task.checkCancellation()
                let request = try Self.request(for: range, cookieHeader: cookieHeader)
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw JDFinancePerformanceHistoryError.network("京东历史收益接口未返回有效响应")
                }
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw JDFinancePerformanceHistoryError.notLoggedIn
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    let suffix = "（HTTP \(httpResponse.statusCode)）"
                    throw JDFinancePerformanceHistoryError.network("京东历史收益接口请求失败\(suffix)")
                }
                if Self.isLoginHTMLResponse(httpResponse, data: data) {
                    throw JDFinancePerformanceHistoryError.notLoggedIn
                }

                let fetchedDays = try JDFinancePerformanceHistoryParser.parse(data: data)
                for day in fetchedDays where day.date >= range.from && day.date <= range.through {
                    daysByDate[day.date] = day
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as JDFinancePerformanceHistoryError {
            throw error
        } catch {
            throw JDFinancePerformanceHistoryError.network(error.localizedDescription)
        }

        return JDFinancePerformanceHistory(
            days: daysByDate.values.sorted { $0.date < $1.date },
            coveredFrom: startDate,
            coveredThrough: resolvedEndDate,
            isComplete: true
        )
    }

    static func requestRanges(
        from startDate: String,
        through endDate: String
    ) throws -> [JDFinancePerformanceHistoryRange] {
        guard let start = exactDate(startDate),
              let end = exactDate(endDate),
              start <= end
        else {
            throw JDFinancePerformanceHistoryError.invalidDateRange
        }

        var ranges: [JDFinancePerformanceHistoryRange] = []
        var cursor = start
        while cursor <= end {
            let year = calendar.component(.year, from: cursor)
            guard let yearEnd = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: 12,
                day: 31
            )),
            let maximumSpanEnd = calendar.date(byAdding: .day, value: 365, to: cursor)
            else {
                throw JDFinancePerformanceHistoryError.invalidDateRange
            }

            let rangeEnd = min(end, min(yearEnd, maximumSpanEnd))
            ranges.append(
                JDFinancePerformanceHistoryRange(
                    from: DateOnlyFormatter.string(from: cursor),
                    through: DateOnlyFormatter.string(from: rangeEnd)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: rangeEnd) else {
                throw JDFinancePerformanceHistoryError.invalidDateRange
            }
            cursor = next
        }
        return ranges
    }

    static func request(
        for range: JDFinancePerformanceHistoryRange,
        cookieHeader: String
    ) throws -> URLRequest {
        guard let cookieHeader = JDFinanceCookieHeaderFilter.scopedHeader(from: cookieHeader) else {
            throw JDFinancePerformanceHistoryError.notLoggedIn
        }
        let payload: [String: Any] = [
            "risk_type": "",
            "rf_type": "fund",
            "rateType": "most",
            "rateFlag": "1",
            "incomeDateDimension": "day",
            "dateFrom": range.from,
            "dateTo": range.through
        ]
        let payloadData = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        guard let payloadText = String(data: payloadData, encoding: .utf8) else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "reqData", value: payloadText)]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }

        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        return request
    }

    private static func exactDate(_ value: String) -> Date? {
        guard let date = DateOnlyFormatter.parse(value),
              DateOnlyFormatter.string(from: date) == value
        else {
            return nil
        }
        return date
    }

    private static func isLoginHTMLResponse(_ response: HTTPURLResponse, data: Data) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/html") { return true }

        let prefix = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html")
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
}
