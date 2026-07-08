import Foundation

struct MarketIndexService {
    private static let eastmoneyBatchQuoteEndpoints = [
        URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")!,
        URL(string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get")!
    ]
    private static let eastmoneyMarketBreadthEndpoints = [
        URL(string: "https://push2delay.eastmoney.com/api/qt/clist/get")!,
        URL(string: "https://push2.eastmoney.com/api/qt/clist/get")!
    ]
    private static let eastmoneyMarketBreadthPageSize = 100
    private static let eastmoneyMarketBreadthMaxPages = 80
    private static let eastmoneyMarketBreadthConcurrentPages = 8
    private static let tonghuashunMarketBreadthEndpoint = URL(string: "https://q.10jqka.com.cn/api.php")!

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

    func fetchMarketBreadth() async -> MarketBreadth? {
        if let breadth = try? await fetchTonghuashunMarketBreadth() {
            return breadth
        }
        return try? await fetchEastmoneyMarketBreadth()
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

    private func fetchTonghuashunMarketBreadth() async throws -> MarketBreadth {
        var components = URLComponents(url: Self.tonghuashunMarketBreadthEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "t", value: "indexflash")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await session.data(for: tonghuashunMarketBreadthRequest(url: url))
        let response = try JSONDecoder().decode(TonghuashunIndexFlashResponse.self, from: data)
        guard let payload = response.distribution,
              let risingCount = payload.risingCount?.value,
              let fallingCount = payload.fallingCount?.value,
              risingCount > 0 || fallingCount > 0
        else {
            throw URLError(.badServerResponse)
        }

        return MarketBreadth(
            risingCount: risingCount,
            fallingCount: fallingCount,
            distribution: payload.buckets?.compactMap(\.value) ?? [],
            limitUpCount: response.limitData?.latest?.limitUpCount?.value,
            limitDownCount: response.limitData?.latest?.limitDownCount?.value
        )
    }

    private func fetchEastmoneyMarketBreadth() async throws -> MarketBreadth {
        let firstPage = try await fetchEastmoneyMarketBreadthPage(page: 1)
        var rates = firstPage.rates
        let totalPages = min(
            Self.eastmoneyMarketBreadthMaxPages,
            max(1, Int(ceil(Double(firstPage.total) / Double(Self.eastmoneyMarketBreadthPageSize))))
        )

        if totalPages > 1 {
            for batchStart in stride(from: 2, through: totalPages, by: Self.eastmoneyMarketBreadthConcurrentPages) {
                let batchEnd = min(batchStart + Self.eastmoneyMarketBreadthConcurrentPages - 1, totalPages)
                let batchRates = try await withThrowingTaskGroup(of: [Double].self) { group in
                    for page in batchStart...batchEnd {
                        group.addTask {
                            try await self.fetchEastmoneyMarketBreadthPage(page: page).rates
                        }
                    }

                    var rates: [Double] = []
                    for try await pageRates in group {
                        rates.append(contentsOf: pageRates)
                    }
                    return rates
                }
                rates.append(contentsOf: batchRates)
            }
        }

        let validRates = rates.filter(\.isFinite)
        let risingCount = validRates.filter { $0 > 0 }.count
        let fallingCount = validRates.filter { $0 < 0 }.count
        guard risingCount > 0 || fallingCount > 0 else {
            throw URLError(.badServerResponse)
        }

        return MarketBreadth(
            risingCount: risingCount,
            fallingCount: fallingCount,
            distribution: eastmoneyDistribution(from: validRates),
            limitUpCount: validRates.filter { $0 >= 9.9 }.count,
            limitDownCount: validRates.filter { $0 <= -9.9 }.count
        )
    }

    private func fetchEastmoneyMarketBreadthPage(page: Int) async throws -> EastmoneyMarketBreadthPage {
        var lastError: Error?
        for endpoint in Self.eastmoneyMarketBreadthEndpoints {
            do {
                var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "pn", value: "\(page)"),
                    URLQueryItem(name: "pz", value: "\(Self.eastmoneyMarketBreadthPageSize)"),
                    URLQueryItem(name: "po", value: "1"),
                    URLQueryItem(name: "np", value: "1"),
                    URLQueryItem(name: "ut", value: "fa5fd1943c7b386f172d6893dbfba10b"),
                    URLQueryItem(name: "fltt", value: "2"),
                    URLQueryItem(name: "invt", value: "2"),
                    URLQueryItem(name: "fid", value: "f3"),
                    URLQueryItem(name: "fs", value: "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23"),
                    URLQueryItem(name: "fields", value: "f12,f14,f3")
                ]
                guard let url = components.url else { throw URLError(.badURL) }

                let (data, _) = try await session.data(for: marketIndexRequest(url: url))
                let response = try JSONDecoder().decode(EastmoneyMarketBreadthResponse.self, from: data)
                guard response.rc == 0,
                      let payload = response.data,
                      let items = payload.items
                else {
                    throw URLError(.badServerResponse)
                }
                return EastmoneyMarketBreadthPage(
                    total: payload.total ?? items.count,
                    rates: items.compactMap { $0.changeRate?.value }
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.badServerResponse)
    }

    private func eastmoneyDistribution(from rates: [Double]) -> [Int] {
        var buckets = Array(repeating: 0, count: 10)
        for rate in rates {
            switch rate {
            case ..<(-7):
                buckets[0] += 1
            case ..<(-5):
                buckets[1] += 1
            case ..<(-3):
                buckets[2] += 1
            case ..<(-1):
                buckets[3] += 1
            case ..<0:
                buckets[4] += 1
            case 0:
                continue
            case ...1:
                buckets[5] += 1
            case ...3:
                buckets[6] += 1
            case ...5:
                buckets[7] += 1
            case ...7:
                buckets[8] += 1
            default:
                buckets[9] += 1
            }
        }
        return buckets
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

    private func tonghuashunMarketBreadthRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("https://q.10jqka.com.cn/", forHTTPHeaderField: "Referer")
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

private struct EastmoneyMarketBreadthResponse: Decodable {
    var rc: Int
    var data: EastmoneyMarketBreadthPayload?
}

private struct EastmoneyMarketBreadthPayload: Decodable {
    var total: Int?
    var items: [EastmoneyMarketBreadthItem]?

    enum CodingKeys: String, CodingKey {
        case total
        case items = "diff"
    }
}

private struct EastmoneyMarketBreadthItem: Decodable {
    var changeRate: LossyMarketIndexNumber?

    enum CodingKeys: String, CodingKey {
        case changeRate = "f3"
    }
}

private struct EastmoneyMarketBreadthPage {
    var total: Int
    var rates: [Double]
}

private struct TonghuashunIndexFlashResponse: Decodable {
    var distribution: TonghuashunBreadthPayload?
    var limitData: TonghuashunLimitPayload?

    enum CodingKeys: String, CodingKey {
        case distribution = "zdfb_data"
        case limitData = "zdt_data"
    }
}

private struct TonghuashunBreadthPayload: Decodable {
    var buckets: [LossyMarketIndexInteger]?
    var risingCount: LossyMarketIndexInteger?
    var fallingCount: LossyMarketIndexInteger?

    enum CodingKeys: String, CodingKey {
        case buckets = "zdfb"
        case risingCount = "znum"
        case fallingCount = "dnum"
    }
}

private struct TonghuashunLimitPayload: Decodable {
    var latest: TonghuashunLatestLimit?

    enum CodingKeys: String, CodingKey {
        case latest = "last_zdt"
    }
}

private struct TonghuashunLatestLimit: Decodable {
    var limitUpCount: LossyMarketIndexInteger?
    var limitDownCount: LossyMarketIndexInteger?

    enum CodingKeys: String, CodingKey {
        case limitUpCount = "ztzs"
        case limitDownCount = "dtzs"
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

private struct LossyMarketIndexInteger: Decodable {
    var value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else if let string = try? container.decode(String.self) {
            let normalized = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            if let int = Int(normalized) {
                value = int
            } else if let double = Double(normalized) {
                value = Int(double)
            } else {
                value = nil
            }
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
