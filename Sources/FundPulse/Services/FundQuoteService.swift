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

    func fetchQuote(code: String, source: QuoteSource = .eastmoneyCore) async throws -> FundQuote {
        switch source {
        case .eastmoneyCore, .fundBabyAuto:
            return try await fetchFundBabyAutoQuote(code: code)
        case .eastmoneyFundGZ:
            return try await fetchEastmoneyFundGZQuote(code: code)
        case .tencentOfficial:
            return try await fetchTencentOfficialQuote(code: code)
        }
    }

    func fetchQuotes(codes: [String], source: QuoteSource = .eastmoneyCore) async -> [String: FundQuote] {
        let uniqueCodes = Array(Set(codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        guard !uniqueCodes.isEmpty else { return [:] }

        switch source {
        case .eastmoneyCore, .fundBabyAuto:
            var quotes = (try? await fetchEastmoneyCoreQuotes(codes: uniqueCodes)) ?? [:]
            let missingCodes = uniqueCodes.filter { quotes[$0] == nil }
            if !missingCodes.isEmpty {
                let fallbackQuotes = await fetchLegacyQuotesIndividually(codes: missingCodes)
                quotes.merge(fallbackQuotes) { current, _ in current }
            }
            return quotes
        case .eastmoneyFundGZ, .tencentOfficial:
            return await fetchQuotesIndividually(codes: uniqueCodes, source: source)
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

    func fetchFundDetailSupplement(code: String, now: Date = .now) async -> FundDetailSupplement {
        async let history = fetchNetValueHistorySafely(code: code)
        async let position = fetchPositionSupplementSafely(code: code)
        async let assetAllocation = fetchAssetAllocationSafely(code: code)
        let (historyPoints, positionSupplement, assetItems) = await (history, position, assetAllocation)
        let industryAllocation = await fetchSectorAllocationSafely(
            code: code,
            date: positionSupplement.holdingDisclosureDate
        )
        let yesterdayPoint = Self.yesterdayNetValuePoint(from: historyPoints, now: now)
        return FundDetailSupplement(
            trend: historyPoints,
            history: historyPoints,
            topHoldings: positionSupplement.topHoldings,
            relatedSectors: positionSupplement.relatedSectors,
            industryAllocation: industryAllocation,
            assetAllocation: assetItems,
            holdingDisclosureDate: positionSupplement.holdingDisclosureDate,
            industryDisclosureDate: industryAllocation.first?.date,
            assetAllocationDate: assetItems.first?.date,
            yesterdayPoint: yesterdayPoint
        )
    }

    private static func yesterdayNetValuePoint(from points: [FundNetValuePoint], now: Date) -> FundNetValuePoint? {
        let today = DateOnlyFormatter.string(from: now)
        return points.last { point in
            let date = Date(timeIntervalSince1970: TimeInterval(point.timestamp) / 1000)
            return DateOnlyFormatter.string(from: date) < today
        }
    }

    private func fetchQuotesIndividually(codes: [String], source: QuoteSource) async -> [String: FundQuote] {
        await withTaskGroup(of: (String, FundQuote?).self) { group in
            for code in codes {
                group.addTask { [session] in
                    let service = FundQuoteService(session: session)
                    do {
                        return (code, try await service.fetchQuote(code: code, source: source))
                    } catch {
                        return (code, nil)
                    }
                }
            }

            var quotes: [String: FundQuote] = [:]
            for await (code, quote) in group {
                if let quote {
                    quotes[code] = quote
                }
            }
            return quotes
        }
    }

    private func fetchLegacyQuotesIndividually(codes: [String]) async -> [String: FundQuote] {
        await withTaskGroup(of: (String, FundQuote?).self) { group in
            for code in codes {
                group.addTask { [session] in
                    let service = FundQuoteService(session: session)
                    do {
                        return (code, try await service.fetchLegacyQuoteWithTencentFallback(code: code))
                    } catch {
                        return (code, nil)
                    }
                }
            }

            var quotes: [String: FundQuote] = [:]
            for await (code, quote) in group {
                if let quote {
                    quotes[code] = quote
                }
            }
            return quotes
        }
    }

    private func fetchFundBabyAutoQuote(code: String) async throws -> FundQuote {
        do {
            return try await fetchEastmoneyCoreQuote(code: code)
        } catch {
            return try await fetchLegacyQuoteWithTencentFallback(code: code)
        }
    }

    private func fetchLegacyQuoteWithTencentFallback(code: String) async throws -> FundQuote {
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

    private func fetchEastmoneyCoreQuote(code: String) async throws -> FundQuote {
        guard let quote = try await fetchEastmoneyCoreQuotes(codes: [code])[code] else {
            throw QuoteError.invalidResponse
        }
        return quote
    }

    private func fetchEastmoneyCoreQuotes(codes: [String]) async throws -> [String: FundQuote] {
        let codes = codes.filter { !$0.isEmpty }
        guard !codes.isEmpty else { return [:] }

        var components = URLComponents(string: "https://fundcomapi.eastmoney.com/mm/newCore/FundCoreDiyNew")!
        components.queryItems = [
            URLQueryItem(name: "FCODES", value: codes.joined(separator: ",")),
            URLQueryItem(name: "FIELDS", value: "SHORTNAME,RZDF,DWJZ,JZRQ,FSRQ,NAV,GSZZL,GZTIME,GSZ,FCODE,QDCODE,PTYPE"),
            URLQueryItem(name: "deviceid", value: "1234567.py.service"),
            URLQueryItem(name: "version", value: "6.5.5"),
            URLQueryItem(name: "product", value: "EFund"),
            URLQueryItem(name: "plat", value: "web")
        ]
        guard let url = components.url else { throw QuoteError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(EastmoneyCoreQuoteResponse.self, from: data)
        guard response.success != false,
              let rows = response.data,
              !rows.isEmpty
        else {
            throw QuoteError.invalidResponse
        }

        var quotes: [String: FundQuote] = [:]
        for row in rows {
            guard let quote = row.quote else { continue }
            quotes[quote.code] = quote
        }
        if quotes.isEmpty {
            throw QuoteError.invalidResponse
        }
        return quotes
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

    private func fetchPositionSupplementSafely(code: String) async -> FundPositionSupplement {
        if let supplement = try? await fetchMobileInvestmentPosition(code: code),
           !supplement.topHoldings.isEmpty || !supplement.relatedSectors.isEmpty {
            return supplement
        }
        let holdings = await fetchTopStockHoldingsSafely(code: code)
        return FundPositionSupplement(
            topHoldings: holdings,
            relatedSectors: [],
            holdingDisclosureDate: nil
        )
    }

    private func fetchSectorAllocationSafely(code: String, date: String?) async -> [FundSectorExposure] {
        (try? await fetchSectorAllocation(code: code, date: date)) ?? []
    }

    private func fetchAssetAllocationSafely(code: String) async -> [FundAssetAllocationItem] {
        (try? await fetchAssetAllocation(code: code)) ?? []
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

    private func fetchMobileInvestmentPosition(code: String) async throws -> FundPositionSupplement {
        var components = URLComponents(string: "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNInverstPosition")!
        components.queryItems = eastmoneyMobileQueryItems(code: code)
        guard let url = components.url else { throw QuoteError.invalidResponse }

        let (data, _) = try await session.data(for: eastmoneyMobileRequest(url: url))
        let response = try JSONDecoder().decode(MobileInvestmentPositionResponse.self, from: data)
        guard response.success == true,
              let stocks = response.datas?.fundStocks
        else {
            throw QuoteError.invalidResponse
        }

        var holdings = stocks.prefix(10).compactMap { row -> FundStockHolding? in
            let code = row.code?.nilIfBlank ?? ""
            let name = row.name?.nilIfBlank ?? ""
            let weight = row.weight.doubleValue
            guard !code.isEmpty || !name.isEmpty || weight > 0 else { return nil }
            return FundStockHolding(
                code: code,
                name: name,
                weight: weight > 0 ? MoneyFormatter.percent(weight, signed: false) : "",
                changeRate: nil,
                industryCode: row.industryCode?.nilIfBlank,
                industryName: row.industryName?.nilIfBlank,
                positionChangeType: row.positionChangeType?.nilIfBlank,
                positionChangeRate: row.positionChangeRate.doubleValue,
                market: row.market?.nilIfBlank
            )
        }

        if !holdings.isEmpty,
           let changes = try? await fetchStockChanges(for: holdings.map(\.code)) {
            holdings = holdings.map { holding in
                var next = holding
                next.changeRate = changes[holding.code]
                return next
            }
        }

        let relatedSectors = aggregateRelatedSectors(
            from: stocks,
            date: response.expansion?.nilIfBlank
        )
        return FundPositionSupplement(
            topHoldings: holdings,
            relatedSectors: relatedSectors,
            holdingDisclosureDate: response.expansion?.nilIfBlank
        )
    }

    private func fetchSectorAllocation(code: String, date: String?) async throws -> [FundSectorExposure] {
        var components = URLComponents(string: "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNSectorAllocation")!
        var queryItems = eastmoneyMobileQueryItems(code: code)
        queryItems.append(URLQueryItem(name: "DATE", value: date ?? ""))
        components.queryItems = queryItems
        guard let url = components.url else { throw QuoteError.invalidResponse }

        let (data, _) = try await session.data(for: eastmoneyMobileRequest(url: url))
        let response = try JSONDecoder().decode(MobileSectorAllocationResponse.self, from: data)
        guard response.success == true,
              let rows = response.datas
        else {
            throw QuoteError.invalidResponse
        }

        return rows.compactMap { row -> FundSectorExposure? in
            guard let name = row.name?.nilIfBlank,
                  name != "合计"
            else { return nil }
            let weight = row.weight.doubleValue
            guard weight > 0 else { return nil }
            return FundSectorExposure(
                code: nil,
                name: name,
                weight: weight,
                date: row.date?.nilIfBlank ?? response.expansion?.nilIfBlank,
                source: .disclosedIndustry
            )
        }
        .sorted { $0.weight > $1.weight }
    }

    private func fetchAssetAllocation(code: String) async throws -> [FundAssetAllocationItem] {
        var components = URLComponents(string: "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNAssetAllocationNew")!
        components.queryItems = eastmoneyMobileQueryItems(code: code)
        guard let url = components.url else { throw QuoteError.invalidResponse }

        let (data, _) = try await session.data(for: eastmoneyMobileRequest(url: url))
        let response = try JSONDecoder().decode(MobileAssetAllocationResponse.self, from: data)
        guard response.success == true,
              let row = response.datas?.first
        else {
            throw QuoteError.invalidResponse
        }

        let date = row.date?.nilIfBlank ?? response.expansion?.nilIfBlank
        let items: [(String, Double)] = [
            ("股票", row.stock.doubleValue),
            ("债券", row.bond.doubleValue),
            ("现金", row.cash.doubleValue),
            ("基金", row.fund.doubleValue),
            ("其他", row.other.doubleValue)
        ]
        return items.compactMap { name, weight in
            guard weight > 0 else { return nil }
            return FundAssetAllocationItem(name: name, weight: weight, date: date)
        }
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

    private func aggregateRelatedSectors(
        from stocks: [MobileFundStockPayload],
        date: String?
    ) -> [FundSectorExposure] {
        var sectors: [String: (code: String?, name: String, weight: Double)] = [:]
        for stock in stocks {
            guard let name = stock.industryName?.nilIfBlank else { continue }
            let code = stock.industryCode?.nilIfBlank
            let key = code ?? name
            let current = sectors[key] ?? (code: code, name: name, weight: 0)
            sectors[key] = (code: code, name: name, weight: current.weight + stock.weight.doubleValue)
        }

        return sectors.values
            .filter { $0.weight > 0 }
            .map {
                FundSectorExposure(
                    code: $0.code,
                    name: $0.name,
                    weight: $0.weight,
                    date: date,
                    source: .topHoldings
                )
            }
            .sorted { $0.weight > $1.weight }
    }

    private func eastmoneyMobileQueryItems(code: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "FCODE", value: code),
            URLQueryItem(name: "deviceid", value: "Wap"),
            URLQueryItem(name: "plat", value: "Wap"),
            URLQueryItem(name: "product", value: "EFund"),
            URLQueryItem(name: "version", value: "2.0.0"),
            URLQueryItem(name: "Uid", value: "")
        ]
    }

    private func eastmoneyMobileRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        return request
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

private struct EastmoneyCoreQuoteResponse: Decodable {
    var data: [EastmoneyCoreQuotePayload]?
    var success: Bool?
}

private struct EastmoneyCoreQuotePayload: Decodable {
    var code: String?
    var quoteCode: String?
    var name: String?
    var netValue: LossyString?
    var netValueDate: LossyString?
    var fallbackNetValueDate: LossyString?
    var estimatedNetValue: LossyString?
    var estimatedGrowthRate: LossyString?
    var estimateTime: LossyString?
    var latestGrowthRate: LossyString?

    var quote: FundQuote? {
        let resolvedCode = code?.nilIfBlank ?? quoteCode?.nilIfBlank ?? ""
        guard !resolvedCode.isEmpty else { return nil }

        let netValue = netValue.doubleValue
        let estimatedNetValue = estimatedNetValue.doubleValue
        let hasRealtimeEstimate = estimatedNetValue > 0 || estimateTime.stringValue?.nilIfDash != nil
        let growthRate = hasRealtimeEstimate
            ? estimatedGrowthRate.doubleValue
            : (latestGrowthRate.doubleValue != 0 ? latestGrowthRate.doubleValue : estimatedGrowthRate.doubleValue)
        let resolvedNetValue = netValue > 0 ? netValue : estimatedNetValue
        guard resolvedNetValue > 0 else { return nil }

        return FundQuote(
            code: resolvedCode,
            name: name?.nilIfDash ?? resolvedCode,
            netValue: resolvedNetValue,
            estimatedNetValue: estimatedNetValue > 0 ? estimatedNetValue : resolvedNetValue,
            growthRate: growthRate,
            estimateTime: hasRealtimeEstimate ? (estimateTime.stringValue?.nilIfDash ?? "") : "",
            netValueDate: netValueDate.stringValue?.nilIfDash
                ?? fallbackNetValueDate.stringValue?.nilIfDash
                ?? ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case code = "FCODE"
        case quoteCode = "QDCODE"
        case name = "SHORTNAME"
        case netValue = "DWJZ"
        case netValueDate = "FSRQ"
        case fallbackNetValueDate = "JZRQ"
        case estimatedNetValue = "GSZ"
        case estimatedGrowthRate = "GSZZL"
        case estimateTime = "GZTIME"
        case latestGrowthRate = "RZDF"
    }
}

private struct FundPositionSupplement: Equatable {
    var topHoldings: [FundStockHolding]
    var relatedSectors: [FundSectorExposure]
    var holdingDisclosureDate: String?
}

private struct MobileInvestmentPositionResponse: Decodable {
    var datas: MobileInvestmentPositionData?
    var success: Bool?
    var expansion: String?

    private enum CodingKeys: String, CodingKey {
        case datas = "Datas"
        case success = "Success"
        case expansion = "Expansion"
    }
}

private struct MobileInvestmentPositionData: Decodable {
    var fundStocks: [MobileFundStockPayload]?
}

private struct MobileFundStockPayload: Decodable {
    var code: String?
    var name: String?
    var weight: String?
    var industryCode: String?
    var industryName: String?
    var positionChangeType: String?
    var positionChangeRate: String?
    var market: String?

    private enum CodingKeys: String, CodingKey {
        case code = "GPDM"
        case name = "GPJC"
        case weight = "JZBL"
        case industryCode = "INDEXCODE"
        case industryName = "INDEXNAME"
        case positionChangeType = "PCTNVCHGTYPE"
        case positionChangeRate = "PCTNVCHG"
        case market = "NEWTEXCH"
    }
}

private struct MobileSectorAllocationResponse: Decodable {
    var datas: [MobileSectorAllocationPayload]?
    var success: Bool?
    var expansion: String?

    private enum CodingKeys: String, CodingKey {
        case datas = "Datas"
        case success = "Success"
        case expansion = "Expansion"
    }
}

private struct MobileSectorAllocationPayload: Decodable {
    var name: String?
    var weight: String?
    var date: String?

    private enum CodingKeys: String, CodingKey {
        case name = "HYMC"
        case weight = "ZJZBL"
        case date = "FSRQ"
    }
}

private struct MobileAssetAllocationResponse: Decodable {
    var datas: [MobileAssetAllocationPayload]?
    var success: Bool?
    var expansion: String?

    private enum CodingKeys: String, CodingKey {
        case datas = "Datas"
        case success = "Success"
        case expansion = "Expansion"
    }
}

private struct MobileAssetAllocationPayload: Decodable {
    var date: String?
    var stock: String?
    var bond: String?
    var cash: String?
    var fund: String?
    var other: String?

    private enum CodingKeys: String, CodingKey {
        case date = "FSRQ"
        case stock = "GP"
        case bond = "ZQ"
        case cash = "HB"
        case fund = "JJ"
        case other = "QT"
    }
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

private struct LossyString: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = ""
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = ""
        }
    }
}

private extension Optional where Wrapped == String {
    var doubleValue: Double {
        guard let self else { return 0 }
        let normalized = self
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized) ?? 0
    }
}

private extension Optional where Wrapped == LossyString {
    var stringValue: String? {
        self?.value
    }

    var doubleValue: Double {
        stringValue.doubleValue
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfDash: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "--" ? nil : trimmed
    }
}
