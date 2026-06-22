import CoreFoundation
import Foundation

struct FundQuoteService {
    enum QuoteError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "行情接口返回异常"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuote(code: String, source: QuoteSource = .fundBabyAuto) async throws -> FundQuote {
        switch source {
        case .fundBabyAuto:
            return try await fetchFundBabyAutoQuote(code: code)
        case .eastmoneyFundGZ:
            return try await fetchEastmoneyFundGZQuote(code: code)
        case .tencentOfficial:
            return try await fetchTencentOfficialQuote(code: code)
        }
    }

    func fetchSmartNetValue(code: String, startDate: String) async -> (date: String, value: Double)? {
        guard let start = DateOnlyFormatter.parse(startDate) else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        var current = Calendar.current.startOfDay(for: start)

        for _ in 0..<30 {
            if current > today { return nil }
            let dateText = DateOnlyFormatter.string(from: current)
            if let value = try? await fetchHistoricalNetValue(code: code, date: dateText) {
                return (dateText, value)
            }
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return nil
    }

    func fetchConfirmedNetValue(
        code: String,
        acceptedDate: String,
        latestQuote: FundQuote? = nil
    ) async -> Double? {
        if latestQuote?.netValueDate == acceptedDate,
           let netValue = latestQuote?.netValue,
           netValue > 0 {
            return netValue
        }

        guard let value = try? await fetchHistoricalNetValue(code: code, date: acceptedDate),
              value > 0
        else {
            return nil
        }
        return value
    }

    func lookupFundName(code: String) async -> String? {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }

        if let name = try? await searchFundName(code: code), !name.isEmpty {
            return name
        }

        if let quote = try? await fetchQuote(code: code, source: .fundBabyAuto),
           quote.name != code {
            return quote.name
        }

        return nil
    }

    func fetchFundDetailSupplement(code: String) async -> FundDetailSupplement {
        async let history = fetchNetValueHistorySafely(code: code)
        async let holdings = fetchTopStockHoldingsSafely(code: code)
        let (historyPoints, topHoldings) = await (history, holdings)
        let trendPoints = Array(historyPoints.suffix(90))
        let yesterdayPoint = trendPoints.count >= 2 ? trendPoints[trendPoints.count - 2] : nil
        return FundDetailSupplement(
            trend: trendPoints,
            history: historyPoints,
            topHoldings: topHoldings,
            yesterdayPoint: yesterdayPoint
        )
    }

    private func fetchFundBabyAutoQuote(code: String) async throws -> FundQuote {
        do {
            let eastmoneyQuote = try await fetchEastmoneyFundGZQuote(code: code)
            guard let tencentQuote = try? await fetchTencentOfficialQuote(code: code) else {
                return eastmoneyQuote
            }
            return mergedQuote(eastmoney: eastmoneyQuote, tencent: tencentQuote)
        } catch {
            return try await fetchTencentOfficialQuote(code: code)
        }
    }

    private func fetchEastmoneyFundGZQuote(code: String) async throws -> FundQuote {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "https://fundgz.1234567.com.cn/js/\(code).js?rt=\(timestamp)")!
        var request = URLRequest(url: url)
        request.setValue("https://fundgz.1234567.com.cn/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = String(data: data, encoding: .utf8),
              let payload = parseJSONP(text)
        else {
            throw QuoteError.invalidResponse
        }

        let decoder = JSONDecoder()
        let row = try decoder.decode(FundGZPayload.self, from: payload)
        let realtimeQuote = FundQuote(
            code: row.fundcode ?? code,
            name: row.name ?? code,
            netValue: row.dwjz.doubleValue,
            estimatedNetValue: (row.gsz ?? row.dwjz).doubleValue,
            growthRate: row.gszzl.doubleValue,
            estimateTime: row.gztime ?? "",
            netValueDate: row.jzrq ?? ""
        )
        guard let officialQuote = try? await fetchEastmoneyLatestOfficialQuote(
            code: code,
            fallbackName: realtimeQuote.name
        ) else {
            return realtimeQuote
        }
        return mergedEastmoneyQuote(realtime: realtimeQuote, official: officialQuote)
    }

