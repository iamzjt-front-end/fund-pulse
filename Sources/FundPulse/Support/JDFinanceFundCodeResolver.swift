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
        let tradeOrderCodesByName = Self.tradeOrderCodesByNormalizedName(snapshot.tradeOrders)
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

            if let code = Self.nameLookupKeys(for: product.name)
                .compactMap({ tradeOrderCodesByName[$0] })
                .first
            {
                product.code = code
                product.codeResolution = .tradeOrderMatched
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

        let knownCodesByName = Self.knownCodesByNormalizedName(
            products: products,
            localFunds: localSnapshot.funds,
            localRecords: localSnapshot.tradeRecords ?? []
        )
        let baselineDate = localSnapshot.jdFinanceSyncState.map {
            DateOnlyFormatter.string(from: $0.baselineEstablishedAt)
        }
        var lookupCache: [String: String?] = [:]
        var tradeOrders: [JDFinanceTradeOrderRecord] = []
        tradeOrders.reserveCapacity(snapshot.tradeOrders.count)
        for var order in snapshot.tradeOrders {
            if let code = Self.normalizedCode(order.code) {
                order.code = code
                order.codeResolution = .explicit
            } else if let name = order.productName,
                      let code = Self.uniqueCode(for: name, in: knownCodesByName)
            {
                order.code = code
                order.codeResolution = .nameMatched
            } else if let name = order.productName,
                      Self.shouldLookupOrderCode(order, baselineDate: baselineDate),
                      let code = await resolvedLookupCode(
                        for: Self.lookupName(name),
                        cache: &lookupCache
                      )
            {
                order.code = code
                order.codeResolution = .nameMatched
            }

            if order.action == .conversion,
               Self.normalizedCode(order.conversionTargetCode) == nil,
               let targetName = order.conversionTargetName
            {
                if let code = Self.uniqueCode(for: targetName, in: knownCodesByName) {
                    order.conversionTargetCode = code
                } else if Self.shouldLookupOrderCode(order, baselineDate: baselineDate),
                          let code = await resolvedLookupCode(
                            for: Self.lookupName(targetName),
                            cache: &lookupCache
                          )
                {
                    order.conversionTargetCode = code
                }
            }
            tradeOrders.append(order)
        }

        return JDFinanceHoldingsSnapshot(
            totalAssets: snapshot.totalAssets,
            yesterdayIncome: snapshot.yesterdayIncome,
            todayIncome: snapshot.todayIncome,
            holdIncome: snapshot.holdIncome,
            totalIncome: snapshot.totalIncome,
            products: products,
            tradeOrders: tradeOrders,
            tradeOrderFetchState: snapshot.tradeOrderFetchState
        )
    }

    private func resolvedLookupCode(
        for name: String,
        cache: inout [String: String?]
    ) async -> String? {
        if let cached = cache[name] {
            return cached
        }
        let code = await lookup(name)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = Self.normalizedCode(code)
        cache[name] = resolved
        return resolved
    }

    private static func shouldLookupOrderCode(
        _ order: JDFinanceTradeOrderRecord,
        baselineDate: String?
    ) -> Bool {
        guard let baselineDate,
              let tradeDate = order.tradeDate
        else {
            return false
        }
        return tradeDate >= baselineDate
    }

    private static func knownCodesByNormalizedName(
        products: [JDFinanceHoldingProduct],
        localFunds: [FundPosition],
        localRecords: [FundTradeRecord]
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for product in products where product.isCodeResolved {
            for key in nameLookupKeys(for: product.name) {
                result[key, default: []].insert(product.code)
            }
        }
        for fund in localFunds {
            for key in nameLookupKeys(for: fund.name) {
                result[key, default: []].insert(fund.code)
            }
        }
        for record in localRecords {
            for key in nameLookupKeys(for: record.name) {
                result[key, default: []].insert(record.code)
            }
        }
        return result
    }

    private static func uniqueCode(for name: String, in lookup: [String: Set<String>]) -> String? {
        let matches = Set(nameLookupKeys(for: name).flatMap { lookup[$0] ?? [] })
        return matches.count == 1 ? matches.first : nil
    }

    private static func normalizedCode(_ code: String?) -> String? {
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else { return nil }
        return trimmed
    }

    private static func lookupName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "转换-", with: "")
            .replacingOccurrences(of: "转入-", with: "")
            .replacingOccurrences(of: "转出-", with: "")
    }

    private static func tradeOrderCodesByNormalizedName(
        _ records: [JDFinanceTradeOrderRecord]
    ) -> [String: String] {
        var result: [String: String] = [:]
        var duplicateKeys = Set<String>()

        for record in records {
            guard let code = record.code?.trimmingCharacters(in: .whitespacesAndNewlines),
                  code.count == 6,
                  let name = record.productName
            else {
                continue
            }
            for key in nameLookupKeys(for: name) {
                guard !key.isEmpty, !duplicateKeys.contains(key) else { continue }
                if let existing = result[key], existing != code {
                    result[key] = nil
                    duplicateKeys.insert(key)
                } else {
                    result[key] = code
                }
            }
        }
        return result
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
