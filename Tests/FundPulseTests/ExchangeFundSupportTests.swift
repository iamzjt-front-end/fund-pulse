import Foundation
import XCTest
@testable import FundPulse

final class ExchangeFundSupportTests: XCTestCase {
    override func tearDown() {
        ExchangeQuoteURLProtocol.responseStore.reset()
        super.tearDown()
    }

    func testExchangeQuoteDecodingKeepsMarketPriceTimeAndPreviousClose() throws {
        let quotes = try ExchangeFundQuoteService.decodeQuotes(from: Self.quoteFixture)
        let quote = try XCTUnwrap(quotes["510300"])

        XCTAssertEqual(quote.name, "沪深300ETF华泰柏瑞")
        XCTAssertEqual(quote.netValue, 4.627, accuracy: 0.000_001)
        XCTAssertEqual(quote.estimatedNetValue, 4.627, accuracy: 0.000_001)
        XCTAssertEqual(quote.growthRate, -1.13, accuracy: 0.000_001)
        XCTAssertEqual(quote.previousClose, 4.68)
        XCTAssertEqual(quote.netValueDate, "2026-08-24")
        XCTAssertEqual(quote.marketPriceTime, "2026-08-24 16:11")
        XCTAssertEqual(quote.estimateTime, quote.marketPriceTime)
        XCTAssertEqual(ExchangeFundQuoteService.securityID(for: "510300"), "1.510300")
        XCTAssertEqual(ExchangeFundQuoteService.securityID(for: "159915"), "0.159915")
        XCTAssertNil(ExchangeFundQuoteService.securityID(for: "51030"))
    }

    func testExchangePositionEntryUsesSharesAndSellableBaseline() {
        XCTAssertEqual(FundPositionEntryPolicy.modes(for: .onExchange), [.share])
        XCTAssertEqual(FundPositionEntryPolicy.defaultMode(for: .onExchange, existingMode: nil), .share)
        XCTAssertEqual(FundPositionEntryPolicy.modes(for: .offExchange), [.amount, .share])
        XCTAssertEqual(FundPositionEntryPolicy.defaultMode(for: .offExchange, existingMode: nil), .amount)
        XCTAssertEqual(FundPositionEntryPolicy.defaultMode(for: .onExchange, existingMode: .amount), .share)
    }

    func testOnExchangeFundListDoesNotExposePendingFilter() {
        XCTAssertEqual(FundListFilterPolicy.visibleFilters(for: .onExchange), [.holding])
        XCTAssertEqual(FundListFilterPolicy.visibleFilters(for: .offExchange), [.holding, .pending])
    }

    func testExchangeQuoteFallsBackToDelayEndpoint() async throws {
        ExchangeQuoteURLProtocol.responseStore.set([
            "push2.eastmoney.com": Data("not-json".utf8),
            "push2delay.eastmoney.com": Self.quoteFixture
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))

        let quote = try await service.fetchQuote(code: "510300")

        XCTAssertEqual(quote.name, "沪深300ETF华泰柏瑞")
        XCTAssertEqual(
            ExchangeQuoteURLProtocol.responseStore.requestedHosts(),
            ["push2.eastmoney.com", "push2delay.eastmoney.com"]
        )
    }

