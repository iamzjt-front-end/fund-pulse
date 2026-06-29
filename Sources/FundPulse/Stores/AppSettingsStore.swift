import Foundation
import Observation

@Observable
@MainActor
final class AppSettingsStore {
    private(set) var settings: AppSettings = AppSettings()
    private(set) var dataDirectory: URL

    init(dataDirectory: URL = AppDataPaths.sharedDataDirectory) {
        self.dataDirectory = dataDirectory
        load()
    }

    func load() {
        do {
            let url = settingsFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                settings = AppSettings()
                try save()
                return
            }
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
            settings = AppSettings()
        }
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
