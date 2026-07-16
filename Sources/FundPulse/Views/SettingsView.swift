import AppKit
import SwiftUI
@preconcurrency import UserNotifications

private struct FocuslessSwitch: NSViewRepresentable {
    @Binding var isOn: Bool

    func makeNSView(context: Context) -> NoFocusSwitch {
        let control = NoFocusSwitch()
        control.target = context.coordinator
        control.action = #selector(Coordinator.valueChanged(_:))
        control.state = isOn ? .on : .off
        return control
    }

    func updateNSView(_ control: NoFocusSwitch, context: Context) {
        context.coordinator.isOn = $isOn
        control.state = isOn ? .on : .off
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    @MainActor
    final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
        }

        @MainActor
        @objc func valueChanged(_ sender: NSSwitch) {
            isOn.wrappedValue = sender.state == .on
        }
    }
}

private final class NoFocusSwitch: NSSwitch {
    override var acceptsFirstResponder: Bool { false }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case display
    case refreshAndReminders
    case data
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display:
            "显示"
        case .refreshAndReminders:
            "提醒"
        case .data:
            "数据"
        case .about:
            "关于"
        }
    }
}

struct SettingsSectionSession: Equatable {
    private(set) var selectedSection: SettingsSection

    init(selectedSection: SettingsSection = .display) {
        self.selectedSection = selectedSection
    }

    mutating func select(_ section: SettingsSection) {
        selectedSection = section
    }
}

struct SettingsView: View {
    let store: PortfolioStore
    let settingsStore: AppSettingsStore
    let updateStore: AppUpdateStore
    let appVersion: String
    let onSettingsChanged: (() -> Void)?
    let onRefresh: (() async -> Void)?
    let onCheckUpdate: (() async -> Void)?
    let onOpenJDFinanceSync: (() -> Void)?
    let onOpenPrivacyDisclaimer: (() -> Void)?
    let onOpenOnboarding: (() -> Void)?
    let onSectionChanged: ((SettingsSection) -> Void)?
    let onClose: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: SettingsSection
    @State private var selectedAutoRefreshInterval: AutoRefreshInterval
    @State private var selectedMarketClosedAutoRefreshInterval: AutoRefreshInterval
    @State private var operationReminderTimeText: String
    @State private var operationReminderDraftHour: Int
    @State private var operationReminderDraftMinute: Int
    @State private var isOperationReminderTimeSelectorPresented = false
    @State private var isTestingReminder = false
    @State private var testReminderStatusMessage: String?
    @State private var canOpenNotificationSettings = false
    @State private var displayedAppearanceMode: AppAppearanceMode
    @State private var displayedMenuBarContentMode: MenuBarContentMode
    @State private var displayedMenuBarDisplayMode: MenuBarDisplayMode
    @State private var isClearHoldingsConfirmationPresented = false
    @State private var clearHoldingsStatusMessage: String?
    @State private var isClearingJDFinanceSession = false
    @State private var jdFinanceSessionStatusMessage: String?
    @Namespace private var appearanceModeSelectionNamespace
    @Namespace private var menuBarContentModeSelectionNamespace
    @Namespace private var menuBarDisplayModeSelectionNamespace

