import Foundation

struct AppSettings: Codable, Equatable {
    static let currentSchemaVersion = 13
    static let currentOnboardingVersion = 1
    static let defaultMainPanelHeight = 640
    static let minMainPanelHeight = 560
    static let maxMainPanelHeight = 900
    static let defaultOperationReminderTimeMinutes = 14 * 60 + 30
    static let defaultThresholdReminderInterval: FundThresholdReminderInterval = .thirtyMinutes
    static let defaultDailyGrowthReminderEnabled = false
    static let defaultAutoRefreshInterval: AutoRefreshInterval = .fiveSeconds
    static let defaultMarketClosedAutoRefreshInterval: AutoRefreshInterval = .tenMinutes
    static let defaultMarketIndexIdentifier: MarketIndexID = .shanghaiComposite

    var settingsSchemaVersion: Int? = Self.currentSchemaVersion
    var menuBarDisplayMode: MenuBarDisplayMode = .color
    var menuBarContentMode: MenuBarContentMode = .amount
    var autoRefreshInterval: AutoRefreshInterval = Self.defaultAutoRefreshInterval
    var marketClosedAutoRefreshInterval: AutoRefreshInterval = Self.defaultMarketClosedAutoRefreshInterval
    var mainPanelHeight: Int = Self.defaultMainPanelHeight
    var operationReminderEnabled: Bool = true
    var operationReminderTimeMinutes: Int = Self.defaultOperationReminderTimeMinutes
    var thresholdReminderInterval: FundThresholdReminderInterval = Self.defaultThresholdReminderInterval
    var dailyGrowthReminderEnabled: Bool = Self.defaultDailyGrowthReminderEnabled
    var dailyGrowthRiseTiers: [FundGrowthReminderTier] = []
    var dailyGrowthFallTiers: [FundGrowthReminderTier] = []
    var appearanceMode: AppAppearanceMode = .system
    var showsMarketIndexes: Bool = true
    var defaultMarketIndexID: MarketIndexID = Self.defaultMarketIndexIdentifier
    var betaFeaturesEnabled: Bool = false
    var completedOnboardingVersion: Int? = nil

    init(
        settingsSchemaVersion: Int? = Self.currentSchemaVersion,
        menuBarDisplayMode: MenuBarDisplayMode = .color,
        menuBarContentMode: MenuBarContentMode = .amount,
        autoRefreshInterval: AutoRefreshInterval = Self.defaultAutoRefreshInterval,
        marketClosedAutoRefreshInterval: AutoRefreshInterval = Self.defaultMarketClosedAutoRefreshInterval,
        mainPanelHeight: Int = Self.defaultMainPanelHeight,
        operationReminderEnabled: Bool = true,
        operationReminderTimeMinutes: Int = Self.defaultOperationReminderTimeMinutes,
        thresholdReminderInterval: FundThresholdReminderInterval = Self.defaultThresholdReminderInterval,
        dailyGrowthReminderEnabled: Bool = Self.defaultDailyGrowthReminderEnabled,
        dailyGrowthRiseTiers: [FundGrowthReminderTier] = [],
        dailyGrowthFallTiers: [FundGrowthReminderTier] = [],
        appearanceMode: AppAppearanceMode = .system,
        showsMarketIndexes: Bool = true,
        defaultMarketIndexID: MarketIndexID = Self.defaultMarketIndexIdentifier,
        betaFeaturesEnabled: Bool = false,
        completedOnboardingVersion: Int? = nil
    ) {
        self.settingsSchemaVersion = settingsSchemaVersion
        self.menuBarDisplayMode = menuBarDisplayMode
        self.menuBarContentMode = menuBarContentMode
        self.autoRefreshInterval = Self.validMarketOpenAutoRefreshInterval(autoRefreshInterval)
        self.marketClosedAutoRefreshInterval = Self.validMarketClosedAutoRefreshInterval(marketClosedAutoRefreshInterval)
        self.mainPanelHeight = Self.clampedMainPanelHeight(mainPanelHeight)
        self.operationReminderEnabled = operationReminderEnabled
        self.operationReminderTimeMinutes = Self.clampedReminderTimeMinutes(operationReminderTimeMinutes)
        self.thresholdReminderInterval = thresholdReminderInterval
        self.dailyGrowthReminderEnabled = dailyGrowthReminderEnabled
        self.dailyGrowthRiseTiers = Self.normalizedGrowthReminderTiers(dailyGrowthRiseTiers)
        self.dailyGrowthFallTiers = Self.normalizedGrowthReminderTiers(dailyGrowthFallTiers)
        self.appearanceMode = appearanceMode
        self.showsMarketIndexes = showsMarketIndexes
        self.defaultMarketIndexID = defaultMarketIndexID
        self.betaFeaturesEnabled = betaFeaturesEnabled
        self.completedOnboardingVersion = completedOnboardingVersion
    }

