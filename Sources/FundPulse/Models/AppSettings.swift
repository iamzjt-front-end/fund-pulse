import Foundation

struct AppSettings: Codable, Equatable {
    static let currentSchemaVersion = 7
    static let defaultMainPanelHeight = 640
    static let minMainPanelHeight = 560
    static let maxMainPanelHeight = 900
    static let mainPanelHeightSliderStep = 10
    static let defaultOperationReminderTimeMinutes = 14 * 60 + 30
    static let defaultThresholdReminderInterval: FundThresholdReminderInterval = .thirtyMinutes

    var settingsSchemaVersion: Int? = Self.currentSchemaVersion
    var menuBarDisplayMode: MenuBarDisplayMode = .color
    var autoRefreshInterval: AutoRefreshInterval = .tenSeconds
    var mainPanelHeight: Int = Self.defaultMainPanelHeight
    var operationReminderEnabled: Bool = true
    var operationReminderTimeMinutes: Int = Self.defaultOperationReminderTimeMinutes
    var thresholdReminderInterval: FundThresholdReminderInterval = Self.defaultThresholdReminderInterval
    var appearanceMode: AppAppearanceMode = .system

    init(
        settingsSchemaVersion: Int? = Self.currentSchemaVersion,
        menuBarDisplayMode: MenuBarDisplayMode = .color,
        autoRefreshInterval: AutoRefreshInterval = .tenSeconds,
        mainPanelHeight: Int = Self.defaultMainPanelHeight,
        operationReminderEnabled: Bool = true,
        operationReminderTimeMinutes: Int = Self.defaultOperationReminderTimeMinutes,
        thresholdReminderInterval: FundThresholdReminderInterval = Self.defaultThresholdReminderInterval,
        appearanceMode: AppAppearanceMode = .system
    ) {
        self.settingsSchemaVersion = settingsSchemaVersion
        self.menuBarDisplayMode = menuBarDisplayMode
        self.autoRefreshInterval = autoRefreshInterval
        self.mainPanelHeight = Self.clampedMainPanelHeight(mainPanelHeight)
        self.operationReminderEnabled = operationReminderEnabled
        self.operationReminderTimeMinutes = Self.clampedReminderTimeMinutes(operationReminderTimeMinutes)
        self.thresholdReminderInterval = thresholdReminderInterval
        self.appearanceMode = appearanceMode
    }

    enum CodingKeys: String, CodingKey {
        case settingsSchemaVersion
        case menuBarDisplayMode
        case autoRefreshInterval
        case mainPanelHeight
        case operationReminderEnabled
        case operationReminderTimeMinutes
        case thresholdReminderInterval
        case appearanceMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settingsSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion)
        menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .color
        autoRefreshInterval = try container.decodeIfPresent(AutoRefreshInterval.self, forKey: .autoRefreshInterval) ?? .tenSeconds
        let decodedMainPanelHeight = try container.decodeIfPresent(Int.self, forKey: .mainPanelHeight)
            ?? Self.defaultMainPanelHeight
        mainPanelHeight = Self.clampedMainPanelHeight(decodedMainPanelHeight)
        operationReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .operationReminderEnabled) ?? true
        let decodedReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .operationReminderTimeMinutes)
            ?? Self.defaultOperationReminderTimeMinutes
        operationReminderTimeMinutes = Self.clampedReminderTimeMinutes(decodedReminderMinutes)
        thresholdReminderInterval = try container.decodeIfPresent(
            FundThresholdReminderInterval.self,
            forKey: .thresholdReminderInterval
        ) ?? Self.defaultThresholdReminderInterval
        appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system
    }

    static func clampedMainPanelHeight(_ height: Int) -> Int {
        min(max(height, minMainPanelHeight), maxMainPanelHeight)
    }

    static func clampedReminderTimeMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 23 * 60 + 59)
    }

    var operationReminderTimeText: String {
        let hours = operationReminderTimeMinutes / 60
        let minutes = operationReminderTimeMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "display"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }
}

enum FundThresholdReminderInterval: String, Codable, CaseIterable, Identifiable, Equatable {
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case oneDay = "1d"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes:
            15 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        case .twoHours:
            2 * 60 * 60
        case .fourHours:
            4 * 60 * 60
        case .oneDay:
            24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .fifteenMinutes:
            "15分钟"
        case .thirtyMinutes:
            "30分钟"
        case .oneHour:
            "1小时"
        case .twoHours:
            "2小时"
        case .fourHours:
            "4小时"
        case .oneDay:
            "每天一次"
        }
    }

    var detail: String {
        let intervalText = self == .oneDay ? "24小时" : title
        return "同一只基金同一类提醒命中后，\(intervalText)内不再重复提醒。"
    }
}

enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case color
    case sign

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color:
            "红绿颜色"
        case .sign:
            "正负号"
        }
    }

    var detail: String {
        switch self {
        case .color:
            "上涨红色、下跌绿色，不显示正负号"
        case .sign:
            "显示正负号，文字使用系统默认颜色"
        }
    }
}

enum AutoRefreshInterval: String, Codable, CaseIterable, Identifiable, Equatable {
    case twoSeconds = "2s"
    case fiveSeconds = "5s"
    case tenSeconds = "10s"
    case thirtySeconds = "30s"
    case oneMinute = "1m"
    case threeMinutes = "3m"
    case fiveMinutes = "5m"

    var id: String { rawValue }

    var sliderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func interval(atSliderIndex index: Int) -> AutoRefreshInterval {
        let clampedIndex = min(max(index, 0), allCases.count - 1)
        return allCases[clampedIndex]
    }

    var seconds: TimeInterval {
        switch self {
        case .twoSeconds:
            2
        case .fiveSeconds:
            5
        case .tenSeconds:
            10
        case .thirtySeconds:
            30
        case .oneMinute:
            60
        case .threeMinutes:
            180
        case .fiveMinutes:
            300
        }
    }

    var title: String {
        switch self {
        case .twoSeconds:
            "2秒"
        case .fiveSeconds:
            "5秒"
        case .tenSeconds:
            "10秒"
        case .thirtySeconds:
            "30秒"
        case .oneMinute:
            "1分"
        case .threeMinutes:
            "3分"
        case .fiveMinutes:
            "5分"
        }
    }

    var detail: String {
        "后台每 \(title) 自动刷新基金数据，并同步更新菜单栏收益。"
    }
}

enum QuoteSource: String, Codable, CaseIterable, Identifiable, Equatable {
    case fundBabyAuto
    case eastmoneyFundGZ
    case tencentOfficial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fundBabyAuto:
            "养基宝组合源"
        case .eastmoneyFundGZ:
            "东方财富实时估值"
        case .tencentOfficial:
            "腾讯官方净值"
        }
    }

    var detail: String {
        switch self {
        case .fundBabyAuto:
            "fundgz.1234567.com.cn + qt.gtimg.cn + fundf10.eastmoney.com，跟养基宝同一套组合接口"
        case .eastmoneyFundGZ:
            "fundgz.1234567.com.cn + fundf10.eastmoney.com，官方净值用于累计收益"
        case .tencentOfficial:
            "qt.gtimg.cn/q=jj{基金代码}，只返回官方净值"
        }
    }
}
