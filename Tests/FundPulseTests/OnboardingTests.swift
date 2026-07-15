import XCTest
import SwiftUI
@testable import FundPulse

final class OnboardingTests: XCTestCase {
    @MainActor
    func testChildPanelRootUsesWindowManagedAutoresizing() {
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let container = PanelCardContainerView(contentView: hostingView)

        XCTAssertTrue(container.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(hostingView.sizingOptions, [])
    }

    func testStepStateSupportsDirectSelectionAndBoundedNavigation() {
        var state = OnboardingStepState(initialStep: 1)

        XCTAssertEqual(state.step, 1)

        state.select(0)
        XCTAssertEqual(state.step, 0)

        state.retreat()
        XCTAssertEqual(state.step, 0)

        state.select(2)
        XCTAssertEqual(state.step, 2)

        state.advance()
        XCTAssertEqual(state.step, 2)

        state.select(1)
        XCTAssertEqual(state.step, 1)
    }

    func testStepStateClampsRestoredAndSelectedSteps() {
        XCTAssertEqual(OnboardingStepState(initialStep: -1).step, 0)
        XCTAssertEqual(OnboardingStepState(initialStep: 99).step, 2)

        var state = OnboardingStepState(initialStep: 1)
        state.select(-1)
        XCTAssertEqual(state.step, 0)
        state.select(99)
        XCTAssertEqual(state.step, 2)
    }

    func testDefaultChildPanelsUseStandardHeightAndSpecialPanelsKeepOverrides() {
        XCTAssertEqual(PopoverLayout.standardChildPanelHeight, 660)

        let standardSizes = [
            PopoverLayout.settingsSize,
            PopoverLayout.fundDetailSize,
            PopoverLayout.tradeEditorSize,
            PopoverLayout.onboardingSize,
            PopoverLayout.privacyDisclaimerSize,
            PopoverLayout.sampleExperienceSize,
            PopoverLayout.portfolioPerformanceSize,
            PopoverLayout.jdFinancePerformanceSyncSize,
            PopoverLayout.portfolioBreakdownSize,
            PopoverLayout.todayIncomeRankingSize
        ]
        XCTAssertTrue(
            standardSizes.allSatisfy { $0.height == PopoverLayout.standardChildPanelHeight }
        )

        XCTAssertEqual(PopoverLayout.editorSize.height, 600)
        XCTAssertEqual(PopoverLayout.tradeRecordsSize.height, 520)
        XCTAssertEqual(PopoverLayout.fundDailyIncomeSize.height, 600)
    }

    func testDefaultChildPanelsUseStandardWidthAndSpecialPanelsKeepOverrides() {
        XCTAssertEqual(PopoverLayout.standardChildPanelWidth, 360)
        XCTAssertEqual(PopoverLayout.settingsWidth, PopoverLayout.standardChildPanelWidth)
        XCTAssertEqual(PopoverLayout.editorWidth, PopoverLayout.standardChildPanelWidth)

        let standardSizes = [
            PopoverLayout.settingsSize,
            PopoverLayout.editorSize,
            PopoverLayout.tradeEditorSize,
            PopoverLayout.fundDetailSize,
            PopoverLayout.tradeRecordsSize,
            PopoverLayout.portfolioBreakdownSize,
            PopoverLayout.todayIncomeRankingSize,
            PopoverLayout.fundDailyIncomeSize,
            PopoverLayout.onboardingSize,
            PopoverLayout.privacyDisclaimerSize
        ]
        XCTAssertTrue(
            standardSizes.allSatisfy { $0.width == PopoverLayout.standardChildPanelWidth }
        )

        XCTAssertEqual(PopoverLayout.sampleExperienceSize.width, 430)
        XCTAssertEqual(PopoverLayout.portfolioPerformanceSize.width, 430)
        XCTAssertEqual(PopoverLayout.jdFinancePerformanceSyncSize.width, 430)
        XCTAssertEqual(PopoverLayout.jdFinanceSyncSize.width, 430)
        XCTAssertEqual(PopoverLayout.jdFinanceNetworkProbeSize.width, 430)
        XCTAssertEqual(PopoverLayout.jdFinanceLoginSize.width, 1040)
    }

    @MainActor
    func testFreshSettingsAreMarkedCreatedNewAndAwaitOnboarding() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppSettingsStore(dataDirectory: directory)

        XCTAssertEqual(AppSettings.currentSchemaVersion, 13)
        XCTAssertEqual(AppSettings.currentOnboardingVersion, 1)
        XCTAssertEqual(store.loadOrigin, .createdNew)
        XCTAssertNil(store.settings.completedOnboardingVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.settingsFileURL.path))
    }

    @MainActor
    func testLegacySettingsWithoutOnboardingFieldMigrateAsAlreadyCompleted() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appending(path: "settings.json")
        let legacySettings = """
        {
          "settingsSchemaVersion": 12,
          "menuBarDisplayMode": "sign",
          "autoRefreshInterval": "30s"
        }
        """
        try Data(legacySettings.utf8).write(to: settingsURL, options: .atomic)

        let store = AppSettingsStore(dataDirectory: directory)

        XCTAssertEqual(store.loadOrigin, .loadedExisting)
        XCTAssertEqual(store.settings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        XCTAssertEqual(store.settings.completedOnboardingVersion, AppSettings.currentOnboardingVersion)
        XCTAssertEqual(store.settings.menuBarDisplayMode, .sign)

        let persisted = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: settingsURL))
        XCTAssertEqual(persisted.completedOnboardingVersion, AppSettings.currentOnboardingVersion)
    }

    @MainActor
    func testInvalidExistingSettingsAreRecoveredWithoutBecomingANewInstall() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appending(path: "settings.json"), options: .atomic)

        let store = AppSettingsStore(dataDirectory: directory)

        XCTAssertEqual(store.loadOrigin, .recoveredInvalid)
        XCTAssertFalse(
            OnboardingEligibility.shouldPresent(
                settings: store.settings,
                settingsLoadOrigin: store.loadOrigin,
                portfolioLoadState: .missingPlainData(hasLegacyStore: false)
            )
        )
    }

    @MainActor
    func testCompletingOnboardingPersistsCurrentVersion() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppSettingsStore(dataDirectory: directory)

        try store.completeOnboarding()

        XCTAssertEqual(store.settings.completedOnboardingVersion, AppSettings.currentOnboardingVersion)
        let reloaded = AppSettingsStore(dataDirectory: directory)
        XCTAssertEqual(reloaded.loadOrigin, .loadedExisting)
        XCTAssertEqual(reloaded.settings.completedOnboardingVersion, AppSettings.currentOnboardingVersion)
    }

    func testEligibilityPersistsUntilARealNewInstallCompletesOnboarding() {
        let pendingSettings = AppSettings(completedOnboardingVersion: nil)

        XCTAssertTrue(
            OnboardingEligibility.shouldPresent(
                settings: pendingSettings,
                settingsLoadOrigin: .createdNew,
                portfolioLoadState: .missingPlainData(hasLegacyStore: false)
            )
        )
        XCTAssertTrue(
            OnboardingEligibility.shouldPresent(
                settings: pendingSettings,
                settingsLoadOrigin: .loadedExisting,
                portfolioLoadState: .missingPlainData(hasLegacyStore: false)
            )
        )
        XCTAssertFalse(
            OnboardingEligibility.shouldPresent(
                settings: pendingSettings,
                settingsLoadOrigin: .createdNew,
                portfolioLoadState: .missingPlainData(hasLegacyStore: true)
            )
        )
        XCTAssertFalse(
            OnboardingEligibility.shouldPresent(
                settings: pendingSettings,
                settingsLoadOrigin: .createdNew,
                portfolioLoadState: .loaded
            )
        )

        let completedSettings = AppSettings(
            completedOnboardingVersion: AppSettings.currentOnboardingVersion
        )
        XCTAssertFalse(
            OnboardingEligibility.shouldPresent(
                settings: completedSettings,
                settingsLoadOrigin: .createdNew,
                portfolioLoadState: .missingPlainData(hasLegacyStore: false)
            )
        )
    }

    func testSampleExperienceIsDeterministicAndContainsOnlyFictionalData() throws {
        let now = try chinaDate("2026-07-15 12:00")

        let first = SampleExperienceFactory.make(now: now)
        let second = SampleExperienceFactory.make(now: now)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.portfolio.funds.count, 3)
        XCTAssertTrue(first.portfolio.funds.allSatisfy { $0.code.hasPrefix("DEMO") })
        XCTAssertTrue(first.portfolio.funds.allSatisfy { $0.name.hasPrefix("示例·") })
        XCTAssertGreaterThanOrEqual(first.dailyPerformance.count, 60)
        XCTAssertLessThanOrEqual(first.dailyPerformance.count, 70)
        XCTAssertEqual(first.dailyPerformance.last?.date, Calendar.fundPulseChina.startOfDay(for: now))
    }

    func testCreatingSampleExperienceDoesNotTouchDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        _ = SampleExperienceFactory.make(now: try chinaDate("2026-07-15 12:00"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-onboarding-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func chinaDate(_ text: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: text))
    }
}

private extension Calendar {
    static var fundPulseChina: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }
}
