import Foundation

struct MarketIndexService {
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

        var quotes: [MarketIndexID: MarketIndexQuote] = [:]
        for id in uniqueIDs {
            if let quote = try? await fetchEastmoneyQuote(for: id) {
                quotes[id] = quote
            }
        }
        return quotes
    }

    private func fetchEastmoneyQuote(for id: MarketIndexID) async throws -> MarketIndexQuote {
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/stock/get")!
        components.queryItems = [
            URLQueryItem(name: "ut", value: "fa5fd1943c7b386f172d6893dbfba10b"),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f57,f58,f43,f169,f170"),
            URLQueryItem(name: "secid", value: id.eastmoneySecID)
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(EastmoneyMarketIndexResponse.self, from: data)
        guard response.rc == 0,
              let payload = response.data,
              let value = payload.value?.value,
              let change = payload.change?.value,
              let changeRate = payload.changeRate?.value
        else {
            throw URLError(.badServerResponse)
        }

        return MarketIndexQuote(
            id: id,
            name: payload.name?.nilIfBlank ?? id.title,
            value: value,
            change: change,
            changeRate: changeRate
        )
    }
}

private struct EastmoneyMarketIndexResponse: Decodable {
    var rc: Int
    var data: EastmoneyMarketIndexPayload?
}

private struct EastmoneyMarketIndexPayload: Decodable {
    var name: String?
    var value: LossyMarketIndexNumber?
    var change: LossyMarketIndexNumber?
    var changeRate: LossyMarketIndexNumber?

    enum CodingKeys: String, CodingKey {
        case name = "f58"
        case value = "f43"
        case change = "f169"
        case changeRate = "f170"
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
