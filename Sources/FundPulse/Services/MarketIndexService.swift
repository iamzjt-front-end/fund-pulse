import Foundation

struct MarketIndexService {
    private static let eastmoneyBatchQuoteEndpoints = [
        URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")!,
        URL(string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get")!
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuotes(for ids: [MarketIndexID]) async -> [MarketIndexID: MarketIndexQuote] {
        let uniqueIDs = Array(Set(ids)).sorted { lhs, rhs in
            let lhsIndex = MarketIndexID.allCases.firstIndex(of: lhs) ?? 0
            let rhsIndex = MarketIndexID.allCases.firstIndex(of: rhs) ?? 0
            return lhsIndex < rhsIndex
        }
        guard !uniqueIDs.isEmpty else { return [:] }

        return (try? await fetchEastmoneyBatchQuotes(for: uniqueIDs)) ?? [:]
    }

    private func fetchEastmoneyBatchQuotes(for ids: [MarketIndexID]) async throws -> [MarketIndexID: MarketIndexQuote] {
        var lastError: Error?
        for endpoint in Self.eastmoneyBatchQuoteEndpoints {
            do {
                return try await fetchEastmoneyBatchQuotes(for: ids, endpoint: endpoint)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.badServerResponse)
    }

    private func fetchEastmoneyBatchQuotes(
        for ids: [MarketIndexID],
        endpoint: URL
    ) async throws -> [MarketIndexID: MarketIndexQuote] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ut", value: "fa5fd1943c7b386f172d6893dbfba10b"),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f12,f14,f2,f3,f4"),
            URLQueryItem(name: "secids", value: ids.map(\.eastmoneySecID).joined(separator: ","))
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await session.data(for: marketIndexRequest(url: url))
        let response = try JSONDecoder().decode(EastmoneyMarketIndexListResponse.self, from: data)
        guard response.rc == 0, let items = response.data?.items else {
            throw URLError(.badServerResponse)
        }

        let idsByQuoteCode = Dictionary(uniqueKeysWithValues: ids.map { ($0.eastmoneyQuoteCode, $0) })
        var quotes: [MarketIndexID: MarketIndexQuote] = [:]
        for item in items {
            guard let code = item.code,
                  let id = idsByQuoteCode[code],
                  let value = item.value?.value,
                  let change = item.change?.value,
                  let changeRate = item.changeRate?.value
            else { continue }
            quotes[id] = MarketIndexQuote(
                id: id,
                name: item.name?.nilIfBlank ?? id.title,
                value: value,
                change: change,
                changeRate: changeRate
            )
        }
        guard !quotes.isEmpty else { throw URLError(.badServerResponse) }
        return quotes
    }

    private func marketIndexRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }
}

private struct EastmoneyMarketIndexListResponse: Decodable {
    var rc: Int
    var data: EastmoneyMarketIndexListPayload?
}

private struct EastmoneyMarketIndexListPayload: Decodable {
    var items: [EastmoneyMarketIndexListItem]?

    enum CodingKeys: String, CodingKey {
        case items = "diff"
    }
}

private struct EastmoneyMarketIndexListItem: Decodable {
    var code: String?
    var name: String?
    var value: LossyMarketIndexNumber?
    var change: LossyMarketIndexNumber?
    var changeRate: LossyMarketIndexNumber?

    enum CodingKeys: String, CodingKey {
        case code = "f12"
        case name = "f14"
        case value = "f2"
        case changeRate = "f3"
        case change = "f4"
    }
}

private struct LossyMarketIndexNumber: Decodable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let int = try? container.decode(Int.self) {
            value = Double(int)
        } else if let string = try? container.decode(String.self) {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            value = Double(normalized)
        } else {
            value = nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
