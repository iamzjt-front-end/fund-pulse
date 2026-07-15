import XCTest
@testable import FundPulse

final class PortfolioPerformanceMigrationTests: XCTestCase {
    func testSchemaOneHistoryMigratesToLocalSourceWithoutLosingRecordingBoundary() throws {
        let legacy = """
        {
          "schemaVersion" : 1,
          "trackingStartDate" : "2026-07-14",
          "days" : [
            {
              "date" : "2026-07-14",
              "profit" : 8.5,
              "returnRate" : 0.2,
              "status" : "confirmed",
              "updatedAt" : "2026-07-14T12:00:00Z"
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(
            PortfolioPerformanceSnapshot.self,
            from: try XCTUnwrap(legacy.data(using: .utf8))
        )
        let normalized = PortfolioPerformanceRecorder.normalized(snapshot)

        XCTAssertEqual(normalized.schemaVersion, 2)
        XCTAssertEqual(normalized.trackingStartDate, "2026-07-14")
        XCTAssertEqual(normalized.localRecordingStartDate, "2026-07-14")
        XCTAssertEqual(normalized.days.first?.source, .localQuote)
        XCTAssertNil(normalized.days.first?.sourceAccountKey)
        XCTAssertEqual(normalized.days.first?.returnRate, 0.2)
        XCTAssertNil(normalized.jdFinanceSync)
    }

    func testJDFinanceDayMayOmitReturnRateAndRoundTripsAccountMetadata() throws {
        let updatedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
        let snapshot = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-14",
            localRecordingStartDate: "2026-07-15",
            days: [
                PortfolioPerformanceDay(
                    date: "2026-07-14",
                    profit: 12.3,
                    returnRate: nil,
                    status: .confirmed,
                    source: .jdFinance,
                    sourceAccountKey: "jd-account-hash",
                    updatedAt: updatedAt
                )
            ],
            jdFinanceSync: JDFinancePerformanceSyncMetadata(
                accountKey: "jd-account-hash",
                coveredFrom: "2015-01-01",
                coveredThrough: "2026-07-14",
                lastSyncedAt: updatedAt,
                isComplete: true
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            PortfolioPerformanceSnapshot.self,
            from: encoder.encode(snapshot)
        )

        XCTAssertEqual(decoded, snapshot)
        XCTAssertNil(decoded.days.first?.returnRate)
        XCTAssertEqual(decoded.jdFinanceSync?.accountKey, "jd-account-hash")
    }

    func testLocalRecorderDoesNotOverwriteConfirmedJDFinanceDay() throws {
        let remoteUpdate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T11:00:00Z"))
        let laterLocalUpdate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T13:00:00Z"))
        let existing = PortfolioPerformanceSnapshot(
            trackingStartDate: "2026-07-15",
            days: [
                PortfolioPerformanceDay(
                    date: "2026-07-15",
                    profit: 10,
                    returnRate: 0.1,
                    status: .confirmed,
                    source: .jdFinance,
                    sourceAccountKey: "jd-account-hash",
                    updatedAt: remoteUpdate
                )
            ]
        )

        let next = PortfolioPerformanceRecorder.recording(
            .init(
                date: "2026-07-15",
                profit: 99,
                returnRate: 0.99,
                status: .confirmed,
                updatedAt: laterLocalUpdate
            ),
            in: existing
        )

        XCTAssertEqual(next.days.count, 1)
        XCTAssertEqual(next.days.first?.profit, 10)
        XCTAssertEqual(next.days.first?.source, .jdFinance)
        XCTAssertNil(next.localRecordingStartDate)
    }
}
