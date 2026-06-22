import Foundation

struct AppSettings: Codable, Equatable {
    static let currentSchemaVersion = 5
    static let defaultMainPanelHeight = 640
    static let minMainPanelHeight = 560
    static let maxMainPanelHeight = 900
    static let mainPanelHeightSliderStep = 10
    static let defaultOperationReminderTimeMinutes = 14 * 60 + 30

    var settingsSchemaVersion: Int? = Self.currentSchemaVersion
    var menuBarDisplayMode: MenuBarDisplayMode = .color
    var autoRefreshInterval: AutoRefreshInterval = .tenSeconds
    var mainPanelHeight: Int = Self.defaultMainPanelHeight
    var operationReminderEnabled: Bool = true
    var operationReminderTimeMinutes: Int = Self.defaultOperationReminderTimeMinutes

    init(
        settingsSchemaVersion: Int? = Self.currentSchemaVersion,
        menuBarDisplayMode: MenuBarDisplayMode = .color,
        autoRefreshInterval: AutoRefreshInterval = .tenSeconds,
        mainPanelHeight: Int = Self.defaultMainPanelHeight,
        operationReminderEnabled: Bool = true,
        operationReminderTimeMinutes: Int = Self.defaultOperationReminderTimeMinutes
    ) {
        self.settingsSchemaVersion = settingsSchemaVersion
        self.menuBarDisplayMode = menuBarDisplayMode
        self.autoRefreshInterval = autoRefreshInterval
        self.mainPanelHeight = Self.clampedMainPanelHeight(mainPanelHeight)
        self.operationReminderEnabled = operationReminderEnabled
        self.operationReminderTimeMinutes = Self.clampedReminderTimeMinutes(operationReminderTimeMinutes)
    }

    enum CodingKeys: String, CodingKey {
        case settingsSchemaVersion
        case menuBarDisplayMode
        case autoRefreshInterval
        case mainPanelHeight
        case operationReminderEnabled
        case operationReminderTimeMinutes
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
    case tenSeconds = "10s"
    case thirtySeconds = "30s"
    case oneMinute = "1m"
    case threeMinutes = "3m"
    case fiveMinutes = "5m"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
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
            "fundgz.1234567.com.cn + fundf10.eastmoney.com，官方净值用于持有收益"
        case .tencentOfficial:
            "qt.gtimg.cn/q=jj{基金代码}，只返回官方净值"
        }
    }
}