    init(
        store: PortfolioStore,
        settingsStore: AppSettingsStore,
        updateStore: AppUpdateStore,
        appVersion: String,
        onSettingsChanged: (() -> Void)?,
        onRefresh: (() async -> Void)?,
        onCheckUpdate: (() async -> Void)?,
        onOpenJDFinanceSync: (() -> Void)? = nil,
        onOpenPrivacyDisclaimer: (() -> Void)? = nil,
        onOpenOnboarding: (() -> Void)? = nil,
        initialSection: SettingsSection = .display,
        onSectionChanged: ((SettingsSection) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.updateStore = updateStore
        self.appVersion = appVersion
        self.onSettingsChanged = onSettingsChanged
        self.onRefresh = onRefresh
        self.onCheckUpdate = onCheckUpdate
        self.onOpenJDFinanceSync = onOpenJDFinanceSync
        self.onOpenPrivacyDisclaimer = onOpenPrivacyDisclaimer
        self.onOpenOnboarding = onOpenOnboarding
        self.onSectionChanged = onSectionChanged
        self.onClose = onClose
        _selectedSection = State(initialValue: initialSection)
        _selectedAutoRefreshInterval = State(initialValue: settingsStore.settings.autoRefreshInterval)
        _selectedMarketClosedAutoRefreshInterval = State(
            initialValue: settingsStore.settings.marketClosedAutoRefreshInterval
        )
        _operationReminderTimeText = State(initialValue: settingsStore.settings.operationReminderTimeText)
        _operationReminderDraftHour = State(initialValue: settingsStore.settings.operationReminderTimeMinutes / 60)
        _operationReminderDraftMinute = State(initialValue: settingsStore.settings.operationReminderTimeMinutes % 60)
        _displayedAppearanceMode = State(initialValue: settingsStore.settings.appearanceMode)
        _displayedMenuBarContentMode = State(initialValue: settingsStore.settings.menuBarContentMode)
        _displayedMenuBarDisplayMode = State(initialValue: settingsStore.settings.menuBarDisplayMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .layoutPriority(1)

            settingsSectionPicker
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 7)

            Divider()
                .opacity(0.45)

            ScrollView {
                selectedSettingsContent
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .id(selectedSection)
            .scrollIndicators(.hidden)

            Divider()
                .opacity(0.45)

            settingsFooter
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(
            width: PopoverLayout.settingsWidth,
            height: PopoverLayout.settingsSize.height,
            alignment: .top
        )
        .background(PanelDesign.panelBackground)
        .onAppear {
            selectedAutoRefreshInterval = settingsStore.settings.autoRefreshInterval
            selectedMarketClosedAutoRefreshInterval = settingsStore.settings.marketClosedAutoRefreshInterval
            displayedAppearanceMode = settingsStore.settings.appearanceMode
            displayedMenuBarContentMode = settingsStore.settings.menuBarContentMode
            displayedMenuBarDisplayMode = settingsStore.settings.menuBarDisplayMode
            syncOperationReminderTimeText()
        }
        .onChange(of: settingsStore.settings.appearanceMode) { _, mode in
            displayedAppearanceMode = mode
        }
        .onChange(of: settingsStore.settings.menuBarContentMode) { _, mode in
            displayedMenuBarContentMode = mode
        }
        .onChange(of: settingsStore.settings.menuBarDisplayMode) { _, mode in
            displayedMenuBarDisplayMode = mode
        }
        .onChange(of: settingsStore.settings.autoRefreshInterval) { _, interval in
            selectedAutoRefreshInterval = interval
        }
        .onChange(of: settingsStore.settings.marketClosedAutoRefreshInterval) { _, interval in
            selectedMarketClosedAutoRefreshInterval = interval
        }
        .onChange(of: settingsStore.settings.operationReminderTimeMinutes) { _, _ in
            if !isOperationReminderTimeSelectorPresented {
                syncOperationReminderTimeText()
            }
        }
        .onChange(of: selectedSection) { _, section in
            onSectionChanged?(section)
        }
        .alert("清空所有持仓", isPresented: $isClearHoldingsConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAllHoldings()
            }
        } message: {
            Text("会删除全部基金、待确认操作、交易记录、组合收益历史和当前收益汇总。此操作无法撤销。")
        }
    }

    private var header: some View {
        PanelHeader(
            systemImage: "gearshape",
            title: "设置",
            subtitle: "v\(appVersion)",
            tint: Color(nsColor: .systemGray),
            onClose: { onClose?() }
        )
    }

    private var settingsSectionPicker: some View {
        PanelSegmentedPicker(
            values: SettingsSection.allCases,
            selection: $selectedSection,
            title: \SettingsSection.title
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置分类")
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSection {
        case .display:
            displaySettingsContent
        case .refreshAndReminders:
            refreshAndReminderSettingsContent
        case .data:
            dataSettingsContent
        case .about:
            aboutSettingsContent
        }
    }

    private var displaySettingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "外观") {
                appearanceModePicker
            }

            PanelSection(title: "菜单栏") {
                VStack(alignment: .leading, spacing: 8) {
                    menuBarContentModeRow
                    menuBarDisplayModeRow
                }
            }

            PanelSection(title: "主弹窗") {
                mainPanelSettingsSection
            }
        }
    }

    private var refreshAndReminderSettingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "自动刷新") {
                autoRefreshSettingsSection
            }

            PanelSection(title: "每日操作提醒") {
                operationReminderSettingsSection
            }

            PanelSection(title: "涨跌幅提醒") {
                dailyGrowthReminderSection
            }

            PanelSection(title: "通知测试") {
                notificationTestSection
            }
        }
    }

    private var dataSettingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "实验功能") {
                betaFeaturesSection
            }

            PanelSection(title: "京东会话") {
                jdFinanceSessionSection
            }

            PanelSection(title: "本地数据") {
                clearHoldingsSection
            }
        }
    }

    private var settingsFooter: some View {
        plainTextButton("退出 Fund Pulse", systemImage: "power", role: .destructive) {
            NSApp.terminate(nil)
        }
    }

    private var aboutSettingsContent: some View {
        PanelSection(title: "关于与隐私") {
            aboutAndPrivacySection
        }
    }

    private var operationReminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开启每日操作提醒")
                        .font(.system(size: 12, weight: .semibold))
                    Text("在设定时间发送系统通知，提醒检查估值并决定是否加仓或减仓。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                FocuslessSwitch(isOn: operationReminderEnabledBinding)
                    .frame(width: 54, height: 30)
            }

            HStack {
                Text("提醒时间")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                operationReminderTimeInput
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
            .opacity(settingsStore.settings.operationReminderEnabled ? 1 : 0.58)
        }
    }

    private var notificationTestSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("测试系统通知")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("只验证当前通知权限，不代表某只基金提醒已命中。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                testReminderButton
                    .frame(width: 108)
            }

            if let testReminderStatusMessage {
                Text(testReminderStatusMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(canOpenNotificationSettings ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if canOpenNotificationSettings {
                Button {
                    openNotificationSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("打开通知设置")
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PanelDesign.accent)
                .focusable(false)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var autoRefreshSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            autoRefreshIntervalControl(
                title: "开市间隔",
                selectedInterval: selectedAutoRefreshInterval,
                binding: autoRefreshIntervalSliderBinding,
                intervals: AutoRefreshInterval.marketOpenIntervals,
                detail: "开市时每 \(selectedAutoRefreshInterval.title) 刷新基金数据。"
            )

            Divider()
                .overlay(.secondary.opacity(0.14))

            autoRefreshIntervalControl(
                title: "休市间隔",
                selectedInterval: selectedMarketClosedAutoRefreshInterval,
                binding: marketClosedAutoRefreshIntervalSliderBinding,
                intervals: AutoRefreshInterval.marketClosedIntervals,
                detail: "午休、盘前、盘后、周末和节假日每 \(selectedMarketClosedAutoRefreshInterval.title) 刷新。"
            )
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var mainPanelSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("显示大盘指数")
                        .font(.system(size: 11, weight: .semibold))
                    Text("在主弹窗底部展示一行指数行情，可展开查看更多。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                FocuslessSwitch(isOn: marketIndexesShownBinding)
                    .frame(width: 54, height: 30)
            }

            if settingsStore.settings.showsMarketIndexes {
                Divider()
                    .overlay(.secondary.opacity(0.14))

                HStack {
                    Text("默认显示的指数")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    defaultMarketIndexPicker
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var isUpdateBusy: Bool {
        switch updateStore.status {
        case .checking, .downloading, .installing:
            return true
        case .idle, .available, .downloaded, .upToDate, .failed:
            return false
        }
    }

    private var betaFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("启用 Beta 功能")
                        .font(.system(size: 11, weight: .semibold))
                    Text("显示仍在验证中的功能入口。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                FocuslessSwitch(isOn: betaFeaturesEnabledBinding)
                    .frame(width: 54, height: 30)
            }

            if settingsStore.settings.betaFeaturesEnabled {
                Divider()
                    .overlay(.secondary.opacity(0.14))

                VStack(alignment: .leading, spacing: 7) {
                    Text("京东金融同步")
                        .font(.system(size: 11, weight: .semibold))
                    Text("从京东金融读取持仓并生成本地同步预览。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        onOpenJDFinanceSync?()
                    } label: {
                        PanelButtonLabel(
                            title: "同步京东",
                            systemImage: "arrow.triangle.2.circlepath",
                            style: .primary
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(onOpenJDFinanceSync == nil)
                    .help("打开京东金融同步")
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
        .animation(.easeInOut(duration: 0.16), value: settingsStore.settings.betaFeaturesEnabled)
    }

    private var clearHoldingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("清空所有持仓")
                        .font(.system(size: 11, weight: .semibold))
                    Text("删除本地基金列表、待确认操作、交易记录和组合收益历史，适合彻底重新开始。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }

            if let clearHoldingsStatusMessage {
                Text(clearHoldingsStatusMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                clearHoldingsStatusMessage = nil
                isClearHoldingsConfirmationPresented = true
            } label: {
                PanelButtonLabel(
                    title: "清空所有持仓",
                    systemImage: "trash",
                    style: .destructive
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!canClearHoldings)
            .help(canClearHoldings ? "清空所有本地持仓数据" : "当前没有可清空的持仓数据")
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var jdFinanceSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("清除这台 Mac 上的京东网页登录状态。不会删除本地持仓、交易记录或历史收益。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let jdFinanceSessionStatusMessage {
                Text(jdFinanceSessionStatusMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: clearJDFinanceSession) {
                PanelButtonLabel(
                    title: isClearingJDFinanceSession ? "正在清除..." : "清除京东登录",
                    systemImage: "person.crop.circle.badge.xmark",
                    style: .secondary,
                    isEnabled: !isClearingJDFinanceSession
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(isClearingJDFinanceSession)
            .help("清除本机京东网页登录会话")
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var aboutAndPrivacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onOpenPrivacyDisclaimer?()
            } label: {
                PanelButtonLabel(
                    title: "隐私与免责声明",
                    systemImage: "hand.raised",
                    style: .secondary
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(onOpenPrivacyDisclaimer == nil)

            Button {
                onOpenOnboarding?()
            } label: {
                PanelButtonLabel(
                    title: "重新查看使用引导",
                    systemImage: "sparkles.rectangle.stack",
                    style: .secondary
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(onOpenOnboarding == nil)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var canClearHoldings: Bool {
        !store.snapshot.funds.isEmpty
            || store.snapshot.pendingTrades?.isEmpty == false
            || store.snapshot.pendingConversions?.isEmpty == false
            || store.snapshot.tradeRecords?.isEmpty == false
            || store.snapshot.syncedAccountTotal != nil
            || !store.performanceStore.snapshot.days.isEmpty
    }

    private func autoRefreshIntervalControl(
        title: String,
        selectedInterval: AutoRefreshInterval,
        binding: Binding<Double>,
        intervals: [AutoRefreshInterval],
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedInterval.title)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(PanelDesign.border(cornerRadius: 7))
            }

            Slider(
                value: binding,
                in: 0...Double(max(intervals.count - 1, 0)),
                step: 1
            )
            .controlSize(.small)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var operationReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.operationReminderEnabled },
            set: { isEnabled in
                settingsStore.setOperationReminderEnabled(isEnabled)
                onSettingsChanged?()
            }
        )
    }

    private var dailyGrowthReminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开启涨跌幅提醒")
                        .font(.system(size: 12, weight: .semibold))
                    Text("按统一档位监控全部基金，涨幅和跌幅可分别选择。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                FocuslessSwitch(isOn: dailyGrowthReminderEnabledBinding)
                    .frame(width: 54, height: 30)
            }

            growthTierPicker(
                title: "涨幅档位",
                systemImage: "arrow.up.right",
                tiers: settingsStore.settings.dailyGrowthRiseTiers,
                isRise: true
            )
            growthTierPicker(
                title: "跌幅档位",
                systemImage: "arrow.down.right",
                tiers: settingsStore.settings.dailyGrowthFallTiers,
                isRise: false
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("当日去重")
                    .font(.system(size: 11, weight: .semibold))
                Text("达到条件后立即提醒；当天已经提醒过的同一基金、同一方向、同一档位，不会再重复弹出。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        }
    }

    private var dailyGrowthReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.dailyGrowthReminderEnabled },
            set: { isEnabled in
                settingsStore.setDailyGrowthReminderEnabled(isEnabled)
                onSettingsChanged?()
            }
        )
    }

    private func growthTierPicker(
        title: String,
        systemImage: String,
        tiers: [FundGrowthReminderTier],
        isRise: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(isRise ? Color.red : Color.green)

            HStack(spacing: 5) {
                ForEach(FundGrowthReminderTier.allCases) { tier in
                    growthTierButton(tier, isSelected: tiers.contains(tier), isRise: isRise)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
        .opacity(settingsStore.settings.dailyGrowthReminderEnabled ? 1 : 0.58)
    }

    private func growthTierButton(
        _ tier: FundGrowthReminderTier,
        isSelected: Bool,
        isRise: Bool
    ) -> some View {
        let accent = isRise ? Color.red : Color.green
        return Button {
            toggleDailyGrowthTier(tier, isRise: isRise)
        } label: {
            Text(tier.title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? accent : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    isSelected ? accent.opacity(colorScheme == .dark ? 0.18 : 0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? accent.opacity(0.34) : Color.clear, lineWidth: 0.8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!settingsStore.settings.dailyGrowthReminderEnabled)
    }

    private func toggleDailyGrowthTier(_ tier: FundGrowthReminderTier, isRise: Bool) {
        let current = isRise
            ? settingsStore.settings.dailyGrowthRiseTiers
            : settingsStore.settings.dailyGrowthFallTiers
        let updated: [FundGrowthReminderTier]
        if current.contains(tier) {
            updated = current.filter { $0 != tier }
        } else {
            updated = current + [tier]
        }

        if isRise {
            settingsStore.setDailyGrowthRiseTiers(updated)
        } else {
            settingsStore.setDailyGrowthFallTiers(updated)
        }
        onSettingsChanged?()
    }

    private var betaFeaturesEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.betaFeaturesEnabled },
            set: { isEnabled in
                settingsStore.setBetaFeaturesEnabled(isEnabled)
                onSettingsChanged?()
            }
        )
    }

    private var autoRefreshIntervalSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(
                    AutoRefreshInterval.marketOpenIntervals.firstIndex(of: selectedAutoRefreshInterval) ?? 0
                )
            },
            set: { index in
                let interval = AutoRefreshInterval.interval(
                    atSliderIndex: Int(index.rounded()),
                    in: AutoRefreshInterval.marketOpenIntervals
                )
                guard interval != selectedAutoRefreshInterval else { return }
                selectedAutoRefreshInterval = interval
                settingsStore.setAutoRefreshInterval(interval)
                onSettingsChanged?()
            }
        )
    }

    private var marketClosedAutoRefreshIntervalSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(
                    AutoRefreshInterval.marketClosedIntervals.firstIndex(
                        of: selectedMarketClosedAutoRefreshInterval
                    ) ?? 0
                )
            },
            set: { index in
                let interval = AutoRefreshInterval.interval(
                    atSliderIndex: Int(index.rounded()),
                    in: AutoRefreshInterval.marketClosedIntervals
                )
                guard interval != selectedMarketClosedAutoRefreshInterval else { return }
                selectedMarketClosedAutoRefreshInterval = interval
                settingsStore.setMarketClosedAutoRefreshInterval(interval)
                onSettingsChanged?()
            }
        )
    }

    private var marketIndexesShownBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.showsMarketIndexes },
            set: { isShown in
                settingsStore.setShowsMarketIndexes(isShown)
                onSettingsChanged?()
            }
        )
    }

    private var defaultMarketIndexPicker: some View {
        Menu {
            ForEach(MarketIndexID.allCases) { indexID in
                Button {
                    settingsStore.setDefaultMarketIndexID(indexID)
                    onSettingsChanged?()
                } label: {
                    HStack {
                        Text(indexID.title)
                        if indexID == settingsStore.settings.defaultMarketIndexID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(settingsStore.settings.defaultMarketIndexID.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 130, height: 26)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var operationReminderTimeInput: some View {
        Button {
            syncOperationReminderTimeDraft()
            isOperationReminderTimeSelectorPresented = true
        } label: {
            Text(settingsStore.settings.operationReminderTimeText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!settingsStore.settings.operationReminderEnabled)
            .padding(.horizontal, 8)
            .frame(width: 74, height: 26)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 7))
            .popover(isPresented: $isOperationReminderTimeSelectorPresented, arrowEdge: .top) {
                OperationReminderTimeSelectorPanel(
                    text: $operationReminderTimeText,
                    hour: $operationReminderDraftHour,
                    minute: $operationReminderDraftMinute,
                    onUseCurrentTime: setOperationReminderDraftToCurrentTime,
                    onConfirm: commitOperationReminderTimeText
                )
            }
    }

    private var menuBarContentModeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("显示内容")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            menuBarContentModePicker

            Text(settingsStore.settings.menuBarContentMode.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var menuBarContentModePicker: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarContentMode.allCases) { mode in
                let isSelected = mode == displayedMenuBarContentMode
                Button {
                    selectMenuBarContentMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: menuBarContentModeSystemImage(mode))
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(isSelected ? .primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PanelDesign.segmentSelectionBackground)
                                .matchedGeometryEffect(
                                    id: "menuBarContentModeSelection",
                                    in: menuBarContentModeSelectionNamespace
                                )
                                .shadow(color: Color.black.opacity(0.16), radius: 5, x: 0, y: 2)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(PanelDesign.segmentSelectionBorder, lineWidth: 0.8)
                                .matchedGeometryEffect(
                                    id: "menuBarContentModeSelectionBorder",
                                    in: menuBarContentModeSelectionNamespace
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(2)
        .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: displayedMenuBarContentMode)
    }

    private var menuBarDisplayModeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("涨跌颜色")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            menuBarDisplayModePicker

            Text(settingsStore.settings.menuBarDisplayMode.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var menuBarDisplayModePicker: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarDisplayMode.allCases) { mode in
                let isSelected = mode == displayedMenuBarDisplayMode
                Button {
                    selectMenuBarDisplayMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: menuBarDisplayModeSystemImage(mode))
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(isSelected ? .primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PanelDesign.segmentSelectionBackground)
                                .matchedGeometryEffect(
                                    id: "menuBarDisplayModeSelection",
                                    in: menuBarDisplayModeSelectionNamespace
                                )
                                .shadow(color: Color.black.opacity(0.16), radius: 5, x: 0, y: 2)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(PanelDesign.segmentSelectionBorder, lineWidth: 0.8)
                                .matchedGeometryEffect(
                                    id: "menuBarDisplayModeSelectionBorder",
                                    in: menuBarDisplayModeSelectionNamespace
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(2)
        .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: displayedMenuBarDisplayMode)
    }

    private var appearanceModePicker: some View {
        HStack(spacing: 4) {
            ForEach(AppAppearanceMode.allCases) { mode in
                let isSelected = mode == displayedAppearanceMode
                Button {
                    selectAppearanceMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(isSelected ? .primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PanelDesign.segmentSelectionBackground)
                                .matchedGeometryEffect(
                                    id: "appearanceModeSelection",
                                    in: appearanceModeSelectionNamespace
                                )
                                .shadow(color: Color.black.opacity(0.16), radius: 5, x: 0, y: 2)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(PanelDesign.segmentSelectionBorder, lineWidth: 0.8)
                                .matchedGeometryEffect(
                                    id: "appearanceModeSelectionBorder",
                                    in: appearanceModeSelectionNamespace
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(2)
        .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: displayedAppearanceMode)
    }

    private func selectAppearanceMode(_ mode: AppAppearanceMode) {
        guard mode != displayedAppearanceMode else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            displayedAppearanceMode = mode
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard displayedAppearanceMode == mode else { return }
            settingsStore.setAppearanceMode(mode)
            onSettingsChanged?()
        }
    }

    private func selectMenuBarContentMode(_ mode: MenuBarContentMode) {
        guard mode != displayedMenuBarContentMode else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            displayedMenuBarContentMode = mode
        }
        settingsStore.setMenuBarContentMode(mode)
        onSettingsChanged?()
    }

    private func selectMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        guard mode != displayedMenuBarDisplayMode else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            displayedMenuBarDisplayMode = mode
        }
        settingsStore.setMenuBarDisplayMode(mode)
        onSettingsChanged?()
    }

    private func menuBarContentModeSystemImage(_ mode: MenuBarContentMode) -> String {
        switch mode {
        case .amount:
            "yensign.circle"
        case .rate:
            "percent"
        case .both:
            "rectangle.split.2x1"
        case .hidden:
            "eye.slash"
        }
    }

    private func menuBarDisplayModeSystemImage(_ mode: MenuBarDisplayMode) -> String {
        switch mode {
        case .color:
            "paintpalette"
        case .sign:
            "circle"
        }
    }

    private var testReminderButton: some View {
        Button {
            testReminderPermission()
        } label: {
            PanelButtonLabel(
                title: isTestingReminder ? "检测中" : "测试",
                systemImage: isTestingReminder ? "hourglass" : "bell.badge",
                isEnabled: !isTestingReminder
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isTestingReminder)
    }

    private func setOperationReminderDraftToCurrentTime() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        operationReminderDraftHour = components.hour ?? 0
        operationReminderDraftMinute = components.minute ?? 0
        operationReminderTimeText = reminderTimeText(
            hour: operationReminderDraftHour,
            minute: operationReminderDraftMinute
        )
    }

    private func syncOperationReminderTimeDraft() {
        syncOperationReminderTimeText()
        operationReminderDraftHour = settingsStore.settings.operationReminderTimeMinutes / 60
        operationReminderDraftMinute = settingsStore.settings.operationReminderTimeMinutes % 60
    }

    private func commitOperationReminderTimeText() {
        guard let minutes = parsedReminderTimeMinutes(operationReminderTimeText) else {
            syncOperationReminderTimeText()
            isOperationReminderTimeSelectorPresented = false
            return
        }

        let previousMinutes = settingsStore.settings.operationReminderTimeMinutes
        settingsStore.setOperationReminderTimeMinutes(minutes)
        syncOperationReminderTimeText()

        if settingsStore.settings.operationReminderTimeMinutes != previousMinutes {
            onSettingsChanged?()
        }
        isOperationReminderTimeSelectorPresented = false
    }

    private func syncOperationReminderTimeText() {
        operationReminderTimeText = settingsStore.settings.operationReminderTimeText
    }

    private func testReminderPermission() {
        guard !isTestingReminder else { return }
        isTestingReminder = true
        canOpenNotificationSettings = false
        testReminderStatusMessage = "正在检测提醒权限..."

        Task {
            let result = await sendTestReminderNotification()
            await MainActor.run {
                testReminderStatusMessage = result.message
                canOpenNotificationSettings = result.canOpenNotificationSettings
                isTestingReminder = false
            }
        }
    }

    private func sendTestReminderNotification() async -> (message: String, canOpenNotificationSettings: Bool) {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    return ("未获得通知权限，无法发送测试提醒。", true)
                }
            } catch {
                return ("请求通知权限失败：\(error.localizedDescription)", true)
            }
        case .denied:
            return ("系统通知权限已关闭，请在 macOS 系统设置中允许 fund-pulse 通知。", true)
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return ("当前系统通知权限状态未知，请检查 macOS 通知设置。", true)
        }

        let refreshedSettings = await center.notificationSettings()
        if refreshedSettings.alertSetting == .disabled {
            return ("通知权限已允许，但横幅/提醒显示被关闭，请检查 fund-pulse 的通知样式。", true)
        }

        let content = UNMutableNotificationContent()
        content.title = "fund-pulse 测试提醒"
        content.body = "如果你看到这条通知，说明系统通知权限正常。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fund-pulse.test-reminder.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        do {
            try await center.add(request)
            return ("测试提醒已安排，1秒后弹出。若未看到横幅，请检查专注模式或通知样式。", false)
        } catch {
            return ("测试提醒发送失败：\(error.localizedDescription)", true)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateStore.status {
        case .idle:
            statusText("尚未检查更新")
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查更新")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        case .available(let info):
            VStack(alignment: .leading, spacing: 4) {
                Text("发现新版本 v\(info.version)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                if !info.releaseName.isEmpty {
                    Text(info.releaseName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 0.6)
            )
        case .downloading(let info):
            HStack(spacing: 8) {
                UpdateProgressRing(progress: updateStore.downloadProgress)
                    .frame(width: 22, height: 22)
                Text("正在下载 v\(info.version) · \(Int(updateStore.downloadProgress * 100))%")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        case .downloaded(let info, let package):
            VStack(alignment: .leading, spacing: 4) {
                Text("更新已下载")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text("v\(info.version) · \(package.downloadedAt.formatted(date: .omitted, time: .shortened)) · 点击“现在更新”后会自动重启")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.green.opacity(0.18), lineWidth: 0.6)
            )
        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在更新，完成后会自动重启")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        case .upToDate(let date):
            statusText("已是最新版本 · \(date.formatted(date: .omitted, time: .shortened))")
        case .failed(let reason):
            Text("检查失败：\(reason)")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 0.6)
                )
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func dataSourceRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.primary)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private func plainTextButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            PanelButtonLabel(
                title: title,
                systemImage: systemImage,
                style: role == .destructive ? .destructive : .secondary
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func checkUpdate() {
        Task {
            await onCheckUpdate?()
        }
    }

    private func clearAllHoldings() {
        do {
            try store.clearAllHoldings()
            clearHoldingsStatusMessage = "已清空所有本地持仓数据。"
            onSettingsChanged?()
            Task {
                await onRefresh?()
            }
        } catch {
            clearHoldingsStatusMessage = "清空失败：\(error.localizedDescription)"
        }
    }

    private func clearJDFinanceSession() {
        guard !isClearingJDFinanceSession else { return }
        isClearingJDFinanceSession = true
        jdFinanceSessionStatusMessage = nil
        Task { @MainActor in
            await JDFinanceWebSession.clearSession()
            isClearingJDFinanceSession = false
            jdFinanceSessionStatusMessage = "已清除京东登录；本地持仓和收益记录未变。"
        }
    }
}

private struct OperationReminderTimeSelectorPanel: View {
    @Binding var text: String
    @Binding var hour: Int
    @Binding var minute: Int

    let onUseCurrentTime: () -> Void
    let onConfirm: () -> Void

    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .monospacedDigit()
                    .focused($isTextFocused)
                    .onSubmit {
                        syncDraftFromText()
                    }
                    .onChange(of: text) { _, newValue in
                        let normalized = normalizedTimeInput(newValue)
                        if normalized != newValue {
                            text = normalized
                            return
                        }
                        syncDraftFromText()
                    }

                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.72))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .systemBlue), lineWidth: 1.4)
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            HStack(spacing: 0) {
                timeColumn(values: Array(0...23), selection: $hour)
                Divider().opacity(0.4)
                timeColumn(values: Array(0...59), selection: $minute)
            }
            .frame(height: 178)
            .padding(.horizontal, 10)
            .onChange(of: hour) { _, _ in
                syncTextFromDraft()
            }
            .onChange(of: minute) { _, _ in
                syncTextFromDraft()
            }

            Divider().opacity(0.45)

            HStack {
                Button("此刻") {
                    onUseCurrentTime()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue))

                Spacer()

                Button {
                    syncDraftFromText()
                    onConfirm()
                } label: {
                    Text("确定")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 30)
                        .background(Color(nsColor: .systemBlue), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
        }
        .frame(width: 160)
        .background(PanelDesign.panelBackground)
        .onAppear {
            isTextFocused = true
        }
    }

    private func timeColumn(values: [Int], selection: Binding<Int>) -> some View {
        ZStack {
            SnappingTimeColumn(values: values, selection: selection)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .systemBlue).opacity(0.12))
                .frame(height: 28)
                .allowsHitTesting(false)
        }
    }

    private func syncTextFromDraft() {
        text = reminderTimeText(hour: hour, minute: minute)
    }

    private func syncDraftFromText() {
        guard let minutes = parsedReminderTimeMinutes(text) else { return }
        hour = minutes / 60
        minute = minutes % 60
        text = reminderTimeText(hour: hour, minute: minute)
    }
}

