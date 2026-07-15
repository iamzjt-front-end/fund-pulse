import Foundation
import XCTest
@testable import FundPulse

final class LegalContentTests: XCTestCase {
    func testPublicLinksUseRepositoryPrivacyAndIssuePages() {
        XCTAssertEqual(
            LegalContent.privacyPolicyURL.absoluteString,
            "https://github.com/iamzjt-front-end/fund-pulse/blob/main/PRIVACY.md"
        )
        XCTAssertEqual(
            LegalContent.supportURL.absoluteString,
            "https://github.com/iamzjt-front-end/fund-pulse/issues"
        )
    }

    func testPrivacyContentDescribesLocalDataAndEveryNetworkProvider() {
        let text = LegalContent.searchableText

        XCTAssertTrue(text.contains("portfolio.json"))
        XCTAssertTrue(text.contains("settings.json"))
        XCTAssertTrue(text.contains("历史收益"))
        XCTAssertTrue(text.contains("东方财富"))
        XCTAssertTrue(text.contains("腾讯"))
        XCTAssertTrue(text.contains("同花顺"))
        XCTAssertTrue(text.contains("京东"))
        XCTAssertTrue(text.contains("Cookie"))
        XCTAssertTrue(text.contains("GitHub"))
        XCTAssertTrue(text.contains("启动时会自动"))
    }

    func testPrivacyContentStatesCollectionBoundaries() {
        let text = LegalContent.searchableText

        XCTAssertTrue(text.contains("仅向京东"))
        XCTAssertTrue(text.contains("自有账号"))
        XCTAssertTrue(text.contains("广告"))
        XCTAssertTrue(text.contains("分析 SDK"))
    }

    func testJDFinanceDisclosureIncludesOptionalHistoricalIncomeSync() throws {
        let section = try XCTUnwrap(LegalContent.sections.first { $0.id == "jd-finance" })
        let text = (section.paragraphs + section.bullets).joined(separator: "\n")

        XCTAssertTrue(text.contains("历史收益记录"))
        XCTAssertTrue(text.contains("主动"))
        XCTAssertTrue(text.contains("仅向京东"))
    }

    func testDisclaimerCoversRequiredRiskStatementsAndDeletion() {
        let text = LegalContent.searchableText

        XCTAssertTrue(text.contains("估值"))
        XCTAssertTrue(text.contains("官方净值"))
        XCTAssertTrue(text.contains("延迟"))
        XCTAssertTrue(text.contains("错误"))
        XCTAssertTrue(text.contains("投资建议"))
        XCTAssertTrue(text.contains("不承诺"))
        XCTAssertTrue(text.contains("独立"))
        XCTAssertTrue(text.contains("清空所有持仓"))
        XCTAssertTrue(text.contains("设置 > 数据 > 京东会话"))
        XCTAssertTrue(text.contains("删除应用"))
    }

    func testSectionIdentifiersAreUniqueAndContentIsNotEmpty() {
        XCTAssertFalse(LegalContent.sections.isEmpty)
        XCTAssertEqual(
            Set(LegalContent.sections.map(\.id)).count,
            LegalContent.sections.count
        )

        for section in LegalContent.sections {
            XCTAssertFalse(section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(section.paragraphs.isEmpty && section.bullets.isEmpty)
        }
    }
}
