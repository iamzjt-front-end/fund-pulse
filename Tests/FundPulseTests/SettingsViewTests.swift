import Foundation
import XCTest
@testable import FundPulse

final class SettingsViewTests: XCTestCase {
    func testSectionsHaveStableOrderAndTitles() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.display, .refreshAndReminders, .data, .about]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["显示", "提醒", "数据", "关于"]
        )
    }

    func testSessionDefaultsToDisplayAndRetainsSelection() {
        var session = SettingsSectionSession()

        XCTAssertEqual(session.selectedSection, .display)

        session.select(.about)

        XCTAssertEqual(session.selectedSection, .about)
    }

    func testQuitActionLivesInGlobalFooterInsteadOfAboutSection() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FundPulse/Views/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View"))
        let bodyEnd = try XCTUnwrap(
            source.range(of: "private var header", range: bodyStart.upperBound..<source.endIndex)
        )
        let bodySource = source[bodyStart.lowerBound..<bodyEnd.lowerBound]
        XCTAssertTrue(bodySource.contains("settingsFooter"))

        let aboutStart = try XCTUnwrap(source.range(of: "private var aboutSettingsContent"))
        let aboutEnd = try XCTUnwrap(
            source.range(of: "private var operationReminderSettingsSection", range: aboutStart.upperBound..<source.endIndex)
        )
        let aboutSource = source[aboutStart.lowerBound..<aboutEnd.lowerBound]
        XCTAssertFalse(aboutSource.contains("退出 Fund Pulse"))

        let footerStart = try XCTUnwrap(source.range(of: "private var settingsFooter"))
        let footerEnd = try XCTUnwrap(source.range(of: "private var aboutSettingsContent"))
        let footerSource = source[footerStart.lowerBound..<footerEnd.lowerBound]
        XCTAssertTrue(footerSource.contains("退出 Fund Pulse"))
        XCTAssertFalse(footerSource.contains("PanelSection"))
        XCTAssertFalse(footerSource.contains("\"应用\""))
    }
}