    private func fetchTencentOfficialQuote(code: String) async throws -> FundQuote {
        let url = URL(string: "https://qt.gtimg.cn/q=jj\(code)")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data, preferredEncoding: Self.gb18030Encoding),
              let row = parseTencentPayload(text, code: code)
        else {
            throw QuoteError.invalidResponse
        }
        return row
    }

    private func fetchHistoricalNetValue(code: String, date: String) async throws -> Double? {
        let url = URL(string: "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(code)&page=1&per=1&sdate=\(date)&edate=\(date)")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data) else {
            throw QuoteError.invalidResponse
        }
        if text.contains("暂无数据") {
            return nil
        }
        return parseHistoricalNetValue(text, date: date)
    }

    private func fetchNetValueHistorySafely(code: String) async -> [FundNetValuePoint] {
        (try? await fetchNetValueHistory(code: code)) ?? []
    }

    private func fetchTopStockHoldingsSafely(code: String) async -> [FundStockHolding] {
        (try? await fetchTopStockHoldings(code: code)) ?? []
    }

    private func fetchNetValueHistory(code: String) async throws -> [FundNetValuePoint] {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "https://fund.eastmoney.com/pingzhongdata/\(code).js?v=\(timestamp)")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data),
              let payload = extractJSONArray(named: "Data_netWorthTrend", from: text)
        else {
            throw QuoteError.invalidResponse
        }
        let rows = try JSONDecoder().decode([NetWorthTrendPayload].self, from: payload)
        return rows.map {
            FundNetValuePoint(
                timestamp: Int64($0.x),
                value: $0.y,
                equityReturn: $0.equityReturn
            )
        }
    }

    private func fetchTopStockHoldings(code: String) async throws -> [FundStockHolding] {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=\(code)&topline=10&year=&month=&_=\(timestamp)")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data) else {
            throw QuoteError.invalidResponse
        }
        var holdings = parseTopStockHoldings(text)
        if holdings.isEmpty {
            return []
        }

        let changes = try? await fetchStockChanges(for: holdings.map(\.code))
        if let changes {
            holdings = holdings.map { holding in
                var next = holding
                next.changeRate = changes[holding.code]
                return next
            }
        }
        return holdings
    }

    private func fetchStockChanges(for codes: [String]) async throws -> [String: Double] {
        let symbols = codes.compactMap(tencentStockSymbol(for:))
        guard !symbols.isEmpty else { return [:] }
        let url = URL(string: "https://qt.gtimg.cn/q=\(symbols.joined(separator: ","))")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data, preferredEncoding: Self.gb18030Encoding) else {
            throw QuoteError.invalidResponse
        }

        var changes: [String: Double] = [:]
        for code in codes {
            guard let symbol = tencentStockSymbol(for: code),
                  let payload = parseTencentStockPayload(text, symbol: symbol)
            else {
                continue
            }
            changes[code] = payload
        }
        return changes
    }

    private func searchFundName(code: String) async throws -> String? {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let callback = "FundPulseSuggest_\(timestamp)"
        var components = URLComponents(string: "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx")!
        components.queryItems = [
            URLQueryItem(name: "m", value: "1"),
            URLQueryItem(name: "key", value: code),
            URLQueryItem(name: "callback", value: callback),
            URLQueryItem(name: "_", value: "\(timestamp)")
        ]
        guard let url = components.url else { throw QuoteError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data),
              let payload = parseJSONP(text)
        else {
            throw QuoteError.invalidResponse
        }

        let response = try JSONDecoder().decode(FundSearchResponse.self, from: payload)
        let matchedFund = response.datas?.first { $0.code == code }
        return matchedFund?.name?.nilIfBlank ?? matchedFund?.shortName?.nilIfBlank
    }

    private func fetchEastmoneyLatestOfficialQuote(code: String, fallbackName: String) async throws -> FundQuote? {
        let url = URL(string: "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(code)&page=1&per=1")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let text = decodedText(data),
              let row = parseLatestOfficialNetValue(text)
        else {
            throw QuoteError.invalidResponse
        }
        return FundQuote(
            code: code,
            name: fallbackName,
            netValue: row.value,
            estimatedNetValue: row.value,
            growthRate: row.growthRate ?? 0,
            estimateTime: "",
            netValueDate: row.date
        )
    }

    private func parseJSONP(_ text: String) -> Data? {
        guard let start = text.firstIndex(of: "("),
              let end = text.lastIndex(of: ")"),
              start < end
        else {
            return nil
        }
        let json = text[text.index(after: start)..<end]
        return String(json).data(using: .utf8)
    }

    private func parseTencentPayload(_ text: String, code: String) -> FundQuote? {
        guard let firstQuote = text.firstIndex(of: "\""),
              let lastQuote = text.lastIndex(of: "\""),
              firstQuote < lastQuote
        else {
            return nil
        }

        let payload = String(text[text.index(after: firstQuote)..<lastQuote])
        let parts = payload.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        func part(_ index: Int) -> String {
            parts.indices.contains(index) ? parts[index] : ""
        }

        let netValue = Double(part(5)) ?? 0
        guard netValue > 0 else { return nil }
        let growthRate = Double(part(7)) ?? 0
        let netValueDate = String(part(8).prefix(10))
        return FundQuote(
            code: part(0).isEmpty ? code : part(0),
            name: part(1).isEmpty ? code : part(1),
            netValue: netValue,
            estimatedNetValue: netValue,
            growthRate: growthRate,
            estimateTime: "",
            netValueDate: netValueDate
        )
    }

    private func parseHistoricalNetValue(_ text: String, date: String) -> Double? {
        let rows = text.components(separatedBy: "<tr")
        guard let row = rows.first(where: { $0.contains("<td>\(date)</td>") }),
              let parsed = parseOfficialNetValueRow(row)
        else {
            return nil
        }
        return parsed.value
    }

    private func parseLatestOfficialNetValue(_ text: String) -> (date: String, value: Double, growthRate: Double?)? {
        let rows = text.components(separatedBy: "<tr")
        return rows.lazy.compactMap(parseOfficialNetValueRow).first
    }

    private func extractJSONArray(named variableName: String, from text: String) -> Data? {
        guard let nameRange = text.range(of: variableName),
              let start = text[nameRange.upperBound...].firstIndex(of: "[")
        else {
            return nil
        }

        var depth = 0
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    return String(text[start..<end]).data(using: .utf8)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func parseTopStockHoldings(_ text: String) -> [FundStockHolding] {
        let headerRow = firstMatch(
            pattern: #"<thead[\s\S]*?<tr[\s\S]*?</tr>[\s\S]*?</thead>"#,
            in: text
        ) ?? ""
        let headerCells = matches(
            pattern: #"<th[\s\S]*?>([\s\S]*?)</th>"#,
            in: headerRow
        ).map { stripHTML($0).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression) }

        var codeIndex = -1
        var nameIndex = -1
        var weightIndex = -1
        for (index, title) in headerCells.enumerated() {
            if codeIndex < 0, title.contains("股票代码") || title.contains("证券代码") {
                codeIndex = index
            }
            if nameIndex < 0, title.contains("股票名称") || title.contains("证券名称") {
                nameIndex = index
            }
            if weightIndex < 0, title.contains("占净值比例") || title.contains("占比") {
                weightIndex = index
            }
        }

        let body = firstMatch(pattern: #"<tbody[\s\S]*?</tbody>"#, in: text) ?? text
        return matches(pattern: #"<tr[\s\S]*?</tr>"#, in: body).compactMap { row in
            let cells = matches(pattern: #"<td[\s\S]*?>([\s\S]*?)</td>"#, in: row).map(stripHTML)
            guard !cells.isEmpty else { return nil }

            let code = cell(at: codeIndex, in: cells).flatMap(stockCode(in:))
                ?? cells.compactMap(stockCode(in:)).first
                ?? ""
            let name = cell(at: nameIndex, in: cells)
                ?? cells.first(where: {
                    !$0.isEmpty
                        && $0 != code
                        && !$0.contains("%")
                        && Double($0.replacingOccurrences(of: ",", with: "")) == nil
                })
                ?? ""
            let weight = cell(at: weightIndex, in: cells).flatMap(weightText(in:))
                ?? cells.compactMap(weightText(in:)).first
                ?? ""

            guard !code.isEmpty || !name.isEmpty || !weight.isEmpty else { return nil }
            return FundStockHolding(code: code, name: name, weight: weight, changeRate: nil)
        }
        .prefix(10)
        .map { $0 }
    }

    private func parseTencentStockPayload(_ text: String, symbol: String) -> Double? {
        let variable = "v_\(symbol)"
        guard let variableRange = text.range(of: "\(variable)=\""),
              let endQuote = text[variableRange.upperBound...].firstIndex(of: "\"")
        else {
            return nil
        }
        let payload = String(text[variableRange.upperBound..<endQuote])
        let parts = payload.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 5 else { return nil }
        return Double(parts[5])
    }

    private func tencentStockSymbol(for code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{6}$"#, options: .regularExpression) != nil {
            if trimmed.hasPrefix("6") || trimmed.hasPrefix("9") {
                return "s_sh\(trimmed)"
            }
            if trimmed.hasPrefix("4") || trimmed.hasPrefix("8") {
                return "s_bj\(trimmed)"
            }
            return "s_sz\(trimmed)"
        }
        if trimmed.range(of: #"^\d{5}$"#, options: .regularExpression) != nil {
            return "s_hk\(trimmed)"
        }
        return nil
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        matches(pattern: pattern, in: text).first
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let matchRange = Range(match.range(at: captureIndex), in: text) else {
                return nil
            }
            return String(text[matchRange])
        }
    }

    private func cell(at index: Int, in cells: [String]) -> String? {
        guard index >= 0, cells.indices.contains(index) else {
            return nil
        }
        return cells[index]
    }

    private func stockCode(in text: String) -> String? {
        firstMatch(pattern: #"(\d{5,6})"#, in: text)
    }

    private func weightText(in text: String) -> String? {
        firstMatch(pattern: #"(\d+(?:\.\d+)?)\s*%"#, in: text).map { "\($0)%" }
    }

    private func parseOfficialNetValueRow(_ row: String) -> (date: String, value: Double, growthRate: Double?)? {
        let pattern = #"<td[^>]*>(.*?)</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(row.startIndex..<row.endIndex, in: row)
        let cells = regex.matches(in: row, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let cellRange = Range(match.range(at: 1), in: row)
            else {
                return nil
            }
            return stripHTML(String(row[cellRange]))
        }
        guard cells.count >= 2 else { return nil }
        let date = cells[0]
        guard DateOnlyFormatter.parse(date) != nil,
              let value = Double(cells[1])
        else {
            return nil
        }
        let growthRate = cells.count >= 4 ? Double(cells[3].replacingOccurrences(of: "%", with: "")) : nil
        return (date, value, growthRate)
    }

    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergedQuote(eastmoney: FundQuote, tencent: FundQuote) -> FundQuote {
        guard !tencent.netValueDate.isEmpty,
              tencent.netValueDate >= eastmoney.netValueDate
        else {
            return eastmoney
        }

        var merged = eastmoney
        merged.netValue = tencent.netValue
        merged.netValueDate = tencent.netValueDate

        let estimateDate = eastmoney.estimateTime.count >= 10 ? String(eastmoney.estimateTime.prefix(10)) : ""
        if estimateDate.isEmpty || estimateDate <= tencent.netValueDate {
            merged.estimatedNetValue = tencent.netValue
            merged.growthRate = tencent.growthRate
            merged.estimateTime = ""
        }
        return merged
    }

    private func mergedEastmoneyQuote(realtime: FundQuote, official: FundQuote) -> FundQuote {
        guard !official.netValueDate.isEmpty,
              official.netValueDate >= realtime.netValueDate
        else {
            return realtime
        }

        var merged = realtime
        merged.netValue = official.netValue
        merged.netValueDate = official.netValueDate

        let estimateDate = realtime.estimateTime.count >= 10 ? String(realtime.estimateTime.prefix(10)) : ""
        if estimateDate.isEmpty || estimateDate <= official.netValueDate {
            merged.estimatedNetValue = official.netValue
            merged.growthRate = official.growthRate
            merged.estimateTime = ""
        }
        return merged
    }

    private func decodedText(_ data: Data, preferredEncoding: String.Encoding = .utf8) -> String? {
        String(data: data, encoding: preferredEncoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: Self.gb18030Encoding)
    }

    private static let gb18030Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
}

private struct FundGZPayload: Decodable {
    var fundcode: String?
    var name: String?
    var dwjz: String?
    var gsz: String?
    var gszzl: String?
    var gztime: String?
    var jzrq: String?
}

private struct NetWorthTrendPayload: Decodable {
    var x: Double
    var y: Double
    var equityReturn: Double?
}

private struct FundSearchResponse: Decodable {
    var datas: [FundSearchItem]?

    private enum CodingKeys: String, CodingKey {
        case datas = "Datas"
    }
}

private struct FundSearchItem: Decodable {
    var code: String?
    var name: String?
    var shortName: String?

    private enum CodingKeys: String, CodingKey {
        case code = "CODE"
        case name = "NAME"
        case shortName = "SHORTNAME"
    }
}

private extension Optional where Wrapped == String {
    var doubleValue: Double {
        guard let self else { return 0 }
        return Double(self.replacingOccurrences(of: "%", with: "")) ?? 0
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
