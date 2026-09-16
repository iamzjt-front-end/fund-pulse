import CryptoKit
import Darwin
import Foundation

/// Immutable values cross the executor boundary. Only the final rename occurs
/// on the main actor, after PortfolioStore rechecks its snapshot revision.
struct PreparedPortfolioWrite: Sendable {
    let temporaryURL: URL
    let destinationURL: URL
    let isQuoteCache: Bool

    func commit() throws {
        guard rename(temporaryURL.path, destinationURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func discard() { try? FileManager.default.removeItem(at: temporaryURL) }
}

private struct PortfolioQuoteCache: Codable {
    var ledgerDigest: String
    var snapshot: PortfolioSnapshot
}

extension PortfolioSnapshot {
    /// Keep every financial/source field; exclude only derived display values.
    /// Any confirmation, metadata edit or lot change therefore forces a ledger write.
    var ledgerProjection: PortfolioSnapshot {
        var result = self
        result.updateTime = .distantPast
        result.totalAmount = 0
        result.holdingIncome = 0
        result.holdingIncomeRate = 0
        result.todayIncome = 0
        result.todayIncomeRate = 0
        result.pendingCount = 0
        result.funds = funds.map { fund in
            var value = fund
            value.dateText = ""
            value.todayIncome = 0
            value.todayRate = 0
            value.holdingIncome = nil
            value.holdingRate = nil
            value.confirmedHoldingIncome = nil
            value.confirmedHoldingRate = nil
            value.currentAmount = nil
            value.isUpdated = false
            value.isIncomeActive = nil
            value.intradayRateDate = nil
            value.intradayRateHistory = nil
            value.lastExchangeQuote = nil
            value.lastOffExchangeQuote = nil
            return value
        }
        return result
    }
}

extension JSONPortfolioRepository {
    var quoteCacheURL: URL { dataDirectory.appending(path: "portfolio-quotes.json") }

    func prepareRefresh(_ snapshot: PortfolioSnapshot, replacing base: PortfolioSnapshot) async throws -> PreparedPortfolioWrite {
        let directory = dataDirectory
        let ledgerURL = dataFileURL
        let cacheURL = quoteCacheURL
        return try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let isCache = snapshot.ledgerProjection == base.ledgerProjection
                && FileManager.default.fileExists(atPath: ledgerURL.path)
            let data: Data
            if isCache {
                let digest = Self.digest(try Data(contentsOf: ledgerURL))
                var valuation = snapshot
                // The growing transaction history remains in portfolio.json.
                valuation.tradeRecords = nil
                data = try encoder.encode(PortfolioQuoteCache(ledgerDigest: digest, snapshot: valuation))
            } else {
                data = try encoder.encode(snapshot)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporaryURL = directory.appending(path: ".refresh-\(UUID().uuidString).tmp")
            do {
                try data.write(to: temporaryURL, options: .atomic)
                try Task.checkCancellation()
                return PreparedPortfolioWrite(temporaryURL: temporaryURL,
                    destinationURL: isCache ? cacheURL : ledgerURL, isQuoteCache: isCache)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
        }.value
    }

    func applyingQuoteCache(to ledger: PortfolioSnapshot, data: Data) -> PortfolioSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cacheData = try? Data(contentsOf: quoteCacheURL),
              let cache = try? decoder.decode(PortfolioQuoteCache.self, from: cacheData),
              cache.ledgerDigest == Self.digest(data)
        else { return ledger }
        var restored = cache.snapshot
        restored.tradeRecords = ledger.tradeRecords
        guard restored.ledgerProjection == ledger.ledgerProjection,
              (try? PortfolioValidation.validate(restored)) != nil
        else { return ledger }
        return restored
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
