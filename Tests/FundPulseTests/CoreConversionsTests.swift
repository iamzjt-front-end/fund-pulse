import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    @MainActor
    func testPendingConversionCreatesLinkedRecordsWithoutMutatingHoldings() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-pending-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        let pendingConversion = try XCTUnwrap(store.snapshot.pendingConversions?.first)
        XCTAssertEqual(pendingConversion.fromCode, Self.tradeTestCode)
        XCTAssertEqual(pendingConversion.toCode, "290008")
        XCTAssertEqual(pendingConversion.shares, 100, accuracy: 0.0001)
        XCTAssertEqual(pendingConversion.acceptedDate, "2026-06-22")

        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.kind)), [.conversionOut, .conversionIn])
        XCTAssertEqual(Set(records.compactMap(\.conversionID)), [pendingConversion.id])
        XCTAssertTrue(records.allSatisfy { $0.status == .pending })

        let outRecord = try XCTUnwrap(records.first { $0.kind == .conversionOut })
        XCTAssertEqual(outRecord.id, pendingConversion.outRecordID)
        XCTAssertEqual(outRecord.code, Self.tradeTestCode)
        XCTAssertEqual(outRecord.linkedCode, "290008")
        XCTAssertEqual(outRecord.shares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(outRecord.sellFeeMode, .rate)
        XCTAssertEqual(outRecord.sellFeeValue ?? 0, 1, accuracy: 0.0001)

        let inRecord = try XCTUnwrap(records.first { $0.kind == .conversionIn })
        XCTAssertEqual(inRecord.id, pendingConversion.inRecordID)
        XCTAssertEqual(inRecord.code, "290008")
        XCTAssertEqual(inRecord.linkedCode, Self.tradeTestCode)
        XCTAssertEqual(inRecord.buyFeeRate ?? 0, 0.5, accuracy: 0.0001)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingPendingConversionRecordCancelsLinkedRecordsWithoutMutatingHoldings() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-pending-conversion-delete-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionOut })
        let conversionID = try XCTUnwrap(outRecord.conversionID)

        try await store.deleteTradeRecord(id: outRecord.id)

        XCTAssertNil(store.snapshot.pendingConversions)
        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.conversionID == conversionID } ?? false)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedCost ?? 0, 1, accuracy: 0.0001)
    }

    @MainActor
    func testPendingConversionWaitsUntilNextDayThenConfirmsAfterBothNetValuesAndAppliesFees() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-confirm-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        let sameDayRecords = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertTrue(sameDayRecords.allSatisfy { $0.status == .pending })
        let sameDaySourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let sameDayTargetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sameDaySourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sameDayTargetFund.migratedShares ?? 0, 50, accuracy: 0.0001)

        now = try chinaDate("2026-06-23 00:01")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingConversions)
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.count, 2)

        let outRecord = try XCTUnwrap(records.first { $0.kind == .conversionOut })
        let inRecord = try XCTUnwrap(records.first { $0.kind == .conversionIn })
        XCTAssertEqual(outRecord.status, .confirmed)
        XCTAssertEqual(inRecord.status, .confirmed)
        XCTAssertEqual(outRecord.price ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(outRecord.amount ?? 0, 250, accuracy: 0.0001)
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(outRecord.feeAmount ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(inRecord.price ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(inRecord.amount ?? 0, 247.5, accuracy: 0.0001)
        XCTAssertEqual(inRecord.confirmedShares ?? 0, 197.014925, accuracy: 0.000001)
        XCTAssertEqual(((inRecord.confirmedShares ?? 0) * 100).rounded() / 100, 197.01, accuracy: 0.0001)
        XCTAssertEqual(inRecord.feeAmount ?? 0, 1.23, accuracy: 0.01)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedPrincipal ?? 0, 100, accuracy: 0.0001)

        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(targetFund.migratedShares ?? 0, 247.014925, accuracy: 0.000001)
        XCTAssertEqual(targetFund.migratedPrincipal ?? 0, 297.5, accuracy: 0.01)
        XCTAssertEqual(targetFund.migratedCost ?? 0, 1.2044, accuracy: 0.0001)
    }

    @MainActor
    func testPendingConversionWaitsUntilAcceptedDateNextDayEvenWhenNetValuesAreAvailable() async throws {
        var now = try chinaDate("2026-06-18 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-18", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-18", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-next-trading-day-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-18",
                tradeTimeType: .before15,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        let sameDayRecords = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertTrue(sameDayRecords.allSatisfy { $0.status == .pending })
        let sourceBeforeNextDay = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetBeforeNextDay = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceBeforeNextDay.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(targetBeforeNextDay.migratedShares ?? 0, 50, accuracy: 0.0001)

        now = try chinaDate("2026-06-19 00:01")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingConversions)
        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionOut })
        let inRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionIn })
        XCTAssertEqual(outRecord.status, .confirmed)
        XCTAssertEqual(inRecord.status, .confirmed)
        let sourceAfterExecution = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetAfterExecution = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceAfterExecution.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(targetAfterExecution.migratedShares ?? 0, 247.014925, accuracy: 0.000001)
    }

    @MainActor
    func testFullConversionOutDoesNotBecomePendingNewFund() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-full-conversion-out-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        let createdAt = try chinaDate("2026-06-22 15:00")
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(
                        id: "initial-source",
                        kind: .newFund,
                        status: .confirmed,
                        code: Self.tradeTestCode,
                        name: Self.tradeTestName,
                        mode: .share,
                        amount: 100,
                        shares: 100,
                        confirmedShares: 100,
                        price: 1,
                        tradeDate: "2026-06-22",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-06-22",
                        createdAt: createdAt,
                        confirmedAt: createdAt,
                        failureReason: nil
                    )
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        now = try chinaDate("2026-06-23 00:01")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingConversions)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertFalse(records.contains { $0.status == .pending && $0.kind == .newFund && $0.code == Self.tradeTestCode })
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertTrue(PendingFundDisplayRules.isClosedZeroPosition(sourceFund, tradeRecords: records))
        XCTAssertTrue(FundListDisplayRules.isDisplayedHolding(sourceFund, tradeRecords: records))
        XCTAssertFalse(FundListDisplayRules.isDisplayedPending(sourceFund, tradeRecords: records))
    }

    @MainActor
    func testFullConversionAllowsDisplayedShareRoundingAboveStoredShares() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-rounded-full-conversion-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 2_615.35765, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 2_615.36,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        now = try chinaDate("2026-06-23 00:01")
        await store.refreshQuotes()

        XCTAssertNil(store.snapshot.pendingConversions)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.kind == .conversionOut })
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 2_615.36, accuracy: 0.0001)
    }

    @MainActor
    func testPendingConversionWaitsWhenEitherConfirmedNetValueIsMissing() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-missing-nav-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 100,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        XCTAssertEqual(store.snapshot.tradeRecords?.filter { $0.status == .pending }.count, 2)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
    }

    @MainActor
    func testConversionToNewFundWaitsUntilNextDayThenConfirmsIntoHolding() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "024480": ("永赢先进制造智选混合发起A", "2026-06-22", 1.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-new-target-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "024480",
                toName: "永赢先进制造智选混合发起A",
                shares: 60,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        let pendingTargetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024480" })
        XCTAssertEqual(pendingTargetFund.status, .pending)
        XCTAssertEqual(pendingTargetFund.migratedShares ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)

        now = try chinaDate("2026-06-23 00:01")
        await store.refreshQuotes()

        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024480" })
        XCTAssertEqual(targetFund.status, .holding)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedPrincipal ?? 0, 150, accuracy: 0.0001)
        XCTAssertNil(store.snapshot.pendingConversions)
    }

    @MainActor
    func testPendingConversionToNewFundCountsAsSinglePendingItem() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-pending-count-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.convertFundPosition(
            FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "024480",
                toName: "永赢先进制造智选混合发起A",
                shares: 60,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertEqual(store.snapshot.pendingConversions?.count, 1)
        XCTAssertEqual(store.snapshot.pendingCount, 1)
    }

    func testPendingHeaderImpactExcludesConversionsFromSubscriptionAndRedemptionAmounts() throws {
        let impact = try XCTUnwrap(PendingHeaderImpact.make(activities: [
            makePendingHeaderActivity(id: "buy-1", kind: .buy, displayAmount: 51_112),
            makePendingHeaderActivity(id: "sell-1", kind: .sell, displayAmount: 9_986.45),
            makePendingHeaderActivity(
                id: "conversion-1-out",
                kind: .conversionOut,
                displayAmount: 11_565.75,
                conversionID: "conversion-1"
            ),
            makePendingHeaderActivity(
                id: "conversion-2-out",
                kind: .conversionOut,
                displayAmount: 4_033.11,
                conversionID: "conversion-2"
            )
        ]))

        XCTAssertEqual(impact.count, 4)
        XCTAssertEqual(impact.buyAmount, 51_112, accuracy: 0.0001)
        XCTAssertEqual(impact.sellAmount, 9_986.45, accuracy: 0.0001)
        XCTAssertEqual(impact.conversionCount, 2)
        XCTAssertEqual(impact.netAmount, 41_125.55, accuracy: 0.0001)
    }

    func testPendingHeaderImpactKeepsConversionOnlyActivitiesVisibleWithoutCashFlow() throws {
        let impact = try XCTUnwrap(PendingHeaderImpact.make(activities: [
            makePendingHeaderActivity(
                id: "conversion-out",
                kind: .conversionOut,
                displayAmount: 11_565.75,
                conversionID: "conversion-1"
            ),
            makePendingHeaderActivity(
                id: "conversion-in",
                kind: .conversionIn,
                displayAmount: 11_565.75,
                conversionID: "conversion-1"
            )
        ]))

        XCTAssertEqual(impact.count, 2)
        XCTAssertEqual(impact.buyAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(impact.sellAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(impact.conversionCount, 1)
        XCTAssertEqual(impact.netAmount, 0, accuracy: 0.0001)
    }

    func testPendingActivityPresentationExplainsConversionAndFailureReasons() {
        var activity = makePendingHeaderActivity(
            id: "conversion",
            kind: .conversionOut,
            displayAmount: 1_000,
            conversionID: "conversion"
        )
        activity.acceptedDate = "2026-07-15"

        XCTAssertEqual(
            PendingActivityPresentation(activity: activity).waitingText,
            "次日检查确认 · 净值就绪后自动更新"
        )

        activity.failureReason = "可转换份额不足"
        XCTAssertEqual(
            PendingActivityPresentation(activity: activity).waitingText,
            "暂无法确认 · 可转换份额不足"
        )
    }

    @MainActor
    func testPendingConversionWithInsufficientSharesKeepsLinkedRecordsPendingWithFailureReason() async throws {
        var now = try chinaDate("2026-06-22 16:00")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-insufficient-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "pending-conversion-1"
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 80, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1)
                ],
                migration: nil,
                pendingConversions: [
                    FundPendingConversion(
                        id: conversionID,
                        outRecordID: "conversion-out",
                        inRecordID: "conversion-in",
                        fromCode: Self.tradeTestCode,
                        toCode: "290008",
                        toName: "泰信发展主题混合",
                        shares: 100,
                        tradeDate: "2026-06-22",
                        tradeTimeType: .before15,
                        acceptedDate: "2026-06-22",
                        createdAt: createdAt
                    )
                ],
                tradeRecords: [
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .pending, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: nil, shares: 100, confirmedShares: nil, price: nil, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: nil, failureReason: nil, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合"),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .pending, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: nil, shares: nil, confirmedShares: nil, price: nil, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: nil, failureReason: nil, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        now = try chinaDate("2026-06-23 09:30")
        await store.refreshQuotes()

        let pendingConversion = try XCTUnwrap(store.snapshot.pendingConversions?.first)
        XCTAssertEqual(pendingConversion.failureReason, "可转换份额不足")
        let records = try XCTUnwrap(store.snapshot.tradeRecords)
        XCTAssertEqual(records.filter { $0.status == .pending }.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.failureReason == "可转换份额不足" })

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingOneConversionRecordDeletesLinkedLegAndRecalculatesBothFunds() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-delete-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "conversion-1"
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 247.01, cost: 1.2044)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "source-new", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 200, shares: 200, confirmedShares: 200, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "target-new", kind: .newFund, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .share, amount: 50, shares: 50, confirmedShares: 50, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, sellFeeMode: .rate, sellFeeValue: 1, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合", feeAmount: 2.5),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 247.5, shares: nil, confirmedShares: 197.01, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, buyFeeRate: 0.5, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName, feeAmount: 1.23)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteTradeRecord(id: "conversion-out")

        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.conversionID == conversionID } ?? true)
        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedCost ?? 0, 1, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingFundRemovesLinkedConversionRecordsAndRebuildsOtherFund() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-delete-linked-conversion-fund-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "conversion-1"
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 247.01, cost: 1.2044)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "source-new", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 200, shares: 200, confirmedShares: 200, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "target-new", kind: .newFund, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .share, amount: 50, shares: 50, confirmedShares: 50, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, sellFeeMode: .rate, sellFeeValue: 1, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合", feeAmount: 2.5),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 247.5, shares: nil, confirmedShares: 197.01, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, buyFeeRate: 0.5, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName, feeAmount: 1.23)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteFund(code: "290008")

        XCTAssertFalse(store.snapshot.funds.contains { $0.code == "290008" })
        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.code == "290008" || $0.linkedCode == "290008" || $0.conversionID == conversionID } ?? false)
        XCTAssertNil(store.snapshot.pendingConversions)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 1, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingConfirmedConversionRestoresLegacySourceWithoutCreatingInitialRecord() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            "024424": ("东方阿尔法科技优选混合发起C", "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-delete-legacy-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "legacy-conversion-1"
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    FundPosition(
                        code: "024424",
                        name: "东方阿尔法科技优选混合发起C",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 100,
                        migratedCost: 2,
                        migratedPrincipal: 200,
                        incomeStartDate: "2026-06-17",
                        positionMode: .share,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "legacy-remaining", shares: 100, cost: 2, incomeStartDate: "2026-06-17", positionDate: "2026-06-17", positionTimeType: .before15)
                        ]
                    ),
                    FundPosition(
                        code: "290008",
                        name: "泰信发展主题混合",
                        dateText: "06-22 15:00",
                        todayIncome: 0,
                        todayRate: 0,
                        holdingRate: nil,
                        status: .holding,
                        isUpdated: true,
                        migratedShares: 200,
                        migratedCost: 1.25,
                        migratedPrincipal: 250,
                        incomeStartDate: "2026-06-22",
                        positionMode: .amount,
                        positionDate: "2026-06-22",
                        positionTimeType: .before15,
                        lots: [
                            FundPositionLot(id: "conversion-target", shares: 200, cost: 1.25, incomeStartDate: "2026-06-22", positionDate: "2026-06-22", positionTimeType: .before15)
                        ]
                    )
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: "024424", name: "东方阿尔法科技优选混合发起C", mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合"),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 250, shares: nil, confirmedShares: 200, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: "024424", linkedName: "东方阿尔法科技优选混合发起C")
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.deleteTradeRecord(id: "conversion-out")

        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.conversionID == conversionID } ?? false)
        XCTAssertFalse(store.snapshot.tradeRecords?.contains { $0.code == "024424" && $0.kind == .newFund } ?? false)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "024424" })
        XCTAssertEqual(sourceFund.status, .holding)
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedCost ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(sourceFund.migratedPrincipal ?? 0, 400, accuracy: 0.0001)

        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(targetFund.status, .pending)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 0, accuracy: 0.0001)
    }

    @MainActor
    func testEditingConfirmedConversionRecalculatesBothFunds() async throws {
        let now = try chinaDate("2026-06-23 09:30")
        let service = multiTradeQuoteService([
            Self.tradeTestCode: (Self.tradeTestName, "2026-06-22", 2.5),
            "290008": ("泰信发展主题混合", "2026-06-22", 1.25)
        ])
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-conversion-edit-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let createdAt = try chinaDate("2026-06-22 15:00")
        let conversionID = "conversion-1"
        let store = PortfolioStore(dataDirectory: tempDirectory, quoteService: service, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1),
                    conversionFund(code: "290008", name: "泰信发展主题混合", shares: 250, cost: 1.2)
                ],
                migration: nil,
                tradeRecords: [
                    FundTradeRecord(id: "source-new", kind: .newFund, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 200, shares: 200, confirmedShares: 200, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "target-new", kind: .newFund, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .share, amount: 50, shares: 50, confirmedShares: 50, price: 1, tradeDate: "2026-06-17", tradeTimeType: .before15, acceptedDate: "2026-06-17", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil),
                    FundTradeRecord(id: "conversion-out", kind: .conversionOut, status: .confirmed, code: Self.tradeTestCode, name: Self.tradeTestName, mode: .share, amount: 250, shares: 100, confirmedShares: 100, price: 2.5, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: "290008", linkedName: "泰信发展主题混合"),
                    FundTradeRecord(id: "conversion-in", kind: .conversionIn, status: .confirmed, code: "290008", name: "泰信发展主题混合", mode: .amount, amount: 250, shares: nil, confirmedShares: 200, price: 1.25, tradeDate: "2026-06-22", tradeTimeType: .before15, acceptedDate: "2026-06-22", createdAt: createdAt, confirmedAt: createdAt, failureReason: nil, conversionID: conversionID, linkedCode: Self.tradeTestCode, linkedName: Self.tradeTestName)
                ]
            ),
            into: store,
            directory: tempDirectory
        )

        try await store.editConversion(
            id: conversionID,
            with: FundConversionDraft(
                fromCode: Self.tradeTestCode,
                toCode: "290008",
                toName: "泰信发展主题混合",
                shares: 80,
                tradeDate: "2026-06-22",
                tradeTimeType: .before15
            )
        )

        XCTAssertNil(store.snapshot.pendingConversions)
        let outRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "conversion-out" })
        let inRecord = try XCTUnwrap(store.snapshot.tradeRecords?.first { $0.id == "conversion-in" })
        XCTAssertEqual(outRecord.status, .confirmed)
        XCTAssertEqual(inRecord.status, .confirmed)
        XCTAssertEqual(outRecord.confirmedShares ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(outRecord.amount ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(inRecord.confirmedShares ?? 0, 160, accuracy: 0.0001)
        XCTAssertEqual(inRecord.amount ?? 0, 200, accuracy: 0.0001)

        let sourceFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == Self.tradeTestCode })
        let targetFund = try XCTUnwrap(store.snapshot.funds.first { $0.code == "290008" })
        XCTAssertEqual(sourceFund.migratedShares ?? 0, 120, accuracy: 0.0001)
        XCTAssertEqual(targetFund.migratedShares ?? 0, 210, accuracy: 0.0001)
    }

    @MainActor
    func testConversionRejectsInvalidDrafts() async throws {
        let now = try chinaDate("2026-06-22 16:00")
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-invalid-conversion-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let store = PortfolioStore(dataDirectory: tempDirectory, now: { now })
        try seedPortfolio(
            PortfolioSnapshot(
                updateTime: now,
                totalAmount: 0,
                holdingIncome: 0,
                holdingIncomeRate: 0,
                todayIncome: 0,
                todayIncomeRate: 0,
                pendingCount: 0,
                funds: [
                    conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 100, cost: 1)
                ],
                migration: nil
            ),
            into: store,
            directory: tempDirectory
        )

        await XCTAssertThrowsErrorAsync {
            try await store.convertFundPosition(
                FundConversionDraft(fromCode: Self.tradeTestCode, toCode: Self.tradeTestCode, shares: 10, tradeDate: "2026-06-22", tradeTimeType: .before15)
            )
        } errorHandler: { error in
            XCTAssertEqual(error as? PortfolioStoreError, .invalidConversionTarget)
        }

        await XCTAssertThrowsErrorAsync {
            try await store.convertFundPosition(
                FundConversionDraft(fromCode: Self.tradeTestCode, toCode: "290008", shares: 0, tradeDate: "2026-06-22", tradeTimeType: .before15)
            )
        } errorHandler: { error in
            XCTAssertEqual(error as? PortfolioStoreError, .invalidPosition)
        }

        await XCTAssertThrowsErrorAsync {
            try await store.convertFundPosition(
                FundConversionDraft(fromCode: Self.tradeTestCode, toCode: "290008", shares: 120, tradeDate: "2026-06-22", tradeTimeType: .before15)
            )
        } errorHandler: { error in
            XCTAssertEqual(error as? PortfolioStoreError, .insufficientShares)
        }
    }

    func testConversionEditorPrimaryActionRequiresConfirmationBeforeSaving() {
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: false, isSaving: false, isConfirming: false),
            .ignore
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: true, isSaving: true, isConfirming: false),
            .ignore
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: true, isSaving: false, isConfirming: false),
            .showConfirmation
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryAction(canSubmit: true, isSaving: false, isConfirming: true),
            .save
        )
    }

    func testConversionEditorPresentationUsesConfirmationCopy() {
        XCTAssertEqual(
            FundConversionEditorPresentation.headerTitle(isEditing: false, isConfirming: false),
            "基金转换"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: false, isConfirming: false, isSaving: false),
            "转换确认"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.headerTitle(isEditing: false, isConfirming: true),
            "转换确认"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.headerSubtitle(isEditing: false, isConfirming: true),
            "确认后写入两条转换记录，净值更新后自动完成"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.cancelTitle(isConfirming: true),
            "返回修改"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: false, isConfirming: true, isSaving: false),
            "确认转换"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: true, isConfirming: false, isSaving: false),
            "保存确认"
        )
        XCTAssertEqual(
            FundConversionEditorPresentation.primaryTitle(isEditing: true, isConfirming: true, isSaving: false),
            "确认保存"
        )
    }

    func testConversionConfirmationSummaryIncludesBothFundsFeesAndAcceptedDate() {
        let summary = FundConversionConfirmationSummary.make(
            sourceFund: conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
            targetCode: "290008",
            targetName: "泰信发展主题混合",
            shares: 100,
            sellFeeMode: .rate,
            sellFeeValue: 1,
            buyFeeRate: 0.5,
            tradeDate: "2026-06-22",
            tradeTimeType: .after15
        )
        let rows = Dictionary(uniqueKeysWithValues: summary.rows.map { ($0.title, $0.value) })

        XCTAssertEqual(rows["转出基金"], "\(Self.tradeTestName) \(Self.tradeTestCode)")
        XCTAssertEqual(rows["转入基金"], "泰信发展主题混合 290008")
        XCTAssertEqual(rows["转出份额"], "100.00 份")
        XCTAssertEqual(rows["转出费率/费用"], "1.00%")
        XCTAssertEqual(rows["转入费率"], "0.50%")
        XCTAssertEqual(rows["交易日期"], "2026-06-22")
        XCTAssertEqual(rows["交易时段"], PositionTimeType.after15.title)
        XCTAssertEqual(rows["确认净值日"], "2026-06-23")
        XCTAssertEqual(summary.footnote, "*净值未取到时会先进入待确认，净值更新后自动完成转换")
    }

    func testConversionAmountProjectionUsesEstimateUntilBothNetValuesConfirmed() throws {
        let projection = try XCTUnwrap(
            FundConversionAmountProjection.make(
                sourceFund: conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                targetFund: nil,
                sourceQuote: FundQuote(
                    code: Self.tradeTestCode,
                    name: Self.tradeTestName,
                    netValue: 1,
                    estimatedNetValue: 1.05,
                    growthRate: 5,
                    estimateTime: "2026-06-26 14:30",
                    netValueDate: "2026-06-25"
                ),
                targetQuote: FundQuote(
                    code: "290008",
                    name: "泰信发展主题混合",
                    netValue: 2,
                    estimatedNetValue: 1.9,
                    growthRate: -5,
                    estimateTime: "2026-06-26 14:30",
                    netValueDate: "2026-06-25"
                ),
                sourceReferenceNetValue: nil,
                sourceReferenceNetValueDate: nil,
                targetReferenceNetValue: nil,
                targetReferenceNetValueDate: nil,
                acceptedDate: "2026-06-26",
                shares: 100,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertFalse(projection.isFullyConfirmed)
        XCTAssertEqual(projection.sourcePrice.value, 1.05, accuracy: 0.0001)
        XCTAssertFalse(projection.sourcePrice.isConfirmed)
        XCTAssertEqual(projection.targetPrice.value, 1.9, accuracy: 0.0001)
        XCTAssertFalse(projection.targetPrice.isConfirmed)
        XCTAssertEqual(projection.grossAmount, 105, accuracy: 0.0001)
        XCTAssertEqual(projection.sellFee, 1.05, accuracy: 0.0001)
        XCTAssertEqual(projection.transferAmount, 103.95, accuracy: 0.0001)
        XCTAssertEqual(projection.buyFee, 0.52, accuracy: 0.01)
        XCTAssertEqual(projection.targetShares, 54.44, accuracy: 0.01)
    }

    func testConversionAmountProjectionUsesConfirmedReferenceValuesWhenUpdated() throws {
        let projection = try XCTUnwrap(
            FundConversionAmountProjection.make(
                sourceFund: conversionFund(code: Self.tradeTestCode, name: Self.tradeTestName, shares: 200, cost: 1),
                targetFund: conversionFund(code: "290008", name: "泰信发展主题混合", shares: 50, cost: 1),
                sourceQuote: nil,
                targetQuote: nil,
                sourceReferenceNetValue: 2.5,
                sourceReferenceNetValueDate: "2026-06-22",
                targetReferenceNetValue: 1.25,
                targetReferenceNetValueDate: "2026-06-22",
                acceptedDate: "2026-06-22",
                shares: 100,
                sellFeeMode: .rate,
                sellFeeValue: 1,
                buyFeeRate: 0.5
            )
        )

        XCTAssertTrue(projection.isFullyConfirmed)
        XCTAssertEqual(projection.grossAmount, 250, accuracy: 0.0001)
        XCTAssertEqual(projection.transferAmount, 247.5, accuracy: 0.0001)
        XCTAssertEqual(projection.buyFee, 1.23, accuracy: 0.01)
        XCTAssertEqual(projection.targetShares, 197.01, accuracy: 0.01)
    }

    @MainActor
    func testPendingConversionKeepsPublishedSnapshotWhenPersistenceFails() async throws {
        let tempDirectory = temporaryPortfolioDirectory(prefix: "conversion-transaction")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let store = PortfolioStore(dataDirectory: tempDirectory)
        try seedPortfolio(transactionTestSnapshot(), into: store, directory: tempDirectory)
        let originalSnapshot = store.snapshot
        try makePortfolioStorageUnwritable(for: store)

        do {
            try await store.convertFundPosition(
                FundConversionDraft(
                    fromCode: Self.tradeTestCode,
                    toCode: "290008",
                    toName: "测试转换目标基金",
                    shares: 10,
                    tradeDate: "2026-07-10",
                    tradeTimeType: .before15
                )
            )
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(store.snapshot, originalSnapshot)
        }
    }
}
