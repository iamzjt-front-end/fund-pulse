import Foundation
import XCTest
@testable import FundPulse

@MainActor
final class RemainingOptimizationTests: XCTestCase {
    func testQuoteRefreshWritesSmallCacheWithoutRewritingLedger() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        let original = fixture()
        try repository.save(original)
        let ledger = try Data(contentsOf: repository.dataFileURL)
        var quoted = original
        quoted.totalAmount = 120
        quoted.funds[0].currentAmount = 120
        quoted.funds[0].todayIncome = 20
        let prepared = try await repository.prepareRefresh(quoted, replacing: original)
        defer { prepared.discard() }
        XCTAssertTrue(prepared.isQuoteCache)
        try prepared.commit()
        XCTAssertEqual(try Data(contentsOf: repository.dataFileURL), ledger)
        XCTAssertEqual(try repository.load()?.funds[0].currentAmount, 120)
        XCTAssertEqual(try repository.load()?.tradeRecords, original.tradeRecords)
    }

    func testNewLedgerInvalidatesOldQuoteCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        var original = fixture()
        try repository.save(original)
        var quoted = original
        quoted.funds[0].currentAmount = 120
        let prepared = try await repository.prepareRefresh(quoted, replacing: original)
        defer { prepared.discard() }
        try prepared.commit()
        original.funds[0].migratedShares = 50
        original.funds[0].currentAmount = 50
        try repository.save(original)
        XCTAssertEqual(try repository.load()?.funds[0].currentAmount, 50)
        XCTAssertEqual(try repository.load()?.funds[0].migratedShares, 50)
    }

    func testConfirmationIsPersistedInLedgerAndCorruptCacheIsIgnored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        let original = fixture()
        try repository.save(original)
        var confirmed = original
        confirmed.funds[0].migratedShares = 200
        let prepared = try await repository.prepareRefresh(confirmed, replacing: original)
        defer { prepared.discard() }
        XCTAssertFalse(prepared.isQuoteCache)
        try prepared.commit()
        try Data("broken cache".utf8).write(to: directory.appending(path: "portfolio-quotes.json"))
        XCTAssertEqual(try repository.load()?.funds[0].migratedShares, 200)
    }

    func testAbandonedBackgroundPreparationDoesNotChangePersistedData() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        let original = fixture()
        try repository.save(original)
        var oldRefresh = original
        oldRefresh.funds[0].migratedShares = 200
        let prepared = try await repository.prepareRefresh(oldRefresh, replacing: original)
        var newer = original
        newer.funds[0].migratedShares = 300
        try repository.save(newer)
        prepared.discard()
        XCTAssertEqual(try repository.load()?.funds[0].migratedShares, 300)
    }

    func testPresentationCachesByRevisionAndSortWithoutStaleValues() {
        let cache = PortfolioPresentationCache()
        var snapshot = fixture()
        for _ in 0..<20 {
            _ = cache.value(snapshot: snapshot, revision: 0, filter: .holding, sort: .todayRate)
        }
        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(cache.sortCount, 1)
        snapshot.funds[0].currentAmount = 777
        let changed = cache.value(snapshot: snapshot, revision: 1, filter: .holding, sort: .todayRate)
        XCTAssertEqual(changed.funds[0].currentAmount, 777)
        XCTAssertEqual(cache.buildCount, 2)
        let pending = cache.value(snapshot: snapshot, revision: 1, filter: .pending, sort: .todayRate)
        XCTAssertTrue(pending.funds.isEmpty)
        XCTAssertEqual(cache.buildCount, 2)
    }

    func testClearingHoldingsDuringBackgroundRefreshCannotResurrectThem() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        try repository.save(fixture())
        let store = PortfolioStore(repository: repository)
        store.load()
        let refresh = Task { await store.refreshQuotes(prefetched: [:]) }
        for _ in 0..<1_000 {
            if store.isRefreshingQuotes { break }
            await Task.yield()
        }
        XCTAssertTrue(store.isRefreshingQuotes)
        try store.clearAllHoldings()
        await refresh.value
        XCTAssertTrue(store.snapshot.funds.isEmpty)
        XCTAssertTrue(try XCTUnwrap(repository.load()).funds.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.hasPrefix(".refresh-") })
    }

    func testIncompleteAccountsRestoreBlocksRefreshAndNormalWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        try repository.save(fixture())
        let original = try Data(contentsOf: repository.dataFileURL)
        let store = PortfolioStore(repository: repository)
        store.load()
        try Data("{}".utf8).write(to: directory.appending(path: "pending-accounts-restore.json"))
        await store.refreshQuotes(prefetched: [:])
        if case .failed = store.loadState {} else { XCTFail("Recovery journal must block refresh") }
        XCTAssertEqual(try Data(contentsOf: repository.dataFileURL), original)
        XCTAssertThrowsError(try store.clearAllHoldings())
        store.load()
        if case .failed = store.loadState {} else { XCTFail("Do not expose partially restored accounts") }
    }

    func testHistoricalCacheCoalescesConcurrentRequestsAndExpires() async {
        let cache = FundDataCache<Double>(capacity: 2)
        let counter = OptimizationCounter()
        let now = Date(timeIntervalSince1970: 100)
        async let first = cache.value(key: "000001/2026-09-15", now: now, ttl: 60) {
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(20))
            return 1.25
        }
        async let second = cache.value(key: "000001/2026-09-15", now: now, ttl: 60) {
            await counter.increment()
            return 1.25
        }
        let values = await (first, second)
        XCTAssertEqual(values.0, 1.25)
        XCTAssertEqual(values.1, 1.25)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        let expired = await cache.value(key: "000001/2026-09-15", now: now.addingTimeInterval(61), ttl: 60) {
            await counter.increment()
            return 1.3
        }
        XCTAssertEqual(expired, 1.3)
        let finalCount = await counter.value
        XCTAssertEqual(finalCount, 2)
    }

    func testFailedHistoricalLookupsAreRetriedAndDatesAreIsolated() async {
        let cache = FundDataCache<Double>(capacity: 2)
        let missing = await cache.value(key: "code/day1", ttl: 60) { nil }
        XCTAssertNil(missing)
        let retry = await cache.value(key: "code/day1", ttl: 60) { 1.2 }
        let other = await cache.value(key: "code/day2", ttl: 60) { 1.4 }
        XCTAssertEqual(retry, 1.2)
        XCTAssertEqual(other, 1.4)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "fund-pulse-optimization-\(UUID().uuidString)")
    }

    private func fixture() -> PortfolioSnapshot {
        var value = PortfolioSnapshot.empty
        value.updateTime = Date(timeIntervalSince1970: 1_789_516_800)
        value.funds = [FundPosition(code: "000001", name: "测试基金", dateText: "", todayIncome: 0,
            todayRate: 0, holdingRate: 0, currentAmount: 100, status: .holding, isUpdated: false,
            migratedShares: 100, migratedCost: 1, positionDate: "2026-09-01")]
        return value
    }
}

private actor OptimizationCounter {
    var value = 0
    func increment() { value += 1 }
}
