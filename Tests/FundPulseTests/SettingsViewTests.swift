import Foundation
import XCTest
@testable import FundPulse

final class SettingsViewTests: XCTestCase {
    func testSectionsHaveStableOrderAndTitles() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.display, .refreshAndReminders, .data, .support, .about]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["显示", "提醒", "数据", "支持", "关于"]
        )
    }

    func testSessionDefaultsToDisplayAndRetainsSelection() {
        var session = SettingsSectionSession()

        XCTAssertEqual(session.selectedSection, .display)

        session.select(.about)

        XCTAssertEqual(session.selectedSection, .about)
    }

    func testSupportHasItsOwnTopLevelSectionAndAboutSeparatesFeedbackFromContact() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FundPulse/Views/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let supportStart = try XCTUnwrap(source.range(of: "private var supportSettingsContent"))
        let aboutStart = try XCTUnwrap(source.range(of: "private var aboutSettingsContent"))
        let supportSource = source[supportStart.lowerBound..<aboutStart.lowerBound]
        let aboutEnd = try XCTUnwrap(
            source.range(of: "private var operationReminderSettingsSection", range: aboutStart.upperBound..<source.endIndex)
        )
        let aboutSource = source[aboutStart.lowerBound..<aboutEnd.lowerBound]
        let feedback = try XCTUnwrap(aboutSource.range(of: "PanelSection(title: \"建议反馈\")"))
        let contact = try XCTUnwrap(aboutSource.range(of: "PanelSection(title: \"联系作者\")"))
        let privacy = try XCTUnwrap(aboutSource.range(of: "PanelSection(title: \"关于与隐私\")"))

        XCTAssertLessThan(feedback.lowerBound, contact.lowerBound)
        XCTAssertLessThan(contact.lowerBound, privacy.lowerBound)
        XCTAssertTrue(supportSource.contains("PanelSection(title: \"支持作者\")"))
        XCTAssertTrue(supportSource.contains("supportAuthorSection"))
        XCTAssertTrue(source.contains("SupportAuthorSection()"))
        XCTAssertFalse(aboutSource.contains("支持作者"))
        XCTAssertFalse(source.contains("onOpenSupportAuthor"))

        let feedbackSectionStart = try XCTUnwrap(source.range(of: "private var feedbackSection"))
        let contactSectionStart = try XCTUnwrap(source.range(of: "private var contactAuthorSection"))
        let feedbackSectionSource = source[feedbackSectionStart.lowerBound..<contactSectionStart.lowerBound]
        let contactSectionEnd = try XCTUnwrap(
            source.range(of: "private var canClearHoldings", range: contactSectionStart.upperBound..<source.endIndex)
        )
        let contactSectionSource = source[contactSectionStart.lowerBound..<contactSectionEnd.lowerBound]

        XCTAssertTrue(feedbackSectionSource.contains("报告问题"))
        XCTAssertTrue(feedbackSectionSource.contains("提出建议"))
        XCTAssertFalse(feedbackSectionSource.contains("邮件联系"))
        XCTAssertTrue(contactSectionSource.contains("ContactAuthorResources"))
        XCTAssertTrue(contactSectionSource.contains("微信联系二维码"))
        XCTAssertFalse(contactSectionSource.contains("邮件联系"))
        XCTAssertFalse(contactSectionSource.contains("报告问题"))
        XCTAssertFalse(contactSectionSource.contains("提出建议"))
        XCTAssertFalse(source.contains("openFeedbackMail"))
        XCTAssertFalse(source.contains("feedbackMailURL"))
    }

    func testSupportAuthorIsNotAChildPanelRoute() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FundPulse/Controllers/ChildPanelRoute.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("case supportAuthor"))
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
