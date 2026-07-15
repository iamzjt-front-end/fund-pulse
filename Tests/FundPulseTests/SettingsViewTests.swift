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
}
