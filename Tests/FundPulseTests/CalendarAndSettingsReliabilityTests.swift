import Foundation
import XCTest
@testable import FundPulse

final class CalendarAndSettingsReliabilityTests: XCTestCase {
    @MainActor
    func testUnknownNextTradingDayDoesNotUnlockExchangeSharesOnPurchaseDate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = "2026-12-31"
        let now = try XCTUnwrap(DateOnlyFormatter.parse(date))
        var snapshot = PortfolioSnapshot.empty
        snapshot.funds = [FundPosition(code: "510300", name: "ETF", dateText: date, todayIncome: 0, todayRate: 0,
            holdingRate: 0, status: .holding, isUpdated: true, migratedShares: 100, migratedCost: 1,
            lots: [FundPositionLot(id: "buy", shares: 100, cost: 1, incomeStartDate: date, positionDate: date, positionTimeType: .before15)])]
        snapshot.tradeRecords = [FundTradeRecord(id: "buy", kind: .buy, status: .confirmed, code: "510300", name: "ETF",
            mode: .share, amount: 100, shares: 100, confirmedShares: 100, price: 1, tradeDate: date,
            tradeTimeType: .before15, acceptedDate: date, createdAt: now, confirmedAt: now, failureReason: nil)]
        try JSONPortfolioRepository(dataDirectory: directory).save(snapshot)
        let store = PortfolioStore(dataDirectory: directory, accountKind: .onExchange, now: { now })
        store.load()
        let result = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(result.sellableShares, 0)
        XCTAssertEqual(result.lockedShares, 100)
        XCTAssertNil(result.nextUnlockDate)
    }

    @MainActor
    func testFutureSettingsSchemaIsNotOverwrittenByASetter() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data(#"{"settingsSchemaVersion":999,"betaFeaturesEnabled":false}"#.utf8)
        let file = directory.appending(path: "settings.json")
        try bytes.write(to: file)
        let store = AppSettingsStore(dataDirectory: directory)
        store.setBetaFeaturesEnabled(true)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertNotNil(store.lastError)
    }
    func testUnknownCalendarYearCannotConfirmTradingOrScheduleReminders() throws {
        let unknown = try XCTUnwrap(DateOnlyFormatter.parse("2027-01-01"))
        XCTAssertFalse(TradingCalendar.isFundTradingDay(unknown))
        XCTAssertNil(TradingCalendar.nextFundTradingDate(after: "2026-12-31"))
        XCTAssertTrue(TradingCalendar.nextMarketOpenReminderDates(minutes: 600, from: unknown).isEmpty)
        XCTAssertNil(TradingCalendar.nextMarketSessionBoundary(after: unknown))
        XCTAssertEqual(TradingCalendar.acceptedTradeDate(positionDate: "2026-12-31", timeType: .after15), "")
    }

    func testHistoricalHolidayAndWeekendMakeupAreNotTradingDays() throws {
        for date in ["2025-01-01", "2025-01-28", "2025-02-04", "2025-10-08", "2026-02-14"] {
            XCTAssertFalse(TradingCalendar.isFundTradingDay(try XCTUnwrap(DateOnlyFormatter.parse(date))), date)
        }
        XCTAssertEqual(TradingCalendar.acceptedTradeDate(positionDate: "2025-09-30", timeType: .after15), "2025-10-09")
    }

    @MainActor
    func testFailedSettingsSaveRollsBackAndCanRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppSettingsStore(dataDirectory: directory)
        let previous = store.settings.betaFeaturesEnabled
        try FileManager.default.removeItem(at: store.settingsFileURL)
        try FileManager.default.createDirectory(at: store.settingsFileURL, withIntermediateDirectories: true)
        store.setBetaFeaturesEnabled(!previous)
        XCTAssertEqual(store.settings.betaFeaturesEnabled, previous)
        try FileManager.default.removeItem(at: store.settingsFileURL)
        store.setBetaFeaturesEnabled(!previous)
        XCTAssertEqual(AppSettingsStore(dataDirectory: directory).settings.betaFeaturesEnabled, !previous)
    }
}