    enum CodingKeys: String, CodingKey {
        case settingsSchemaVersion
        case menuBarDisplayMode
        case menuBarContentMode
        case autoRefreshInterval
        case marketClosedAutoRefreshInterval
        case mainPanelHeight
        case operationReminderEnabled
        case operationReminderTimeMinutes
        case thresholdReminderInterval
        case dailyGrowthReminderEnabled
        case dailyGrowthRiseTiers
        case dailyGrowthFallTiers
        case appearanceMode
        case showsMarketIndexes
        case defaultMarketIndexID
        case betaFeaturesEnabled
        case completedOnboardingVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion)
        settingsSchemaVersion = decodedSchemaVersion
        menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .color
        menuBarContentMode = try container.decodeIfPresent(MenuBarContentMode.self, forKey: .menuBarContentMode) ?? .amount
        let decodedAutoRefreshInterval = try container.decodeIfPresent(
            AutoRefreshInterval.self,
            forKey: .autoRefreshInterval
        ) ?? Self.defaultAutoRefreshInterval
        autoRefreshInterval = Self.validMarketOpenAutoRefreshInterval(decodedAutoRefreshInterval)
        let decodedMarketClosedAutoRefreshInterval = try container.decodeIfPresent(
            AutoRefreshInterval.self,
            forKey: .marketClosedAutoRefreshInterval
        ) ?? Self.defaultMarketClosedAutoRefreshInterval
        marketClosedAutoRefreshInterval = Self.validMarketClosedAutoRefreshInterval(
            decodedMarketClosedAutoRefreshInterval
        )
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
        dailyGrowthReminderEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .dailyGrowthReminderEnabled
        ) ?? Self.defaultDailyGrowthReminderEnabled
        let decodedRiseTierValues = try container.decodeIfPresent([Int].self, forKey: .dailyGrowthRiseTiers) ?? []
        dailyGrowthRiseTiers = Self.normalizedGrowthReminderTiers(
            decodedRiseTierValues.compactMap(FundGrowthReminderTier.init(rawValue:))
        )
        let decodedFallTierValues = try container.decodeIfPresent([Int].self, forKey: .dailyGrowthFallTiers) ?? []
        dailyGrowthFallTiers = Self.normalizedGrowthReminderTiers(
            decodedFallTierValues.compactMap(FundGrowthReminderTier.init(rawValue:))
        )
        appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system
        showsMarketIndexes = try container.decodeIfPresent(Bool.self, forKey: .showsMarketIndexes) ?? true
        let decodedMarketIndexID = try container.decodeIfPresent(String.self, forKey: .defaultMarketIndexID)
        defaultMarketIndexID = decodedMarketIndexID
            .flatMap(MarketIndexID.init(rawValue:))
            ?? Self.defaultMarketIndexIdentifier
        betaFeaturesEnabled = try container.decodeIfPresent(Bool.self, forKey: .betaFeaturesEnabled) ?? false
        if container.contains(.completedOnboardingVersion) {
            completedOnboardingVersion = try container.decodeIfPresent(
                Int.self,
                forKey: .completedOnboardingVersion
            )
        } else if (decodedSchemaVersion ?? 0) < Self.currentSchemaVersion {
            // Onboarding was introduced in schema 13. Existing installs must never
            // be mistaken for a new install merely because the field is absent.
            completedOnboardingVersion = Self.currentOnboardingVersion
        } else {
            completedOnboardingVersion = nil
        }
    }

    static func clampedMainPanelHeight(_ height: Int) -> Int {
        min(max(height, minMainPanelHeight), maxMainPanelHeight)
    }

    static func clampedReminderTimeMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 23 * 60 + 59)
    }

    static func normalizedGrowthReminderTiers(_ tiers: [FundGrowthReminderTier]) -> [FundGrowthReminderTier] {
        Array(Set(tiers)).sorted { $0.rawValue < $1.rawValue }
    }

    static func validMarketOpenAutoRefreshInterval(_ interval: AutoRefreshInterval) -> AutoRefreshInterval {
        AutoRefreshInterval.marketOpenIntervals.contains(interval) ? interval : defaultAutoRefreshInterval
    }

    static func validMarketClosedAutoRefreshInterval(_ interval: AutoRefreshInterval) -> AutoRefreshInterval {
        AutoRefreshInterval.marketClosedIntervals.contains(interval) ? interval : defaultMarketClosedAutoRefreshInterval
    }

    func effectiveAutoRefreshInterval(now: Date = .now) -> AutoRefreshInterval {
        effectiveAutoRefreshInterval(for: TradingCalendar.marketSessionState(now: now))
    }

    func effectiveAutoRefreshInterval(for state: MarketSessionState) -> AutoRefreshInterval {
        switch state {
        case .open:
            autoRefreshInterval
        case .middayBreak, .closed:
            marketClosedAutoRefreshInterval
        }
    }

    var operationReminderTimeText: String {
        let hours = operationReminderTimeMinutes / 60
        let minutes = operationReminderTimeMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

enum FundGrowthReminderTier: Int, Codable, CaseIterable, Identifiable, Equatable, Hashable {
    case two = 2
    case three = 3
    case five = 5
    case seven = 7
    case ten = 10

    var id: Int { rawValue }

    var value: Double { Double(rawValue) }

    var title: String {
        "\(rawValue)%"
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
            "红绿"
        case .sign:
            "单色"
        }
    }

    var detail: String {
        switch self {
        case .color:
            "未隐藏时文字按涨跌红/绿；隐藏金额时仅图标按涨跌红/绿。"
        case .sign:
            "未隐藏时文字使用系统颜色；隐藏金额时图标也使用系统单色。"
        }
    }

    var usesGrowthColor: Bool {
        self == .color
    }
}

