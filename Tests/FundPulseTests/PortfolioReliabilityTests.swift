import Foundation
import XCTest
@testable import FundPulse

private final class RegressionRepository: PortfolioRepository {
    let dataDirectory = FileManager.default.temporaryDirectory.appending(path: "fund-pulse-audit-data-\(UUID().uuidString)")
    var dataFileURL: URL { dataDirectory.appending(path: "portfolio.json") }
    var value: PortfolioSnapshot
    var fails = false
    var attempts = 0
    init(_ value: PortfolioSnapshot) { self.value = value }
    func load() throws -> PortfolioSnapshot? { value }
    func save(_ snapshot: PortfolioSnapshot) throws {
        attempts += 1
        if fails { throw CocoaError(.fileWriteNoPermission) }
        value = snapshot
    }
}

private final class RegressionRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var fail = false
    private var hold = false
    private var coreOverride: String?
    private var pending: RegressionHTTPProtocol?
    func reset(fail: Bool = false, hold: Bool = false, coreOverride: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.fail = fail; self.hold = hold; pending = nil
        self.coreOverride = coreOverride
    }
    var isWaiting: Bool {
        lock.lock(); defer { lock.unlock() }; return pending != nil
    }
    func route(_ request: RegressionHTTPProtocol) {
        lock.lock()
        let shouldFail = fail
        let override = coreOverride
        let historical = request.request.url!.path.contains("/f10/lsjz")
        if historical && hold && !shouldFail {
            pending = request
            lock.unlock()
            return
        }
        lock.unlock()
        if shouldFail { request.fail() }
        else { request.respond(historical: historical, override: override) }
    }
    func release() {
        lock.lock()
        let request = pending; pending = nil; hold = false
        lock.unlock()
        request?.respond(historical: true)
    }
}

