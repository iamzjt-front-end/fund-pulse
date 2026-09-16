import Foundation
import XCTest
@testable import FundPulse

@MainActor
final class AccountsOptimizationTests: XCTestCase {
    func testAllAccountsRequestEachOffExchangeSymbolOnce() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BatchQuoteProtocol.self]
        let service = FundQuoteService(session: URLSession(configuration: configuration))
        let accounts = PortfolioAccountsStore(dataDirectory: directory, quoteService: service)
        accounts.load()
        let second = try accounts.createAccount(name: "支付宝", kind: .offExchange)
        try accounts.defaultStore.importPortfolio(fixture(codes: ["000001", "000002"]))
        try XCTUnwrap(accounts.store(for: second.id)).importPortfolio(fixture(codes: ["000001", "000003"]))
        BatchQuoteProtocol.requests.reset()
        await accounts.refreshQuotes()
        let requests = BatchQuoteProtocol.requests.values
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(Set(requests.first ?? []), Set(["000001", "000002", "000003"]))
        XCTAssertEqual(accounts.defaultStore.snapshot.funds.count, 2)
        XCTAssertEqual(accounts.store(for: second.id)?.snapshot.funds.count, 2)
        XCTAssertEqual(accounts.defaultStore.snapshot.funds.first?.lastOffExchangeQuote?.netValue, 1.2)
    }

    func testAllAccountBackupRestoresNamesKindsSelectionAndHoldings() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = PortfolioAccountsStore(dataDirectory: directory, now: { Date(timeIntervalSince1970: 1_789_516_800) })
        accounts.load()
        let second = try accounts.createAccount(name: "券商", kind: .onExchange)
        try accounts.defaultStore.importPortfolio(fixture(codes: ["000001"]))
        accounts.select(.all)
        let backup = try accounts.backupSnapshot()
        try accounts.renameAccount(id: second.id, name: "changed")
        try accounts.defaultStore.clearAllHoldings()
        try accounts.restoreBackup(backup)
        XCTAssertEqual(accounts.accounts.map(\.name), backup.registry.accounts.map(\.name))
        XCTAssertEqual(accounts.account(id: second.id)?.kind, .onExchange)
        XCTAssertEqual(accounts.selection, .all)
        XCTAssertEqual(accounts.defaultStore.snapshot.funds.map(\.code), ["000001"])
        XCTAssertNotNil(accounts.latestBackupURL)
        let reloaded = PortfolioAccountsStore(dataDirectory: directory, now: { Date(timeIntervalSince1970: 1_789_516_800) })
        reloaded.load()
        XCTAssertEqual(reloaded.accounts, accounts.accounts)
        XCTAssertEqual(reloaded.defaultStore.snapshot.funds, accounts.defaultStore.snapshot.funds)
    }

    func testInvalidAllAccountBackupCannotPartiallyReplaceHoldings() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = PortfolioAccountsStore(dataDirectory: directory, now: { Date(timeIntervalSince1970: 1_789_516_800) })
        accounts.load()
        try accounts.defaultStore.importPortfolio(fixture(codes: ["000001"]))
        var backup = try accounts.backupSnapshot()
        backup.registry.accounts[0].directoryName = "../escape"
        XCTAssertThrowsError(try accounts.restoreBackup(backup))
        XCTAssertEqual(accounts.defaultStore.snapshot.funds.map(\.code), ["000001"])
        backup = try accounts.backupSnapshot()
        backup.portfolios.removeAll()
        XCTAssertThrowsError(try accounts.restoreBackup(backup))
        XCTAssertEqual(accounts.defaultStore.snapshot.funds.count, 1)
    }

    func testInterruptedAllAccountRestoreRollsBackBeforeLoad() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = PortfolioAccountsStore(dataDirectory: directory, now: { Date(timeIntervalSince1970: 1_789_516_800) })
        accounts.load()
        try accounts.defaultStore.importPortfolio(fixture(codes: ["000001"]))
        let backup = try accounts.backupSnapshot()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: directory.appending(path: "pending-accounts-restore.json"))
        try JSONPortfolioRepository(dataDirectory: directory).save(fixture(codes: ["000002"]))
        let restarted = PortfolioAccountsStore(dataDirectory: directory, now: { Date(timeIntervalSince1970: 1_789_516_800) })
        restarted.load()
        XCTAssertEqual(restarted.defaultStore.snapshot.funds.map(\.code), ["000001"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "pending-accounts-restore.json").path))
    }

    func testBackupRejectsSecondAccountSharingDefaultDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = PortfolioAccountsStore(dataDirectory: directory)
        accounts.load()
        try accounts.defaultStore.importPortfolio(fixture(codes: ["000001"]))
        var backup = try accounts.backupSnapshot()
        backup.registry.accounts.append(PortfolioAccount(id: "invalid", name: "错误账户", kind: .offExchange,
            createdAt: .now, directoryName: nil))
        backup.portfolios["invalid"] = .empty
        XCTAssertThrowsError(try accounts.restoreBackup(backup))
        XCTAssertEqual(accounts.defaultStore.snapshot.funds.map(\.code), ["000001"])
    }

    func testRestoreCannotFollowAccountSymlinkOutsideDataDirectory() throws {
        let directory = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        let accounts = PortfolioAccountsStore(dataDirectory: directory)
        accounts.load()
        var backup = try accounts.backupSnapshot()
        let linked = PortfolioAccount(id: "linked", name: "linked", kind: .offExchange,
            createdAt: .now, directoryName: "linked")
        backup.registry.accounts.append(linked)
        backup.portfolios[linked.id] = fixture(codes: ["000001"])
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: accounts.accountsDataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: accounts.dataDirectory(for: linked), withDestinationURL: outside)
        XCTAssertThrowsError(try accounts.restoreBackup(backup))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appending(path: "portfolio.json").path))
    }

    func testRestoreRefusesTargetWithUnfinishedSingleAccountImport() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = PortfolioAccountsStore(dataDirectory: directory)
        accounts.load()
        let backup = try accounts.backupSnapshot()
        let journal = directory.appending(path: "pending-import-rollback.json")
        try Data("unfinished".utf8).write(to: journal)
        XCTAssertThrowsError(try accounts.restoreBackup(backup))
        XCTAssertEqual(try Data(contentsOf: journal), Data("unfinished".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "pending-accounts-restore.json").path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "fund-pulse-accounts-optimization-\(UUID().uuidString)")
    }
    private func fixture(codes: [String]) -> PortfolioSnapshot {
        var value = PortfolioSnapshot.empty
        value.funds = codes.map { code in
            FundPosition(code: code, name: code, dateText: "", todayIncome: 0, todayRate: 0,
                holdingRate: 0, status: .holding, isUpdated: false, migratedShares: 100, migratedCost: 1,
                positionDate: "2026-09-01")
        }
        return value
    }
}

private final class BatchRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String]] = []
    var values: [[String]] { lock.withLock { storage } }
    func reset() { lock.withLock { storage = [] } }
    func append(_ codes: [String]) { lock.withLock { storage.append(codes) } }
}
private final class BatchQuoteProtocol: URLProtocol {
    static let requests = BatchRequestLog()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        guard url.path.contains("FundCoreDiyNew") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let codes = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "FCODES" })?.value?.components(separatedBy: ",") ?? []
        Self.requests.append(codes)
        let rows = codes.map { ["FCODE": $0, "SHORTNAME": $0, "DWJZ": "1.2", "JZRQ": "2026-09-15",
                               "GSZ": "1.3", "GSZZL": "8.333", "GZTIME": "2026-09-16 10:00"] }
        let data = try! JSONSerialization.data(withJSONObject: ["data": rows, "success": true])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