enum MenuBarContentMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case amount
    case rate
    case both
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amount:
            "金额"
        case .rate:
            "百分比"
        case .both:
            "都显示"
        case .hidden:
            "都不显示"
        }
    }

    var detail: String {
        switch self {
        case .amount:
            "菜单栏只显示实时收益金额。"
        case .rate:
            "菜单栏只显示实时收益率。"
        case .both:
            "菜单栏显示金额和百分比，中间用竖线分隔。"
        case .hidden:
            "菜单栏只显示图标，不显示金额和百分比。"
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
    case tenMinutes = "10m"
    case thirtyMinutes = "30m"

    static let marketOpenIntervals: [AutoRefreshInterval] = [
        .twoSeconds,
        .fiveSeconds,
        .tenSeconds,
        .thirtySeconds,
        .oneMinute,
        .threeMinutes,
        .fiveMinutes
    ]

    static let marketClosedIntervals: [AutoRefreshInterval] = [
        .oneMinute,
        .threeMinutes,
        .fiveMinutes,
        .tenMinutes,
        .thirtyMinutes
    ]

    var id: String { rawValue }

    var sliderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func interval(atSliderIndex index: Int) -> AutoRefreshInterval {
        interval(atSliderIndex: index, in: allCases)
    }

    static func interval(atSliderIndex index: Int, in intervals: [AutoRefreshInterval]) -> AutoRefreshInterval {
        guard !intervals.isEmpty else { return .fiveSeconds }
        let clampedIndex = min(max(index, 0), allCases.count - 1)
        return intervals[min(clampedIndex, intervals.count - 1)]
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
        case .tenMinutes:
            600
        case .thirtyMinutes:
            1_800
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
        case .tenMinutes:
            "10分"
        case .thirtyMinutes:
            "30分"
        }
    }

    var detail: String {
        "每 \(title) 自动刷新基金数据，并同步更新菜单栏收益。"
    }
}