private final class RegressionHTTPProtocol: URLProtocol {
    static let router = RegressionRouter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.router.route(self) }
    override func stopLoading() {}
    func fail() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    func respond(historical: Bool, override: String? = nil) {
        let body: String
        if historical {
            body = #"{"ErrCode":0,"Data":{"LSJZList":[{"FSRQ":"2026-09-14","DWJZ":"1.0"}]}}"#
        } else if let override {
            body = override
        } else {
            body = #"{"success":true,"data":[{"FCODE":"000001","SHORTNAME":"Regression A","DWJZ":"1.2","JZRQ":"2026-09-15","GSZ":"1.3","GSZZL":"8.3333","GZTIME":"2026-09-16 10:00"},{"FCODE":"000002","SHORTNAME":"Regression B","DWJZ":"1.2","JZRQ":"2026-09-15","GSZ":"1.3","GSZZL":"8.3333","GZTIME":"2026-09-16 10:00"}]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class PortfolioReliabilityTests: XCTestCase {
    override func tearDown() {
        RegressionHTTPProtocol.router.release()
        RegressionHTTPProtocol.router.reset()
        super.tearDown()
    }
    private var now: Date { DateOnlyFormatter.parse("2026-09-16")!.addingTimeInterval(10 * 3600) }
    private func fund(_ code: String, shares: Double = 100) -> FundPosition {
        FundPosition(code: code, name: "Regression \(code)", dateText: "09-16 10:00", todayIncome: 0,
                     todayRate: 0, holdingRate: 0, status: .holding, isUpdated: false,
                     migratedShares: shares, migratedCost: 1, incomeStartDate: "2026-09-01", positionMode: .share,
                     positionDate: "2026-09-01", positionTimeType: .before15,
                     lots: [FundPositionLot(id: "lot-\(code)", shares: shares, cost: 1,
                         incomeStartDate: "2026-09-01", positionDate: "2026-09-01", positionTimeType: .before15)])
    }
    private func base(twoFunds: Bool = false) -> PortfolioSnapshot {
        var snapshot = PortfolioSnapshot.empty
        snapshot.funds = twoFunds ? [fund("000001"), fund("000002", shares: 200)] : [fund("000001")]
        return snapshot
    }
    private func service() -> FundQuoteService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RegressionHTTPProtocol.self]
        return FundQuoteService(session: URLSession(configuration: config))
    }

    @MainActor
    func testMissingOfficialNAVCannotConfirmWithIntradayEstimate() async throws {
        RegressionHTTPProtocol.router.reset(coreOverride:
            #"{"success":true,"data":[{"FCODE":"000001","SHORTNAME":"Regression A","DWJZ":"-","FSRQ":"2026-09-14","GSZ":"1.3","GSZZL":"8.3333","GZTIME":"2026-09-16 10:00"}]}"#)
        let quotes = service()
        let quote = try await quotes.fetchQuote(code: "000001")
        let confirmed = await quotes.fetchConfirmedNetValue(code: "000001", acceptedDate: "2026-09-14", latestQuote: quote)
        XCTAssertEqual(confirmed ?? 0, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testOfflineRefreshPreservesLastKnownFinancialValues() async throws {
        RegressionHTTPProtocol.router.reset(fail: true)
        let quote = FundQuote(code: "000001", name: "Regression", netValue: 1.2, estimatedNetValue: 1.3,
                              growthRate: 8.3333, estimateTime: "2026-09-16 10:00", netValueDate: "2026-09-15")
        let before = PortfolioCalculator.applyingQuotes(to: base(), quotes: [quote.code: quote], now: now)
        let repo = RegressionRepository(before)
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        await store.refreshQuotes()
        XCTAssertEqual(store.snapshot.totalAmount, before.totalAmount, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.holdingIncome, before.holdingIncome, accuracy: 0.0001)
    }

    @MainActor
    func testLegacySnapshotWithoutQuoteCachePreservesValuationOffline() async throws {
        RegressionHTTPProtocol.router.reset(fail: true)
        var legacy = base()
        legacy.totalAmount = 120; legacy.holdingIncome = 20
        legacy.funds[0].currentAmount = 120; legacy.funds[0].holdingIncome = 20
        let repo = RegressionRepository(legacy)
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        await store.refreshQuotes()
        XCTAssertEqual(store.snapshot.totalAmount, 120)
        XCTAssertEqual(store.snapshot.holdingIncome, 20)
        XCTAssertNotNil(store.quoteRefreshWarning)
        XCTAssertNil(store.lastSuccessfulQuoteRefresh)
    }

    @MainActor
    func testRefreshRecoversAfterTransientPersistenceFailure() async throws {
        RegressionHTTPProtocol.router.reset()
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load(); repo.fails = true
        await store.refreshQuotes()
        repo.fails = false
        await store.refreshQuotes()
        XCTAssertEqual(repo.attempts, 2)
        XCTAssertEqual(store.loadState, .loaded)
    }

    @MainActor
    func testImportRejectsDuplicateFundCodes() throws {
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let store = PortfolioStore(repository: repo)
        store.load()
        var duplicate = base(); duplicate.funds.append(duplicate.funds[0])
        try FileManager.default.createDirectory(at: repo.dataDirectory, withIntermediateDirectories: true)
        let input = repo.dataDirectory.appending(path: "duplicate.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(duplicate).write(to: input)
        XCTAssertThrowsError(try store.importPortfolio(from: input))
    }

    @MainActor
    func testDeletingFundDuringConfirmationDoesNotCreditAnotherFund() async throws {
        RegressionHTTPProtocol.router.reset(hold: true)
        var snapshot = base(twoFunds: true)
        snapshot.pendingTrades = [FundPendingTrade(id: "pending", recordID: "record", action: .buy,
            code: "000001", mode: .amount, amount: 10, shares: nil,
            tradeDate: "2026-09-14", tradeTimeType: .before15, createdAt: now)]
        snapshot.tradeRecords = [FundTradeRecord(id: "record", kind: .buy, status: .pending,
            code: "000001", name: "Regression A", mode: .amount, amount: 10, shares: nil,
            confirmedShares: nil, price: nil, tradeDate: "2026-09-14", tradeTimeType: .before15,
            acceptedDate: "2026-09-14", createdAt: now, confirmedAt: nil, failureReason: nil)]
        let repo = RegressionRepository(snapshot)
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        let refresh = Task { @MainActor in await store.refreshQuotes() }
        for _ in 0..<200 where !RegressionHTTPProtocol.router.isWaiting { try await Task.sleep(for: .milliseconds(5)) }
        guard RegressionHTTPProtocol.router.isWaiting else { XCTFail("Did not reach historical NAV await"); return }
        let deletion = Task { @MainActor in try await store.deleteFund(code: "000001") }
        for _ in 0..<200 where store.snapshot.funds.count != 1 { try await Task.sleep(for: .milliseconds(5)) }
        RegressionHTTPProtocol.router.release()
        await refresh.value
        try await deletion.value
        let remaining = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(remaining.code, "000002")
        XCTAssertEqual(remaining.migratedShares ?? 0, 200, accuracy: 0.0001)
    }
}

extension PortfolioReliabilityTests {
    @MainActor
    func testSuccessfulHTTPWithOnlyStaleQuotesReportsIncompleteDailyData() async throws {
        RegressionHTTPProtocol.router.reset(coreOverride:
            #"{"success":true,"data":[{"FCODE":"000001","SHORTNAME":"A","DWJZ":"1.2","FSRQ":"2026-09-15","GSZ":"1.2","GZTIME":"2026-09-15 15:00"}]}"#)
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        await store.refreshQuotes()
        XCTAssertEqual(store.snapshot.totalAmount, 120)
        XCTAssertEqual(store.snapshot.todayIncome, 0)
        XCTAssertNotNil(store.quoteRefreshWarning)
        XCTAssertNil(store.lastSuccessfulQuoteRefresh)
    }

    @MainActor
    func testExchangeBaselineRetainsLockedPortionWhenNextCalendarYearIsUnknown() async throws {
        RegressionHTTPProtocol.router.reset(fail: true)
        let repo = RegressionRepository(.empty)
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RegressionHTTPProtocol.self]
        let date = try XCTUnwrap(DateOnlyFormatter.parse("2026-12-31"))
        let store = PortfolioStore(repository: repo,
            exchangeQuoteService: ExchangeFundQuoteService(session: URLSession(configuration: config)),
            accountKind: .onExchange, now: { date })
        store.load()
        try await store.upsertFund(FundPositionDraft(code: "510300", name: "ETF", positionMode: .share,
            positionProfit: 0, shares: 100, cost: 1, positionDate: "2026-12-31", positionTimeType: .before15,
            memo: "", exchangeSellableShares: 40))
        let result = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(result.sellableShares, 40)
        XCTAssertEqual(result.lockedShares, 60)
        XCTAssertNil(result.nextUnlockDate)
    }

    @MainActor
    func testUnreadablePortfolioIsNeverOverwrittenByRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "portfolio.json")
        let original = Data("{broken-user-data".utf8)
        try original.write(to: file)
        let store = PortfolioStore(dataDirectory: directory, quoteService: service())
        store.load()
        await store.refreshQuotes()
        XCTAssertEqual(try Data(contentsOf: file), original)
        guard case .failed = store.loadState else { return XCTFail("Unreadable data must remain protected") }
    }

    @MainActor
    func testImportRejectsDuplicateRecordIDsAndCrossFundReferences() throws {
        let repo = RegressionRepository(base(twoFunds: true))
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let store = PortfolioStore(repository: repo)
        store.load()
        let record = pendingBuyRecord()
        var invalid = base(twoFunds: true)
        invalid.tradeRecords = [record, record]
        try assertRejected(invalid, store: store, directory: repo.dataDirectory)
        invalid.tradeRecords = [record]
        invalid.pendingTrades = [FundPendingTrade(id: "mismatch", recordID: record.id, action: .buy,
            code: "000002", mode: .amount, amount: 10, shares: nil, tradeDate: "2026-09-14", tradeTimeType: .before15, createdAt: now)]
        try assertRejected(invalid, store: store, directory: repo.dataDirectory)
        XCTAssertEqual(repo.attempts, 0)
    }

    @MainActor
    func testNewPendingTradeDuringConfirmationIsNotLost() async throws {
        RegressionHTTPProtocol.router.reset(hold: true)
        var initial = base()
        let record = pendingBuyRecord()
        initial.tradeRecords = [record]
        initial.pendingTrades = [FundPendingTrade(id: "old", recordID: record.id, action: .buy,
            code: record.code, mode: .amount, amount: 10, shares: nil, tradeDate: "2026-09-14", tradeTimeType: .before15, createdAt: now)]
        let repo = RegressionRepository(initial)
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        let refresh = Task { @MainActor in await store.refreshQuotes() }
        for _ in 0..<200 where !RegressionHTTPProtocol.router.isWaiting { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(RegressionHTTPProtocol.router.isWaiting)
        let addition = Task { @MainActor in
            try await store.adjustFundPosition(FundTradeDraft(action: .buy, code: "000001", mode: .amount,
                amount: 20, shares: nil, tradeDate: "2026-09-16", tradeTimeType: .before15))
        }
        for _ in 0..<200 where store.snapshot.tradeRecords?.count == 1 { try await Task.sleep(for: .milliseconds(5)) }
        RegressionHTTPProtocol.router.release()
        await refresh.value
        try await addition.value
        XCTAssertEqual(store.snapshot.funds[0].migratedShares, 110)
        XCTAssertEqual(store.snapshot.pendingTrades?.count, 1)
        XCTAssertEqual(store.snapshot.pendingTrades?.first?.amount, 20)
    }

    private func pendingBuyRecord() -> FundTradeRecord {
        FundTradeRecord(id: "record", kind: .buy, status: .pending, code: "000001", name: "A",
            mode: .amount, amount: 10, shares: nil, confirmedShares: nil, price: nil,
            tradeDate: "2026-09-14", tradeTimeType: .before15, acceptedDate: "2026-09-14",
            createdAt: now, confirmedAt: nil, failureReason: nil)
    }

    @MainActor
    func testImportCreatesRestorableBackupBeforeReplacingHoldings() throws {
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let store = PortfolioStore(repository: repo)
        store.load()
        let original = store.snapshot
        try FileManager.default.createDirectory(at: repo.dataDirectory, withIntermediateDirectories: true)
        let input = repo.dataDirectory.appending(path: "input.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(base(twoFunds: true)).write(to: input)
        try store.importPortfolio(from: input)
        let backups = (try? FileManager.default.contentsOfDirectory(at: repo.dataDirectory.appending(path: "Backups"), includingPropertiesForKeys: nil)) ?? []
        let backup = try XCTUnwrap(backups.first)
        try store.importPortfolio(from: backup)
        XCTAssertEqual(store.snapshot.funds, original.funds)
    }

    @MainActor
    func testInterruptedImportRestoresBothFilesOnNextLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = JSONPortfolioRepository(dataDirectory: directory)
        var original = base(); original.updateTime = now
        try repo.save(base(twoFunds: true)) // Simulate process termination after portfolio write.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let originalJSON = try JSONSerialization.jsonObject(with: encoder.encode(original))
        let historyJSON = try JSONSerialization.jsonObject(with: encoder.encode(PortfolioPerformanceSnapshot.empty))
        try JSONSerialization.data(withJSONObject: ["portfolio": originalJSON, "performance": historyJSON])
            .write(to: directory.appending(path: "pending-import-rollback.json"))
        let store = PortfolioStore(dataDirectory: directory)
        store.load()
        XCTAssertEqual(store.snapshot, original)
        XCTAssertEqual(store.performanceStore.snapshot, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "pending-import-rollback.json").path))
    }

    @MainActor
    func testOlderQuoteCannotRollBackOfficialNAV() async throws {
        RegressionHTTPProtocol.router.reset()
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        await store.refreshQuotes()
        RegressionHTTPProtocol.router.reset(coreOverride:
            #"{"success":true,"data":[{"FCODE":"000001","DWJZ":"0.9","FSRQ":"2026-09-14","GSZ":"0.91","GZTIME":"2026-09-15 10:00"}]}"#)
        await store.refreshQuotes()
        XCTAssertEqual(store.snapshot.totalAmount, 120, accuracy: 0.001)
    }

    @MainActor
    func testUpdateMetadataRetainsAssetDigest() async throws {
        RegressionHTTPProtocol.router.reset(coreOverride:
            #"{"tag_name":"v2.0","html_url":"https://github.com/test/test/releases/tag/v2.0","assets":[{"name":"fund-pulse-arm64-swift.zip","browser_download_url":"https://example.invalid/update.zip","digest":"sha256:abc123"}]}"#)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RegressionHTTPProtocol.self]
        let result = try await AppUpdateService(session: URLSession(configuration: config)).check(currentVersion: "1.0")
        let info = try XCTUnwrap(result.updateInfo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(info)) as? [String: Any])
        XCTAssertEqual(json["archiveDigest"] as? String, "sha256:abc123")
    }

    @MainActor
    func testImportDuringConfirmationPreservesReplacementLedger() async throws {
        RegressionHTTPProtocol.router.reset(hold: true)
        var pending = base()
        pending.pendingTrades = [FundPendingTrade(id: "pending", recordID: "record", action: .buy,
            code: "000001", mode: .amount, amount: 10, shares: nil,
            tradeDate: "2026-09-14", tradeTimeType: .before15, createdAt: now)]
        pending.tradeRecords = [FundTradeRecord(id: "record", kind: .buy, status: .pending,
            code: "000001", name: "A", mode: .amount, amount: 10, shares: nil,
            confirmedShares: nil, price: nil, tradeDate: "2026-09-14", tradeTimeType: .before15,
            acceptedDate: "2026-09-14", createdAt: now, confirmedAt: nil, failureReason: nil)]
        let repo = RegressionRepository(pending)
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        let refresh = Task { @MainActor in await store.refreshQuotes() }
        for _ in 0..<200 where !RegressionHTTPProtocol.router.isWaiting { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(RegressionHTTPProtocol.router.isWaiting)
        var replacement = base(); replacement.funds = [fund("000001", shares: 500)]
        try FileManager.default.createDirectory(at: repo.dataDirectory, withIntermediateDirectories: true)
        let input = repo.dataDirectory.appending(path: "replacement.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(replacement).write(to: input)
        try store.importPortfolio(from: input)
        RegressionHTTPProtocol.router.release()
        await refresh.value
        XCTAssertEqual(store.snapshot.funds.first?.migratedShares, 500)
        XCTAssertFalse(store.snapshot.tradeRecords?.contains(where: { $0.id == "record" }) ?? false)
    }

    @MainActor
    func testOfflineRefreshAfterRestartDoesNotReuseYesterdayDailyIncome() async throws {
        RegressionHTTPProtocol.router.reset()
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let first = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        first.load()
        await first.refreshQuotes()
        let previous = first.snapshot
        RegressionHTTPProtocol.router.reset(fail: true)
        let second = PortfolioStore(repository: repo, quoteService: service(), now: { date.addingTimeInterval(86400) })
        second.load()
        await second.refreshQuotes()
        XCTAssertEqual(second.snapshot.totalAmount, previous.totalAmount, accuracy: 0.0001)
        XCTAssertEqual(second.snapshot.holdingIncome, previous.holdingIncome, accuracy: 0.0001)
        XCTAssertEqual(second.snapshot.todayIncome, 0)
    }

    @MainActor
    func testPartialRefreshPreservesMissingFundValue() async throws {
        RegressionHTTPProtocol.router.reset()
        let repo = RegressionRepository(base(twoFunds: true))
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let date = now
        let store = PortfolioStore(repository: repo, quoteService: service(), now: { date })
        store.load()
        await store.refreshQuotes()
        let previous = store.snapshot.funds[1]
        RegressionHTTPProtocol.router.reset(coreOverride:
            #"{"success":true,"data":[{"FCODE":"000001","SHORTNAME":"A","DWJZ":"1.25","FSRQ":"2026-09-16","GSZ":"1.25","GSZZL":"4.1667","GZTIME":"2026-09-16 15:00"}]}"#)
        await store.refreshQuotes()
        XCTAssertEqual(store.snapshot.funds[1].currentAmount, previous.currentAmount)
        XCTAssertEqual(store.snapshot.funds[1].holdingIncome, previous.holdingIncome)
        XCTAssertEqual(store.snapshot.funds[0].currentAmount ?? 0, 125, accuracy: 0.001)
    }

    @MainActor
    func testNonFiniteOfficialNAVFallsBackToExactHistoricalValue() async throws {
        RegressionHTTPProtocol.router.reset()
        let quote = FundQuote(code: "000001", name: "A", netValue: .infinity, estimatedNetValue: 1.3,
                              growthRate: 1, estimateTime: "", netValueDate: "2026-09-14")
        let result = await service().fetchConfirmedNetValue(code: "000001", acceptedDate: "2026-09-14", latestQuote: quote)
        XCTAssertEqual(result, 1)
    }

    @MainActor
    func testImportRejectsInvalidLotsAndLeavesOriginalUntouched() throws {
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let store = PortfolioStore(repository: repo)
        store.load()
        let previous = store.snapshot
        var invalid = base()
        invalid.funds[0].lots![0].shares = -10
        try assertRejected(invalid, store: store, directory: repo.dataDirectory)
        invalid = base()
        invalid.funds[0].lots![0].positionDate = "2026-02-30"
        try assertRejected(invalid, store: store, directory: repo.dataDirectory)
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertEqual(repo.value, previous)
        XCTAssertEqual(repo.attempts, 0)
    }

    @MainActor
    func testImportRejectsFutureSchemaAndWrongAccountKind() throws {
        let repo = RegressionRepository(base())
        defer { try? FileManager.default.removeItem(at: repo.dataDirectory) }
        let store = PortfolioStore(repository: repo)
        store.load()
        try FileManager.default.createDirectory(at: repo.dataDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(base())) as? [String: Any])
        let input = repo.dataDirectory.appending(path: "input.json")
        for metadata: [String: Any] in [["schemaVersion": 999], ["schemaVersion": 1, "accountKind": "onExchange"]] {
            object.merge(metadata) { _, value in value }
            try JSONSerialization.data(withJSONObject: object).write(to: input)
            XCTAssertThrowsError(try store.importPortfolio(from: input))
        }
        XCTAssertEqual(repo.attempts, 0)
    }

    func testRepositoryRejectsDuplicateFundCodesOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var invalid = base(); invalid.funds.append(invalid.funds[0])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(invalid)
        let repo = JSONPortfolioRepository(dataDirectory: directory)
        try bytes.write(to: repo.dataFileURL)
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(try Data(contentsOf: repo.dataFileURL), bytes)
    }

    @MainActor
    private func assertRejected(_ snapshot: PortfolioSnapshot, store: PortfolioStore, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appending(path: "invalid.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: input)
        XCTAssertThrowsError(try store.importPortfolio(from: input))
    }
}
