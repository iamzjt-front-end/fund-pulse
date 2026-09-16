import XCTest
import AppKit
@testable import FundPulse

extension FundPulseCoreTests {
    func testVersionComparatorHandlesTagsAndPatchVersions() {
        XCTAssertTrue(VersionComparator.isVersion("0.0.13", newerThan: "0.0.12"))
        XCTAssertTrue(VersionComparator.isVersion("v0.1.0", newerThan: "0.0.99"))
        XCTAssertFalse(VersionComparator.isVersion("v0.0.12", newerThan: "0.0.12"))
        XCTAssertFalse(VersionComparator.isVersion("0.0.11", newerThan: "0.0.12"))
    }

    func testAppUpdateMenuItemPresentationShowsIdleCheckAction() {
        let presentation = AppUpdateMenuItemPresentation(status: .idle, downloadProgress: 0)

        XCTAssertEqual(presentation.title, "检查更新")
        XCTAssertEqual(presentation.action, .checkForUpdates)
        XCTAssertTrue(presentation.isEnabled)
        XCTAssertNil(presentation.toolTip)
        XCTAssertFalse(presentation.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationShowsUpToDateAsDisabledLatestStatus() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = AppUpdateMenuItemPresentation(status: .upToDate(date), downloadProgress: 0)

        XCTAssertEqual(presentation.title, "已是最新版本")
        XCTAssertNil(presentation.action)
        XCTAssertFalse(presentation.isEnabled)
        XCTAssertNotNil(presentation.toolTip)
        XCTAssertFalse(presentation.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationShowsAvailableVersionAsOpenUpdateAction() throws {
        let info = try appUpdateInfo(version: "1.0.30")
        let presentation = AppUpdateMenuItemPresentation(status: .available(info), downloadProgress: 0)

        XCTAssertEqual(presentation.title, "检测到新版本")
        XCTAssertEqual(presentation.action, .openUpdate)
        XCTAssertTrue(presentation.isEnabled)
        XCTAssertEqual(presentation.toolTip, "v1.0.30 · 点击下载")
        XCTAssertFalse(presentation.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationKeepsTransientAndFailedStates() throws {
        let info = try appUpdateInfo(version: "1.0.30")
        let downloading = AppUpdateMenuItemPresentation(status: .downloading(info), downloadProgress: 0.42)
        let checking = AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 2)
        let failed = AppUpdateMenuItemPresentation(status: .failed("网络异常"), downloadProgress: 0)

        XCTAssertEqual(downloading.title, "正在下载 v1.0.30 · 42%")
        XCTAssertNil(downloading.action)
        XCTAssertFalse(downloading.isEnabled)
        XCTAssertTrue(downloading.isActiveStatus)
        XCTAssertEqual(checking.title, "正在检查更新...")
        XCTAssertNil(checking.action)
        XCTAssertFalse(checking.isEnabled)
        XCTAssertTrue(checking.isActiveStatus)
        XCTAssertEqual(failed.title, "重新检查更新")
        XCTAssertEqual(failed.action, .checkForUpdates)
        XCTAssertEqual(failed.toolTip, "网络异常")
        XCTAssertFalse(failed.isActiveStatus)
    }

    func testAppUpdateMenuItemPresentationAnimatesCheckingEllipsis() {
        XCTAssertEqual(
            AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 0).title,
            "正在检查更新."
        )
        XCTAssertEqual(
            AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 1).title,
            "正在检查更新.."
        )
        XCTAssertEqual(
            AppUpdateMenuItemPresentation(status: .checking, downloadProgress: 0, activityFrame: 2).title,
            "正在检查更新..."
        )
    }

    func testAppUpdateStatusContextMenuCheckPolicyPreservesActiveUpdateFlows() throws {
        let info = try appUpdateInfo(version: "1.0.30")
        let package = AppUpdatePackage(
            localURL: try XCTUnwrap(URL(string: "file:///tmp/fund-pulse.zip")),
            stagedAppURL: try XCTUnwrap(URL(string: "file:///tmp/fund-pulse.app")),
            downloadedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(AppUpdateStatus.idle.shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.upToDate(Date()).shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.available(info).shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.failed("网络异常").shouldCheckWhenOpeningContextMenu)
        XCTAssertTrue(AppUpdateStatus.checking.shouldCheckWhenOpeningContextMenu)
        XCTAssertFalse(AppUpdateStatus.downloading(info).shouldCheckWhenOpeningContextMenu)
        XCTAssertFalse(AppUpdateStatus.downloaded(info, package).shouldCheckWhenOpeningContextMenu)
        XCTAssertFalse(AppUpdateStatus.installing(info).shouldCheckWhenOpeningContextMenu)
    }

    @MainActor
    func testAppUpdateStoreStartAndFinishCheckCanApplyExternalCompletion() {
        let store = AppUpdateStore(service: appUpdateServiceWithMockResponses([:]))
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let request = store.startCheck(currentVersion: "1.0.29", mode: .interactive)

        XCTAssertEqual(store.status, .checking)
        XCTAssertEqual(request?.currentVersion, "1.0.29")
        XCTAssertEqual(request?.mode, .interactive)

        guard let request else {
            return XCTFail("Expected update check request")
        }
        store.finishCheck(request, completion: .success(.upToDate(checkedAt)))

        XCTAssertEqual(store.status, .upToDate(checkedAt))
        XCTAssertNotNil(store.lastCheckedAt)
    }

    @MainActor
    func testAppUpdateStoreExternalCompletionIgnoresStaleGeneration() throws {
        let store = AppUpdateStore(service: appUpdateServiceWithMockResponses([:]))
        let olderRequest = try XCTUnwrap(store.startCheck(currentVersion: "1.0.29", mode: .background))
        let newerRequest = try XCTUnwrap(store.startCheck(currentVersion: "1.0.29", mode: .interactive))
        let staleInfo = try appUpdateInfo(version: "1.0.30")
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.finishCheck(olderRequest, completion: .success(.available(staleInfo)))

        XCTAssertEqual(store.status, .checking)

        store.finishCheck(newerRequest, completion: .success(.upToDate(checkedAt)))

        XCTAssertEqual(store.status, .upToDate(checkedAt))
    }

    func testAppUpdateServiceInteractiveCheckReportsUpToDateFromGitHubAPI() async throws {
        let service = appUpdateServiceWithMockResponses([
            Self.githubLatestReleaseAPIEndpoint(): Self.githubReleaseResponse(version: "1.0.29")
        ])

        let status = try await service.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .upToDate = status else {
            return XCTFail("Expected GitHub API response to report up-to-date, got \(status)")
        }
    }

    func testAppUpdateServiceInteractiveCheckReportsAvailableVersionFromGitHubAPI() async throws {
        let service = appUpdateServiceWithMockResponses([
            Self.githubLatestReleaseAPIEndpoint(): Self.githubReleaseResponse(version: "1.0.30")
        ])

        let status = try await service.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .available(let info) = status else {
            return XCTFail("Expected GitHub API response to report available version, got \(status)")
        }
        XCTAssertEqual(info.version, "1.0.30")
        XCTAssertEqual(info.downloadURL?.absoluteString, Self.githubZipDownloadURL(version: "1.0.30"))
    }

    func testAppUpdateServiceInteractiveCheckFallsBackToMacReleaseFeedWhenAPIFails() async throws {
        let service = appUpdateServiceWithMockResponses(
            [
                Self.githubLatestReleaseWebEndpoint(): "",
                Self.githubMacReleaseFeedEndpoint(version: "1.0.30"): Self.macReleaseFeedResponse(version: "1.0.30")
            ],
            finalURLs: [
                Self.githubLatestReleaseWebEndpoint(): Self.githubReleaseTagURL(version: "1.0.30")
            ]
        )

        let status = try await service.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .available(let info) = status else {
            return XCTFail("Expected interactive check to fallback to mac release feed, got \(status)")
        }
        XCTAssertEqual(info.version, "1.0.30")
        XCTAssertEqual(info.downloadURL?.absoluteString, Self.githubZipDownloadURL(version: "1.0.30"))
    }

    func testAppUpdateServiceInteractiveCheckUsesHardTimeout() async {
        MockURLProtocol.responseStore.set([
            Self.githubLatestReleaseAPIEndpoint(): Data(Self.githubReleaseResponse(version: "1.0.29").utf8)
        ])
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 300_000_000)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            interactiveAPIRequestTimeout: 0.05
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.check(currentVersion: "1.0.29", mode: .interactive)
        } errorHandler: { error in
            XCTAssertEqual(error.localizedDescription, "检查更新超时，请稍后重试")
        }
    }

    @MainActor
    func testAppUpdateStoreInteractiveCheckSupersedesBackgroundChecking() async throws {
        let service = appUpdateServiceWithMockResponses([
            Self.githubLatestReleaseAPIEndpoint(): Self.githubReleaseResponse(version: "1.0.30")
        ])
        MockURLProtocol.responseStore.setResponseDelay(nanoseconds: 300_000_000)
        let store = AppUpdateStore(service: service)

        let backgroundTask = Task {
            await store.check(currentVersion: "1.0.29", mode: .background)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.status, .checking)

        MockURLProtocol.responseStore.set([
            Self.githubLatestReleaseAPIEndpoint(): Data(Self.githubReleaseResponse(version: "1.0.29").utf8)
        ])
        await store.check(currentVersion: "1.0.29", mode: .interactive)

        guard case .upToDate = store.status else {
            return XCTFail("Expected interactive check to supersede background checking, got \(store.status)")
        }

        await backgroundTask.value
        guard case .upToDate = store.status else {
            return XCTFail("Expected stale background result to be ignored, got \(store.status)")
        }
    }

    func testAppUpdateServiceBackgroundCheckFallsBackToMacReleaseFeedWhenAPIFails() async throws {
        let service = appUpdateServiceWithMockResponses(
            [
                Self.githubLatestReleaseWebEndpoint(): "",
                Self.githubMacReleaseFeedEndpoint(version: "1.0.29"): Self.macReleaseFeedResponse(version: "1.0.29")
            ],
            finalURLs: [
                Self.githubLatestReleaseWebEndpoint(): Self.githubReleaseTagURL(version: "1.0.29")
            ]
        )

        let status = try await service.check(currentVersion: "1.0.29", mode: .background)

        guard case .upToDate = status else {
            return XCTFail("Expected background check to fallback to mac release feed, got \(status)")
        }
    }
}
