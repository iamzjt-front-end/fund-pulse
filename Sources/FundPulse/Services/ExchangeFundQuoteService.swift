import Foundation

struct ExchangeFundQuoteService {
    private static let eastmoneyQuoteEndpoints = [
        URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")!,
        URL(string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get")!
    ]

    enum QuoteError: LocalizedError {
        case invalidCode
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidCode:
                "请输入 6 位场内基金代码"
            case .invalidResponse:
                "交易所行情接口返回异常"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuote(code: String) async throws -> FundQuote {
        let normalizedCode = Self.normalizedCode(code)
        guard let normalizedCode else { throw QuoteError.invalidCode }
        guard let quote = try await fetchEastmoneyQuotes(codes: [normalizedCode])[normalizedCode] else {
            throw QuoteError.invalidResponse
        }
        return quote
    }

    func fetchQuotes(codes: [String]) async -> [String: FundQuote] {
        let normalizedCodes = Array(Set(codes.compactMap(Self.normalizedCode))).sorted()
        guard !normalizedCodes.isEmpty else { return [:] }

        var quotes: [String: FundQuote] = [:]
        for batchStart in stride(from: 0, to: normalizedCodes.count, by: 50) {
            let batchEnd = min(batchStart + 50, normalizedCodes.count)
            guard let batchQuotes = try? await fetchEastmoneyQuotes(
                codes: Array(normalizedCodes[batchStart..<batchEnd])
            ) else {
                continue
            }
            quotes.merge(batchQuotes) { _, latest in latest }
        }
        return quotes
    }

    func lookupFundName(code: String) async -> String? {
        guard let quote = try? await fetchQuote(code: code), quote.name != quote.code else {
            return nil
        }
        return quote.name
    }

    static func securityID(for code: String) -> String? {
        guard let code = normalizedCode(code) else { return nil }
        let market = code.first.map { "569".contains($0) } == true ? "1" : "0"
        return "\(market).\(code)"
    }

    static func decodeQuotes(from data: Data) throws -> [String: FundQuote] {
        let payload = try JSONDecoder().decode(EastmoneyExchangeQuoteResponse.self, from: data)
        guard payload.returnCode == 0,
              let rows = payload.data?.quotes,
              !rows.isEmpty
        else {
            throw QuoteError.invalidResponse
        }

        var quotes: [String: FundQuote] = [:]
        for row in rows {
            guard let code = normalizedCode(row.code?.value ?? ""),
                  let price = row.price?.value,
                  price.isFinite,
                  price > 0,
                  let timestamp = row.timestamp?.value,
                  timestamp.isFinite,
                  timestamp > 946_684_800
            else {
                continue
            }

            let previousClose = row.previousClose?.value
            let growthRate: Double
            if let reportedRate = row.growthRate?.value, reportedRate.isFinite {
                growthRate = reportedRate
            } else if let previousClose, previousClose.isFinite, previousClose > 0 {
                growthRate = (price - previousClose) / previousClose * 100
            } else {
                growthRate = 0
            }

            let quoteDate = Date(timeIntervalSince1970: timestamp)
            let priceTime = formattedPriceTime(quoteDate)
            let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            quotes[code] = FundQuote(
                code: code,
                name: name?.isEmpty == false ? name! : code,
                netValue: price,
                estimatedNetValue: price,
                growthRate: growthRate,
                estimateTime: priceTime,
                netValueDate: DateOnlyFormatter.string(from: quoteDate),
                marketPriceTime: priceTime,
                previousClose: previousClose
            )
        }

        guard !quotes.isEmpty else { throw QuoteError.invalidResponse }
        return quotes
    }

    private func fetchEastmoneyQuotes(codes: [String]) async throws -> [String: FundQuote] {
        var lastError: Error?
        for endpoint in Self.eastmoneyQuoteEndpoints {
            try Task.checkCancellation()
            do {
                return try await fetchEastmoneyQuotes(codes: codes, endpoint: endpoint)
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
            }
        }
        throw lastError ?? QuoteError.invalidResponse
    }

    private func fetchEastmoneyQuotes(
        codes: [String],
        endpoint: URL
    ) async throws -> [String: FundQuote] {
        let securityIDs = codes.compactMap(Self.securityID)
        guard securityIDs.count == codes.count, !securityIDs.isEmpty else {
            throw QuoteError.invalidCode
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f2,f3,f12,f14,f18,f124"),
            URLQueryItem(name: "secids", value: securityIDs.joined(separator: ","))
        ]
        guard let url = components.url else { throw QuoteError.invalidResponse }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw QuoteError.invalidResponse
        }
        return try Self.decodeQuotes(from: data)
    }

    private static func normalizedCode(_ code: String) -> String? {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
        return code
    }

    private static func formattedPriceTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct EastmoneyExchangeQuoteResponse: Decodable {
    var returnCode: Int?
    var data: EastmoneyExchangeQuoteData?

    private enum CodingKeys: String, CodingKey {
        case returnCode = "rc"
        case data
    }
}

private struct EastmoneyExchangeQuoteData: Decodable {
    var quotes: [EastmoneyExchangeQuotePayload]?

    private enum CodingKeys: String, CodingKey {
        case quotes = "diff"
    }
}

private struct EastmoneyExchangeQuotePayload: Decodable {
    var price: ExchangeLossyDouble?
    var growthRate: ExchangeLossyDouble?
    var code: ExchangeLossyString?
    var name: String?
    var previousClose: ExchangeLossyDouble?
    var timestamp: ExchangeLossyDouble?

    private enum CodingKeys: String, CodingKey {
        case price = "f2"
        case growthRate = "f3"
        case code = "f12"
        case name = "f14"
        case previousClose = "f18"
        case timestamp = "f124"
    }
}

private struct ExchangeLossyDouble: Decodable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let integer = try? container.decode(Int64.self) {
            value = Double(integer)
        } else if let string = try? container.decode(String.self) {
            value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            value = nil
        }
    }
}

private struct ExchangeLossyString: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int64.self) {
            value = String(integer)
        } else {
            value = ""
        }
    }
}
