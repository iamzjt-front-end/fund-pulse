import Foundation
import Observation

@Observable
@MainActor
final class AppSettingsStore {
    enum LoadOrigin: Equatable {
        case createdNew
        case loadedExisting
        case recoveredInvalid
    }

    private(set) var settings: AppSettings = AppSettings()
    private(set) var dataDirectory: URL
    private(set) var loadOrigin: LoadOrigin = .createdNew

    init(dataDirectory: URL = AppDataPaths.sharedDataDirectory) {
        self.dataDirectory = dataDirectory
        load()
    }

    func load() {
        do {
            let url = settingsFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadOrigin = .createdNew
                settings = AppSettings()
                try save()
                return
            }
            loadOrigin = .loadedExisting
            let data = try Data(contentsOf: url)
            var decodedSettings = try JSONDecoder().decode(AppSettings.self, from: data)
            if decodedSettings.settingsSchemaVersion != AppSettings.currentSchemaVersion {
                decodedSettings.settingsSchemaVersion = AppSettings.currentSchemaVersion
                settings = decodedSettings
                try save()
            } else {
                settings = decodedSettings
            }
        } catch {
            loadOrigin = .recoveredInvalid
            settings = AppSettings()
        }
    }

    func completeOnboarding(version: Int = AppSettings.currentOnboardingVersion) throws {
        settings.completedOnboardingVersion = version
        try save()
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        settings.menuBarDisplayMode = mode
        try? save()
    }

    func setMenuBarContentMode(_ mode: MenuBarContentMode) {
        settings.menuBarContentMode = mode
        try? save()
    }

    func setAutoRefreshInterval(_ interval: AutoRefreshInterval) {
        settings.autoRefreshInterval = AppSettings.validMarketOpenAutoRefreshInterval(interval)
        try? save()
    }

    func setMarketClosedAutoRefreshInterval(_ interval: AutoRefreshInterval) {
        settings.marketClosedAutoRefreshInterval = AppSettings.validMarketClosedAutoRefreshInterval(interval)
        try? save()
    }

    func setMainPanelHeight(_ height: Int) {
        settings.mainPanelHeight = AppSettings.clampedMainPanelHeight(height)
        try? save()
    }

    func setOperationReminderEnabled(_ isEnabled: Bool) {
        settings.operationReminderEnabled = isEnabled
        try? save()
    }

    func setOperationReminderTimeMinutes(_ minutes: Int) {
        settings.operationReminderTimeMinutes = AppSettings.clampedReminderTimeMinutes(minutes)
        try? save()
    }

    func setThresholdReminderInterval(_ interval: FundThresholdReminderInterval) {
        settings.thresholdReminderInterval = interval
        try? save()
    }

    func setDailyGrowthReminderEnabled(_ isEnabled: Bool) {
        settings.dailyGrowthReminderEnabled = isEnabled
        try? save()
    }

    func setDailyGrowthRiseTiers(_ tiers: [FundGrowthReminderTier]) {
        settings.dailyGrowthRiseTiers = AppSettings.normalizedGrowthReminderTiers(tiers)
        try? save()
    }

    func setDailyGrowthFallTiers(_ tiers: [FundGrowthReminderTier]) {
        settings.dailyGrowthFallTiers = AppSettings.normalizedGrowthReminderTiers(tiers)
        try? save()
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        settings.appearanceMode = mode
        try? save()
    }

    func setShowsMarketIndexes(_ isShown: Bool) {
        settings.showsMarketIndexes = isShown
        try? save()
    }

    func setDefaultMarketIndexID(_ id: MarketIndexID) {
        settings.defaultMarketIndexID = id
        try? save()
    }

    func setBetaFeaturesEnabled(_ isEnabled: Bool) {
        settings.betaFeaturesEnabled = isEnabled
        try? save()
    }

    var settingsFileURL: URL {
        dataDirectory.appending(path: "settings.json")
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL, options: .atomic)
    }
}
