import Foundation
import XCTest
@testable import FundPulse

final class AppExternalLinksTests: XCTestCase {
    func testFeedbackTargetsAreExact() {
        XCTAssertEqual(
            AppExternalLinks.bugReportURL.absoluteString,
            "https://github.com/iamzjt-front-end/fund-pulse/issues/new?template=issue_template_bug.md"
        )
        XCTAssertEqual(
            AppExternalLinks.featureRequestURL.absoluteString,
            "https://github.com/iamzjt-front-end/fund-pulse/issues/new?template=issue_template_feature.md"
        )
    }

    func testRemovedEmailContactDoesNotLeaveAMailtoInterface() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FundPulse/Models/AppExternalLinks.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("contactEmail"))
        XCTAssertFalse(source.contains("feedbackMailURL"))
        XCTAssertFalse(source.contains("mailto"))
    }

    func testFailedExternalOpenCopiesFallbackAndReturnsVisibleMessage() {
        var openedURL: URL?
        var copiedText: String?

        let outcome = AppExternalLinkAction.perform(
            url: AppExternalLinks.bugReportURL,
            fallbackText: AppExternalLinks.bugReportURL.absoluteString,
            failureMessage: "无法打开浏览器，链接已复制。",
            open: { url in
                openedURL = url
                return false
            },
            copy: { copiedText = $0 }
        )

        XCTAssertEqual(openedURL, AppExternalLinks.bugReportURL)
        XCTAssertEqual(copiedText, AppExternalLinks.bugReportURL.absoluteString)
        XCTAssertEqual(outcome, .copied(message: "无法打开浏览器，链接已复制。"))
    }

    func testSuccessfulExternalOpenDoesNotTouchClipboard() {
        var copiedText: String?

        let outcome = AppExternalLinkAction.perform(
            url: AppExternalLinks.featureRequestURL,
            fallbackText: AppExternalLinks.featureRequestURL.absoluteString,
            failureMessage: "无法打开浏览器，链接已复制。",
            open: { _ in true },
            copy: { copiedText = $0 }
        )

        XCTAssertNil(copiedText)
        XCTAssertEqual(outcome, .opened)
    }
}