private func normalizedTimeInput(_ value: String) -> String {
    let normalized = value
        .replacingOccurrences(of: "：", with: ":")
        .filter { $0.isNumber || $0 == ":" }
    return String(normalized.prefix(normalized.contains(":") ? 5 : 4))
}

private func reminderTimeText(hour: Int, minute: Int) -> String {
    String(format: "%02d:%02d", hour, minute)
}

private func parsedReminderTimeMinutes(_ value: String) -> Int? {
    let text = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "：", with: ":")

    let hour: Int
    let minute: Int

    if text.contains(":") {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let parsedHour = Int(parts[0]),
              let parsedMinute = Int(parts[1])
        else { return nil }
        hour = parsedHour
        minute = parsedMinute
    } else {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        if digits.count <= 2 {
            guard let parsedHour = Int(digits) else { return nil }
            hour = parsedHour
            minute = 0
        } else {
            let splitIndex = digits.index(digits.endIndex, offsetBy: -2)
            guard let parsedHour = Int(digits[..<splitIndex]),
                  let parsedMinute = Int(digits[splitIndex...])
            else { return nil }
            hour = parsedHour
            minute = parsedMinute
        }
    }

    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    return hour * 60 + minute
}

private struct SnappingTimeColumn: NSViewRepresentable {
    let values: [Int]
    @Binding var selection: Int

