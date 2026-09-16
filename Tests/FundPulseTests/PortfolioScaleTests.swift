import Foundation
import XCTest
@testable import FundPulse

final class PortfolioScaleTests: XCTestCase {
    @MainActor
    func testThreeAccountsHundredFundsTenThousandRecordsKeepCorrectTotals() async throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-09-16"))
        var snapshot = PortfolioSnapshot.empty
        var quotes: [String: FundQuote] = [:]
        snapshot.funds = (0..<100).map { index in
            let code = String(format: "%06d", index)
            quotes[code] = FundQuote(code: code, name: code, netValue: 1.2, estimatedNetValue: 1.3,
                growthRate: 8.3333, estimateTime: "2026-09-16 10:00", netValueDate: "2026-09-15")
            return FundPosition(code: code, name: code, dateText: "", todayIncome: 0, todayRate: 0,
                holdingRate: 0, status: .holding, isUpdated: false, migratedShares: 100, migratedCost: 1,
                lots: [FundPositionLot(id: code, shares: 100, cost: 1, incomeStartDate: "2026-09-01",
                    positionDate: "2026-09-01", positionTimeType: .before15)])
        }
        snapshot.tradeRecords = (0..<10_000).map { index in
            let code = String(format: "%06d", index % 100)
            return FundTradeRecord(id: "record-\(index)", kind: .buy, status: .confirmed, code: code,
                name: code, mode: .amount, amount: 1, shares: 1, confirmedShares: 1, price: 1,
                tradeDate: "2026-09-01", tradeTimeType: .before15, acceptedDate: "2026-09-01",
                createdAt: now, confirmedAt: now, failureReason: nil)
        }
        // Fixed workload, with financial invariants. Timings are observations,
        // not flaky CI limits; use a release build when comparing optimizations.
        let clock = ContinuousClock()
        let started = clock.now
        var results: [PortfolioSnapshot] = []
        for _ in 0..<3 {
            results.append(PortfolioCalculator.applyingQuotes(to: snapshot, quotes: quotes, now: now))
        }
        let calculation = started.duration(to: clock.now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encodingStart = clock.now
        let encoded = try results.map { try encoder.encode($0) }
        let encoding = encodingStart.duration(to: clock.now)
        for result in results {
            XCTAssertEqual(result.totalAmount, 12_000, accuracy: 0.0001)
            XCTAssertEqual(result.holdingIncome, 2_000, accuracy: 0.0001)
            XCTAssertEqual(result.todayIncome, 1_000, accuracy: 0.0001)
            XCTAssertEqual(result.tradeRecords?.count, 10_000)
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "fund-pulse-scale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var cacheBytes = 0
        var backgroundDuration = Duration.zero
        var derivations = 0
        var sorts = 0
        for (index, result) in results.enumerated() {
            let repository = JSONPortfolioRepository(dataDirectory: directory.appending(path: "\(index)"))
            try repository.save(result)
            var next = result
            next.funds[0].todayIncome += 1
            let preparationStart = clock.now
            let prepared = try await repository.prepareRefresh(next, replacing: result)
            backgroundDuration += preparationStart.duration(to: clock.now)
            XCTAssertTrue(prepared.isQuoteCache)
            cacheBytes += try Data(contentsOf: prepared.temporaryURL).count
            try prepared.commit()
            XCTAssertEqual(try repository.load()?.tradeRecords?.count, 10_000)
            let cache = PortfolioPresentationCache()
            for _ in 0..<20 {
                let presentation = cache.value(snapshot: next, revision: 1, filter: .holding, sort: .todayRate)
                XCTAssertEqual(presentation.holdingCount, 100)
            }
            derivations += cache.buildCount
            sorts += cache.sortCount
        }
        XCTAssertLessThan(cacheBytes, encoded.reduce(0) { $0 + $1.count } / 10)
        XCTAssertEqual(derivations, 3)
        XCTAssertEqual(sorts, 3)
        print("CACHE accounts=3 bytes=\(cacheBytes) backgroundPreparation=\(backgroundDuration) viewReads=60 derivations=\(derivations) sorts=\(sorts)")
        print("SCALE accounts=3 funds/account=100 records/account=10000 calculation=\(calculation) encoding=\(encoding) bytes=\(encoded.reduce(0) { $0 + $1.count })")
    }
}