    @MainActor
    func testOnExchangeNameLookupUsesFundSearchIndependentlyOfMarketQuote() async {
        ExchangeQuoteURLProtocol.responseStore.set([
            "fundsuggest.eastmoney.com": Data(#"""
            FundPulseSuggest_123({"Datas":[{"CODE":"588060","NAME":"科创50ETF广发","SHORTNAME":"科创50ETF广发","CATEGORYDESC":"基金"}]});
            """#.utf8)
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = PortfolioStore(
            quoteService: FundQuoteService(session: session),
            exchangeQuoteService: ExchangeFundQuoteService(session: session),
            accountKind: .onExchange
        )

        let name = await store.lookupFundName(code: "588060")

        XCTAssertEqual(name, "科创50ETF广发")
        XCTAssertEqual(
            ExchangeQuoteURLProtocol.responseStore.requestedHosts(),
            ["fundsuggest.eastmoney.com"]
        )
    }

    @MainActor
    func testExchangeAmountBaselineDerivesSharesAndCostFromMarketValueAndProfit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-amount-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try JSONPortfolioRepository(dataDirectory: directory).save(.empty)
        ExchangeQuoteURLProtocol.responseStore.set(Self.quoteFixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let store = PortfolioStore(
            dataDirectory: directory,
            exchangeQuoteService: service,
            accountKind: .onExchange,
            now: { now }
        )
        store.load()

        try await store.upsertFund(FundPositionDraft(
            code: "510300",
            name: "",
            positionMode: .amount,
            positionAmount: 4_627,
            positionProfit: -53,
            positionDate: "2026-08-21",
            positionTimeType: .before15,
            memo: ""
        ))

        let fund = try XCTUnwrap(store.snapshot.funds.first)
        XCTAssertEqual(fund.positionMode, .amount)
        XCTAssertEqual(fund.migratedShares ?? -1, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(fund.migratedPrincipal ?? -1, 4_680, accuracy: 0.000_001)
        XCTAssertEqual(fund.migratedCost ?? -1, 4.68, accuracy: 0.000_001)
        XCTAssertEqual(fund.currentAmount ?? -1, 4_627, accuracy: 0.000_001)
        XCTAssertEqual(fund.holdingIncome ?? 0, -53, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertNil(store.snapshot.pendingTrades)

        let record = try XCTUnwrap(store.snapshot.tradeRecords?.first)
        XCTAssertEqual(record.mode, .amount)
        XCTAssertEqual(record.status, .confirmed)
        XCTAssertEqual(record.amount, 4_627)
        XCTAssertEqual(record.profit, -53)
        XCTAssertEqual(record.price, 4.627)
        XCTAssertEqual(record.confirmedShares, 1_000)
    }

    @MainActor
    func testExchangeAmountBaselineRequiresLatestMarketPrice() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-no-quote-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try JSONPortfolioRepository(dataDirectory: directory).save(.empty)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))
        let store = PortfolioStore(
            dataDirectory: directory,
            exchangeQuoteService: service,
            accountKind: .onExchange
        )
        store.load()

        do {
            try await store.upsertFund(FundPositionDraft(
                code: "510300",
                name: "沪深300ETF",
                positionMode: .amount,
                positionAmount: 4_627,
                positionProfit: -53,
                positionDate: "2026-08-21",
                positionTimeType: .before15,
                memo: ""
            ))
            XCTFail("按金额录入场内持仓时，没有最新成交价不应保存")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .missingExchangeMarketPrice)
        }
    }

    func testExchangeCalculatorUsesPreviousCloseForOldLotsAndExecutionCostForTodayLots() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let oldLot = FundPositionLot(
            id: "old",
            shares: 100,
            cost: 4,
            principal: 400,
            incomeStartDate: "2026-08-21",
            positionDate: "2026-08-21",
            positionTimeType: .before15
        )
        let todayLot = FundPositionLot(
            id: "today",
            shares: 50,
            cost: 4.7,
            principal: 237,
            incomeStartDate: "2026-08-24",
            positionDate: "2026-08-24",
            positionTimeType: .before15
        )
        let fund = FundPosition(
            code: "510300",
            name: "沪深300ETF",
            dateText: "08-24 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: nil,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: 150,
            migratedCost: 637 / 150,
            migratedPrincipal: 637,
            incomeStartDate: "2026-08-21",
            positionMode: .share,
            positionDate: "2026-08-24",
            positionTimeType: .before15,
            lots: [oldLot, todayLot]
        )
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [fund],
            migration: nil,
            tradeRecords: [
                FundTradeRecord(
                    id: "today",
                    kind: .buy,
                    status: .confirmed,
                    code: "510300",
                    name: "沪深300ETF",
                    mode: .share,
                    amount: 237,
                    shares: 50,
                    confirmedShares: 50,
                    price: 4.7,
                    tradeDate: "2026-08-24",
                    tradeTimeType: .before15,
                    acceptedDate: "2026-08-24",
                    createdAt: now,
                    confirmedAt: now,
                    failureReason: nil,
                    feeAmount: 2
                )
            ]
        )
        let quote = FundQuote(
            code: "510300",
            name: "沪深300ETF",
            netValue: 4.8,
            estimatedNetValue: 4.8,
            growthRate: (4.8 - 4.6) / 4.6 * 100,
            estimateTime: "2026-08-24 14:30",
            netValueDate: "2026-08-24",
            marketPriceTime: "2026-08-24 14:30",
            previousClose: 4.6
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: [quote.code: quote],
            now: now,
            accountKind: .onExchange
        )

        // Old lot: 100 × (4.8 - 4.6) = 20. Today's lot includes its ¥2 fee:
        // 50 × 4.8 - 237 = 3.
        XCTAssertEqual(result.todayIncome, 23, accuracy: 0.000_001)
        XCTAssertEqual(result.todayIncomeRate, 23 / 720 * 100, accuracy: 0.000_001)
        XCTAssertEqual(result.totalAmount, 720, accuracy: 0.000_001)
        XCTAssertEqual(result.holdingIncome, 83, accuracy: 0.000_001)
        XCTAssertEqual(result.funds[0].todayRate, quote.growthRate, accuracy: 0.000_001)
        XCTAssertEqual(result.funds[0].dateText, "08-24 14:30")
    }

    func testExchangeBaselineEnteredTodayStillUsesPreviousCloseForTodayIncome() throws {
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let baselineLot = FundPositionLot(
            id: "unmatched-baseline-lot",
            shares: 100,
            cost: 5,
            principal: 500,
            incomeStartDate: "2026-08-24",
            positionDate: "2026-08-24",
            positionTimeType: .before15
        )
        let fund = FundPosition(
            code: "510300",
            name: "沪深300ETF",
            dateText: "08-24 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: nil,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: 100,
            migratedCost: 5,
            migratedPrincipal: 500,
            incomeStartDate: "2026-08-24",
            positionMode: .share,
            positionDate: "2026-08-24",
            positionTimeType: .before15,
            lots: [baselineLot]
        )
        let baselineRecord = FundTradeRecord(
            id: "baseline-record",
            kind: .newFund,
            status: .confirmed,
            code: "510300",
            name: "沪深300ETF",
            mode: .share,
            amount: 500,
            shares: 100,
            confirmedShares: 100,
            price: 5,
            tradeDate: "2026-08-24",
            tradeTimeType: .before15,
            acceptedDate: "2026-08-24",
            createdAt: now,
            confirmedAt: now,
            failureReason: nil
        )
        let snapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [fund],
            migration: nil,
            tradeRecords: [baselineRecord]
        )
        let quote = FundQuote(
            code: "510300",
            name: "沪深300ETF",
            netValue: 4.8,
            estimatedNetValue: 4.8,
            growthRate: (4.8 - 4.6) / 4.6 * 100,
            estimateTime: "2026-08-24 14:30",
            netValueDate: "2026-08-24",
            marketPriceTime: "2026-08-24 14:30",
            previousClose: 4.6
        )

        let result = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: [quote.code: quote],
            now: now,
            accountKind: .onExchange
        )

        // The baseline was entered today but was not bought today. It should
        // use yesterday's close for daily income while holding income keeps
        // using the imported cost basis.
        XCTAssertEqual(result.todayIncome, 20, accuracy: 0.000_001)
        XCTAssertEqual(result.todayIncomeRate, 20 / 480 * 100, accuracy: 0.000_001)
        XCTAssertEqual(result.holdingIncome, -20, accuracy: 0.000_001)
        XCTAssertEqual(result.holdingIncomeRate, -4, accuracy: 0.000_001)
    }

    func testExchangeFirstDayReconciliationOverridesAmountsOnlyOnBaselineDate() throws {
        let baselineDate = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let baselineLot = FundPositionLot(
            id: "baseline-lot",
            shares: 100,
            cost: 5,
            principal: 500,
            incomeStartDate: "2026-08-21",
            positionDate: "2026-08-21",
            positionTimeType: .before15
        )
        let fund = FundPosition(
            code: "510300",
            name: "沪深300ETF",
            dateText: "08-24 15:00",
            todayIncome: 0,
            todayRate: 0,
            holdingRate: nil,
            status: .holding,
            isUpdated: false,
            isIncomeActive: true,
            migratedShares: 100,
            migratedCost: 5,
            migratedPrincipal: 500,
            incomeStartDate: "2026-08-21",
            positionMode: .share,
            positionDate: "2026-08-21",
            positionTimeType: .before15,
            lots: [baselineLot]
        )
        let snapshot = PortfolioSnapshot(
            updateTime: baselineDate,
            totalAmount: 0,
            holdingIncome: 0,
            holdingIncomeRate: 0,
            todayIncome: 0,
            todayIncomeRate: 0,
            pendingCount: 0,
            funds: [fund],
            migration: nil,
            exchangeAccountReconciliation: ExchangeAccountReconciliation(
                date: "2026-08-24",
                holdingsMarketValue: 480,
                reportedHoldingIncome: -25,
                reportedTodayIncome: -30
            )
        )
        let baselineQuote = FundQuote(
            code: "510300",
            name: "沪深300ETF",
            netValue: 4.8,
            estimatedNetValue: 4.8,
            growthRate: (4.8 - 4.6) / 4.6 * 100,
            estimateTime: "2026-08-24 15:00",
            netValueDate: "2026-08-24",
            marketPriceTime: "2026-08-24 15:00",
            previousClose: 4.6
        )

        let reconciled = PortfolioCalculator.applyingQuotes(
            to: snapshot,
            quotes: [baselineQuote.code: baselineQuote],
            now: baselineDate,
            accountKind: .onExchange
        )

        XCTAssertEqual(reconciled.totalAmount, 480, accuracy: 0.000_001)
        XCTAssertEqual(reconciled.holdingIncome, -25, accuracy: 0.000_001)
        XCTAssertEqual(reconciled.holdingIncomeRate, -25 / 505 * 100, accuracy: 0.000_001)
        XCTAssertEqual(reconciled.todayIncome, -30, accuracy: 0.000_001)
        XCTAssertEqual(reconciled.todayIncomeRate, -30 / 480 * 100, accuracy: 0.000_001)

        let nextDate = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-25"))
        let nextQuote = FundQuote(
            code: "510300",
            name: "沪深300ETF",
            netValue: 4.9,
            estimatedNetValue: 4.9,
            growthRate: (4.9 - 4.8) / 4.8 * 100,
            estimateTime: "2026-08-25 15:00",
            netValueDate: "2026-08-25",
            marketPriceTime: "2026-08-25 15:00",
            previousClose: 4.8
        )
        let nextDay = PortfolioCalculator.applyingQuotes(
            to: reconciled,
            quotes: [nextQuote.code: nextQuote],
            now: nextDate,
            accountKind: .onExchange
        )

        XCTAssertEqual(nextDay.totalAmount, 490, accuracy: 0.000_001)
        XCTAssertEqual(nextDay.holdingIncome, -10, accuracy: 0.000_001)
        XCTAssertEqual(nextDay.todayIncome, 10, accuracy: 0.000_001)
        XCTAssertEqual(nextDay.todayIncomeRate, 10 / 490 * 100, accuracy: 0.000_001)
    }

    @MainActor
    func testStorePersistsFirstDayReconciliationUsingHoldingsOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-reconciliation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let fund = FundPosition(
            code: "510300",
            name: "沪深300ETF",
            dateText: "08-24 15:00",
            todayIncome: 20,
            todayRate: 4.35,
            holdingIncome: -20,
            holdingRate: -4,
            currentAmount: 480,
            status: .holding,
            isUpdated: true,
            isIncomeActive: true,
            migratedShares: 100,
            migratedCost: 5,
            migratedPrincipal: 500,
            incomeStartDate: "2026-08-21",
            positionMode: .share,
            positionDate: "2026-08-21",
            positionTimeType: .before15,
            lots: [
                FundPositionLot(
                    id: "baseline-lot",
                    shares: 100,
                    cost: 5,
                    principal: 500,
                    incomeStartDate: "2026-08-21",
                    positionDate: "2026-08-21",
                    positionTimeType: .before15
                )
            ]
        )
        let initialSnapshot = PortfolioSnapshot(
            updateTime: now,
            totalAmount: 480,
            holdingIncome: -20,
            holdingIncomeRate: -4,
            todayIncome: 20,
            todayIncomeRate: 20 / 480 * 100,
            pendingCount: 0,
            funds: [fund],
            migration: nil
        )
        let repository = JSONPortfolioRepository(dataDirectory: directory)
        try repository.save(initialSnapshot)
        let store = PortfolioStore(
            dataDirectory: directory,
            accountKind: .onExchange,
            now: { now }
        )
        store.load()

        try store.applyExchangeFirstDayReconciliation(
            date: "2026-08-24",
            reportedHoldingIncome: -25,
            reportedTodayIncome: -30
        )

        XCTAssertEqual(store.snapshot.totalAmount, 480, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.holdingIncome, -25, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.holdingIncomeRate, -25 / 505 * 100, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.todayIncome, -30, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.todayIncomeRate, -30 / 480 * 100, accuracy: 0.000_001)
        XCTAssertEqual(
            store.snapshot.exchangeAccountReconciliation,
            ExchangeAccountReconciliation(
                date: "2026-08-24",
                holdingsMarketValue: 480,
                reportedHoldingIncome: -25,
                reportedTodayIncome: -30
            )
        )

        let persisted = try XCTUnwrap(try repository.load())
        XCTAssertEqual(persisted.exchangeAccountReconciliation, store.snapshot.exchangeAccountReconciliation)
        XCTAssertEqual(persisted.totalAmount, 480, accuracy: 0.000_001)
    }

    @MainActor
    func testExchangeTradesConfirmImmediatelyAndRebuildFeeAdjustedCost() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try JSONPortfolioRepository(dataDirectory: directory).save(.empty)
        ExchangeQuoteURLProtocol.responseStore.set(Self.quoteFixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let store = PortfolioStore(
            dataDirectory: directory,
            exchangeQuoteService: service,
            accountKind: .onExchange,
            now: { now }
        )
        store.load()

        try await store.upsertFund(FundPositionDraft(
            code: "510300",
            name: "",
            positionMode: .share,
            positionProfit: 0,
            shares: 100,
            cost: 4,
            positionDate: "2026-08-21",
            positionTimeType: .before15,
            memo: ""
        ))

        XCTAssertEqual(store.accountKind, .onExchange)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.status, .confirmed)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.price, 4)

        try await store.adjustFundPosition(FundTradeDraft(
            action: .buy,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 50,
            tradeDate: "2026-08-24",
            tradeTimeType: .before15,
            price: 4.7,
            feeAmount: 2
        ))

        XCTAssertNil(store.snapshot.pendingTrades)
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertEqual(store.snapshot.funds[0].migratedShares ?? -1, 150, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.funds[0].migratedPrincipal ?? -1, 637, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.funds[0].migratedCost ?? -1, 637 / 150, accuracy: 0.000_1)
        let buyRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(buyRecord.kind, .buy)
        XCTAssertEqual(buyRecord.status, .confirmed)
        XCTAssertEqual(buyRecord.amount, 237)
        XCTAssertEqual(buyRecord.feeAmount, 2)

        try await store.editTradeRecord(id: buyRecord.id, with: FundTradeDraft(
            action: .buy,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 60,
            tradeDate: "2026-08-24",
            tradeTimeType: .before15,
            price: 4.5,
            feeAmount: 3
        ))

        XCTAssertEqual(store.snapshot.funds[0].migratedShares ?? -1, 160, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.funds[0].migratedPrincipal ?? -1, 673, accuracy: 0.000_001)

        try await store.adjustFundPosition(FundTradeDraft(
            action: .sell,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 20,
            tradeDate: "2026-08-24",
            tradeTimeType: .before15,
            price: 4.8,
            feeAmount: 1
        ))

        XCTAssertEqual(store.snapshot.funds[0].migratedShares ?? -1, 140, accuracy: 0.000_001)
        XCTAssertEqual(store.snapshot.funds[0].migratedPrincipal ?? -1, 593, accuracy: 0.000_001)
        let sellRecord = try XCTUnwrap(store.snapshot.tradeRecords?.last)
        XCTAssertEqual(sellRecord.kind, .sell)
        XCTAssertEqual(sellRecord.status, .confirmed)
        XCTAssertEqual(sellRecord.amount, 95)
        XCTAssertEqual(sellRecord.feeAmount, 1)
        XCTAssertTrue(store.snapshot.tradeRecords?.allSatisfy { $0.status == .confirmed } == true)

        do {
            try await store.convertFundPosition(FundConversionDraft(
                fromCode: "510300",
                toCode: "159915",
                shares: 10,
                tradeDate: "2026-08-24",
                tradeTimeType: .before15
            ))
            XCTFail("场内账户不应进入场外基金转换流程")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .operationUnavailableForAccount)
        }
    }

    @MainActor
    func testNextTradingDayRuleLocksOnlyActualBuyLotsUntilMonday() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-t1-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try JSONPortfolioRepository(dataDirectory: directory).save(.empty)
        ExchangeQuoteURLProtocol.responseStore.set(Self.quoteFixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-28"))
        let store = PortfolioStore(
            dataDirectory: directory,
            exchangeQuoteService: service,
            accountKind: .onExchange,
            now: { now }
        )
        store.load()

        try await store.upsertFund(FundPositionDraft(
            code: "510300",
            name: "沪深300ETF",
            positionMode: .share,
            positionProfit: 0,
            shares: 100,
            cost: 4,
            positionDate: "2026-08-28",
            positionTimeType: .before15,
            memo: "",
            exchangeTurnaroundRule: .nextTradingDay
        ))
        try await store.adjustFundPosition(FundTradeDraft(
            action: .buy,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 50,
            tradeDate: "2026-08-28",
            tradeTimeType: .before15,
            price: 4.2,
            feeAmount: 0
        ))

        let availability = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(availability.heldShares, 150, accuracy: 0.000_001)
        XCTAssertEqual(availability.sellableShares, 100, accuracy: 0.000_001)
        XCTAssertEqual(availability.lockedShares, 50, accuracy: 0.000_001)
        XCTAssertEqual(availability.nextUnlockDate, "2026-08-31")
        XCTAssertEqual(store.snapshot.pendingCount, 0)
        XCTAssertTrue(store.snapshot.tradeRecords?.allSatisfy { $0.status == .confirmed } == true)

        do {
            try await store.adjustFundPosition(FundTradeDraft(
                action: .sell,
                code: "510300",
                mode: .share,
                amount: nil,
                shares: 101,
                tradeDate: "2026-08-28",
                tradeTimeType: .before15,
                price: 4.3,
                feeAmount: 0
            ))
            XCTFail("T+1 基金不应允许卖出当日买入份额")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .insufficientShares)
        }

        // The imported baseline represents an existing holding and remains
        // sellable even though its baseline date is today.
        try await store.adjustFundPosition(FundTradeDraft(
            action: .sell,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 100,
            tradeDate: "2026-08-28",
            tradeTimeType: .before15,
            price: 4.3,
            feeAmount: 0
        ))

        let afterBaselineSale = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(afterBaselineSale.heldShares, 50, accuracy: 0.000_001)
        XCTAssertEqual(afterBaselineSale.sellableShares, 0, accuracy: 0.000_001)
        XCTAssertEqual(afterBaselineSale.lockedShares, 50, accuracy: 0.000_001)

        try await store.adjustFundPosition(FundTradeDraft(
            action: .sell,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 50,
            tradeDate: "2026-08-31",
            tradeTimeType: .before15,
            price: 4.3,
            feeAmount: 0
        ))
        XCTAssertEqual(store.snapshot.funds[0].migratedShares ?? -1, 0, accuracy: 0.000_001)
    }

    @MainActor
    func testExchangeBaselineStoresBrokerSellableSharesAndKeepsThemAfterTradeRebuild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-baseline-sellable-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try JSONPortfolioRepository(dataDirectory: directory).save(.empty)
        ExchangeQuoteURLProtocol.responseStore.set(Self.quoteFixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-28"))
        let store = PortfolioStore(
            dataDirectory: directory,
            exchangeQuoteService: service,
            accountKind: .onExchange,
            now: { now }
        )
        store.load()

        do {
            try await store.upsertFund(FundPositionDraft(
                code: "510300",
                name: "沪深300ETF",
                positionMode: .share,
                positionProfit: 0,
                shares: 150,
                cost: 4,
                positionDate: "2026-08-28",
                positionTimeType: .before15,
                memo: "",
                exchangeTurnaroundRule: .nextTradingDay,
                exchangeSellableShares: 151
            ))
            XCTFail("可卖份额超过持仓份额时不应保存")
        } catch {
            XCTAssertEqual(error as? PortfolioStoreError, .invalidExchangeSellableShares)
        }

        try await store.upsertFund(FundPositionDraft(
            code: "510300",
            name: "沪深300ETF",
            positionMode: .share,
            positionProfit: 0,
            shares: 150,
            cost: 4,
            positionDate: "2026-08-28",
            positionTimeType: .before15,
            memo: "",
            exchangeTurnaroundRule: .nextTradingDay,
            exchangeSellableShares: 100
        ))

        var availability = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(availability.heldShares, 150, accuracy: 0.000_001)
        XCTAssertEqual(availability.sellableShares, 100, accuracy: 0.000_001)
        XCTAssertEqual(availability.lockedShares, 50, accuracy: 0.000_001)
        XCTAssertEqual(availability.nextUnlockDate, "2026-08-31")
        XCTAssertEqual(store.snapshot.funds[0].lots?.count, 2)
        XCTAssertEqual(store.snapshot.tradeRecords?.first?.exchangeInitialSellableShares, 100)

        try await store.adjustFundPosition(FundTradeDraft(
            action: .buy,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 10,
            tradeDate: "2026-08-28",
            tradeTimeType: .before15,
            price: 4.2,
            feeAmount: 0
        ))

        availability = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(availability.heldShares, 160, accuracy: 0.000_001)
        XCTAssertEqual(availability.sellableShares, 100, accuracy: 0.000_001)
        XCTAssertEqual(availability.lockedShares, 60, accuracy: 0.000_001)
        XCTAssertEqual(availability.nextUnlockDate, "2026-08-31")
    }

    @MainActor
    func testSameDayTurnaroundRuleAllowsSellingTodayBuyLots() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-exchange-t0-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try JSONPortfolioRepository(dataDirectory: directory).save(.empty)
        ExchangeQuoteURLProtocol.responseStore.set(Self.quoteFixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeQuoteURLProtocol.self]
        let service = ExchangeFundQuoteService(session: URLSession(configuration: configuration))
        let now = try XCTUnwrap(DateOnlyFormatter.parse("2026-08-24"))
        let store = PortfolioStore(
            dataDirectory: directory,
            exchangeQuoteService: service,
            accountKind: .onExchange,
            now: { now }
        )
        store.load()

        try await store.upsertFund(FundPositionDraft(
            code: "510300",
            name: "测试 T+0 ETF",
            positionMode: .share,
            positionProfit: 0,
            shares: 100,
            cost: 4,
            positionDate: "2026-08-21",
            positionTimeType: .before15,
            memo: "",
            exchangeTurnaroundRule: .sameDay
        ))
        try await store.adjustFundPosition(FundTradeDraft(
            action: .buy,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 50,
            tradeDate: "2026-08-24",
            tradeTimeType: .before15,
            price: 4.2,
            feeAmount: 0
        ))

        let availability = store.exchangeShareAvailability(for: "510300")
        XCTAssertEqual(store.snapshot.funds[0].exchangeTurnaroundRule, .sameDay)
        XCTAssertEqual(availability.heldShares, 150, accuracy: 0.000_001)
        XCTAssertEqual(availability.sellableShares, 150, accuracy: 0.000_001)
        XCTAssertEqual(availability.lockedShares, 0, accuracy: 0.000_001)
        XCTAssertNil(availability.nextUnlockDate)

        try await store.adjustFundPosition(FundTradeDraft(
            action: .sell,
            code: "510300",
            mode: .share,
            amount: nil,
            shares: 150,
            tradeDate: "2026-08-24",
            tradeTimeType: .before15,
            price: 4.3,
            feeAmount: 0
        ))
        XCTAssertEqual(store.snapshot.funds[0].migratedShares ?? -1, 0, accuracy: 0.000_001)
    }

    private static let quoteFixture = Data(#"""
    {
      "rc": 0,
      "data": {
        "total": 2,
        "diff": [
          {
            "f2": 4.627,
            "f3": -1.13,
            "f12": "510300",
            "f14": "沪深300ETF华泰柏瑞",
            "f18": 4.68,
            "f124": 1787559092
          },
          {
            "f2": 3.457,
            "f3": -2.89,
            "f12": "159915",
            "f14": "创业板ETF易方达",
            "f18": 3.56,
            "f124": 1787556855
          }
        ]
      }
    }
    """#.utf8)
}

private final class ExchangeQuoteResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var responseData: Data?
    private var responsesByHost: [String: Data] = [:]
    private var requests: [URLRequest] = []

    func set(_ data: Data) {
        lock.lock()
        responseData = data
        responsesByHost = [:]
        requests = []
        lock.unlock()
    }

    func set(_ responses: [String: Data]) {
        lock.lock()
        responseData = nil
        responsesByHost = responses
        requests = []
        lock.unlock()
    }

    func reset() {
        lock.lock()
        responseData = nil
        responsesByHost = [:]
        requests = []
        lock.unlock()
    }

    func response(for request: URLRequest) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        if let host = request.url?.host, let response = responsesByHost[host] {
            return response
        }
        return responseData
    }

    func requestedHosts() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests.compactMap { $0.url?.host }
    }
}

private final class ExchangeQuoteURLProtocol: URLProtocol {
    static let responseStore = ExchangeQuoteResponseStore()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let data = Self.responseStore.response(for: request),
              let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