    @MainActor
    func makeNSView(context: Context) -> SnappingTimeColumnScrollView {
        let scrollView = SnappingTimeColumnScrollView()
        scrollView.coordinator = context.coordinator
        context.coordinator.configure(scrollView: scrollView, values: values)
        context.coordinator.applySelection(selection, animated: false)
        return scrollView
    }

    @MainActor
    func updateNSView(_ scrollView: SnappingTimeColumnScrollView, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.configure(scrollView: scrollView, values: values)
        context.coordinator.updateButtonStyles(selected: selection)
        if !context.coordinator.isUserInteracting {
            context.coordinator.applySelection(selection, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>
        var isUserInteracting = false

        private weak var scrollView: SnappingTimeColumnScrollView?
        private var buttons: [Int: NSButton] = [:]
        private var values: [Int] = []
        private var snapWorkItem: DispatchWorkItem?
        private var isProgrammaticScroll = false

        private let rowHeight: CGFloat = 28
        private let rowStride: CGFloat = 30
        private let visibleHeight: CGFloat = 178

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        @MainActor
        func configure(scrollView: SnappingTimeColumnScrollView, values: [Int]) {
            guard self.scrollView !== scrollView || self.values != values else { return }

            self.scrollView = scrollView
            self.values = values
            self.buttons = [:]

            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            scrollView.contentView.postsBoundsChangedNotifications = true

            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            let topPadding = (visibleHeight - rowHeight) / 2
            let contentHeight = topPadding * 2 + CGFloat(values.count) * rowStride
            let documentView = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: 70, height: contentHeight))

            for (index, value) in values.enumerated() {
                let button = NSButton(title: "", target: self, action: #selector(valueButtonClicked(_:)))
                button.identifier = NSUserInterfaceItemIdentifier("\(value)")
                button.isBordered = false
                button.bezelStyle = .regularSquare
                button.setButtonType(.momentaryChange)
                button.focusRingType = .none
                button.frame = NSRect(
                    x: 0,
                    y: topPadding + CGFloat(index) * rowStride,
                    width: documentView.bounds.width,
                    height: rowHeight
                )
                button.autoresizingMask = [.width]
                documentView.addSubview(button)
                buttons[value] = button
            }

            scrollView.documentView = documentView
            updateButtonStyles(selected: selection.wrappedValue)
        }

        @MainActor
        func applySelection(_ selected: Int, animated: Bool) {
            guard let scrollView,
                  let index = values.firstIndex(of: selected)
            else { return }

            let targetY = CGFloat(index) * rowStride
            let currentY = scrollView.contentView.bounds.origin.y
            guard abs(currentY - targetY) > 0.5 else {
                updateButtonStyles(selected: selected)
                return
            }

            isProgrammaticScroll = true
            let targetOrigin = NSPoint(x: 0, y: targetY)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
                }
                isProgrammaticScroll = false
            } else {
                scrollView.contentView.setBoundsOrigin(targetOrigin)
                isProgrammaticScroll = false
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
            updateButtonStyles(selected: selected)
        }

        @MainActor
        func scheduleSnap() {
            isUserInteracting = true
            snapWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.snapToNearestValue()
                }
            }
            snapWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: workItem)
        }

        @MainActor
        @objc private func boundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll else { return }
            updateSelectionFromScrollPosition()
        }

        @MainActor
        @objc private func valueButtonClicked(_ sender: NSButton) {
            guard let rawValue = sender.identifier?.rawValue,
                  let value = Int(rawValue)
            else { return }

            selection.wrappedValue = value
            applySelection(value, animated: true)
        }

        @MainActor
        private func updateSelectionFromScrollPosition() {
            guard let scrollView,
                  let value = nearestValue(for: scrollView.contentView.bounds.origin.y)
            else { return }

            if selection.wrappedValue != value {
                selection.wrappedValue = value
            }
            updateButtonStyles(selected: value)
        }

        @MainActor
        private func snapToNearestValue() {
            guard let scrollView,
                  let value = nearestValue(for: scrollView.contentView.bounds.origin.y)
            else {
                isUserInteracting = false
                return
            }

            selection.wrappedValue = value
            applySelection(value, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                Task { @MainActor in
                    self?.isUserInteracting = false
                }
            }
        }

        private func nearestValue(for offsetY: CGFloat) -> Int? {
            guard !values.isEmpty else { return nil }
            let rawIndex = Int(round(offsetY / rowStride))
            let clampedIndex = min(max(rawIndex, 0), values.count - 1)
            return values[clampedIndex]
        }

        @MainActor
        func updateButtonStyles(selected: Int) {
            for (value, button) in buttons {
                let isSelected = value == selected
                let color: NSColor = isSelected ? .labelColor : .secondaryLabelColor
                let font = NSFont.monospacedDigitSystemFont(
                    ofSize: 15,
                    weight: isSelected ? .semibold : .medium
                )
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                button.attributedTitle = NSAttributedString(
                    string: String(format: "%02d", value),
                    attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                )
            }
        }
    }
}

@MainActor
private final class SnappingTimeColumnScrollView: NSScrollView {
    weak var coordinator: SnappingTimeColumn.Coordinator?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        coordinator?.scheduleSnap()
    }
}

@MainActor
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
