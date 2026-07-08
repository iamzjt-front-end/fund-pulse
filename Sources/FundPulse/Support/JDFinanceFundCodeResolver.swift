import Foundation

@MainActor
struct JDFinanceFundCodeResolver {
    private let lookup: (String) async -> String?

    init(quoteService: FundQuoteService = FundQuoteService()) {
        self.lookup = { name in
            await quoteService.lookupFundCode(name: name)
        }
    }

    init(lookup: @escaping (String) async -> String?) {
        self.lookup = lookup
    }

    func resolve(
        snapshot: JDFinanceHoldingsSnapshot,
        localSnapshot: PortfolioSnapshot
    ) async -> JDFinanceHoldingsSnapshot {
        let localFundsByName = Self.localFundsByNormalizedName(localSnapshot.funds)
        var products: [JDFinanceHoldingProduct] = []
        products.reserveCapacity(snapshot.products.count)

        for var product in snapshot.products {
            if product.isCodeResolved {
                products.append(product)
                continue
            }

            if let localFund = Self.nameLookupKeys(for: product.name).compactMap({ localFundsByName[$0] }).first {
                product.code = localFund.code
                product.codeResolution = .nameMatched
                products.append(product)
                continue
            }

            if let code = await lookup(product.name)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty
            {
                product.code = code
                product.codeResolution = .nameMatched
            }
            products.append(product)
        }

        return JDFinanceHoldingsSnapshot(
            totalAssets: snapshot.totalAssets,
            yesterdayIncome: snapshot.yesterdayIncome,
            todayIncome: snapshot.todayIncome,
            holdIncome: snapshot.holdIncome,
            totalIncome: snapshot.totalIncome,
            products: products
        )
    }

    private static func localFundsByNormalizedName(_ funds: [FundPosition]) -> [String: FundPosition] {
        var result: [String: FundPosition] = [:]
        var duplicateKeys = Set<String>()

        for fund in funds {
            for key in nameLookupKeys(for: fund.name) {
                guard !key.isEmpty, !duplicateKeys.contains(key) else { continue }
                if result[key] != nil {
                    result[key] = nil
                    duplicateKeys.insert(key)
                } else {
                    result[key] = fund
                }
            }
        }

        return result
    }

    private static func nameLookupKeys(for value: String) -> [String] {
        var keys: [String] = []
        appendUnique(normalizedName(value), to: &keys)
        appendUnique(canonicalFundName(value), to: &keys)
        return keys
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    private static func canonicalFundName(_ value: String) -> String {
        normalizedName(value)
            .replacingOccurrences(of: "中证", with: "")
            .replacingOccurrences(of: "转换-", with: "")
            .replacingOccurrences(of: "转入-", with: "")
            .replacingOccurrences(of: "转出-", with: "")
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value)
    }
}
