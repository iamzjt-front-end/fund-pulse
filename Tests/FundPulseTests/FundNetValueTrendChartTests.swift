import Foundation
import XCTest
@testable import FundPulse

final class FundNetValueTrendChartTests: XCTestCase {
    func testScaleKeepsTheSingleHoldingCostReferenceVisible() {
        let scale = FundNetValueTrendScale(
            pointValues: [1.1200, 1.1800, 1.1500],
            holdingCost: 1.4200
        )

        XCTAssertEqual(scale.costReference, 1.4200)
        XCTAssertGreaterThan(scale.maximum, 1.4200)
        XCTAssertLessThan(
            scale.normalizedY(for: 1.4200),
            scale.normalizedY(for: 1.1800)
        )
    }

    func testScaleDoesNotCreateACostReferenceForInvalidValues() {
        XCTAssertNil(
            FundNetValueTrendScale(pointValues: [1.1, 1.2], holdingCost: nil).costReference
        )
        XCTAssertNil(
            FundNetValueTrendScale(pointValues: [1.1, 1.2], holdingCost: 0).costReference
        )
        XCTAssertNil(
            FundNetValueTrendScale(pointValues: [1.1, 1.2], holdingCost: .infinity).costReference
        )
    }

    func testFundDetailWiresHoldingCostInsteadOfHistoricalTradeMarkers() throws {
        let source = try popoverSource()

        XCTAssertTrue(
            source.contains("FundTrendMiniChart(points: trendPoints, holdingCost: fund.migratedCost)")
        )
        XCTAssertFalse(source.contains("netValueTradeMarkers"))
        XCTAssertFalse(source.contains("FundTrendTradeMarker"))
    }

    func testCostReferenceUsesCompactHeaderAndSinglePlotPoint() throws {
        let source = try popoverSource()
        let headerStart = try XCTUnwrap(source.range(of: "private func netValueTrendHeader"))
        let headerEnd = try XCTUnwrap(
            source.range(of: "private var historySection", range: headerStart.upperBound..<source.endIndex)
        )
        let headerSource = source[headerStart.lowerBound..<headerEnd.lowerBound]
        let chartStart = try XCTUnwrap(source.range(of: "private struct FundTrendMiniChart"))
        let chartEnd = try XCTUnwrap(
            source.range(of: "let panelBorderColor", range: chartStart.upperBound..<source.endIndex)
        )
        let chartSource = source[chartStart.lowerBound..<chartEnd.lowerBound]

        XCTAssertTrue(headerSource.contains("HStack(alignment: .firstTextBaseline"))
        XCTAssertTrue(headerSource.contains("Text(\"最新 "))
        XCTAssertTrue(headerSource.contains("Text(\"成本 "))
        XCTAssertFalse(headerSource.contains("VStack("))
        XCTAssertFalse(headerSource.contains("Circle()"))
        XCTAssertFalse(chartSource.contains("Text(\"成本"))
        XCTAssertFalse(chartSource.contains("labelWidth"))
        XCTAssertTrue(chartSource.contains("let pointX = min(CGFloat(4), size.width)"))
        XCTAssertTrue(chartSource.contains("path.addLine(to: CGPoint(x: size.width, y: y))"))
    }

    private func popoverSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FundPulse/Views/PopoverContentView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
