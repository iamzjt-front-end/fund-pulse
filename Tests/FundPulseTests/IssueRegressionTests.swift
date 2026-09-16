import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import FundPulse

final class IssueRegressionTests: XCTestCase {
    @MainActor
    func testIssue2AboutAndSupportSettingsRenderInBothAppearances() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fund-pulse-issue-2-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PortfolioStore(dataDirectory: root)
        let settings = AppSettingsStore(dataDirectory: root)
        let update = AppUpdateStore()

        for section in [SettingsSection.about, .support] {
            for scheme in [ColorScheme.light, .dark] {
                let view = SettingsView(
                    store: store,
                    account: .defaultAccount(),
                    settingsStore: settings,
                    updateStore: update,
                    appVersion: "1.0.61",
                    onSettingsChanged: nil,
                    onRefresh: nil,
                    onCheckUpdate: nil,
                    initialSection: section
                ).environment(\.colorScheme, scheme)
                // Host the native ScrollView too: ImageRenderer only captures
                // the surrounding SwiftUI header and footer on macOS.
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: PopoverLayout.settingsSize),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                XCTAssertEqual(hosting.frame.size, PopoverLayout.settingsSize)
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                if ProcessInfo.processInfo.environment["FUND_PULSE_CAPTURE_ISSUE_2"] == "1" {
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: FileManager.default.temporaryDirectory.appending(
                        path: "fund-pulse-issue-2-\(section.rawValue)-\(scheme).png"
                    ))
                }
            }
        }
    }

    func testIssue2RelocatedAppFindsResourcesInsideContentsResources() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fund-pulse-relocated-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Moved.app")
        let resources = app.appending(path: "Contents/Resources")
        let bundle = resources.appending(path: "FundPulse_FundPulse.bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("image fixture".utf8).write(to: bundle.appending(path: "wechat-contact.png"))
        let resolved = AppResourceBundle.resolve(resourceURL: resources, bundleURL: app)
        XCTAssertNotNil(resolved?.url(forResource: "wechat-contact", withExtension: "png"))
    }

    func testIssue2MissingResourceBundleReturnsNilWithoutFatalError() {
        XCTAssertNil(AppResourceBundle.resolve(resourceURL: nil,
            bundleURL: URL(fileURLWithPath: "/nonexistent/fund-pulse.app")))
    }

    func testIssue2NegativeHoldingReturnUsesOfficialNAVAndActualCost() throws {
        var snapshot = PortfolioSnapshot.empty
        snapshot.funds = [FundPosition(code: "026211", name: "Issue 2", dateText: "", todayIncome: 0,
            todayRate: 0, holdingRate: 0, status: .holding, isUpdated: false,
            migratedShares: 47.92, migratedCost: 2.4373, positionDate: "2026-07-20")]
        let quote = FundQuote(code: "026211", name: "Issue 2", netValue: 1.6772,
            estimatedNetValue: 1.81373, growthRate: 8.14, estimateTime: "2026-07-22 15:00", netValueDate: "2026-07-21")
        let result = PortfolioCalculator.applyingQuotes(to: snapshot, quotes: [quote.code: quote],
            now: try XCTUnwrap(DateOnlyFormatter.parse("2026-07-22")))
        XCTAssertEqual(result.holdingIncome, -36.423992, accuracy: 0.000001)
        XCTAssertEqual(result.holdingIncomeRate, (1.6772 / 2.4373 - 1) * 100, accuracy: 0.00001)
        XCTAssertLessThan(try XCTUnwrap(result.funds.first?.holdingRate), -31)
    }
}
