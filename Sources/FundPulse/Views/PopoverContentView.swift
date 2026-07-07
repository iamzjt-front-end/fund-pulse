import AppKit
import SwiftUI

struct MainPanelWindowView: View {
    let store: PortfolioStore
    let settingsStore: AppSettingsStore
    let marketIndexStore: MarketIndexStore
    let updateStore: AppUpdateStore
    let uiState: PopoverUIState
    let mainPanelHeight: CGFloat
    let selectedFundCode: String?
    let onRefresh: (() async -> Void)?
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onOpenPortfolioBreakdown: () -> Void
    let onOpenTodayIncomeRanking: () -> Void
    let onOpenTodayRateRanking: () -> Void
    let onOpenHoldingIncomeRanking: () -> Void
    let onOpenHoldingRateRanking: () -> Void
    let onAddFund: () -> Void
    let onOpenFundDetail: (FundPosition) -> Void
    let onOpenTradeRecords: (FundPosition) -> Void
    let onOpenPendingActivity: (PendingTradeActivity) -> Void
    let onDeletePendingActivity: (PendingTradeActivity) async -> Void
    let onBuyFund: (FundPosition) -> Void
    let onSellFund: (FundPosition) -> Void
    let onEditFund: (FundPosition) -> Void
    let onDeleteFund: (FundPosition) async -> Void
    let onCheckUpdate: (() async -> Void)?
    let onOpenUpdate: (() -> Void)?

    var body: some View {
        let contentSize = mainPanelContentSize

        ZStack(alignment: .top) {
            PopoverChromeShape(arrowX: uiState.arrowX)
                .fill(popoverChromeFillColor)
                .overlay(
                    PopoverChromeShape(arrowX: uiState.arrowX)
                        .stroke(panelBorderColor, lineWidth: 0.5)
                )
            
            PopoverContentView(
                store: store,
                settingsStore: settingsStore,
                marketIndexStore: marketIndexStore,
                updateStore: updateStore,
                selectedFundCode: selectedFundCode,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
                onOpenPortfolioBreakdown: onOpenPortfolioBreakdown,
                onOpenTodayIncomeRanking: onOpenTodayIncomeRanking,
                onOpenTodayRateRanking: onOpenTodayRateRanking,
                onOpenHoldingIncomeRanking: onOpenHoldingIncomeRanking,
                onOpenHoldingRateRanking: onOpenHoldingRateRanking,
                onAddFund: onAddFund,
                onOpenFundDetail: onOpenFundDetail,
                onOpenTradeRecords: onOpenTradeRecords,
                onOpenPendingActivity: onOpenPendingActivity,
                onDeletePendingActivity: onDeletePendingActivity,
                onBuyFund: onBuyFund,
                onSellFund: onSellFund,
                onEditFund: onEditFund,
                onDeleteFund: onDeleteFund,
                onCheckUpdate: onCheckUpdate,
                onOpenUpdate: onOpenUpdate
            )
            .frame(width: contentSize.width, height: contentSize.height)
            .clipShape(RoundedRectangle(cornerRadius: PopoverLayout.cornerRadius, style: .continuous))
            .offset(y: PopoverLayout.arrowHeight)
        }
        .frame(
            width: contentSize.width,
            height: contentSize.height + PopoverLayout.arrowHeight,
            alignment: .top
        )
        .background(Color.clear)
    }

    private var mainPanelContentSize: NSSize {
        NSSize(
            width: PopoverLayout.mainWidth,
            height: PopoverLayout.clampedMainPanelHeight(mainPanelHeight)
        )
    }

    private var popoverChromeFillColor: Color {
        PanelDesign.panelChromeBackground
    }
}

private struct PopoverChromeShape: Shape {
    let arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = PopoverLayout.cornerRadius
        let panelY = PopoverLayout.arrowHeight
        let arrowHalf = PopoverLayout.arrowWidth / 2
        let x = min(max(arrowX, radius + arrowHalf), rect.width - radius - arrowHalf)

        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x + arrowHalf, y: panelY))
        path.addLine(to: CGPoint(x: rect.width - radius, y: panelY))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: panelY + radius), control: CGPoint(x: rect.width, y: panelY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height - radius), control: CGPoint(x: rect.minX, y: rect.height))
        path.addLine(to: CGPoint(x: rect.minX, y: panelY + radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: panelY), control: CGPoint(x: rect.minX, y: panelY))
        path.addLine(to: CGPoint(x: x - arrowHalf, y: panelY))
        path.closeSubpath()
        return path
    }
}

struct PopoverContentView: View {
    let store: PortfolioStore
    let settingsStore: AppSettingsStore
    let marketIndexStore: MarketIndexStore
    let updateStore: AppUpdateStore
    let selectedFundCode: String?
    let onRefresh: (() async -> Void)?
    let onOpenSettings: () -> Void
    let onOpenPortfolioBreakdown: () -> Void
    let onOpenTodayIncomeRanking: () -> Void
    let onOpenTodayRateRanking: () -> Void
    let onOpenHoldingIncomeRanking: () -> Void
    let onOpenHoldingRateRanking: () -> Void
    let onAddFund: () -> Void
    let onOpenFundDetail: (FundPosition) -> Void
    let onOpenTradeRecords: (FundPosition) -> Void
    let onOpenPendingActivity: (PendingTradeActivity) -> Void
    let onDeletePendingActivity: (PendingTradeActivity) async -> Void
    let onBuyFund: (FundPosition) -> Void
    let onSellFund: (FundPosition) -> Void
    let onEditFund: (FundPosition) -> Void
    let onDeleteFund: (FundPosition) async -> Void
    let onCheckUpdate: (() async -> Void)?
    let onOpenUpdate: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferenceKey.hideHeaderAmounts) private var hidesHeaderAmounts = false
    @State private var isRefreshing = false
    @State private var isRefreshStatusPulsing = false
    @State private var filter: FundListFilter = .holding
    @State private var sortMode: FundSortMode = .todayRate
    @State private var isSortMenuPresented = false
    @State private var isMarketIndexExpanded = false
    @State private var deletingPendingActivity: PendingTradeActivity?
    @Namespace private var filterSwitchNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)
            toolbar
                .zIndex(3)
            fundList
                .layoutPriority(1)
                .zIndex(0)
            if settingsStore.settings.showsMarketIndexes {
                marketIndexFooter
                    .zIndex(1)
            }
        }
        .background(panelSurfaceBackground)
        .alert("删除待确认记录", isPresented: deletePendingActivityConfirmationBinding, presenting: deletingPendingActivity) { activity in
            Button("取消", role: .cancel) {
                deletingPendingActivity = nil
            }
            Button("删除记录", role: .destructive) {
                Task {
                    await onDeletePendingActivity(activity)
                    deletingPendingActivity = nil
                }
            }
        } message: { activity in
            Text(deletePendingActivityConfirmationMessage(for: activity))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 6) {
                    refreshStatusIndicator
                    Text(refreshStatusText)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer()
                marketBadge
                privacyToggleButton
            }

            if let statusMessage {
                statusBanner(statusMessage)
            }

            if shouldShowAppUpdateRow {
                appUpdateRow
            }

            HStack(spacing: 6) {
                Button(action: onOpenPortfolioBreakdown) {
                    metricCard(
                        "总金额",
                        headerMoneyText(store.snapshot.totalAmount),
                        isTotal: true
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help("查看持仓占比")
                Button(action: onOpenHoldingIncomeRanking) {
                    metricCard(
                        "持有收益",
                        headerSignedMoneyText(store.snapshot.holdingIncome),
                        tone: headerMetricTone(store.snapshot.holdingIncome)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help("查看持有收益排行")

                Button(action: onOpenHoldingRateRanking) {
                    metricCard(
                        "持有收益率",
                        headerPercentText(store.snapshot.holdingIncomeRate),
                        tone: store.snapshot.holdingIncomeRate
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help("查看持有收益率排行")
            }

            if let pendingHeaderImpact {
                Button {
                    selectFilter(.pending)
                } label: {
                    pendingImpactBar(pendingHeaderImpact)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("查看待确认")
            }

            HStack(alignment: .bottom) {
                Button(action: onOpenTodayIncomeRanking) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("实时收益(元)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if allConfirmedFundsUpdated {
                                todayIncomeUpdatedTag
                            }
                            disclosureIndicator
                        }
                        todayIncomeAmount(store.snapshot.todayIncome, isMasked: hidesHeaderAmounts)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(headerMetricColor(store.snapshot.todayIncome))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("查看实时收益排行")

                Spacer()

                Button(action: onOpenTodayRateRanking) {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("实时收益率")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            disclosureIndicator
                        }
                        Text(headerPercentText(store.snapshot.todayIncomeRate))
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(toneColor(for: store.snapshot.todayIncomeRate))
                    }
                    .padding(.bottom, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("查看实时收益率排行")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(headerSurfaceBackground)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(nsColor: .separatorColor).opacity(0),
                    Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.22 : 0.18),
                    Color(nsColor: .separatorColor).opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 5) {
            filterSwitchControl

            Spacer(minLength: 4)

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isSortMenuPresented.toggle()
                }
            } label: {
                sortMenuLabel
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("排序")
            .layoutPriority(1)
            .overlay(alignment: .topLeading) {
                if isSortMenuPresented {
                    sortMenuContent
                        .offset(y: 31)
                        .zIndex(10)
                }
            }
            .zIndex(isSortMenuPresented ? 20 : 0)

            toolbarActionGroup
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(toolbarSurfaceBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(colorScheme == .dark ? 0.45 : 0.55)
        }
    }

    private var allConfirmedFundsUpdated: Bool {
        let confirmedFunds = store.snapshot.funds.filter { !$0.status.isPendingDisplay }
        return !confirmedFunds.isEmpty && confirmedFunds.allSatisfy(\.isUpdated)
    }

    private var todayIncomeUpdatedTag: some View {
        Text("已更新")
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.orange.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 0.6)
            )
    }

    private var shouldShowAppUpdateRow: Bool {
        switch updateStore.status {
        case .available, .downloading, .downloaded, .installing:
            return true
        case .idle, .checking, .upToDate, .failed:
            return false
        }
    }

    private var appUpdateRow: some View {
        HStack(alignment: .center, spacing: 10) {
            appUpdateRowIcon
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(appUpdateRowTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(appUpdateRowDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if case .downloading = updateStore.status {
                    ProgressView(value: updateStore.downloadProgress)
                        .controlSize(.small)
                        .tint(.orange)
                }
            }

            Spacer(minLength: 6)

            appUpdateRowTrailingControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appUpdateCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(appUpdateCardBorder)
        .overlay(appUpdateCardInnerHighlight)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.13 : 0.04), radius: 9, x: 0, y: 4)
    }

    @ViewBuilder
    private var appUpdateRowIcon: some View {
        switch updateStore.status {
        case .available:
            appUpdateIconShell(systemName: "arrow.down", color: appUpdateRowAccentColor)
        case .downloading:
            appUpdateIconShell(systemName: "arrow.down", color: appUpdateRowAccentColor)
        case .downloaded:
            appUpdateIconShell(systemName: "checkmark", color: appUpdateRowAccentColor)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .idle, .checking, .upToDate, .failed:
            EmptyView()
        }
    }

    private func appUpdateIconShell(systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
            Circle()
                .stroke(color.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 0.8)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var appUpdateRowTitle: String {
        switch updateStore.status {
        case .available(let info):
            return "发现新版本 v\(info.version)"
        case .downloading:
            return "正在下载更新"
        case .downloaded:
            return "更新已下载"
        case .installing:
            return "正在安装更新"
        case .idle, .checking, .upToDate, .failed:
            return ""
        }
    }

    private var appUpdateRowDetail: String {
        switch updateStore.status {
        case .available(let info):
            return "\(info.releaseName.isEmpty ? "fund-pulse" : info.releaseName) · 点击后先下载，下载完成后再安装。"
        case .downloading:
            return "\(Int(updateStore.downloadProgress * 100))% · 下载完成后会显示“现在更新”。"
        case .downloaded(let info, _):
            return "v\(info.version) 已准备好。现在更新会退出并重新打开 fund-pulse。"
        case .installing:
            return "fund-pulse 将自动退出并重新打开。"
        case .idle, .checking, .upToDate, .failed:
            return ""
        }
    }

    private var appUpdateRowButtonTitle: String? {
        switch updateStore.status {
        case .available:
            return "下载"
        case .downloaded:
            return "现在更新"
        case .idle, .checking, .downloading, .installing, .upToDate, .failed:
            return nil
        }
    }

    private var appUpdateRowButtonColor: Color {
        switch updateStore.status {
        case .downloaded:
            return .fundPulseGreen
        case .available, .idle, .checking, .downloading, .installing, .upToDate, .failed:
            return .orange
        }
    }

    private var appUpdateRowAccentColor: Color {
        appUpdateRowButtonColor
    }

    private var appUpdateCardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                appUpdateRowAccentColor.opacity(colorScheme == .dark ? 0.16 : 0.08),
                metricCardBaseBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var appUpdateCardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                appUpdateRowAccentColor.opacity(colorScheme == .dark ? 0.28 : 0.22),
                lineWidth: 0.9
            )
    }

    private var appUpdateCardInnerHighlight: some View {
        RoundedRectangle(cornerRadius: 9.4, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.34), lineWidth: 0.55)
            .padding(0.7)
            .blendMode(.plusLighter)
    }

    @ViewBuilder
    private var appUpdateRowTrailingControl: some View {
        switch updateStore.status {
        case .available, .downloaded:
            if let title = appUpdateRowButtonTitle {
                appUpdateRowActionButton(title: title, color: appUpdateRowButtonColor) {
                    onOpenUpdate?()
                }
            }
        case .downloading:
            Text("\(Int(updateStore.downloadProgress * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .frame(width: 36, alignment: .trailing)
                .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在下载更新")
            .accessibilityValue("\(Int(updateStore.downloadProgress * 100))%")
            .help(updateStore.badgeTitle ?? "正在下载更新")
        case .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
                .help(updateStore.badgeTitle ?? "正在安装更新")
        case .idle, .checking, .upToDate, .failed:
            EmptyView()
        }
    }

    private func appUpdateRowActionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(color.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(color.opacity(colorScheme == .dark ? 0.34 : 0.24), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(title)
    }

    private var toolbarActionGroup: some View {
        HStack(spacing: 6) {
            toolbarIconButton("plus", "新增基金", tone: PanelDesign.accent, action: onAddFund)
            toolbarRefreshControl
            toolbarIconButton("gearshape", "设置", action: onOpenSettings)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var toolbarRefreshControl: some View {
        if case .failed(let reason) = store.loadState {
            Button {
                refresh()
            } label: {
                toolbarIconLabel("exclamationmark.triangle.fill", tone: .orange)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(isManualRefreshFeedbackVisible)
            .help("基金数据刷新失败：\(reason)。点击重试")
        } else {
            toolbarIconButton("arrow.clockwise", isManualRefreshFeedbackVisible ? "刷新中" : "刷新") {
                refresh()
            }
            .disabled(isManualRefreshFeedbackVisible)
        }
    }

    private func toolbarIconButton(
        _ systemName: String,
        _ help: String,
        tone: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarIconLabel(systemName, tone: tone)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }

    private func toolbarIconLabel(_ systemName: String, tone: Color? = nil) -> some View {
        let foreground = tone ?? toolbarIconForeground

        return Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(tone == nil ? .hierarchical : .monochrome)
            .foregroundStyle(foreground)
            .frame(width: toolbarIconButtonSize, height: toolbarIconButtonSize)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: toolbarIconButtonCornerRadius, style: .continuous)
                        .fill(toolbarControlBackground)

                    if let tone {
                        RoundedRectangle(cornerRadius: toolbarIconButtonCornerRadius, style: .continuous)
                            .fill(tone.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    }
                }
            }
            .overlay(toolbarControlBorder(cornerRadius: toolbarIconButtonCornerRadius, tone: tone))
            .overlay(toolbarControlInnerHighlight(cornerRadius: toolbarIconButtonCornerRadius - 0.6))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.025), radius: 3, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: toolbarIconButtonCornerRadius, style: .continuous))
    }

    private var filterSwitchControl: some View {
        HStack(spacing: 2) {
            ForEach(visibleFilters) { value in
                filterSwitchButton(value)
            }
        }
        .padding(2)
        .background(filterSwitchBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
        .help("切换基金筛选")
    }

    private func filterSwitchButton(_ value: FundListFilter) -> some View {
        let isSelected = filter == value
        let currentCount = count(for: value)
        let isPending = value == .pending
        let pendingHasItems = isPending && currentCount > 0

        return Button {
            selectFilter(value)
        } label: {
            HStack(spacing: 6) {
                Text(value.title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(currentCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(filterCountForeground(isSelected: isSelected, isPending: pendingHasItems))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(filterCountBackground(isSelected: isSelected, isPending: pendingHasItems), in: Capsule())
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .frame(minWidth: isPending ? 68 : 56, minHeight: 24)
            .background {
                if isSelected {
                    Capsule()
                        .fill(filterSelectedBackground)
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 0.55)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 7, x: 0, y: 4)
                        .matchedGeometryEffect(id: "filterSwitchSelection", in: filterSwitchNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func selectFilter(_ value: FundListFilter) {
        withAnimation(.easeInOut(duration: 0.12)) {
            filter = value
            isSortMenuPresented = false
        }
    }

    private var sortMenuLabel: some View {
        HStack(spacing: 5) {
            Text(sortMode.title)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(width: 88, height: 26)
        .background(toolbarPillBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        )
        .contentShape(Capsule())
    }

    private var sortMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(FundSortMode.allCases) { mode in
                Button {
                    sortMode = mode
                    isSortMenuPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Text(mode.title)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        if sortMode == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 12, weight: sortMode == mode ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .frame(width: 118, height: 26, alignment: .leading)
                    .background(
                        sortMode == mode ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(5)
        .background(sortMenuBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.55)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 14, x: 0, y: 8)
    }

    private var fundList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                MainPopoverNativeScrollConfiguration()
                    .frame(height: 0)

                if filter == .pending {
                    pendingActivityList
                } else {
                    fundRows
                }
            }
        }
        .scrollIndicators(.visible)
        .refreshable {
            await refreshWithFeedback()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(listSurfaceBackground)
    }

    @ViewBuilder
    private var fundRows: some View {
        if filteredFunds.isEmpty {
            ContentUnavailableView("暂无基金数据", systemImage: "tray")
                .frame(height: 300)
        } else {
            ForEach(filteredFunds) { fund in
                let isClosedZeroPosition = PendingFundDisplayRules.isClosedZeroPosition(
                    fund,
                    tradeRecords: tradeRecords
                )
                FundRowView(
                    fund: fund,
                    isSelected: selectedFundCode == fund.code,
                    isClosedZeroPosition: isClosedZeroPosition,
                    masksAmounts: hidesHeaderAmounts,
                    onOpen: {
                        onOpenFundDetail(fund)
                    }
                )
                Divider()
            }
        }
    }

    @ViewBuilder
    private var pendingActivityList: some View {
        if pendingActivities.isEmpty {
            ContentUnavailableView("暂无待确认交易", systemImage: "clock.badge.checkmark")
                .frame(height: 300)
        } else {
            VStack(spacing: 0) {
                ForEach(pendingActivities) { activity in
                    PendingTradeActivityRow(
                        activity: activity,
                        isSelected: selectedFundCode == activity.code,
                        onDelete: activity.recordID == nil ? nil : {
                            deletingPendingActivity = activity
                        }
                    ) {
                        onOpenPendingActivity(activity)
                    }
                    Divider()
                }
            }
        }
    }

    private var marketIndexFooter: some View {
        VStack(spacing: 0) {
            if isMarketIndexExpanded {
                marketIndexExpandedContent
            } else {
                marketIndexCollapsedRow
            }
        }
        .background(marketIndexFooterBackground)
        .overlay(alignment: .top) {
            Divider()
                .opacity(colorScheme == .dark ? 0.62 : 0.72)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 8, x: 0, y: -3)
        .onChange(of: settingsStore.settings.showsMarketIndexes) { _, isShown in
            if !isShown {
                isMarketIndexExpanded = false
            }
        }
    }

    private var marketIndexCollapsedRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isMarketIndexExpanded = true
            }
        } label: {
            HStack(spacing: 7) {
                if let quote = primaryMarketIndexQuote {
                    Text(marketIndexDisplayName(quote))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 70, alignment: .leading)

                    Spacer(minLength: 6)

                    Text(marketIndexValueText(quote.value))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(toneColor(for: quote.changeRate))
                        .lineLimit(1)

                    Text(marketIndexChangeText(quote.change))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(toneColor(for: quote.changeRate))
                        .lineLimit(1)
                        .frame(width: 52, alignment: .trailing)

                    Text(MoneyFormatter.percent(quote.changeRate, signed: true))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(toneColor(for: quote.changeRate))
                        .lineLimit(1)
                        .frame(width: 48, alignment: .trailing)
                } else {
                    Text(settingsStore.settings.defaultMarketIndexID.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 70, alignment: .leading)

                    Spacer(minLength: 6)

                    Text(marketIndexStore.isRefreshing ? "加载中" : "暂无数据")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("展开大盘指数")
    }

    private var marketIndexExpandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isMarketIndexExpanded = false
                }
            } label: {
                HStack(spacing: 7) {
                    Text("大盘指数")
                        .font(.system(size: 11, weight: .semibold))
                    if marketIndexStore.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.64)
                            .frame(width: 14, height: 14)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("收起大盘指数")

            if marketIndexQuotes.isEmpty {
                Text(marketIndexStore.isRefreshing ? "指数加载中" : "指数暂无数据")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(marketIndexQuotes) { quote in
                            marketIndexCardButton(quote)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 9)
                }
                .scrollIndicators(.hidden)
                .frame(height: 86)
            }
        }
        .padding(.top, 2)
    }

    private var marketIndexQuotes: [MarketIndexQuote] {
        marketIndexStore.orderedQuotes()
    }

    private var primaryMarketIndexQuote: MarketIndexQuote? {
        marketIndexStore.primaryQuote(defaultID: settingsStore.settings.defaultMarketIndexID)
    }

    private func marketIndexCardButton(_ quote: MarketIndexQuote) -> some View {
        Button {
            selectMarketIndex(quote.id)
        } label: {
            marketIndexCard(quote)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("选择\(marketIndexDisplayName(quote))")
        .accessibilityLabel("选择\(marketIndexDisplayName(quote))")
    }

    private func selectMarketIndex(_ id: MarketIndexID) {
        settingsStore.setDefaultMarketIndexID(id)
        withAnimation(.easeInOut(duration: 0.16)) {
            isMarketIndexExpanded = false
        }
    }

    private func marketIndexCard(_ quote: MarketIndexQuote) -> some View {
        let isSelected = quote.id == settingsStore.settings.defaultMarketIndexID

        return VStack(alignment: .leading, spacing: 5) {
            Text(marketIndexDisplayName(quote))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(marketIndexValueText(quote.value))
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(toneColor(for: quote.changeRate))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 5) {
                Text(marketIndexChangeText(quote.change))
                Text(MoneyFormatter.percent(quote.changeRate, signed: true))
            }
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(toneColor(for: quote.changeRate))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 9)
        .frame(width: 104, height: 74, alignment: .leading)
        .background(
            marketIndexCardBackground(for: quote, isSelected: isSelected),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    toneColor(for: quote.changeRate).opacity(
                        isSelected
                            ? (colorScheme == .dark ? 0.52 : 0.34)
                            : (colorScheme == .dark ? 0.20 : 0.14)
                    ),
                    lineWidth: isSelected ? 1.1 : 0.65
                )
        )
        .shadow(
            color: isSelected
                ? toneColor(for: quote.changeRate).opacity(colorScheme == .dark ? 0.18 : 0.10)
                : Color.clear,
            radius: isSelected ? 4 : 0,
            x: 0,
            y: 1
        )
    }

    private func marketIndexDisplayName(_ quote: MarketIndexQuote) -> String {
        quote.id.title
    }

    private func marketIndexValueText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func marketIndexChangeText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func marketIndexCardBackground(for quote: MarketIndexQuote, isSelected: Bool) -> Color {
        toneColor(for: quote.changeRate).opacity(
            isSelected
                ? (colorScheme == .dark ? 0.24 : 0.14)
                : (colorScheme == .dark ? 0.16 : 0.10)
        )
    }

    private var refreshStatusIndicator: some View {
        ZStack {
            if isManualRefreshFeedbackVisible {
                Circle()
                    .stroke(refreshStatusColor.opacity(colorScheme == .dark ? 0.52 : 0.36), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .scaleEffect(isRefreshStatusPulsing ? 1.15 : 0.55)
                    .opacity(isRefreshStatusPulsing ? 0 : 0.78)
            }

            Circle()
                .fill(refreshStatusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.55), lineWidth: 0.6)
                )
        }
            .frame(width: 14, height: 14)
            .shadow(color: refreshStatusColor.opacity(0.28), radius: 3, x: 0, y: 1)
            .help(refreshStatusHelp)
            .onAppear {
                updateRefreshStatusPulse(isManualRefreshFeedbackVisible)
            }
            .onChange(of: isManualRefreshFeedbackVisible) { _, isRefreshing in
                updateRefreshStatusPulse(isRefreshing)
            }
    }

    private var marketBadge: some View {
        let state = TradingCalendar.marketSessionState()
        return Text(state.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color.white.opacity(0.96))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(marketBadgeBackground(for: state), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.24), lineWidth: 0.55)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 6, x: 0, y: 3)
    }

    private var privacyToggleButton: some View {
        Button(action: toggleHeaderAmountPrivacy) {
            Image(systemName: hidesHeaderAmounts ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(privacyToggleForeground)
                .frame(width: 22, height: 22)
                .background(privacyToggleBackground, in: Circle())
                .overlay(
                    Circle()
                        .stroke(privacyToggleForeground.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 0.6)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(hidesHeaderAmounts ? "显示顶部金额" : "隐藏顶部金额")
        .accessibilityLabel(hidesHeaderAmounts ? "显示顶部金额" : "隐藏顶部金额")
    }

    private var privacyToggleForeground: Color {
        hidesHeaderAmounts
            ? .orange
            : Color.secondary.opacity(colorScheme == .dark ? 0.86 : 0.72)
    }

    private var privacyToggleBackground: Color {
        hidesHeaderAmounts
            ? Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12)
            : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    private func toggleHeaderAmountPrivacy() {
        withAnimation(.easeInOut(duration: 0.16)) {
            hidesHeaderAmounts.toggle()
        }
        NotificationCenter.default.post(name: .fundPulseAmountPrivacyDidChange, object: nil)
    }

    private var hiddenMoneyPlaceholder: String { "***" }

    private func headerMoneyText(_ value: Double) -> String {
        hidesHeaderAmounts ? hiddenMoneyPlaceholder : MoneyFormatter.plainMoney(value)
    }

    private func headerSignedMoneyText(_ value: Double) -> String {
        hidesHeaderAmounts ? hiddenMoneyPlaceholder : MoneyFormatter.money(value, signed: true)
    }

    private func headerPercentText(_ value: Double) -> String {
        MoneyFormatter.percent(value, signed: true)
    }

    private func headerMetricTone(_ value: Double) -> Double? {
        hidesHeaderAmounts ? nil : value
    }

    private func headerMetricColor(_ value: Double) -> Color {
        hidesHeaderAmounts ? hiddenAmountColor : toneColor(for: value)
    }

    private var hiddenAmountColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.84 : 0.78)
    }

    @ViewBuilder
    private var updateButton: some View {
        switch updateStore.status {
        case .available:
            Button {
                onOpenUpdate?()
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(updateStore.badgeTitle ?? "下载更新")
            .help(updateStore.badgeTitle ?? "发现新版本")
        case .downloaded:
            Button {
                onOpenUpdate?()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(updateStore.badgeTitle ?? "现在更新")
            .help(updateStore.badgeTitle ?? "更新已下载")
        case .downloading:
            UpdateProgressRing(progress: updateStore.downloadProgress)
                .frame(width: 24, height: 24)
                .accessibilityLabel(updateStore.badgeTitle ?? "正在下载更新")
                .help(updateStore.badgeTitle ?? "正在下载更新")
        case .checking, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
                .help(updateStore.badgeTitle ?? "更新处理中")
        case .failed:
            EmptyView()
        case .idle, .upToDate:
            EmptyView()
        }
    }

    private var statusMessage: String? {
        switch store.loadState {
        case .missingPlainData(let hasLegacyStore) where hasLegacyStore:
            "检测到旧版加密数据，可通过迁移脚本转换后继续使用。"
        case .failed(let reason):
            "基金数据刷新失败：\(reason)"
        default:
            nil
        }
    }

    private var isRefreshRequestInProgress: Bool {
        isRefreshing || store.isRefreshingQuotes
    }

    private var isManualRefreshFeedbackVisible: Bool {
        isRefreshing
    }

    private var refreshStatusText: String {
        if isManualRefreshFeedbackVisible {
            return "正在刷新基金数据..."
        }
        return "刷新 \(refreshTimeText(store.snapshot.updateTime))"
    }

    private var refreshStatusColor: Color {
        if isManualRefreshFeedbackVisible { return .orange }
        switch store.loadState {
        case .loaded:
            return .fundPulseGreen
        case .loading:
            return .orange
        case .missingPlainData:
            return Color.secondary.opacity(0.45)
        case .failed:
            return Color(red: 239 / 255, green: 77 / 255, blue: 98 / 255)
        }
    }

    private var refreshStatusHelp: String {
        if isManualRefreshFeedbackVisible { return "正在刷新基金数据" }
        switch store.loadState {
        case .loaded:
            return "基金数据刷新正常"
        case .loading:
            return "正在读取基金数据"
        case .missingPlainData:
            return "暂无基金数据文件"
        case .failed(let reason):
            return "基金数据刷新失败：\(reason)"
        }
    }

    private func updateRefreshStatusPulse(_ isRefreshing: Bool) {
        isRefreshStatusPulsing = false
        guard isRefreshing else { return }
        withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
            isRefreshStatusPulsing = true
        }
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: storeFailureSymbol)
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(10)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var storeFailureSymbol: String {
        if case .failed = store.loadState {
            return "exclamationmark.triangle"
        }
        return "lock.doc"
    }

    private func metricCard(
        _ title: String,
        _ value: String,
        footnote: String? = nil,
        tone: Double? = nil,
        isTotal: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                disclosureIndicator
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.64)
                .allowsTightening(true)
                .foregroundStyle(metricCardValueColor(tone, isTotal: isTotal))

            if let footnote {
                Text(footnote)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .foregroundStyle(hidesHeaderAmounts ? Color.secondary : pendingAmountFootnoteColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: footnote == nil ? 44 : 52)
        .background(metricCardBackground(tone, isTotal: isTotal), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(metricCardBorder)
        .overlay(metricCardInnerHighlight)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035), radius: 8, x: 0, y: 4)
    }

    private func pendingImpactBar(_ impact: PendingHeaderImpact) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("待确认 \(impact.count) 笔")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Text(pendingImpactActivityText(impact))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if hidesHeaderAmounts {
                Text("***")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                pendingImpactNetSummary(impact)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.68))
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pendingImpactNetSummary(_ impact: PendingHeaderImpact) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(pendingNetTitle(impact.netAmount))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(signedCompactPendingMoney(impact.netAmount))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(pendingImpactNetColor(impact.netAmount))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
        }
        .frame(minWidth: 86, alignment: .trailing)
    }

    private func pendingImpactActivityText(_ impact: PendingHeaderImpact) -> String {
        let hasSubscription = impact.buyAmount > 0.5
        let hasRedemption = impact.sellAmount > 0.5

        switch (hasSubscription, hasRedemption) {
        case (true, true):
            return "申购 \(pendingMoneyText(impact.buyAmount)) · 赎回 \(pendingMoneyText(impact.sellAmount))"
        case (true, false):
            return "申购待确认 \(pendingMoneyText(impact.buyAmount))"
        case (false, true):
            return "赎回待确认 \(pendingMoneyText(impact.sellAmount))"
        case (false, false):
            if impact.conversionCount > 0 {
                return "转换待确认 \(impact.conversionCount)笔"
            }
            return "交易待确认"
        }
    }

    private func pendingNetTitle(_ value: Double) -> String {
        if value > 0.5 { return "净申购" }
        if value < -0.5 { return "净赎回" }
        return "净额"
    }

    private func metricCardValueColor(_ tone: Double?, isTotal: Bool) -> Color {
        if hidesHeaderAmounts {
            return hiddenAmountColor
        }
        return isTotal ? totalAmountAccentColor : (tone.map(toneColor(for:)) ?? Color.primary)
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(width: 12, height: 12)
    }

    private var toolbarPillBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.035)
    }

    private var toolbarIconForeground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.86)
            : Color(red: 44 / 255, green: 47 / 255, blue: 52 / 255)
    }

    private var toolbarIconButtonSize: CGFloat {
        27
    }

    private var toolbarIconButtonCornerRadius: CGFloat {
        7.5
    }

    private var toolbarControlBackground: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.105),
                    Color.white.opacity(0.060)
                ]
                : [
                    Color.white.opacity(0.92),
                    Color(red: 247 / 255, green: 242 / 255, blue: 233 / 255).opacity(0.90)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func toolbarControlBorder(cornerRadius: CGFloat, tone: Color? = nil) -> some View {
        let borderColor = tone.map {
            $0.opacity(colorScheme == .dark ? 0.50 : 0.36)
        } ?? (
            colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color(red: 213 / 255, green: 204 / 255, blue: 190 / 255).opacity(0.44)
        )

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: 0.85)
    }

    private func toolbarControlInnerHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.55), lineWidth: 0.65)
            .padding(0.7)
            .blendMode(.plusLighter)
    }

    private var iconButtonHoverSurface: Color {
        Color.primary.opacity(0.001)
    }

    private var filterSwitchBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.035)
    }

    private var filterSelectedBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.105)
            : Color.white.opacity(0.95)
    }

    private var sortMenuBackground: Color {
        colorScheme == .dark
            ? Color(red: 28 / 255, green: 30 / 255, blue: 36 / 255)
            : Color.white.opacity(0.98)
    }

    private var metricCardBaseBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.white.opacity(0.72)
    }

    private var totalAmountAccentColor: Color {
        colorScheme == .dark
            ? Color(red: 255 / 255, green: 210 / 255, blue: 126 / 255)
            : Color(red: 157 / 255, green: 96 / 255, blue: 18 / 255)
    }

    private var pendingAmountFootnoteColor: Color {
        colorScheme == .dark
            ? Color(red: 255 / 255, green: 188 / 255, blue: 112 / 255).opacity(0.86)
            : Color(red: 174 / 255, green: 96 / 255, blue: 22 / 255).opacity(0.82)
    }

    private var metricCardBorder: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(metricCardBorderColor, lineWidth: 0.9)
    }

    private var metricCardInnerHighlight: some View {
        RoundedRectangle(cornerRadius: 8.4, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.30), lineWidth: 0.55)
            .padding(0.7)
            .blendMode(.plusLighter)
    }

    private var metricCardBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color(red: 204 / 255, green: 190 / 255, blue: 170 / 255).opacity(0.42)
    }

    private func marketBadgeBackground(for state: MarketSessionState) -> some ShapeStyle {
        let colors: [Color] = {
            switch state {
            case .open:
                return colorScheme == .dark
                    ? [
                        Color(red: 48 / 255, green: 191 / 255, blue: 137 / 255),
                        Color(red: 25 / 255, green: 137 / 255, blue: 96 / 255)
                    ]
                    : [
                        Color(red: 66 / 255, green: 185 / 255, blue: 135 / 255),
                        Color(red: 31 / 255, green: 145 / 255, blue: 100 / 255)
                    ]
            case .middayBreak:
                return [
                    Color(red: 255 / 255, green: 198 / 255, blue: 88 / 255),
                    Color(red: 233 / 255, green: 145 / 255, blue: 45 / 255)
                ]
            case .closed:
                return colorScheme == .dark
                    ? [
                        Color(red: 126 / 255, green: 137 / 255, blue: 148 / 255),
                        Color(red: 79 / 255, green: 88 / 255, blue: 98 / 255)
                    ]
                    : [
                        Color(red: 164 / 255, green: 175 / 255, blue: 184 / 255),
                        Color(red: 126 / 255, green: 138 / 255, blue: 148 / 255)
                    ]
            }
        }()

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var pendingBadgeBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 255 / 255, green: 219 / 255, blue: 103 / 255).opacity(colorScheme == .dark ? 0.94 : 0.78),
                Color(red: 255 / 255, green: 190 / 255, blue: 68 / 255).opacity(colorScheme == .dark ? 0.86 : 0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var pendingBadgeForeground: Color {
        colorScheme == .dark
            ? Color(red: 73 / 255, green: 49 / 255, blue: 12 / 255)
            : Color(red: 174 / 255, green: 103 / 255, blue: 0 / 255)
    }

    private func filterCountForeground(isSelected: Bool, isPending: Bool) -> Color {
        if isPending {
            return Color.orange.opacity(isSelected ? 0.92 : 0.78)
        }
        return isSelected ? Color.primary.opacity(0.82) : Color.secondary.opacity(0.58)
    }

    private func filterCountBackground(isSelected: Bool, isPending: Bool) -> Color {
        if isPending {
            return Color.orange.opacity(isSelected ? 0.15 : 0.09)
        }
        return isSelected
            ? Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
            : Color(nsColor: .separatorColor).opacity(0.12)
    }

    private var panelSurfaceBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 16 / 255, green: 18 / 255, blue: 22 / 255),
                    Color(red: 12 / 255, green: 14 / 255, blue: 18 / 255)
                ]
                : [
                    Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255),
                    Color(red: 244 / 255, green: 241 / 255, blue: 235 / 255)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var headerSurfaceBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 35 / 255, green: 39 / 255, blue: 46 / 255),
                        Color(red: 18 / 255, green: 21 / 255, blue: 27 / 255),
                        Color(red: 42 / 255, green: 25 / 255, blue: 33 / 255).opacity(0.82)
                    ]
                    : [
                        Color(red: 255 / 255, green: 251 / 255, blue: 242 / 255),
                        Color(red: 255 / 255, green: 242 / 255, blue: 224 / 255),
                        Color(red: 255 / 255, green: 236 / 255, blue: 226 / 255)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.30),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var toolbarSurfaceBackground: some View {
        ZStack {
            Color(red: colorScheme == .dark ? 16 / 255 : 250 / 255,
                  green: colorScheme == .dark ? 18 / 255 : 247 / 255,
                  blue: colorScheme == .dark ? 22 / 255 : 241 / 255)
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.025 : 0.22),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var listSurfaceBackground: some View {
        Color(red: colorScheme == .dark ? 15 / 255 : 250 / 255,
              green: colorScheme == .dark ? 17 / 255 : 248 / 255,
              blue: colorScheme == .dark ? 21 / 255 : 243 / 255)
    }

    private var marketIndexFooterBackground: some View {
        Color(red: colorScheme == .dark ? 17 / 255 : 252 / 255,
              green: colorScheme == .dark ? 19 / 255 : 250 / 255,
              blue: colorScheme == .dark ? 23 / 255 : 246 / 255)
    }

    private func metricCardBackground(_ tone: Double?, isTotal: Bool = false) -> some ShapeStyle {
        if isTotal {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        totalAmountAccentColor.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        metricCardBaseBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if let tone, tone != 0 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        toneColor(for: tone).opacity(colorScheme == .dark ? 0.16 : 0.08),
                        metricCardBaseBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(metricCardBaseBackground)
    }

    private var filteredFunds: [FundPosition] {
        let records = tradeRecords
        let funds = store.snapshot.funds.filter { fund in
            switch filter {
            case .holding:
                FundListDisplayRules.isDisplayedHolding(fund, tradeRecords: records)
            case .pending:
                FundListDisplayRules.isDisplayedPending(fund, tradeRecords: records)
            }
        }

        switch sortMode {
        case .custom:
            return funds
        case .todayRate:
            return sortDescending(funds) { $0.todayRate }
        case .costAmount:
            return sortDescending(funds, value: costAmount)
        case .todayIncome:
            return sortDescending(funds) { $0.todayIncome }
        case .todayTotal:
            return sortDescending(funds, value: currentTotal)
        case .holdingIncome:
            return sortDescending(funds, value: holdingIncome)
        case .holdingRate:
            return sortDescending(funds) { $0.holdingRate ?? -Double.greatestFiniteMagnitude }
        case .name:
            return funds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func sortDescending(
        _ funds: [FundPosition],
        value: (FundPosition) -> Double
    ) -> [FundPosition] {
        funds.sorted { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func costAmount(for fund: FundPosition) -> Double {
        if let shares = fund.migratedShares, let cost = fund.migratedCost {
            return shares * cost
        }
        return fund.migratedPrincipal ?? 0
    }

    private func holdingIncome(for fund: FundPosition) -> Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else { return 0 }
        return costAmount(for: fund) * holdingRate / 100
    }

    private func currentTotal(for fund: FundPosition) -> Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        if let shares = fund.migratedShares,
           let cost = fund.migratedCost {
            let costTotal = shares * cost
            return costTotal + holdingIncome(for: fund)
        }
        return fund.migratedPrincipal ?? 0
    }

    private func count(for value: FundListFilter) -> Int {
        switch value {
        case .holding:
            let records = tradeRecords
            return store.snapshot.funds.filter {
                FundListDisplayRules.isDisplayedHolding($0, tradeRecords: records)
            }.count
        case .pending:
            return displayPendingCount
        }
    }

    private var displayPendingCount: Int {
        pendingActivities.count
    }

    private var pendingHeaderImpact: PendingHeaderImpact? {
        PendingHeaderImpact.make(activities: pendingActivities)
    }

    private var visibleFilters: [FundListFilter] {
        FundListFilter.allCases
    }

    private var tradeRecords: [FundTradeRecord] {
        store.snapshot.tradeRecords ?? []
    }

    private var pendingActivities: [PendingTradeActivity] {
        let fundsByCode = Dictionary(uniqueKeysWithValues: store.snapshot.funds.map { ($0.code, $0) })
        let records = tradeRecords
        let pendingTrades = store.snapshot.pendingTrades ?? []
        let pendingTradeRecordIDs = Set(pendingTrades.compactMap(\.recordID))
        let pendingConversionTargetCodes = Set((store.snapshot.pendingConversions ?? []).map(\.toCode))

        var activities: [PendingTradeActivity] = pendingTrades.map { pendingTrade in
            let record = pendingTrade.recordID.flatMap { id in
                records.first { $0.id == id }
            }
            let fund = fundsByCode[pendingTrade.code]
            let acceptedDate = record?.acceptedDate ?? TradingCalendar.acceptedTradeDate(
                positionDate: pendingTrade.tradeDate,
                timeType: pendingTrade.tradeTimeType
            )
            return PendingTradeActivity(
                id: "pending-trade-\(pendingTrade.id)",
                recordID: record?.id ?? pendingTrade.recordID,
                conversionID: record?.conversionID,
                kind: record?.kind ?? tradeKind(for: pendingTrade.action),
                code: pendingTrade.code,
                name: record?.name ?? fund?.name ?? pendingTrade.code,
                linkedCode: record?.linkedCode,
                linkedName: record?.linkedName,
                mode: record?.mode ?? pendingTrade.mode,
                amount: record?.amount ?? pendingTrade.amount,
                shares: record?.shares ?? pendingTrade.shares,
                tradeDate: pendingTrade.tradeDate,
                tradeTimeType: pendingTrade.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: pendingTrade.createdAt,
                displayAmount: pendingDisplayAmount(
                    kind: record?.kind ?? tradeKind(for: pendingTrade.action),
                    amount: record?.amount ?? pendingTrade.amount,
                    shares: record?.shares ?? pendingTrade.shares,
                    acceptedDate: acceptedDate,
                    fund: fund
                ),
                fund: fund
            )
        }

        let pendingRecords = records.filter {
            $0.status == .pending
                && !pendingTradeRecordIDs.contains($0.id)
                && $0.kind != .conversionIn
        }
        activities.append(contentsOf: pendingRecords.map { record in
            PendingTradeActivity(
                id: "pending-record-\(record.id)",
                recordID: record.id,
                conversionID: record.conversionID,
                kind: record.kind,
                code: record.code,
                name: record.name,
                linkedCode: record.linkedCode,
                linkedName: record.linkedName,
                mode: record.mode,
                amount: record.amount,
                shares: record.shares,
                tradeDate: record.tradeDate,
                tradeTimeType: record.tradeTimeType,
                acceptedDate: record.acceptedDate,
                createdAt: record.createdAt,
                displayAmount: pendingDisplayAmount(
                    kind: record.kind,
                    amount: record.amount,
                    shares: record.shares,
                    acceptedDate: record.acceptedDate,
                    fund: fundsByCode[record.code]
                ),
                fund: fundsByCode[record.code]
            )
        })

        let pendingNewFundCodes = Set(
            activities
                .filter { $0.kind == .newFund }
                .map(\.code)
        )
        let legacyPendingFunds = store.snapshot.funds.filter {
            FundListDisplayRules.isDisplayedPending($0, tradeRecords: records)
                && !pendingNewFundCodes.contains($0.code)
                && !pendingConversionTargetCodes.contains($0.code)
        }
        activities.append(contentsOf: legacyPendingFunds.map { fund in
            let tradeDate = fund.positionDate ?? DateOnlyFormatter.string(from: .now)
            let timeType = fund.positionTimeType ?? .before15
            return PendingTradeActivity(
                id: "pending-fund-\(fund.code)",
                recordID: nil,
                conversionID: nil,
                kind: .newFund,
                code: fund.code,
                name: fund.name,
                linkedCode: nil,
                linkedName: nil,
                mode: fund.positionMode ?? .amount,
                amount: fund.pendingAmount,
                shares: fund.migratedShares,
                tradeDate: tradeDate,
                tradeTimeType: timeType,
                acceptedDate: TradingCalendar.acceptedTradeDate(positionDate: tradeDate, timeType: timeType),
                createdAt: .distantPast,
                displayAmount: pendingDisplayAmount(
                    kind: .newFund,
                    amount: fund.pendingAmount,
                    shares: fund.migratedShares,
                    acceptedDate: TradingCalendar.acceptedTradeDate(positionDate: tradeDate, timeType: timeType),
                    fund: fund
                ),
                fund: fund
            )
        })

        return activities.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var deletePendingActivityConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingPendingActivity != nil },
            set: { isPresented in
                if !isPresented {
                    deletingPendingActivity = nil
                }
            }
        )
    }

    private func deletePendingActivityConfirmationMessage(for activity: PendingTradeActivity) -> String {
        if activity.isConversion {
            return "这是一条基金转换待确认记录。删除后会连带删除同一次转换的转出、转入两条记录，并移除这笔待确认转换；已确认持仓不会被提前改动。"
        }
        return "确定删除 \(activity.tradeDate) \(activity.tradeTimeType.title) 的\(activity.kind.title)待确认记录吗？删除后会移除这笔待确认交易，且无法撤销。"
    }

    private func tradeKind(for action: FundTradeAction) -> FundTradeKind {
        switch action {
        case .buy:
            .buy
        case .sell:
            .sell
        }
    }

    private func pendingDisplayAmount(
        kind: FundTradeKind,
        amount: Double?,
        shares: Double?,
        acceptedDate: String,
        fund: FundPosition?
    ) -> PendingActivityAmount? {
        if let amount, amount > 0 {
            return PendingActivityAmount(value: amount, source: .enteredAmount, price: nil, shares: shares)
        }
        guard let shares, shares > 0,
              let reference = pendingReferenceValue(for: fund, acceptedDate: acceptedDate)
        else {
            return nil
        }
        return PendingActivityAmount(
            value: shares * reference.price,
            source: reference.source,
            price: reference.price,
            shares: shares
        )
    }

    private func pendingReferenceValue(
        for fund: FundPosition?,
        acceptedDate: String
    ) -> (price: Double, source: PendingActivityAmount.Source)? {
        guard let fund else { return nil }
        let shares = fund.migratedShares ?? 0
        let currentAmount = PortfolioPanelDisplay.currentAmount(for: fund)
        let basePrice: Double
        if shares > 0, currentAmount > 0 {
            basePrice = currentAmount / shares
        } else if let migratedCost = fund.migratedCost, migratedCost > 0 {
            basePrice = migratedCost
        } else {
            return nil
        }

        let acceptedShortDate = String(acceptedDate.dropFirst(5))
        let updateDate = DateOnlyFormatter.string(from: store.snapshot.updateTime)
        let dateMatchesAcceptedNetValue = fund.dateText.hasPrefix(acceptedShortDate)
        if dateMatchesAcceptedNetValue && (fund.isUpdated || acceptedDate != updateDate) {
            return (basePrice, .confirmedNetValue)
        }

        if acceptedDate == updateDate, !fund.isUpdated, fund.todayRate != 0 {
            return (basePrice * (1 + fund.todayRate / 100), .estimatedNetValue)
        }

        return (basePrice, .latestNetValue)
    }

    private func pendingImpactSideText(amount: Double) -> String {
        amount > 0 ? pendingMoneyText(amount) : "--"
    }

    private func signedCompactPendingMoney(_ value: Double) -> String {
        if abs(value) < 0.5 {
            return "持平"
        }
        let sign = value > 0 ? "+" : "-"
        return "\(sign)\(pendingMoneyText(abs(value)))"
    }

    private func pendingImpactNetColor(_ value: Double) -> Color {
        if value > 0.5 {
            return .red
        }
        if value < -0.5 {
            return .fundPulseGreen
        }
        return .secondary
    }

    private func pendingMoneyText(_ value: Double) -> String {
        "¥\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func numberText(_ value: Double, maxFractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)))
    }

    private func refresh() {
        guard !isRefreshRequestInProgress else { return }
        Task {
            await refreshWithFeedback()
        }
    }

    @MainActor
    private func refreshWithFeedback() async {
        guard !isRefreshRequestInProgress else { return }

        isRefreshing = true
        let startedAt = Date()
        await refreshAsync()

        let remainingDisplayTime = 0.35 - Date().timeIntervalSince(startedAt)
        if remainingDisplayTime > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remainingDisplayTime * 1_000_000_000))
        }

        isRefreshing = false
    }

    private func refreshAsync() async {
        if let onRefresh {
            await onRefresh()
        } else {
            await store.refreshQuotes()
        }
    }
}

private enum FundListFilter: String, CaseIterable, Identifiable {
    case holding
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holding:
            "持仓"
        case .pending:
            "待确认"
        }
    }
}

private enum FundSortMode: String, CaseIterable, Identifiable {
    case custom
    case todayRate
    case costAmount
    case todayIncome
    case todayTotal
    case holdingIncome
    case holdingRate
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom:
            "自定义"
        case .todayRate:
            "今日涨幅"
        case .costAmount:
            "持有成本"
        case .todayIncome:
            "今日收益"
        case .todayTotal:
            "今日总值"
        case .holdingIncome:
            "持有收益"
        case .holdingRate:
            "持有收益率"
        case .name:
            "名称(A-Z)"
        }
    }
}

struct PendingTradeActivity: Identifiable {
    var id: String
    var recordID: String?
    var conversionID: String?
    var kind: FundTradeKind
    var code: String
    var name: String
    var linkedCode: String?
    var linkedName: String?
    var mode: PositionMode
    var amount: Double?
    var shares: Double?
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var acceptedDate: String
    var createdAt: Date
    var displayAmount: PendingActivityAmount?
    var fund: FundPosition?

    var isConversion: Bool {
        kind == .conversionOut || kind == .conversionIn || conversionID != nil
    }
}

struct PendingActivityAmount {
    enum Source {
        case enteredAmount
        case estimatedNetValue
        case confirmedNetValue
        case latestNetValue
    }

    var value: Double
    var source: Source
    var price: Double?
    var shares: Double?
}

struct PendingHeaderImpact {
    var count: Int
    var buyAmount: Double = 0
    var sellAmount: Double = 0
    var conversionCount = 0
    var hasEstimatedAmount = false

    static func make(activities: [PendingTradeActivity]) -> PendingHeaderImpact? {
        var impact = PendingHeaderImpact(count: activities.count)
        var conversionKeys = Set<String>()

        for activity in activities {
            if activity.isConversion {
                conversionKeys.insert(activity.conversionID ?? activity.id)
                continue
            }

            guard let displayAmount = activity.displayAmount else {
                continue
            }

            switch activity.kind {
            case .newFund, .buy:
                impact.buyAmount += displayAmount.value
            case .sell:
                impact.sellAmount += displayAmount.value
            case .conversionOut, .conversionIn:
                conversionKeys.insert(activity.conversionID ?? activity.id)
            }

            if displayAmount.source == .estimatedNetValue {
                impact.hasEstimatedAmount = true
            }
        }

        impact.conversionCount = conversionKeys.count
        guard impact.hasAmount || impact.conversionCount > 0 else { return nil }
        return impact
    }

    var hasAmount: Bool {
        buyAmount > 0 || sellAmount > 0
    }

    var netAmount: Double {
        buyAmount - sellAmount
    }
}

private enum PortfolioPanelDisplay {
    static let allocationPalette: [Color] = [
        Color(red: 48 / 255, green: 120 / 255, blue: 214 / 255),
        Color(red: 231 / 255, green: 126 / 255, blue: 48 / 255),
        Color(red: 118 / 255, green: 92 / 255, blue: 196 / 255),
        Color(red: 37 / 255, green: 164 / 255, blue: 149 / 255),
        Color(red: 221 / 255, green: 87 / 255, blue: 133 / 255),
        Color(red: 93 / 255, green: 142 / 255, blue: 65 / 255),
        Color(red: 183 / 255, green: 95 / 255, blue: 40 / 255),
        Color(red: 92 / 255, green: 120 / 255, blue: 145 / 255)
    ]

    static func holdingFunds(in snapshot: PortfolioSnapshot) -> [FundPosition] {
        snapshot.funds.filter { fund in
            fund.status == .holding && currentAmount(for: fund) > 0
        }
    }

    static func currentAmount(for fund: FundPosition) -> Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        return principal(for: fund) + holdingIncome(for: fund)
    }

    static func principal(for fund: FundPosition) -> Double {
        if let migratedPrincipal = fund.migratedPrincipal {
            return migratedPrincipal
        }
        guard let shares = fund.migratedShares,
              let cost = fund.migratedCost
        else {
            return 0
        }
        return shares * cost
    }

    static func holdingIncome(for fund: FundPosition) -> Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else {
            return 0
        }
        return principal(for: fund) * holdingRate / 100
    }
}

private struct PortfolioAllocationItem: Identifiable {
    let rank: Int
    let fund: FundPosition
    let amount: Double
    let share: Double
    let color: Color

    var id: String { fund.code }
}

private struct PortfolioTreemapSlice: Identifiable {
    let item: PortfolioAllocationItem
    let rect: CGRect

    var id: String { item.id }
}

private struct PortfolioTreemapHoverState {
    let itemID: String
    let location: CGPoint
}

private enum PortfolioTreemapLayout {
    static func slices(for items: [PortfolioAllocationItem], in rect: CGRect) -> [PortfolioTreemapSlice] {
        split(items.filter { $0.amount > 0 }, in: rect)
    }

    private static func split(_ items: [PortfolioAllocationItem], in rect: CGRect) -> [PortfolioTreemapSlice] {
        guard !items.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        guard items.count > 1 else {
            return [PortfolioTreemapSlice(item: items[0], rect: inset(rect))]
        }

        let total = items.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let splitIndex = balancedSplitIndex(for: items, total: total)
        let leadingItems = Array(items.prefix(splitIndex))
        let trailingItems = Array(items.dropFirst(splitIndex))
        let leadingTotal = leadingItems.reduce(0) { $0 + $1.amount }
        let leadingRatio = min(max(leadingTotal / total, 0.05), 0.95)

        let leadingRect: CGRect
        let trailingRect: CGRect
        if rect.width >= rect.height {
            let leadingWidth = rect.width * leadingRatio
            leadingRect = CGRect(x: rect.minX, y: rect.minY, width: leadingWidth, height: rect.height)
            trailingRect = CGRect(x: rect.minX + leadingWidth, y: rect.minY, width: rect.width - leadingWidth, height: rect.height)
        } else {
            let leadingHeight = rect.height * leadingRatio
            leadingRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: leadingHeight)
            trailingRect = CGRect(x: rect.minX, y: rect.minY + leadingHeight, width: rect.width, height: rect.height - leadingHeight)
        }

        return split(leadingItems, in: leadingRect) + split(trailingItems, in: trailingRect)
    }

    private static func balancedSplitIndex(for items: [PortfolioAllocationItem], total: Double) -> Int {
        guard items.count > 2 else { return 1 }

        var runningTotal = 0.0
        var bestIndex = 1
        var bestDelta = Double.greatestFiniteMagnitude

        for index in 1..<items.count {
            runningTotal += items[index - 1].amount
            let delta = abs(total / 2 - runningTotal)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            }
        }

        return min(max(bestIndex, 1), items.count - 1)
    }

    private static func inset(_ rect: CGRect) -> CGRect {
        let insetX = min(rect.width / 8, 1.5)
        let insetY = min(rect.height / 8, 1.5)
        return rect.insetBy(dx: insetX, dy: insetY)
    }
}

private struct PortfolioTreemapChart: View {
    let items: [PortfolioAllocationItem]

    private enum LabelDensity {
        case full
        case stacked
        case compact

        var padding: CGFloat {
            switch self {
            case .full:
                6
            case .stacked:
                5
            case .compact:
                4
            }
        }

        var titleFontSize: CGFloat {
            switch self {
            case .full:
                10
            case .stacked:
                9.5
            case .compact:
                8.5
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverState: PortfolioTreemapHoverState?

    var body: some View {
        GeometryReader { proxy in
            let slices = PortfolioTreemapLayout.slices(
                for: items,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack(alignment: .topLeading) {
                ForEach(slices) { slice in
                    treemapBlock(slice, isHovered: hoverState?.itemID == slice.id)
                        .frame(width: max(slice.rect.width, 0), height: max(slice.rect.height, 0))
                        .position(x: slice.rect.midX, y: slice.rect.midY)
                }

                if let hoverState,
                   let slice = slices.first(where: { $0.id == hoverState.itemID }) {
                    PortfolioTreemapHoverWindowBridge(
                        item: slice.item,
                        location: hoverState.location,
                        chartSize: proxy.size,
                        colorScheme: colorScheme
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                } else {
                    PortfolioTreemapHoverWindowBridge(
                        item: nil,
                        location: nil,
                        chartSize: proxy.size,
                        colorScheme: colorScheme
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    updateHoverState(for: slices.first { $0.rect.contains(location) }, location: location)
                case .ended:
                    updateHoverState(for: nil, location: nil)
                }
            }
        }
        .accessibilityLabel("持仓占比方块图")
    }

    private func updateHoverState(for slice: PortfolioTreemapSlice?, location: CGPoint?) {
        guard let slice, let location else {
            if hoverState != nil {
                hoverState = nil
            }
            return
        }

        let movementThreshold: CGFloat = 10
        if let hoverState,
           hoverState.itemID == slice.id,
           hypot(hoverState.location.x - location.x, hoverState.location.y - location.y) < movementThreshold {
            return
        }
        hoverState = PortfolioTreemapHoverState(itemID: slice.id, location: location)
    }

    private func treemapBlock(_ slice: PortfolioTreemapSlice, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(blockFill(for: slice.item))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isHovered ? Color.white.opacity(0.86) : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.36),
                        lineWidth: isHovered ? 1.5 : 0.65
                    )
            )
            .overlay(alignment: .topLeading) {
                treemapLabel(for: slice)
                    .frame(width: max(slice.rect.width, 0), height: max(slice.rect.height, 0), alignment: .topLeading)
                    .clipped()
            }
            .shadow(
                color: isHovered ? slice.item.color.opacity(colorScheme == .dark ? 0.36 : 0.24) : .clear,
                radius: isHovered ? 9 : 0,
                x: 0,
                y: isHovered ? 3 : 0
            )
    }

    @ViewBuilder
    private func treemapLabel(for slice: PortfolioTreemapSlice) -> some View {
        if let density = labelDensity(for: slice.rect) {
            VStack(alignment: .leading, spacing: 1) {
                Text(treemapTitle(for: slice.item, density: density, width: slice.rect.width))
                    .font(.system(size: density.titleFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .truncationMode(.tail)

                Text(treemapPercentText(for: slice.item, density: density))
                    .font(.system(size: percentFontSize(for: density), weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.32), radius: 2, x: 0, y: 1)
            .padding(density.padding)
        }
    }

    private func labelDensity(for rect: CGRect) -> LabelDensity? {
        guard rect.width >= 16, rect.height >= 28 else {
            return nil
        }
        if rect.width >= 76, rect.height >= 42 {
            return .full
        }
        if rect.width >= 54, rect.height >= 34 {
            return .stacked
        }
        return .compact
    }

    private func treemapTitle(for item: PortfolioAllocationItem, density: LabelDensity, width: CGFloat) -> String {
        let name = item.fund.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = name.isEmpty ? FundCodeFormatter.display(item.fund.code) : name
        guard density != .full else {
            return source
        }

        let availableWidth = max(width - density.padding * 2, 8)
        let estimatedCharacterWidth: CGFloat = density == .compact ? 8 : 9
        let maxCharacters = max(Int(availableWidth / estimatedCharacterWidth), 1)
        return String(source.prefix(maxCharacters))
    }

    private func treemapPercentText(for item: PortfolioAllocationItem, density: LabelDensity) -> String {
        let value = item.share * 100
        if density == .compact {
            return value.formatted(.number.precision(.fractionLength(0))) + "%"
        }
        return MoneyFormatter.percent(value)
    }

    private func percentFontSize(for density: LabelDensity) -> CGFloat {
        switch density {
        case .full:
            10
        case .stacked:
            9
        case .compact:
            7.5
        }
    }

    private func blockFill(for item: PortfolioAllocationItem) -> LinearGradient {
        LinearGradient(
            colors: [
                item.color.opacity(colorScheme == .dark ? 0.96 : 0.90),
                item.color.opacity(colorScheme == .dark ? 0.70 : 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

}

private struct PortfolioTreemapHoverWindowBridge: NSViewRepresentable {
    let item: PortfolioAllocationItem?
    let location: CGPoint?
    let chartSize: CGSize
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(
            item: item,
            location: location,
            chartSize: chartSize,
            colorScheme: colorScheme,
            anchorView: view
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var panel: NSPanel?
        private var hostingView: NSHostingView<AnyView>?
        private var lastItemID: String?
        private var lastLocation: CGPoint?

        private let contentSize = CGSize(width: 238, height: 156)
        private let shadowMargin: CGFloat = 22
        private let gap: CGFloat = 14

        @MainActor
        func update(
            item: PortfolioAllocationItem?,
            location: CGPoint?,
            chartSize: CGSize,
            colorScheme: ColorScheme,
            anchorView: NSView
        ) {
            guard let item, let location, chartSize.width > 0, chartSize.height > 0 else {
                close()
                return
            }

            let movementThreshold: CGFloat = 6
            if lastItemID == item.id,
               let lastLocation,
               hypot(lastLocation.x - location.x, lastLocation.y - location.y) < movementThreshold {
                return
            }

            lastItemID = item.id
            lastLocation = location

            let panel = ensurePanel()
            let content = PortfolioTreemapTooltipWindowContent(
                item: item,
                colorScheme: colorScheme
            )
            .padding(shadowMargin)
            .frame(
                width: contentSize.width + shadowMargin * 2,
                height: contentSize.height + shadowMargin * 2
            )

            if let hostingView {
                hostingView.rootView = AnyView(content)
            } else {
                let hostingView = NSHostingView(rootView: AnyView(content))
                hostingView.frame = NSRect(
                    origin: .zero,
                    size: NSSize(
                        width: contentSize.width + shadowMargin * 2,
                        height: contentSize.height + shadowMargin * 2
                    )
                )
                hostingView.autoresizingMask = [.width, .height]
                panel.contentView = hostingView
                self.hostingView = hostingView
            }

            guard let frame = frame(for: location, chartSize: chartSize, anchorView: anchorView) else {
                close()
                return
            }
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }

        @MainActor
        func close() {
            panel?.orderOut(nil)
            lastItemID = nil
            lastLocation = nil
        }

        @MainActor
        private func ensurePanel() -> NSPanel {
            if let panel {
                return panel
            }

            let windowSize = NSSize(
                width: contentSize.width + shadowMargin * 2,
                height: contentSize.height + shadowMargin * 2
            )
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            self.panel = panel
            return panel
        }

        @MainActor
        private func frame(for location: CGPoint, chartSize: CGSize, anchorView: NSView) -> NSRect? {
            let panelSize = NSSize(
                width: contentSize.width + shadowMargin * 2,
                height: contentSize.height + shadowMargin * 2
            )
            guard let screenPoint = screenPoint(for: location, in: anchorView) else {
                return nil
            }
            let horizontalDirection: CGFloat = location.x > chartSize.width * 0.58 ? -1 : 1
            let verticalDirection: CGFloat = location.y > chartSize.height * 0.55 ? -1 : 1
            let center = CGPoint(
                x: screenPoint.x + horizontalDirection * (contentSize.width / 2 + gap),
                y: screenPoint.y - verticalDirection * (contentSize.height / 2 + gap)
            )
            var frame = NSRect(
                x: center.x - panelSize.width / 2,
                y: center.y - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            )

            if let visibleFrame = screen(for: frame)?.visibleFrame {
                let inset: CGFloat = 8
                frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + inset), visibleFrame.maxX - frame.width - inset)
                frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + inset), visibleFrame.maxY - frame.height - inset)
            }
            return frame
        }

        @MainActor
        private func screenPoint(for location: CGPoint, in anchorView: NSView) -> CGPoint? {
            guard let window = anchorView.window else {
                return nil
            }
            let localPoint = NSPoint(x: location.x, y: anchorView.bounds.height - location.y)
            let windowPoint = anchorView.convert(localPoint, to: nil)
            return window.convertPoint(toScreen: windowPoint)
        }

        @MainActor
        private func screen(for frame: NSRect) -> NSScreen? {
            NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        }
    }
}

private struct PortfolioTreemapTooltipWindowContent: View {
    let item: PortfolioAllocationItem
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.color)
                    .frame(width: 7, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.fund.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(FundCodeFormatter.display(item.fund.code))
                        Text("第\(item.rank)大持仓")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 7
            ) {
                tooltipMetric("持仓占比", MoneyFormatter.percent(item.share * 100), color: item.color)
                tooltipMetric("持仓金额", MoneyFormatter.plainMoney(item.amount), color: .primary)
                tooltipMetric("今日涨幅", MoneyFormatter.percent(item.fund.todayRate, signed: true), color: toneColor(for: item.fund.todayRate))
                tooltipMetric("今日收益", MoneyFormatter.money(item.fund.todayIncome, signed: true), color: toneColor(for: item.fund.todayIncome))
                tooltipMetric(
                    "持有收益",
                    MoneyFormatter.money(PortfolioPanelDisplay.holdingIncome(for: item.fund), signed: true),
                    color: toneColor(for: PortfolioPanelDisplay.holdingIncome(for: item.fund))
                )
                tooltipMetric(
                    "持有收益率",
                    item.fund.holdingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "--",
                    color: item.fund.holdingRate.map(toneColor(for:)) ?? .secondary
                )
            }
        }
        .padding(11)
        .frame(width: 238, height: 156, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tooltipBaseColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tooltipAccentOverlay)
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.color.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.17), radius: 14, x: 0, y: 8)
    }

    private func tooltipMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var tooltipBaseColor: Color {
        colorScheme == .dark
            ? Color(red: 26 / 255, green: 29 / 255, blue: 35 / 255).opacity(0.99)
            : Color(nsColor: .windowBackgroundColor).opacity(0.99)
    }

    private var tooltipAccentOverlay: LinearGradient {
        LinearGradient(
            colors: [
                item.color.opacity(colorScheme == .dark ? 0.10 : 0.055),
                item.color.opacity(colorScheme == .dark ? 0.05 : 0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PortfolioAllocationPanelView: View {
    let store: PortfolioStore
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "square.grid.3x3.fill",
                title: "持仓占比",
                subtitle: allocationHeaderSubtitle,
                subtitleWeight: .semibold,
                tint: Color(nsColor: .systemBlue),
                onClose: onClose
            )

            ScrollView {
                if allocationItems.isEmpty {
                    ContentUnavailableView("暂无持仓占比", systemImage: "chart.pie")
                        .frame(height: 420)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        allocationSummary
                        allocationChartSection
                        allocationBreakdownList
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
    }

    private var allocationItems: [PortfolioAllocationItem] {
        let funds = PortfolioPanelDisplay.holdingFunds(in: store.snapshot)
            .sorted {
                let lhsAmount = PortfolioPanelDisplay.currentAmount(for: $0)
                let rhsAmount = PortfolioPanelDisplay.currentAmount(for: $1)
                if lhsAmount != rhsAmount {
                    return lhsAmount > rhsAmount
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        let total = funds.reduce(0) { $0 + PortfolioPanelDisplay.currentAmount(for: $1) }
        guard total > 0 else { return [] }

        return funds.enumerated().map { index, fund in
            let amount = PortfolioPanelDisplay.currentAmount(for: fund)
            return PortfolioAllocationItem(
                rank: index + 1,
                fund: fund,
                amount: amount,
                share: amount / total,
                color: PortfolioPanelDisplay.allocationPalette[index % PortfolioPanelDisplay.allocationPalette.count]
            )
        }
    }

    private var allocationTotal: Double {
        allocationItems.reduce(0) { $0 + $1.amount }
    }

    private var allocationHeaderSubtitle: String {
        guard !allocationItems.isEmpty else { return "暂无持仓基金" }
        return "\(allocationItems.count)只基金 · \(MoneyFormatter.plainMoney(allocationTotal))"
    }

    private var largestAllocationText: String {
        allocationItems.first.map { MoneyFormatter.percent($0.share * 100) } ?? "--"
    }

    private var allocationSummary: some View {
        HStack(spacing: 0) {
            allocationSummaryMetric("持仓总额", MoneyFormatter.plainMoney(allocationTotal), color: .primary)
            summaryDivider
            allocationSummaryMetric("基金数量", "\(allocationItems.count)只", color: .primary)
            summaryDivider
            allocationSummaryMetric("最大占比", largestAllocationText, color: allocationItems.first?.color ?? .secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var allocationChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelSectionTitle("持仓方块图")
            PortfolioTreemapChart(items: allocationItems)
                .frame(height: 190)
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var allocationBreakdownList: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelSectionTitle("占比明细")
            VStack(spacing: 7) {
                ForEach(allocationItems) { item in
                    allocationRow(item)
                }
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func allocationSummaryMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.30 : 0.22))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 10)
    }

    private func allocationRow(_ item: PortfolioAllocationItem) -> some View {
        HStack(spacing: 10) {
            rankBadge(item.rank, color: item.color)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.fund.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(FundCodeFormatter.display(item.fund.code))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                allocationBar(item)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(MoneyFormatter.percent(item.share * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.color)
                Text(MoneyFormatter.plainMoney(item.amount))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(item.color.opacity(colorScheme == .dark ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func allocationBar(_ item: PortfolioAllocationItem) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055))
                Capsule()
                    .fill(item.color.opacity(colorScheme == .dark ? 0.86 : 0.74))
                    .frame(width: max(proxy.size.width * item.share, 3))
            }
        }
        .frame(height: 6)
    }

    private func rankBadge(_ rank: Int, color: Color) -> some View {
        Text("\(rank)")
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(colorScheme == .dark ? 0.16 : 0.10), in: Circle())
            .overlay(Circle().stroke(color.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 0.7))
    }

    private func panelSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
    }
}

private struct TodayIncomeRankItem: Identifiable {
    let rank: Int
    let fund: FundPosition

    var id: String { fund.code }
}

private enum TodayIncomeRankingMode: String, CaseIterable, Identifiable {
    case gain
    case loss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gain:
            "涨幅榜"
        case .loss:
            "跌幅榜"
        }
    }

    var emptyTitle: String {
        switch self {
        case .gain:
            "暂无上涨基金"
        case .loss:
            "暂无下跌基金"
        }
    }

    var summaryTitle: String {
        switch self {
        case .gain:
            "上涨合计"
        case .loss:
            "下跌合计"
        }
    }

    var tint: Color {
        switch self {
        case .gain:
            Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255)
        case .loss:
            Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255)
        }
    }
}

enum IncomeRankingKind {
    case today
    case holding

    func title(for metric: IncomeRankingMetric) -> String {
        switch self {
        case .today where metric == .amount:
            return "实时收益排行"
        case .today:
            return "实时收益率排行"
        case .holding where metric == .amount:
            return "持有收益排行"
        case .holding:
            return "持有收益率排行"
        }
    }

    var unavailableTitle: String {
        switch self {
        case .today:
            "暂无实时收益"
        case .holding:
            "暂无持有收益"
        }
    }

    var unavailableSystemImage: String {
        switch self {
        case .today:
            "chart.line.uptrend.xyaxis"
        case .holding:
            "chart.bar.xaxis"
        }
    }

    func gainTitle(for metric: IncomeRankingMetric) -> String {
        metric == .amount ? "收益榜" : "涨幅榜"
    }

    func lossTitle(for metric: IncomeRankingMetric) -> String {
        metric == .amount ? "亏损榜" : "跌幅榜"
    }

    var gainEmptyTitle: String {
        switch self {
        case .today:
            "暂无上涨基金"
        case .holding:
            "暂无盈利基金"
        }
    }

    var lossEmptyTitle: String {
        switch self {
        case .today:
            "暂无下跌基金"
        case .holding:
            "暂无亏损基金"
        }
    }

    var gainSummaryTitle: String {
        switch self {
        case .today:
            "涨"
        case .holding:
            "盈"
        }
    }

    var lossSummaryTitle: String {
        switch self {
        case .today:
            "跌"
        case .holding:
            "亏"
        }
    }
}

enum IncomeRankingMetric {
    case amount
    case rate
}

private struct TodayIncomeRankPalette {
    let foreground: Color
    let deep: Color
    let background: Color
    let border: Color
}

private struct TodayIncomeRankMedalPalette {
    let foreground: Color
    let deep: Color
    let light: Color
    let border: Color
}

struct TodayIncomeRankingPanelView: View {
    let store: PortfolioStore
    let kind: IncomeRankingKind
    let metric: IncomeRankingMetric
    let onClose: () -> Void

    @State private var rankingMode: TodayIncomeRankingMode = .gain
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "list.number",
                title: kind.title(for: metric),
                subtitle: rankingHeaderSubtitle,
                subtitleWeight: .semibold,
                tint: toneColor(for: totalValue),
                accessoryText: updatedHeaderTagText,
                accessoryColor: .orange,
                onClose: onClose
            )

            ScrollView {
                if rankableFunds.isEmpty {
                    ContentUnavailableView(kind.unavailableTitle, systemImage: kind.unavailableSystemImage)
                        .frame(height: 420)
                } else {
                    LazyVStack(spacing: 10) {
                        rankingSummary
                        rankingModePicker
                        if rankingItems.isEmpty {
                            ContentUnavailableView(emptyTitle(for: rankingMode), systemImage: rankingMode == .gain ? "arrow.up.right" : "arrow.down.right")
                                .frame(height: 260)
                        } else {
                            ForEach(rankingItems) { item in
                                rankingRow(item)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
    }

    private var rankableFunds: [FundPosition] {
        store.snapshot.funds.filter { fund in
            switch kind {
            case .today:
                !fund.status.isPendingDisplay && (fund.isIncomeActive ?? true)
            case .holding:
                fund.status == .holding && (fund.isIncomeActive ?? true)
            }
        }
    }

    private var rankingItems: [TodayIncomeRankItem] {
        let funds = rankableFunds
            .filter { fund in
                switch rankingMode {
                case .gain:
                    rankingValue(for: fund) > 0
                case .loss:
                    rankingValue(for: fund) < 0
                }
            }
            .sorted { lhs, rhs in
                let lhsValue = rankingValue(for: lhs)
                let rhsValue = rankingValue(for: rhs)
                if lhsValue != rhsValue {
                    return rankingMode == .gain ? lhsValue > rhsValue : lhsValue < rhsValue
                }
                let lhsTieValue = tieBreakValue(for: lhs)
                let rhsTieValue = tieBreakValue(for: rhs)
                if lhsTieValue != rhsTieValue {
                    return rankingMode == .gain ? lhsTieValue > rhsTieValue : lhsTieValue < rhsTieValue
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return funds.enumerated().map { index, fund in
            TodayIncomeRankItem(rank: index + 1, fund: fund)
        }
    }

    private var updatedFundsCount: Int {
        rankingItems.filter { $0.fund.isUpdated }.count
    }

    private var rankingHeaderSubtitle: String {
        guard !rankableFunds.isEmpty else { return "暂无持仓基金" }
        return "\(rankableFunds.count)只基金 · \(summaryValueText(totalValue))"
    }

    private var updatedHeaderTagText: String? {
        let updatedCount = rankableFunds.filter { $0.isUpdated }.count
        guard updatedCount > 0 else { return nil }
        if updatedCount == rankableFunds.count {
            return "全部已更新"
        }
        return "\(updatedCount)只已更新"
    }

    private var rankingModePicker: some View {
        PanelSegmentedPicker(
            values: TodayIncomeRankingMode.allCases,
            selection: $rankingMode,
            title: { title(for: $0) },
            tint: rankingMode.tint
        )
    }

    private var gainFunds: [FundPosition] {
        rankableFunds.filter { rankingValue(for: $0) > 0 }
    }

    private var lossFunds: [FundPosition] {
        rankableFunds.filter { rankingValue(for: $0) < 0 }
    }

    private var gainSummaryValue: Double {
        summaryGroupValue(for: gainFunds)
    }

    private var lossSummaryValue: Double {
        summaryGroupValue(for: lossFunds)
    }

    private var totalValue: Double {
        switch kind {
        case .today where metric == .amount:
            store.snapshot.todayIncome
        case .today:
            store.snapshot.todayIncomeRate
        case .holding where metric == .amount:
            store.snapshot.holdingIncome
        case .holding:
            store.snapshot.holdingIncomeRate
        }
    }

    private func rankingValue(for fund: FundPosition) -> Double {
        switch metric {
        case .amount:
            income(for: fund)
        case .rate:
            rate(for: fund)
        }
    }

    private func tieBreakValue(for fund: FundPosition) -> Double {
        switch metric {
        case .amount:
            rate(for: fund)
        case .rate:
            income(for: fund)
        }
    }

    private func income(for fund: FundPosition) -> Double {
        switch kind {
        case .today:
            return fund.todayIncome
        case .holding:
            if let holdingIncome = fund.holdingIncome {
                return holdingIncome
            }
            guard let holdingRate = fund.holdingRate else { return 0 }
            return principal(for: fund) * holdingRate / 100
        }
    }

    private func rate(for fund: FundPosition) -> Double {
        switch kind {
        case .today:
            fund.todayRate
        case .holding:
            fund.holdingRate ?? 0
        }
    }

    private func principal(for fund: FundPosition) -> Double {
        if let migratedPrincipal = fund.migratedPrincipal {
            return migratedPrincipal
        }
        guard let shares = fund.migratedShares,
              let cost = fund.migratedCost
        else {
            return 0
        }
        return shares * cost
    }

    private func title(for mode: TodayIncomeRankingMode) -> String {
        switch mode {
        case .gain:
            kind.gainTitle(for: metric)
        case .loss:
            kind.lossTitle(for: metric)
        }
    }

    private func emptyTitle(for mode: TodayIncomeRankingMode) -> String {
        switch mode {
        case .gain:
            kind.gainEmptyTitle
        case .loss:
            kind.lossEmptyTitle
        }
    }

    private var rankingSummary: some View {
        HStack(spacing: 0) {
            rankingSummaryMetric(
                "合计",
                summaryValueText(totalValue),
                tone: totalValue,
                footnote: "\(rankableFunds.count)只"
            )
            summaryDivider
            rankingSummaryMetric(
                kind.gainSummaryTitle,
                summaryValueText(gainSummaryValue),
                tone: gainSummaryValue,
                footnote: "\(gainFunds.count)只"
            )
            summaryDivider
            rankingSummaryMetric(
                kind.lossSummaryTitle,
                summaryValueText(lossSummaryValue),
                tone: lossSummaryValue,
                footnote: "\(lossFunds.count)只"
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func summaryGroupValue(for funds: [FundPosition]) -> Double {
        guard !funds.isEmpty else { return 0 }
        switch metric {
        case .amount:
            return funds.reduce(0) { $0 + income(for: $1) }
        case .rate:
            return funds.reduce(0) { $0 + rate(for: $1) } / Double(funds.count)
        }
    }

    private func summaryValueText(_ value: Double) -> String {
        switch metric {
        case .amount:
            MoneyFormatter.money(value, signed: true)
        case .rate:
            MoneyFormatter.percent(value, signed: true)
        }
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.30 : 0.22))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 10)
    }

    private func rankingSummaryMetric(_ title: String, _ value: String, tone: Double?, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(footnote)
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone.map(toneColor(for:)) ?? Color.secondary)
                    .padding(.horizontal, 4)
                    .frame(height: 13)
                    .background((tone.map(toneColor(for:)) ?? Color.secondary).opacity(colorScheme == .dark ? 0.14 : 0.08), in: Capsule())
            }
            .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankingRow(_ item: TodayIncomeRankItem) -> some View {
        let isTopRank = item.rank <= 3
        let palette = rankPalette(for: item)
        return HStack(spacing: 10) {
            rankBadge(for: item)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.fund.name)
                        .font(.system(size: isTopRank ? 12.5 : 12, weight: .semibold))
                        .lineLimit(1)
                    if item.fund.isUpdated {
                        updatedTag
                    }
                }

                HStack(spacing: 7) {
                    Text(FundCodeFormatter.display(item.fund.code))
                        .fontWeight(.semibold)
                    Text(item.fund.dateText)
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(primaryValueText(for: item.fund))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .foregroundStyle(palette.foreground)
                Text(secondaryValueText(for: item.fund))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 6)
                    .frame(height: 19)
                    .background(palette.foreground.opacity(colorScheme == .dark ? 0.18 : 0.10), in: Capsule())
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, isTopRank ? 12 : 10)
        .frame(minHeight: isTopRank ? 70 : 62)
        .background(rowBackground(for: item), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(rowBorder(for: item))
        .shadow(
            color: item.rank <= 3 ? palette.foreground.opacity(colorScheme == .dark ? 0.22 : 0.14) : .clear,
            radius: item.rank <= 3 ? 8 : 0,
            x: 0,
            y: item.rank <= 3 ? 3 : 0
        )
    }

    private func primaryValueText(for fund: FundPosition) -> String {
        switch metric {
        case .amount:
            MoneyFormatter.money(income(for: fund), signed: true)
        case .rate:
            MoneyFormatter.percent(rate(for: fund), signed: true)
        }
    }

    private func secondaryValueText(for fund: FundPosition) -> String {
        switch metric {
        case .amount:
            MoneyFormatter.percent(rate(for: fund), signed: true)
        case .rate:
            MoneyFormatter.money(income(for: fund), signed: true)
        }
    }

    private func rankBadge(for item: TodayIncomeRankItem) -> some View {
        let rank = item.rank
        let palette = rankPalette(for: item)
        if rank <= 3 {
            let medal = medalPalette(for: rank)
            return AnyView(
                VStack(spacing: 1) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("\(rank)")
                        .font(.system(size: 15, weight: .heavy))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.white)
                .shadow(color: medal.deep.opacity(0.30), radius: 1.5, x: 0, y: 0.8)
                .frame(width: 38, height: 38)
                .background(
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        medal.light.opacity(colorScheme == .dark ? 0.78 : 0.96),
                                        medal.foreground.opacity(colorScheme == .dark ? 0.88 : 0.94),
                                        medal.deep.opacity(colorScheme == .dark ? 0.82 : 0.90)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.54), lineWidth: 1.0)
                            .padding(2.5)
                    }
                )
                .overlay(Circle().stroke(medal.border.opacity(colorScheme == .dark ? 0.52 : 0.72), lineWidth: 0.9))
                .shadow(color: medal.deep.opacity(colorScheme == .dark ? 0.24 : 0.16), radius: 6, x: 0, y: 2)
            )
        }

        return AnyView(
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.foreground)
                .frame(width: 28, height: 28)
                .background(circleBackground(for: palette), in: Circle())
                .overlay(Circle().stroke(borderColor(for: palette, isTopRank: false), lineWidth: 0.75))
        )
    }

    private var updatedTag: some View {
        Text("已更新")
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.orange.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 0.6)
            )
    }

    private func rowBackground(for item: TodayIncomeRankItem) -> some ShapeStyle {
        let palette = rankPalette(for: item)
        if item.rank <= 3 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        cardBackgroundColor(for: palette, isTopRank: true),
                        palette.foreground.opacity(colorScheme == .dark ? 0.18 : 0.095),
                        PanelDesign.cardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    cardBackgroundColor(for: palette, isTopRank: false),
                    PanelDesign.cardBackground
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func rowBorder(for item: TodayIncomeRankItem) -> some View {
        let palette = rankPalette(for: item)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                borderColor(for: palette, isTopRank: item.rank <= 3),
                lineWidth: item.rank <= 3 ? 1.05 : 0.75
            )
    }

    private func rankPalette(for item: TodayIncomeRankItem) -> TodayIncomeRankPalette {
        let isLoss = rankingMode == .loss
        switch item.rank {
        case 1:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255),
                    deep: Color(red: 3 / 255, green: 84 / 255, blue: 63 / 255),
                    background: Color(red: 220 / 255, green: 252 / 255, blue: 231 / 255),
                    border: Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 166 / 255, green: 31 / 255, blue: 23 / 255),
                    deep: Color(red: 122 / 255, green: 28 / 255, blue: 20 / 255),
                    background: Color(red: 255 / 255, green: 224 / 255, blue: 219 / 255),
                    border: Color(red: 240 / 255, green: 68 / 255, blue: 56 / 255)
                )
        case 2:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255),
                    deep: Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255),
                    background: Color(red: 229 / 255, green: 253 / 255, blue: 237 / 255),
                    border: Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255),
                    deep: Color(red: 166 / 255, green: 31 / 255, blue: 23 / 255),
                    background: Color(red: 255 / 255, green: 234 / 255, blue: 228 / 255),
                    border: Color(red: 249 / 255, green: 112 / 255, blue: 102 / 255)
                )
        case 3:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 18 / 255, green: 183 / 255, blue: 106 / 255),
                    deep: Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255),
                    background: Color(red: 237 / 255, green: 253 / 255, blue: 243 / 255),
                    border: Color(red: 167 / 255, green: 243 / 255, blue: 208 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255),
                    deep: Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255),
                    background: Color(red: 255 / 255, green: 241 / 255, blue: 236 / 255),
                    border: Color(red: 253 / 255, green: 162 / 255, blue: 155 / 255)
                )
        default:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255),
                    deep: Color(red: 18 / 255, green: 183 / 255, blue: 106 / 255),
                    background: Color(red: 240 / 255, green: 253 / 255, blue: 244 / 255),
                    border: Color(red: 187 / 255, green: 247 / 255, blue: 208 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 239 / 255, green: 96 / 255, blue: 87 / 255),
                    deep: Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255),
                    background: Color(red: 255 / 255, green: 245 / 255, blue: 243 / 255),
                    border: Color(red: 254 / 255, green: 205 / 255, blue: 202 / 255)
                )
        }
    }

    private func cardBackgroundColor(for palette: TodayIncomeRankPalette, isTopRank: Bool) -> Color {
        if colorScheme == .dark {
            return palette.foreground.opacity(isTopRank ? 0.28 : 0.16)
        }
        return isTopRank ? palette.background : palette.background.opacity(0.86)
    }

    private func circleBackground(for palette: TodayIncomeRankPalette) -> Color {
        colorScheme == .dark ? palette.foreground.opacity(0.20) : palette.background
    }

    private func borderColor(for palette: TodayIncomeRankPalette, isTopRank: Bool) -> Color {
        if colorScheme == .dark {
            return palette.foreground.opacity(isTopRank ? 0.54 : 0.32)
        }
        return isTopRank ? palette.border.opacity(0.88) : palette.border.opacity(0.72)
    }

    private func medalPalette(for rank: Int) -> TodayIncomeRankMedalPalette {
        switch rank {
        case 1:
            return TodayIncomeRankMedalPalette(
                foreground: Color(red: 228 / 255, green: 163 / 255, blue: 45 / 255),
                deep: Color(red: 169 / 255, green: 101 / 255, blue: 20 / 255),
                light: Color(red: 255 / 255, green: 223 / 255, blue: 112 / 255),
                border: Color(red: 217 / 255, green: 157 / 255, blue: 45 / 255)
            )
        case 2:
            return TodayIncomeRankMedalPalette(
                foreground: Color(red: 147 / 255, green: 158 / 255, blue: 171 / 255),
                deep: Color(red: 96 / 255, green: 110 / 255, blue: 128 / 255),
                light: Color(red: 234 / 255, green: 238 / 255, blue: 243 / 255),
                border: Color(red: 157 / 255, green: 168 / 255, blue: 183 / 255)
            )
        case 3:
            return TodayIncomeRankMedalPalette(
                foreground: Color(red: 190 / 255, green: 111 / 255, blue: 52 / 255),
                deep: Color(red: 139 / 255, green: 73 / 255, blue: 36 / 255),
                light: Color(red: 242 / 255, green: 181 / 255, blue: 118 / 255),
                border: Color(red: 192 / 255, green: 112 / 255, blue: 56 / 255)
            )
        default:
            return TodayIncomeRankMedalPalette(
                foreground: .secondary,
                deep: .secondary,
                light: .secondary,
                border: .secondary
            )
        }
    }
}

private struct PendingTradeActivityRow: View {
    let activity: PendingTradeActivity
    let isSelected: Bool
    let onDelete: (() -> Void)?
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onOpen) {
                rowContent
            }
            .buttonStyle(.plain)
            .focusable(false)

            if let onDelete {
                deleteButton(action: onDelete)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: rowMinHeight)
        .background(selectionBackground)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accentColor)
                .frame(width: 3, height: selectionBarHeight)
                .opacity(isSelected ? 1 : 0)
                .padding(.leading, 4)
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            leftColumn
            Spacer(minLength: 6)
            amountColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            tagRow
            titleBlock
            metaContent
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            tag(kindTagTitle, color: kindTagColor)
            tag("待确认", color: .orange)
        }
    }

    private var amountColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(primaryValueText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            Text(valueCaption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 98, alignment: .trailing)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 24, height: 24)
                .background(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(activity.isConversion ? "删除这笔转换待确认记录" : "删除这笔待确认记录")
    }

    private var rowMinHeight: CGFloat {
        activity.isConversion ? 118 : 74
    }

    private var verticalPadding: CGFloat {
        activity.isConversion ? 9 : 6
    }

    private var selectionBarHeight: CGFloat {
        activity.isConversion ? 80 : 46
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let route = conversionRoute {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.sourceName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(kindTagColor)
                    .frame(height: 10)
                    .accessibilityHidden(true)
                Text(route.targetName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 14, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(titleText)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var metaContent: some View {
        if let route = conversionRoute {
            Text(conversionMetaText(route))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
        } else {
            Text(plainTradeMetaText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
        }
    }

    private var accentColor: Color {
        switch activity.kind {
        case .sell, .conversionOut:
            .fundPulseGreen
        case .newFund, .buy, .conversionIn:
            .red
        }
    }

    private var kindTagColor: Color {
        if activity.isConversion {
            return Color.orange
        }
        if activity.kind == .newFund {
            return .blue
        }
        return accentColor
    }

    private var kindTagTitle: String {
        if activity.isConversion {
            return "转换"
        }
        if activity.kind == .newFund {
            return "新增"
        }
        return activity.kind.title
    }

    private var titleText: String {
        guard let route = conversionRoute else {
            return activity.name
        }
        return "\(route.sourceName)\n→ \(route.targetName)"
    }

    private var valueCaption: String {
        guard activity.isConversion else {
            return activity.mode.title
        }
        switch activity.displayAmount?.source {
        case .estimatedNetValue, .latestNetValue:
            return "估算金额"
        case .confirmedNetValue:
            return "确认金额"
        case .enteredAmount, nil:
            return "金额"
        }
    }

    private var conversionSharesText: String? {
        let shares = activity.shares ?? activity.displayAmount?.shares
        guard let shares, shares > 0 else { return nil }
        return "\(numberText(shares, places: 2))份"
    }

    private var plainTradeMetaText: String {
        let tradeDate = shortDateText(activity.tradeDate)
        let acceptedDate = shortDateText(activity.acceptedDate)
        let prefix = "\(FundCodeFormatter.display(activity.code)) · \(tradeDate) \(activity.tradeTimeType.title)"
        guard acceptedDate != tradeDate else {
            return "\(prefix)确认"
        }
        return "\(prefix) · 确认 \(acceptedDate)"
    }

    private func conversionMetaText(_ route: (sourceName: String, sourceCode: String, targetName: String, targetCode: String)) -> String {
        let routeText = "\(FundCodeFormatter.display(route.sourceCode)) → \(FundCodeFormatter.display(route.targetCode))"
        guard let conversionSharesText else {
            return routeText
        }
        return "\(routeText) · \(conversionSharesText)"
    }

    private var conversionRoute: (sourceName: String, sourceCode: String, targetName: String, targetCode: String)? {
        guard activity.isConversion else { return nil }
        let currentName = clean(activity.name) ?? FundCodeFormatter.display(activity.code)
        let currentCode = clean(activity.code) ?? activity.code
        let linkedCode = clean(activity.linkedCode) ?? "--"
        let linkedName = clean(activity.linkedName) ?? FundCodeFormatter.display(linkedCode)

        if activity.kind == .conversionIn {
            return (
                sourceName: linkedName,
                sourceCode: linkedCode,
                targetName: currentName,
                targetCode: currentCode
            )
        }
        return (
            sourceName: currentName,
            sourceCode: currentCode,
            targetName: linkedName,
            targetCode: linkedCode
        )
    }

    private var selectionBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
                    : Color.clear
            )
    }

    private var primaryValueText: String {
        guard let displayAmount = activity.displayAmount else {
            return "--"
        }
        return MoneyFormatter.plainMoney(displayAmount.value)
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .fixedSize()
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shortDateText(_ value: String) -> String {
        guard value.count >= 10 else { return value }
        return String(value.dropFirst(5).prefix(5))
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }
}

struct FundRowView: View {
    let fund: FundPosition
    let isSelected: Bool
    let isClosedZeroPosition: Bool
    let masksAmounts: Bool
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            summaryRow
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(fund.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    tag(statusTagTitle, color: statusTagColor)
                    if !isClosedZeroPosition && fund.status == .holding {
                        tag(rowHoldingRateText, color: toneColor(for: rowHoldingRate ?? rowConfirmedHoldingIncome))
                    }
                }

                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        if showsUpdateStar {
                            updatedInlineTag
                        }
                        Text(FundCodeFormatter.display(fund.code))
                            .fontWeight(.semibold)
                            .foregroundStyle(codeTextColor)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if showsUpdateStar {
                            updateStar
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                    Text(rowHoldingAmountText)
                        .foregroundStyle(amountTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.leading, showsUpdateStar ? 5 : 2)
                    Text(rowConfirmedHoldingIncomeText)
                        .foregroundStyle(toneColor(for: rowConfirmedHoldingIncome))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(MoneyFormatter.percent(fund.todayRate, signed: true))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(minWidth: 60, minHeight: 24)
                .background(rateBadgeBackground(fund.todayRate), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(rateBadgeBorderColor(fund.todayRate), lineWidth: 1.1)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.28), lineWidth: 0.8)
                        .blendMode(.plusLighter)
                }
                .shadow(color: toneColor(for: fund.todayRate).opacity(fund.todayRate == 0 ? 0 : 0.24), radius: 7, x: 0, y: 3)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(selectionBackground)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(selectionAccent)
                .frame(width: 3, height: 34)
                .opacity(isSelected ? 1 : 0)
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
    }

    private var selectionAccent: Color {
        toneColor(for: fund.todayRate)
    }

    private var selectionBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? selectionAccent.opacity(colorScheme == .dark ? 0.16 : 0.10)
                    : Color.clear
            )
    }

    private var updateStarColor: Color {
        Color(nsColor: StatusBarTone.menuBarColor(forRate: fund.todayRate))
    }

    private var updatedTagColor: Color {
        Color(red: 239 / 255, green: 168 / 255, blue: 36 / 255)
    }

    private var codeTextColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.72 : 0.58)
    }

    private var amountTextColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.92 : 0.78)
    }

    private var updateStar: some View {
        UpdatedFundStarShape()
            .fill(updateStarColor)
            .frame(width: 10.4, height: 10.4)
            .frame(width: 11, height: 14, alignment: .center)
            .shadow(color: updateStarColor.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 2, x: 0, y: 1)
            .accessibilityLabel("净值已更新")
    }

    private var updatedInlineTag: some View {
        Text("已更新")
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(updatedTagColor)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(updatedTagColor.opacity(colorScheme == .dark ? 0.20 : 0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(updatedTagColor.opacity(colorScheme == .dark ? 0.38 : 0.26), lineWidth: 0.6)
            )
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("已更新")
    }

    private var showsUpdateStar: Bool {
        fund.isUpdated
    }

    private var statusTagTitle: String {
        isClosedZeroPosition ? "已清仓" : fund.status.title
    }

    private var statusTagColor: Color {
        if isClosedZeroPosition {
            return .secondary
        }
        return fund.status.isPendingDisplay ? .orange : .blue
    }

    private var rowHoldingIncome: Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else {
            return 0
        }
        return principal * holdingRate / 100
    }

    private var rowConfirmedHoldingIncome: Double {
        if let confirmedHoldingIncome = fund.confirmedHoldingIncome {
            return confirmedHoldingIncome
        }
        guard let confirmedHoldingRate = fund.confirmedHoldingRate else {
            return rowHoldingIncome
        }
        return principal * confirmedHoldingRate / 100
    }

    private var rowHoldingRate: Double? {
        fund.confirmedHoldingRate ?? fund.holdingRate
    }

    private var rowHoldingRateText: String {
        rowHoldingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "0.00%"
    }

    private var rowHoldingAmountText: String {
        FundRowAmountPrivacyFormatter.plainMoney(rowHoldingAmount, isMasked: masksAmounts)
    }

    private var rowConfirmedHoldingIncomeText: String {
        FundRowAmountPrivacyFormatter.signedCompactMoney(rowConfirmedHoldingIncome, isMasked: masksAmounts)
    }

    private var rowHoldingAmount: Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        return principal + rowHoldingIncome
    }

    private var principal: Double {
        if let migratedPrincipal = fund.migratedPrincipal {
            return migratedPrincipal
        }
        guard let shares = fund.migratedShares,
              let cost = fund.migratedCost
        else {
            return 0
        }
        return shares * cost
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.6)
            )
    }

    private func rateBadgeBackground(_ value: Double) -> AnyShapeStyle {
        if value == 0 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.secondary.opacity(colorScheme == .dark ? 0.48 : 0.54),
                        Color.secondary.opacity(colorScheme == .dark ? 0.34 : 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        let color = toneColor(for: value)
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    color.opacity(colorScheme == .dark ? 0.98 : 0.93),
                    color.opacity(colorScheme == .dark ? 0.76 : 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func rateBadgeBorderColor(_ value: Double) -> Color {
        if value == 0 {
            return Color.primary.opacity(colorScheme == .dark ? 0.30 : 0.22)
        }

        return toneColor(for: value).opacity(colorScheme == .dark ? 0.76 : 0.60)
    }
}

private struct UpdatedFundStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.56
        let points = (0..<10).map { index in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        var path = Path()

        for index in points.indices {
            let current = points[index]
            let previous = points[(index + points.count - 1) % points.count]
            let next = points[(index + 1) % points.count]
            let cornerLength = index.isMultiple(of: 2) ? outerRadius * 0.18 : outerRadius * 0.12
            let start = point(from: current, toward: previous, distance: cornerLength)
            let end = point(from: current, toward: next, distance: cornerLength)

            if index == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }
            path.addQuadCurve(to: end, control: current)
        }

        path.closeSubpath()
        return path
    }

    private func point(from start: CGPoint, toward end: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let scale = min(distance / length, 0.45)
        return CGPoint(x: start.x + dx * scale, y: start.y + dy * scale)
    }
}

private enum FundDetailTrendTab: String, CaseIterable, Identifiable {
    case intraday
    case netValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intraday:
            "盘中预估实时涨跌"
        case .netValue:
            "净值业绩走势"
        }
    }
}

private enum FundNetValueTrendRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case threeYears

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth:
            "近1月"
        case .threeMonths:
            "近3月"
        case .sixMonths:
            "近6月"
        case .oneYear:
            "近1年"
        case .threeYears:
            "近3年"
        }
    }

    var months: Int {
        switch self {
        case .oneMonth:
            1
        case .threeMonths:
            3
        case .sixMonths:
            6
        case .oneYear:
            12
        case .threeYears:
            36
        }
    }
}

private struct FundDailyIncomeDisplayRow: Identifiable {
    let id: String
    let dateText: String
    let amount: Double
}

struct FundDailyIncomePanelView: View {
    let store: PortfolioStore
    private let initialFund: FundPosition
    let onClose: () -> Void

    @State private var supplement: FundDetailSupplement = .empty
    @State private var isSupplementLoading = false
    @State private var didLoadSupplement = false
    @Environment(\.colorScheme) private var colorScheme

    private let supplementService = FundQuoteService()

    init(
        store: PortfolioStore,
        fund: FundPosition,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.initialFund = fund
        self.onClose = onClose
    }

    private var fund: FundPosition {
        store.snapshot.funds.first { $0.code == initialFund.code } ?? initialFund
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "calendar.badge.clock",
                title: "每日收益",
                subtitle: FundCodeFormatter.display(fund.code),
                subtitleWeight: .semibold,
                tint: toneColor(for: latestDailyIncome),
                accessoryText: rowsAccessoryText,
                accessoryColor: .orange,
                onClose: onClose
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isSupplementLoading && !didLoadSupplement {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 360)
                    } else if dailyIncomeRows.isEmpty {
                        ContentUnavailableView("暂无每日收益", systemImage: "chart.bar.doc.horizontal")
                            .frame(height: 360)
                    } else {
                        dailyIncomeTable
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
        .task(id: fund.code) {
            await loadSupplement()
        }
    }

    private var dailyIncomeTable: some View {
        VStack(spacing: 0) {
            dailyIncomeTableHeader
            ForEach(dailyIncomeDisplayRows) { row in
                Divider()
                    .opacity(0.45)
                dailyIncomeRow(row)
            }
        }
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var dailyIncomeTableHeader: some View {
        HStack(spacing: 12) {
            tableHeaderText("日期", alignment: .leading)
            tableHeaderText("日收益", alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func dailyIncomeRow(_ row: FundDailyIncomeDisplayRow) -> some View {
        HStack(spacing: 12) {
            tableValueText(row.dateText, alignment: .leading)
            tableValueText(MoneyFormatter.money(row.amount, signed: true), alignment: .trailing, tone: row.amount)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func tableHeaderText(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func tableValueText(
        _ text: String,
        alignment: Alignment,
        tone: Double? = nil
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.64)
            .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var rowsAccessoryText: String? {
        dailyIncomeRows.isEmpty ? nil : "\(dailyIncomeRows.count)天"
    }

    private var latestDailyIncome: Double {
        dailyIncomeRows.first?.dailyIncome ?? 0
    }

    private var dailyIncomeDisplayRows: [FundDailyIncomeDisplayRow] {
        dailyIncomeRows.flatMap { row -> [FundDailyIncomeDisplayRow] in
            guard isMeaningfulAmount(row.entryIncome) else {
                return [
                    FundDailyIncomeDisplayRow(
                        id: row.id,
                        dateText: row.dateText,
                        amount: row.dailyIncome
                    )
                ]
            }

            let entryRow = FundDailyIncomeDisplayRow(
                id: "\(row.id)-entry",
                dateText: "\(row.dateText) 录入",
                amount: row.entryIncome
            )
            guard isMeaningfulAmount(row.dailyIncome) else {
                return [entryRow]
            }

            return [
                FundDailyIncomeDisplayRow(
                    id: row.id,
                    dateText: row.dateText,
                    amount: row.dailyIncome
                ),
                entryRow
            ]
        }
    }

    private func isMeaningfulAmount(_ value: Double) -> Bool {
        abs(value) >= 0.005
    }

    private var dailyIncomeRows: [FundDailyIncomeRow] {
        FundDailyIncomeCalculator.rows(lots: effectiveLots, points: sourceNetValuePoints)
    }

    private var sourceNetValuePoints: [FundNetValuePoint] {
        supplement.history.isEmpty ? supplement.trend : supplement.history
    }

    private var effectiveLots: [FundPositionLot] {
        if let lots = fund.lots, !lots.isEmpty {
            return lots
        }
        guard let shares = fund.migratedShares,
              shares > 0
        else {
            return []
        }
        return [
            FundPositionLot(
                id: "\(fund.code)-daily-income",
                shares: shares,
                cost: fund.migratedCost ?? 0,
                incomeStartDate: fund.incomeStartDate ?? fund.positionDate ?? "",
                positionDate: fund.positionDate ?? "",
                positionTimeType: fund.positionTimeType ?? .before15
            )
        ]
    }

    @MainActor
    private func loadSupplement() async {
        guard !isSupplementLoading else { return }
        isSupplementLoading = true
        let next = await supplementService.fetchFundDetailSupplement(code: fund.code)
        supplement = next
        didLoadSupplement = true
        isSupplementLoading = false
    }
}

enum FundRowAmountPrivacyFormatter {
    static let maskedText = "***"

    static func plainMoney(_ value: Double, isMasked: Bool) -> String {
        isMasked ? maskedText : MoneyFormatter.plainMoney(value)
    }

    static func signedCompactMoney(_ value: Double, isMasked: Bool) -> String {
        guard !isMasked else { return maskedText }
        return MoneyFormatter.money(value, signed: true)
            .replacingOccurrences(of: "¥ ", with: "")
            .replacingOccurrences(of: "+¥", with: "+")
            .replacingOccurrences(of: "-¥", with: "-")
    }
}

struct FundDetailView: View {
    let store: PortfolioStore
    private let initialFund: FundPosition
    let totalAmount: Double
    let pendingTradeCount: Int
    let tradeRecords: [FundTradeRecord]
    let onBuy: (FundPosition) -> Void
    let onSell: (FundPosition) -> Void
    let onConvert: (FundPosition) -> Void
    let onEdit: (FundPosition) -> Void
    let onOpenTradeRecords: (FundPosition) -> Void
    let onOpenDailyIncome: (FundPosition) -> Void
    let onDelete: (FundPosition) async -> Void
    let onClose: () -> Void

    @State private var isDeleteConfirmationPresented = false
    @State private var supplement: FundDetailSupplement = .empty
    @State private var isSupplementLoading = false
    @State private var didLoadSupplement = false
    @State private var trendTab: FundDetailTrendTab = .intraday
    @State private var netValueTrendRange: FundNetValueTrendRange = .threeMonths
    @Environment(\.colorScheme) private var colorScheme

    private let supplementService = FundQuoteService()

    init(
        store: PortfolioStore,
        fund: FundPosition,
        totalAmount: Double,
        pendingTradeCount: Int,
        tradeRecords: [FundTradeRecord],
        onBuy: @escaping (FundPosition) -> Void,
        onSell: @escaping (FundPosition) -> Void,
        onConvert: @escaping (FundPosition) -> Void,
        onEdit: @escaping (FundPosition) -> Void,
        onOpenTradeRecords: @escaping (FundPosition) -> Void,
        onOpenDailyIncome: @escaping (FundPosition) -> Void,
        onDelete: @escaping (FundPosition) async -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.initialFund = fund
        self.totalAmount = totalAmount
        self.pendingTradeCount = pendingTradeCount
        self.tradeRecords = tradeRecords
        self.onBuy = onBuy
        self.onSell = onSell
        self.onConvert = onConvert
        self.onEdit = onEdit
        self.onOpenTradeRecords = onOpenTradeRecords
        self.onOpenDailyIncome = onOpenDailyIncome
        self.onDelete = onDelete
        self.onClose = onClose
    }

    private var fund: FundPosition {
        store.snapshot.funds.first { $0.code == initialFund.code } ?? initialFund
    }

    private var detailUpdateStarColor: Color {
        Color(nsColor: StatusBarTone.menuBarColor(forRate: fund.todayRate))
    }

    private var detailUpdateStar: some View {
        UpdatedFundStarShape()
            .fill(detailUpdateStarColor)
            .frame(width: 14.5, height: 14.5)
            .frame(width: 17, height: 18, alignment: .center)
            .shadow(color: detailUpdateStarColor.opacity(colorScheme == .dark ? 0.30 : 0.20), radius: 2.5, x: 0, y: 1)
            .accessibilityLabel("净值已更新")
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "基金详情",
                subtitle: FundCodeFormatter.display(fund.code),
                subtitleWeight: .semibold,
                tint: toneColor(for: fund.todayRate),
                actionSystemImage: "list.bullet.rectangle",
                actionTitle: "交易记录",
                actionBadgeText: tradeRecordsBadgeText,
                actionTint: Color(nsColor: .systemGray),
                actionHelp: tradeRecordsEntrySubtitle,
                onAction: {
                    onOpenTradeRecords(fund)
                },
                onClose: onClose
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fundTitle
                    todayRateHero
                    pendingTradeSummary
                    metricsGrid
                    trendSection
                    historySection
                    topHoldingsSection
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            actionBar
        }
        .background(PanelDesign.panelBackground)
        .task(id: fund.code) {
            await loadSupplement()
        }
        .alert("删除基金", isPresented: $isDeleteConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("删除基金", role: .destructive) {
                Task {
                    await onDelete(fund)
                    onClose()
                }
            }
        } message: {
            Text(deleteFundConfirmationMessage)
        }
    }

    private var deleteFundConfirmationMessage: String {
        "确定删除“\(fund.name)”吗？这会同时删除该基金的持仓、待确认交易和全部交易记录，删除后无法撤销。"
    }

    private var fundTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fund.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                if fund.isUpdated {
                    detailUpdateStar
                        .fixedSize()
                }
            }
            HStack(spacing: 7) {
                Text(FundCodeFormatter.display(fund.code))
                    .fontWeight(.semibold)
                Text(fund.dateText)
                fundTitleReminderTags
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    @ViewBuilder
    private var fundTitleReminderTags: some View {
        if let zdfRangeReminderText {
            titleReminderTag(zdfRangeReminderText, color: .orange)
        }
        if let netValueReminderText {
            titleReminderTag(netValueReminderText, color: .blue)
        }
    }

    private var todayRateHero: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("当日涨幅")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if fund.isUpdated {
                        detailTag("已更新", color: updatedDetailTagColor)
                    }
                }

                Text(MoneyFormatter.percent(fund.todayRate, signed: true))
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(toneColor(for: fund.todayRate))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text("当日收益")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(signedNumberText(fund.todayIncome))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(toneColor(for: fund.todayIncome))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(todayRateHeroBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(toneColor(for: fund.todayRate).opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private var pendingTradeSummary: some View {
        if let title = pendingTradeSummaryTitle,
           let detail = pendingTradeSummaryDetail {
            Button {
                onOpenTradeRecords(fund)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("待确认交易")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(pendingTradeSummaryTone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(pendingTradeSummaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.orange.opacity(0.20), lineWidth: 0.7)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            alignment: .leading,
            spacing: 14
        ) {
            metric("持有金额", numberText(currentTotal, places: 2))
            metric("持仓份额", totalShares > 0 ? numberText(totalShares, places: 2) : "--")
            metric("持仓成本", fund.migratedCost.map { numberText($0, places: 4) } ?? "--")
            dailyIncomeMetricButton("持有收益", signedNumberText(holdingIncome), tone: holdingIncome)
            metric("持有收益率", fund.holdingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "0.00%", tone: fund.holdingRate)
            metric("持有天数", holdingDaysText)
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSegmentedPicker(
                values: FundDetailTrendTab.allCases,
                selection: $trendTab,
                title: \.title,
                tint: toneColor(for: fund.todayRate)
            )

            switch trendTab {
            case .intraday:
                intradayTrendContent
            case .netValue:
                netValueTrendContent
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var intradayTrendContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "盘中预估实时涨跌",
                trailing: intradayTrendTrailingText
            )

            if visibleIntradayRatePoints.isEmpty {
                emptySupplementView(intradayTrendEmptyText)
                    .frame(height: 116)
            } else {
                FundIntradayRateChart(points: visibleIntradayRatePoints)
                    .frame(height: 138)
            }
        }
    }

    private var netValueTrendContent: some View {
        let trendPoints = netValueTrendPoints
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "净值业绩走势",
                trailing: latestNetValuePoint.map { "最新净值 \(numberText($0.value, places: 4))" },
                showsLoading: isSupplementLoading
            )

            if trendPoints.count >= 2 {
                FundTrendMiniChart(points: trendPoints, tradeMarkers: netValueTradeMarkers)
                    .frame(height: 116)
            } else {
                emptySupplementView(isSupplementLoading ? "走势加载中..." : "暂无走势数据")
                    .frame(height: 86)
            }

            netValueTrendRangePicker
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("历史净值", trailing: historyTrailingText, showsLoading: isSupplementLoading)

            if historyRows.isEmpty {
                emptySupplementView(isSupplementLoading ? "净值加载中..." : "暂无历史净值")
                    .frame(height: 74)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        historyHeader("日期", alignment: .leading)
                        historyHeader("净值", alignment: .center)
                        historyHeader("日涨幅", alignment: .trailing)
                    }
                    .frame(height: 26)

                    Divider().opacity(0.45)

                    VStack(spacing: 0) {
                        ForEach(Array(historyRows.enumerated()), id: \.element.id) { index, point in
                            historyRow(point)
                            if index < historyRows.count - 1 {
                                Divider().opacity(0.34)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var topHoldingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("前10重仓股", trailing: topHoldingsTrailingText, showsLoading: isSupplementLoading)

            if supplement.topHoldings.isEmpty {
                emptySupplementView(isSupplementLoading ? "重仓加载中..." : "暂无重仓数据")
                    .frame(height: 64)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(supplement.topHoldings.enumerated()), id: \.offset) { index, holding in
                        stockHoldingRow(holding, rank: index + 1)
                        if index < supplement.topHoldings.count - 1 {
                            Divider()
                                .opacity(0.55)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.45)

            HStack(spacing: 8) {
                Button {
                    onBuy(fund)
                } label: {
                    PanelButtonLabel(title: "加仓", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button {
                    onSell(fund)
                } label: {
                    PanelButtonLabel(title: "减仓", systemImage: "minus.circle")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled((fund.migratedShares ?? 0) <= 0)

                Button {
                    onConvert(fund)
                } label: {
                    PanelButtonLabel(title: "转换", systemImage: "arrow.left.arrow.right.circle")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled((fund.migratedShares ?? 0) <= 0)

                Button {
                    onEdit(fund)
                } label: {
                    PanelButtonLabel(title: "编辑", systemImage: "pencil")
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    PanelButtonLabel(title: "删除", systemImage: "trash", style: .destructive)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(PanelDesign.panelBackground)
    }

    private func sectionHeader(_ title: String, trailing: String? = nil, showsLoading: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            if showsLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptySupplementView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PanelDesign.selectorBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var recentTradeRecords: [FundTradeRecord] {
        let actualRecords = tradeRecords.filter { $0.code == fund.code }
        let records = actualRecords.contains { $0.kind == .newFund }
            ? actualRecords
            : actualRecords + (inferredInitialTradeRecord(for: fund).map { [$0] } ?? [])
        return records.sorted(by: tradeRecordTimeDescending)
    }

    private var pendingTradeRecords: [FundTradeRecord] {
        recentTradeRecords.filter { $0.status == .pending }
    }

    private var netValueSourcePoints: [FundNetValuePoint] {
        let source = supplement.history.isEmpty ? supplement.trend : supplement.history
        return source.sorted { $0.timestamp < $1.timestamp }
    }

    private var latestNetValuePoint: FundNetValuePoint? {
        netValueSourcePoints.last
    }

    private var netValueTrendPoints: [FundNetValuePoint] {
        let source = netValueSourcePoints
        guard let latestTimestamp = source.last?.timestamp else { return [] }

        let calendar = Calendar.current
        let latestDate = Date(timeIntervalSince1970: TimeInterval(latestTimestamp) / 1000)
        let latestDay = calendar.startOfDay(for: latestDate)
        guard let cutoff = calendar.date(byAdding: .month, value: -netValueTrendRange.months, to: latestDay) else {
            return source
        }

        return source.filter { point in
            let pointDate = Date(timeIntervalSince1970: TimeInterval(point.timestamp) / 1000)
            return calendar.startOfDay(for: pointDate) >= cutoff
        }
    }

    private var netValueTrendRangePicker: some View {
        HStack(spacing: 4) {
            ForEach(FundNetValueTrendRange.allCases) { value in
                let isSelected = netValueTrendRange == value
                Button {
                    netValueTrendRange = value
                } label: {
                    Text(value.title)
                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? netValueTrendRangeTint : Color.secondary.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? netValueTrendRangeTint.opacity(colorScheme == .dark ? 0.22 : 0.15) : Color.clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isSelected ? netValueTrendRangeTint.opacity(0.18) : Color.clear, lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(.top, 1)
    }

    private var netValueTrendRangeTint: Color {
        toneColor(for: fund.todayRate)
    }

    private var netValueTradeMarkers: [FundTrendTradeMarker] {
        recentTradeRecords.compactMap { record in
            guard record.status == .confirmed else { return nil }

            switch record.kind {
            case .newFund, .buy:
                return FundTrendTradeMarker(
                    id: record.id,
                    kind: .buy,
                    dateText: record.acceptedDate,
                    price: record.price
                )
            case .sell, .conversionOut:
                return FundTrendTradeMarker(
                    id: record.id,
                    kind: .sell,
                    dateText: record.acceptedDate,
                    price: record.price
                )
            case .conversionIn:
                return FundTrendTradeMarker(
                    id: record.id,
                    kind: .buy,
                    dateText: record.acceptedDate,
                    price: record.price
                )
            }
        }
    }

    private var pendingTradeSummaryTitle: String? {
        let summary = pendingTradeSummaryValues
        var parts: [String] = []
        if summary.buyAmount > 0 {
            parts.append("+\(compactPendingMoney(summary.buyAmount))")
        }
        if summary.sellAmount > 0 {
            parts.append("-\(compactPendingMoney(summary.sellAmount))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " / ")
    }

    private var pendingTradeSummaryDetail: String? {
        guard !pendingTradeRecords.isEmpty else { return nil }
        var parts: [String] = []
        let buyCount = pendingTradeRecords.filter { $0.kind == .newFund || $0.kind == .buy }.count
        let sellCount = pendingTradeRecords.filter { $0.kind == .sell }.count
        let conversionCount = Set(pendingTradeRecords.filter { $0.kind == .conversionOut || $0.kind == .conversionIn }.compactMap(\.conversionID)).count
        if buyCount > 0 {
            parts.append("加仓 \(buyCount)笔")
        }
        if sellCount > 0 {
            parts.append("减仓 \(sellCount)笔")
        }
        if conversionCount > 0 {
            parts.append("转换 \(conversionCount)笔")
        }
        if let acceptedDate = pendingTradeRecords.map(\.acceptedDate).sorted().first {
            parts.append("确认 \(acceptedDate)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var pendingTradeSummaryTone: Color {
        pendingTradeSummaryValues.buyAmount > 0
            ? .red
            : .fundPulseGreen
    }

    private var pendingTradeSummaryBackground: Color {
        Color.orange.opacity(0.08)
    }

    private var pendingTradeSummaryValues: (buyAmount: Double, sellAmount: Double) {
        var buyAmount: Double = 0
        var sellAmount: Double = 0

        for record in pendingTradeRecords {
            switch record.kind {
            case .newFund, .buy:
                if let amount = record.amount, amount > 0 {
                    buyAmount += amount
                } else if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    buyAmount += pendingTradeSummaryAmount(shares: shares, acceptedDate: record.acceptedDate)
                }
            case .sell:
                if let amount = record.amount, amount > 0 {
                    sellAmount += amount
                } else if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    sellAmount += pendingTradeSummaryAmount(shares: shares, acceptedDate: record.acceptedDate)
                }
            case .conversionOut:
                if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    sellAmount += pendingTradeSummaryAmount(shares: shares, acceptedDate: record.acceptedDate)
                }
            case .conversionIn:
                if let amount = record.amount, amount > 0 {
                    buyAmount += amount
                }
            }
        }

        return (buyAmount, sellAmount)
    }

    private func pendingTradeSummaryAmount(shares: Double, acceptedDate: String) -> Double {
        guard let price = pendingTradeSummaryReferencePrice(acceptedDate: acceptedDate) else {
            return 0
        }
        return shares * price
    }

    private func pendingTradeSummaryReferencePrice(acceptedDate: String) -> Double? {
        let shares = fund.migratedShares ?? 0
        let currentAmount = PortfolioPanelDisplay.currentAmount(for: fund)
        let basePrice: Double
        if shares > 0, currentAmount > 0 {
            basePrice = currentAmount / shares
        } else if let migratedCost = fund.migratedCost, migratedCost > 0 {
            basePrice = migratedCost
        } else {
            return nil
        }

        let today = DateOnlyFormatter.string(from: .now)
        if acceptedDate == today, !fund.isUpdated, fund.todayRate != 0 {
            return basePrice * (1 + fund.todayRate / 100)
        }
        return basePrice
    }

    private var tradeRecordsEntrySubtitle: String {
        let pendingCount = recentTradeRecords.filter { $0.status == .pending }.count
        guard pendingCount > 0 else { return "查看新增、加仓、减仓、转换流水" }
        return "含待确认 \(pendingCount) 笔"
    }

    private var tradeRecordsBadgeText: String? {
        let count = recentTradeRecords.count
        return count > 0 ? "\(count)" : nil
    }

    private func historyHeader(_ title: String, alignment: Alignment) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func historyRow(_ point: FundNetValuePoint) -> some View {
        HStack(spacing: 8) {
            Text(dateText(point.timestamp, format: "yyyy-MM-dd"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(numberText(point.value, places: 4))
                .frame(maxWidth: .infinity, alignment: .center)
            Text(point.equityReturn.map { MoneyFormatter.percent($0, signed: true) } ?? "--")
                .foregroundStyle(point.equityReturn.map(toneColor(for:)) ?? Color.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .frame(height: 34)
    }

    private func stockHoldingRow(_ holding: FundStockHolding, rank: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name.isEmpty ? holding.code : holding.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let detail = stockHoldingDetailText(holding) {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let changeRate = holding.changeRate {
                Text(MoneyFormatter.percent(changeRate, signed: true))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(toneColor(for: changeRate))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(toneColor(for: changeRate).opacity(0.10), in: Capsule())
            }

            Text(holding.weight.isEmpty ? "--" : holding.weight)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 38)
    }

    private func stockHoldingDetailText(_ holding: FundStockHolding) -> String? {
        var parts: [String] = []
        if !holding.code.isEmpty {
            parts.append(holding.code)
        }
        if let industryName = holding.industryName, !industryName.isEmpty {
            parts.append(industryName)
        }
        if let positionChangeType = holding.positionChangeType, !positionChangeType.isEmpty {
            if let positionChangeRate = holding.positionChangeRate, positionChangeRate != 0 {
                parts.append("\(positionChangeType) \(MoneyFormatter.percent(positionChangeRate, signed: false))")
            } else {
                parts.append(positionChangeType)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func metric(_ title: String, _ value: String, tone: Double? = nil, isInteractive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if isInteractive {
                    detailDisclosureIndicator
                }
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dailyIncomeMetricButton(_ title: String, _ value: String, tone: Double? = nil) -> some View {
        Button {
            onOpenDailyIncome(fund)
        } label: {
            metric(title, value, tone: tone, isInteractive: true)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(Rectangle())
        .help("查看每日收益")
    }

    private var detailDisclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
    }

    private func detailTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.6)
            )
    }

    private var updatedDetailTagColor: Color {
        Color(red: 254 / 255, green: 143 / 255, blue: 37 / 255)
    }

    private var todayRateHeroBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                toneColor(for: fund.todayRate).opacity(colorScheme == .dark ? 0.14 : 0.075),
                PanelDesign.cardBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func titleReminderTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(color.opacity(colorScheme == .dark ? 0.16 : 0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 0.6)
            )
    }

    private var currentTotal: Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        return principal + holdingIncome
    }

    private var principal: Double {
        if let migratedPrincipal = fund.migratedPrincipal {
            return migratedPrincipal
        }
        guard let shares = fund.migratedShares, let cost = fund.migratedCost else {
            return 0
        }
        return shares * cost
    }

    private var holdingIncome: Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else {
            return 0
        }
        return principal * holdingRate / 100
    }

    private var totalShares: Double {
        if let shares = fund.migratedShares {
            return shares
        }
        return fund.lots?.reduce(0) { $0 + $1.shares } ?? 0
    }

    private var effectiveLots: [FundPositionLot] {
        if let lots = fund.lots, !lots.isEmpty {
            return lots
        }
        guard let shares = fund.migratedShares,
              shares > 0
        else {
            return []
        }
        return [
            FundPositionLot(
                id: "\(fund.code)-detail",
                shares: shares,
                cost: fund.migratedCost ?? 0,
                incomeStartDate: fund.incomeStartDate ?? fund.positionDate ?? "",
                positionDate: fund.positionDate ?? "",
                positionTimeType: fund.positionTimeType ?? .before15
            )
        ]
    }

    private var topHoldingsTrailingText: String? {
        guard !supplement.topHoldings.isEmpty else { return nil }
        guard let date = supplement.holdingDisclosureDate else {
            return "\(supplement.topHoldings.count)只"
        }
        return "\(supplement.topHoldings.count)只 · \(date)"
    }

    private var intradayRatePoints: [FundIntradayRatePoint] {
        FundIntradayRateHistoryRecorder.activePoints(for: fund)
    }

    private var visibleIntradayRatePoints: [FundIntradayRatePoint] {
        if !intradayRatePoints.isEmpty {
            return intradayRatePoints
        }

        switch TradingCalendar.marketSessionState() {
        case .open:
            return intradayCurrentValueFallbackPoints
        case .middayBreak, .closed:
            guard fund.intradayRateDate == FundIntradayRateHistoryRecorder.tradingDayString(from: .now) else {
                return intradayCurrentValueFallbackPoints
            }
            let storedPoints = (fund.intradayRateHistory ?? []).sorted { $0.timestamp < $1.timestamp }
            return storedPoints.isEmpty ? intradayCurrentValueFallbackPoints : storedPoints
        }
    }

    private var intradayTrendTrailingText: String? {
        guard let lastPoint = visibleIntradayRatePoints.last else { return nil }
        return "\(MoneyFormatter.percent(lastPoint.rate, signed: true)) · \(dateText(lastPoint.timestamp, format: "HH:mm"))"
    }

    private var intradayTrendEmptyText: String {
        switch TradingCalendar.marketSessionState() {
        case .open:
            "等待下一次盘中估值刷新"
        case .middayBreak:
            "午休中，盘中曲线暂停更新"
        case .closed:
            "休市中，盘中曲线停止更新"
        }
    }

    private var intradayCurrentValueFallbackPoints: [FundIntradayRatePoint] {
        guard fund.todayRate.isFinite,
              fund.todayRate != 0
        else {
            return []
        }

        return [
            FundIntradayRatePoint(
                timestamp: intradayFallbackTimestamp,
                rate: fund.todayRate,
                estimateTime: fund.dateText
            )
        ]
    }

    private var intradayFallbackTimestamp: Int64 {
        if let parsedDate = parseFundDateText(fund.dateText) {
            return Int64((parsedDate.timeIntervalSince1970 * 1000).rounded())
        }
        return Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private var zdfRangeReminderText: String? {
        fund.zdfRange.map { "涨跌幅提醒 \(MoneyFormatter.percent($0, signed: false))" }
    }

    private var netValueReminderText: String? {
        fund.jzNotice.map { "净值提醒 \(numberText($0, places: 4))" }
    }

    private var historyTrailingText: String? {
        historyRows.isEmpty ? "近1月" : "近1月 · \(historyRows.count)条"
    }

    private var historyRows: [FundNetValuePoint] {
        let sortedRows = supplement.history.sorted { $0.timestamp > $1.timestamp }
        guard let latestTimestamp = sortedRows.first?.timestamp else {
            return []
        }
        let calendar = Calendar.current
        let latestDate = Date(timeIntervalSince1970: TimeInterval(latestTimestamp) / 1000)
        let latestDay = calendar.startOfDay(for: latestDate)
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: latestDay) else {
            return sortedRows
        }
        return sortedRows.filter { point in
            let date = Date(timeIntervalSince1970: TimeInterval(point.timestamp) / 1000)
            return calendar.startOfDay(for: date) >= cutoff
        }
    }

    private var holdingDaysText: String {
        guard let positionDate = fund.positionDate,
              let startDate = DateOnlyFormatter.parse(positionDate)
        else {
            return "--"
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: .now)
        let days = max((calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1, 1)
        return "\(days)"
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }

    private func signedNumberText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return "\(sign)\(abs(value).formatted(.number.precision(.fractionLength(2))))"
    }

    private func compactPendingMoney(_ value: Double) -> String {
        "¥\(value.formatted(.number.precision(.fractionLength(0...2))))"
    }

    private func compactPendingShares(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func dateText(_ timestamp: Int64, format: String) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func parseFundDateText(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 11 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        let year = calendar.component(.year, from: .now)
        let fullText = "\(year)-\(trimmed)"
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: fullText)
    }

    @MainActor
    private func loadSupplement() async {
        guard !isSupplementLoading else { return }
        isSupplementLoading = true
        let next = await supplementService.fetchFundDetailSupplement(code: fund.code)
        supplement = next
        didLoadSupplement = true
        isSupplementLoading = false
    }
}

private enum TradeRecordFilter: String, CaseIterable, Identifiable {
    case all
    case buy
    case sell
    case conversion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
        case .conversion:
            "转换"
        }
    }

    func matches(_ record: FundTradeRecord) -> Bool {
        switch self {
        case .all:
            true
        case .buy:
            record.kind == .buy || record.kind == .newFund
        case .sell:
            record.kind == .sell
        case .conversion:
            record.kind == .conversionOut || record.kind == .conversionIn
        }
    }
}

struct FundTradeRecordsPanelView: View {
    let fund: FundPosition
    let tradeRecords: [FundTradeRecord]
    let onEdit: (FundTradeRecord) -> Void
    let onDelete: (FundTradeRecord) async -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: TradeRecordFilter = .all
    @State private var deletingRecord: FundTradeRecord?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "clock.arrow.circlepath",
                title: "交易记录",
                subtitle: tradeRecordsHeaderSubtitle,
                subtitleWeight: .semibold,
                onClose: onClose
            )

            filterBar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredTradeRecords.isEmpty {
                        ContentUnavailableView(emptyTitle, systemImage: "tray")
                            .frame(height: 320)
                    } else {
                        ForEach(filteredTradeRecords) { record in
                            tradeRecordRow(record)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
        .alert("删除交易记录", isPresented: deleteConfirmationBinding, presenting: deletingRecord) { record in
            Button("取消", role: .cancel) {
                deletingRecord = nil
            }
            Button("删除记录", role: .destructive) {
                Task {
                    await onDelete(record)
                    deletingRecord = nil
                }
            }
        } message: { record in
            Text(deleteTradeRecordConfirmationMessage(for: record))
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(TradeRecordFilter.allCases) { value in
                Button {
                    filter = value
                } label: {
                    Text(value.title)
                        .font(.system(size: 11, weight: filter == value ? .semibold : .medium))
                        .foregroundStyle(filter == value ? Color.blue : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(
                            filter == value ? Color.blue.opacity(0.11) : PanelDesign.selectorBackground.opacity(0.72),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(filter == value ? Color.blue.opacity(0.16) : Color.clear, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }

    private var recentTradeRecords: [FundTradeRecord] {
        let actualRecords = tradeRecords.filter { $0.code == fund.code }
        let records = actualRecords.contains { $0.kind == .newFund }
            ? actualRecords
            : actualRecords + (inferredInitialTradeRecord(for: fund).map { [$0] } ?? [])
        return records.sorted(by: tradeRecordTimeDescending)
    }

    private var filteredTradeRecords: [FundTradeRecord] {
        recentTradeRecords.filter(filter.matches)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingRecord != nil },
            set: { isPresented in
                if !isPresented {
                    deletingRecord = nil
                }
            }
        )
    }

    private var emptyTitle: String {
        filter == .all ? "暂无交易记录" : "暂无\(filter.title)记录"
    }

    private var tradeRecordsHeaderSubtitle: String {
        let code = FundCodeFormatter.display(fund.code)
        let name = fund.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? code : "\(code) · \(name)"
    }

    private func deleteTradeRecordConfirmationMessage(for record: FundTradeRecord) -> String {
        "确定删除 \(tradeDateTimeText(record)) 的\(record.kind.title)记录（\(tradeRecordAmountText(record))）吗？删除后会重新计算这只基金的持有金额、持有份额和成本，且无法撤销。"
    }

    private func tradeRecordRow(_ record: FundTradeRecord) -> some View {
        let kindColor = tradeKindColor(record.kind)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    recordKindBadge(record.kind)

                    Text(tradeDateTimeText(record))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                Text(tradeRecordAmountText(record))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(kindColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .frame(height: 22, alignment: .center)

            HStack(alignment: .center, spacing: 8) {
                Text(recordConfirmationText(record))
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 19, alignment: .center)

                Spacer(minLength: 4)

                recordStatusBadge(record)
            }
            .frame(height: 22, alignment: .center)

            HStack(alignment: .center, spacing: 8) {
                recordPriceShareLine(record, color: kindColor)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                recordActionStack(record)
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(height: 22, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 88)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(recordCardBackground(record.kind))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kindColor.opacity(colorScheme == .dark ? 0.24 : 0.16), lineWidth: 0.8)
        }
    }

    private func recordActionButton(
        systemName: String,
        title: String,
        color: Color = .secondary,
        backgroundOpacity: Double = 0.06,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(title)
    }

    private func canEdit(_ record: FundTradeRecord) -> Bool {
        !isInferredInitialTradeRecord(record)
    }

    private func recordActionStack(_ record: FundTradeRecord) -> some View {
        HStack(spacing: 5) {
            if canEdit(record) {
                recordActionButton(systemName: "pencil", title: "编辑") {
                    onEdit(record)
                }
            }
            if !isInferredInitialTradeRecord(record) {
                recordActionButton(systemName: "trash", title: "删除", color: .red, backgroundOpacity: 0.08) {
                    deletingRecord = record
                }
            }
        }
    }

    private func recordKindBadge(_ kind: FundTradeKind) -> some View {
        let color = tradeKindColor(kind)
        return Text(recordKindTitle(kind))
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 0.6)
            )
    }

    private func recordStatusBadge(_ record: FundTradeRecord) -> some View {
        let title = recordStatusTitle(record)
        let color = tradeStatusColor(record.status)
        return Text(title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(minWidth: 50)
            .frame(height: 19)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 0.6)
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
    }

    private func recordTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func recordKindTitle(_ kind: FundTradeKind) -> String {
        switch kind {
        case .newFund:
            "新增"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
        case .conversionOut:
            "转出"
        case .conversionIn:
            "转入"
        }
    }

    private func tradeDateTimeText(_ record: FundTradeRecord) -> String {
        if record.kind == .newFund, record.mode == .amount {
            return "首次录入"
        }
        return "\(record.tradeDate) \(record.tradeTimeType.title)"
    }

    private func recordConfirmationText(_ record: FundTradeRecord) -> String {
        if record.status == .pending,
           isConversionRecord(record),
           record.amount != nil,
           let executionDate = TradingCalendar.nextFundTradingDate(after: record.acceptedDate) {
            return "执行 \(executionDate) 00:00后"
        }
        return "确认 \(record.acceptedDate)"
    }

    private func recordStatusTitle(_ record: FundTradeRecord) -> String {
        if record.status == .pending,
           isConversionRecord(record),
           record.amount != nil {
            return "待执行"
        }
        if record.status == .pending,
           isConversionRecord(record) {
            return "待净值"
        }
        return record.status.title
    }

    private func isConversionRecord(_ record: FundTradeRecord) -> Bool {
        record.kind == .conversionOut || record.kind == .conversionIn
    }

    @ViewBuilder
    private func recordPriceShareLine(_ record: FundTradeRecord, color: Color) -> some View {
        let priceText = record.price.map { numberText($0, places: 4) }
        let sharesText = (record.confirmedShares ?? record.shares).map { "\(numberText($0, places: 2))份" }

        if priceText == nil && sharesText == nil {
            Text(record.kind == .newFund && record.mode == .amount ? "手工录入" : "待确认净值和份额")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            HStack(spacing: 8) {
                if let priceText {
                    recordMetricText(
                        label: record.kind == .newFund && record.mode == .amount ? "参考净值" : "净值",
                        value: priceText,
                        color: color
                    )
                }

                if let sharesText {
                    recordMetricText(label: "份额", value: sharesText, color: color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
        }
    }

    private func recordMetricText(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary.opacity(colorScheme == .dark ? 0.82 : 0.70))
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color.opacity(colorScheme == .dark ? 0.95 : 0.82))
        }
        .monospacedDigit()
    }

    private func tradeRecordAmountText(_ record: FundTradeRecord) -> String {
        if let amount = record.amount {
            return MoneyFormatter.plainMoney(amount)
        }
        if let shares = record.shares ?? record.confirmedShares {
            return "\(numberText(shares, places: 2))份"
        }
        return "--"
    }

    private func tradeKindColor(_ kind: FundTradeKind) -> Color {
        switch kind {
        case .newFund:
            Color(nsColor: .systemBlue)
        case .buy:
            Color(nsColor: .systemRed)
        case .sell, .conversionOut:
            .fundPulseGreen
        case .conversionIn:
            Color(nsColor: .systemRed)
        }
    }

    private func recordCardBackground(_ kind: FundTradeKind) -> LinearGradient {
        let color = tradeKindColor(kind)
        return LinearGradient(
            colors: [
                color.opacity(colorScheme == .dark ? 0.18 : 0.10),
                color.opacity(colorScheme == .dark ? 0.10 : 0.055),
                PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.82 : 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func tradeStatusColor(_ status: FundTradeRecordStatus) -> Color {
        switch status {
        case .pending:
            .orange
        case .confirmed:
            .blue
        case .failed:
            .red
        }
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }
}

private struct FundIntradayRateChart: View {
    let points: [FundIntradayRatePoint]

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?

    private static let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = chinaTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                yAxisLabels
                    .frame(width: 36, height: 108)

                GeometryReader { proxy in
                    ZStack {
                        gridLines(in: proxy.size)
                            .stroke(gridColor, lineWidth: 0.7)
                        zeroLine(in: proxy.size)
                            .stroke(zeroLineColor, style: StrokeStyle(lineWidth: 0.9, dash: [6, 5]))
                        chartBorder(in: proxy.size)
                            .stroke(borderColor, lineWidth: 0.75)

                        if renderedPoints.count >= 2 {
                            areaPath(in: proxy.size)
                                .fill(areaFill)
                            linePath(in: proxy.size)
                                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        } else if let point = renderedPoints.first {
                            Circle()
                                .fill(lineColor)
                                .frame(width: 6, height: 6)
                                .position(pointPosition(for: point, in: proxy.size))
                        }

                        if let hoveredIndex,
                           renderedPoints.indices.contains(hoveredIndex) {
                            hoverOverlay(for: hoveredIndex, in: proxy.size)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            hoveredIndex = nearestIndex(for: location.x, width: proxy.size.width)
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
                }
                .frame(height: 108)
            }

            xAxisLabels
        }
        .accessibilityLabel("盘中预估实时涨跌走势图")
    }

    private var sortedPoints: [FundIntradayRatePoint] {
        points.sorted { $0.timestamp < $1.timestamp }
    }

    private var renderedPoints: [FundIntradayRatePoint] {
        sortedPoints
    }

    private var yAxisBounds: (min: Double, max: Double) {
        let rates = sortedPoints.map(\.rate)
        let rawMin = min(rates.min() ?? 0, 0)
        let rawMax = max(rates.max() ?? 0, 0)
        var minValue = floor(rawMin)
        var maxValue = ceil(rawMax)

        if minValue >= rawMin, rawMin < 0 {
            minValue -= 1
        }
        if maxValue <= rawMax, rawMax > 0 {
            maxValue += 1
        }

        if minValue == maxValue {
            minValue -= 0.5
            maxValue += 0.5
        }

        return (minValue, maxValue)
    }

    private var lineColor: Color {
        toneColor(for: sortedPoints.last?.rate ?? 0)
    }

    private var areaFill: LinearGradient {
        LinearGradient(
            colors: [
                lineColor.opacity(colorScheme == .dark ? 0.26 : 0.18),
                lineColor.opacity(colorScheme == .dark ? 0.08 : 0.035)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var gridColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.14)
    }

    private var zeroLineColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.38 : 0.32)
    }

    private var borderColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.16)
    }

    private var yAxisLabels: some View {
        let bounds = yAxisBounds
        return VStack(alignment: .trailing, spacing: 0) {
            Text(MoneyFormatter.percent(bounds.max, signed: true))
            Spacer()
            Text(MoneyFormatter.percent(bounds.min, signed: true))
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var xAxisLabels: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Spacer()
                .frame(width: 42)
            Text("09:30")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("11:30/13:00")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("15:00")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func gridLines(in size: CGSize) -> Path {
        Path { path in
            for ratio in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
                let x = size.width * ratio
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for ratio in [CGFloat(0), 1] {
                let y = size.height * ratio
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    private func zeroLine(in size: CGSize) -> Path {
        Path { path in
            let y = yPosition(for: 0, height: size.height)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
    }

    private func chartBorder(in size: CGSize) -> Path {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let points = renderedPoints
        return Path { path in
            for (index, point) in points.enumerated() {
                let position = pointPosition(for: point, in: size)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        let points = renderedPoints
        return Path { path in
            guard let first = points.first,
                  let last = points.last
            else {
                return
            }

            for (index, point) in points.enumerated() {
                let position = pointPosition(for: point, in: size)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }

            let zeroY = yPosition(for: 0, height: size.height)
            path.addLine(to: CGPoint(x: xPosition(for: last, width: size.width), y: zeroY))
            path.addLine(to: CGPoint(x: xPosition(for: first, width: size.width), y: zeroY))
            path.closeSubpath()
        }
    }

    private func hoverOverlay(for index: Int, in size: CGSize) -> some View {
        let points = renderedPoints
        let point = points[index]
        let position = pointPosition(for: point, in: size)
        let xLabelX = min(max(position.x, 24), max(size.width - 24, 24))
        let yLabelY = min(max(position.y, 9), max(size.height - 9, 9))

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: position.x, y: 0))
                path.addLine(to: CGPoint(x: position.x, y: size.height))
                path.move(to: CGPoint(x: 0, y: position.y))
                path.addLine(to: CGPoint(x: size.width, y: position.y))
            }
            .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 0.9, dash: [4, 3]))

            Circle()
                .fill(lineColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.9 : 0.96), lineWidth: 1.4)
                )
                .position(position)

            hoverAxisLabel(MoneyFormatter.percent(point.rate, signed: true), width: 54)
                .position(x: -31, y: yLabelY)

            hoverAxisLabel(Self.timeFormatter.string(from: date(from: point.timestamp)), width: 42)
                .position(x: xLabelX, y: size.height - 10)
        }
        .allowsHitTesting(false)
    }

    private func hoverAxisLabel(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(lineColor)
            .frame(width: width, height: 18)
            .background(hoverAxisLabelBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(lineColor.opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 0.65)
            )
    }

    private var hoverAxisLabelBackground: Color {
        colorScheme == .dark
            ? PanelDesign.cardBackground.opacity(0.92)
            : Color.white.opacity(0.94)
    }

    private func pointPosition(for point: FundIntradayRatePoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: xPosition(for: point, width: size.width),
            y: yPosition(for: point.rate, height: size.height)
        )
    }

    private func xPosition(for point: FundIntradayRatePoint, width: CGFloat) -> CGFloat {
        sessionProgress(for: point.timestamp) * width
    }

    private func yPosition(for rate: Double, height: CGFloat) -> CGFloat {
        let bounds = yAxisBounds
        let range = bounds.max - bounds.min
        guard range > 0 else { return height / 2 }
        let clampedRate = min(max(rate, bounds.min), bounds.max)
        return CGFloat((bounds.max - clampedRate) / range) * height
    }

    private func sessionProgress(for timestamp: Int64) -> CGFloat {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = Self.chinaTimeZone

        let date = date(from: timestamp)
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double((components.hour ?? 0) * 60 + (components.minute ?? 0)) + Double(components.second ?? 0) / 60

        let morningOpen = 9.0 * 60 + 30
        let morningClose = 11.0 * 60 + 30
        let afternoonOpen = 13.0 * 60
        let afternoonClose = 15.0 * 60
        let activeMinutes = (morningClose - morningOpen) + (afternoonClose - afternoonOpen)

        if minute <= morningOpen {
            return 0
        }
        if minute <= morningClose {
            return CGFloat((minute - morningOpen) / activeMinutes)
        }
        if minute < afternoonOpen {
            return 0.5
        }
        if minute <= afternoonClose {
            return CGFloat((morningClose - morningOpen + minute - afternoonOpen) / activeMinutes)
        }
        return 1
    }

    private func nearestIndex(for x: CGFloat, width: CGFloat) -> Int? {
        let points = renderedPoints
        guard !points.isEmpty, width > 0 else { return nil }
        return points.indices.min { lhs, rhs in
            abs(xPosition(for: points[lhs], width: width) - x) < abs(xPosition(for: points[rhs], width: width) - x)
        }
    }

    private func date(from timestamp: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }
}

private enum FundTrendTradeMarkerKind {
    case buy
    case sell
}

private struct FundTrendTradeMarker: Identifiable, Equatable {
    var id: String
    var kind: FundTrendTradeMarkerKind
    var dateText: String
    var price: Double?
}

private struct FundTrendMiniChart: View {
    let points: [FundNetValuePoint]
    let tradeMarkers: [FundTrendTradeMarker]

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                yAxisLabels
                    .frame(width: 42, height: 90)

                GeometryReader { proxy in
                    ZStack {
                        chartGrid
                        chartAxes
                        linePath(in: proxy.size)
                            .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        ForEach(resolvedTradeMarkers) { marker in
                            tradeMarkerView(marker)
                                .position(markerPosition(for: marker, in: proxy.size))
                        }
                        if let hoveredIndex,
                           points.indices.contains(hoveredIndex) {
                            hoverOverlay(for: hoveredIndex, in: proxy.size)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            hoveredIndex = nearestIndex(for: location.x, width: proxy.size.width)
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
                }
                .frame(height: 90)
            }

            HStack {
                Spacer()
                    .frame(width: 48)
                Text(dateText(points.first?.timestamp))
                Spacer()
                Text(dateText(points.last?.timestamp))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var chartGrid: some View {
        GeometryReader { proxy in
            Path { path in
                let rows: [CGFloat] = [0, 0.5, 1]
                for row in rows {
                    let y = row * proxy.size.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
        }
    }

    private var chartAxes: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
            }
            .stroke(Color.secondary.opacity(0.24), lineWidth: 0.8)
        }
    }

    private var lineColor: Color {
        toneColor(for: points.last?.equityReturn ?? 0)
    }

    private var yValueBounds: (min: Double, max: Double) {
        let values = points.map(\.value) + tradeMarkers.compactMap { marker in
            guard let price = marker.price, price.isFinite else { return nil }
            return price
        }
        guard let minValue = values.min(),
              let maxValue = values.max()
        else {
            return (0, 1)
        }

        let range = max(maxValue - minValue, 0.0001)
        let padding = max(range * 0.12, 0.01)
        return (minValue - padding, maxValue + padding)
    }

    private var yAxisLabels: some View {
        let bounds = yValueBounds
        let middleValue = (bounds.min + bounds.max) / 2

        return VStack(alignment: .trailing, spacing: 0) {
            Text(numberText(bounds.max))
            Spacer()
            Text(numberText(middleValue))
            Spacer()
            Text(numberText(bounds.min))
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var resolvedTradeMarkers: [ResolvedFundTrendTradeMarker] {
        tradeMarkers.compactMap { marker in
            guard let index = nearestPointIndex(for: marker.dateText) else { return nil }
            let fallbackValue = points[index].value
            let value: Double
            if let price = marker.price, price.isFinite {
                value = price
            } else {
                value = fallbackValue
            }

            return ResolvedFundTrendTradeMarker(
                id: marker.id,
                kind: marker.kind,
                pointIndex: index,
                value: value
            )
        }
    }

    private func hoverOverlay(for index: Int, in size: CGSize) -> some View {
        let point = points[index]
        let pointPosition = pointPosition(for: index, in: size)
        let xLabelX = min(max(pointPosition.x, 24), max(size.width - 24, 24))
        let yLabelY = min(max(pointPosition.y, 9), max(size.height - 9, 9))

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: pointPosition.x, y: 0))
                path.addLine(to: CGPoint(x: pointPosition.x, y: size.height))
                path.move(to: CGPoint(x: 0, y: pointPosition.y))
                path.addLine(to: CGPoint(x: size.width, y: pointPosition.y))
            }
            .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 0.9, dash: [4, 3]))

            Circle()
                .fill(lineColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.9 : 0.96), lineWidth: 1.4)
                )
                .position(pointPosition)

            hoverAxisLabel(numberText(point.value), width: 54)
                .position(x: -31, y: yLabelY)

            hoverAxisLabel(dateText(point.timestamp), width: 42)
                .position(x: xLabelX, y: size.height - 10)
        }
        .allowsHitTesting(false)
    }

    private func hoverAxisLabel(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(lineColor)
            .frame(width: width, height: 18)
            .background(hoverAxisLabelBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(lineColor.opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 0.65)
            )
    }

    private var hoverAxisLabelBackground: Color {
        colorScheme == .dark
            ? PanelDesign.cardBackground.opacity(0.92)
            : Color.white.opacity(0.94)
    }

    private func tradeMarkerView(_ marker: ResolvedFundTrendTradeMarker) -> some View {
        Circle()
            .fill(tradeMarkerColor(marker.kind))
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.88 : 0.96), lineWidth: 1.4)
            )
            .shadow(color: tradeMarkerColor(marker.kind).opacity(colorScheme == .dark ? 0.38 : 0.26), radius: 3, x: 0, y: 1)
            .accessibilityHidden(true)
    }

    private func tradeMarkerColor(_ kind: FundTrendTradeMarkerKind) -> Color {
        switch kind {
        case .buy:
            toneColor(for: 1)
        case .sell:
            .fundPulseGreen
        }
    }

    private func nearestIndex(for x: CGFloat, width: CGFloat) -> Int? {
        guard points.count > 1, width > 0 else { return nil }
        let ratio = min(max(x / width, 0), 1)
        return min(max(Int((ratio * CGFloat(points.count - 1)).rounded()), 0), points.count - 1)
    }

    private func nearestPointIndex(for markerDateText: String) -> Int? {
        guard !points.isEmpty,
              let markerDate = DateOnlyFormatter.parse(markerDateText)
        else {
            return nil
        }

        if let exactIndex = points.indices.first(where: { dateOnlyText(points[$0].timestamp) == markerDateText }) {
            return exactIndex
        }

        let firstDate = date(from: points[0].timestamp)
        let lastDate = date(from: points[points.count - 1].timestamp)
        guard markerDate >= firstDate && markerDate <= lastDate else {
            return nil
        }

        return points.indices.min { lhs, rhs in
            abs(points[lhs].timestamp - Int64(markerDate.timeIntervalSince1970 * 1000)) <
                abs(points[rhs].timestamp - Int64(markerDate.timeIntervalSince1970 * 1000))
        }
    }

    private func pointPosition(for index: Int, in size: CGSize) -> CGPoint {
        guard points.indices.contains(index),
              points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return .zero
        }
        let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
        let y = yPosition(for: points[index].value, height: size.height)
        return CGPoint(x: x, y: y)
    }

    private func markerPosition(for marker: ResolvedFundTrendTradeMarker, in size: CGSize) -> CGPoint {
        guard points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return .zero
        }

        let x = CGFloat(marker.pointIndex) / CGFloat(points.count - 1) * size.width
        let y = yPosition(for: marker.value, height: size.height)
        return CGPoint(x: x, y: y)
    }

    private func yPosition(for value: Double, height: CGFloat) -> CGFloat {
        let bounds = yValueBounds
        let range = max(bounds.max - bounds.min, 0.0001)
        let clampedValue = min(max(value, bounds.min), bounds.max)
        return (1 - CGFloat((clampedValue - bounds.min) / range)) * height
    }

    private func linePath(in size: CGSize) -> Path {
        guard points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return Path()
        }

        var path = Path()
        for (index, point) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
            let y = yPosition(for: point.value, height: size.height)
            let cgPoint = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }
        return path
    }

    private func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }

    private func dateText(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func dateOnlyText(_ timestamp: Int64) -> String {
        DateOnlyFormatter.string(from: date(from: timestamp))
    }

    private func date(from timestamp: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

}

private struct ResolvedFundTrendTradeMarker: Identifiable {
    var id: String
    var kind: FundTrendTradeMarkerKind
    var pointIndex: Int
    var value: Double
}

let panelBorderColor = Color(nsColor: .separatorColor).opacity(0.12)

private func toneColor(for value: Double) -> Color {
    if value > 0 { return Color(red: 239 / 255, green: 77 / 255, blue: 98 / 255) }
    if value < 0 { return .fundPulseGreen }
    return Color.secondary
}

private func todayIncomeAmount(_ value: Double, isMasked: Bool = false) -> Text {
    if isMasked {
        return Text("***")
            .font(.system(size: 30, weight: .semibold))
    }
    let sign = value > 0 ? "+" : value < 0 ? "-" : ""
    let amount = abs(value).formatted(.number.precision(.fractionLength(2)))
    return Text("\(sign)\(amount)")
        .font(.system(size: 30, weight: .semibold))
}

func inferredInitialTradeRecord(for fund: FundPosition) -> FundTradeRecord? {
    let shares = fund.migratedShares ?? 0
    let amount = inferredInitialTradeRecordAmount(for: fund)
    guard shares > 0 || (amount ?? 0) > 0 else {
        return nil
    }

    let tradeDate = fund.positionDate ?? fund.incomeStartDate ?? ""
    let acceptedDate = fund.incomeStartDate ?? fund.positionDate ?? tradeDate
    let status: FundTradeRecordStatus = fund.status.isPendingDisplay ? .pending : .confirmed
    return FundTradeRecord(
        id: inferredInitialTradeRecordID(for: fund.code),
        kind: .newFund,
        status: status,
        code: fund.code,
        name: fund.name,
        mode: fund.positionMode ?? .share,
        amount: amount,
        shares: fund.positionMode == .amount ? nil : (shares > 0 ? shares : nil),
        confirmedShares: fund.positionMode == .amount ? nil : (status == .confirmed && shares > 0 ? shares : nil),
        price: fund.positionMode == .amount ? nil : fund.migratedCost,
        profit: fund.positionMode == .amount ? fund.pendingProfit : nil,
        tradeDate: tradeDate,
        tradeTimeType: fund.positionTimeType ?? .before15,
        acceptedDate: acceptedDate,
        createdAt: .distantPast,
        confirmedAt: status == .confirmed ? .distantPast : nil,
        failureReason: nil
    )
}

private func inferredInitialTradeRecordAmount(for fund: FundPosition) -> Double? {
    if fund.positionMode == .amount {
        return firstPositiveAmount(fund.pendingAmount, fund.migratedPrincipal, fund.currentAmount)
    }
    return firstPositiveAmount(fund.migratedPrincipal, fund.pendingAmount, fund.currentAmount)
}

private func firstPositiveAmount(_ values: Double?...) -> Double? {
    for value in values {
        if let value, value > 0 {
            return value
        }
    }
    return nil
}

private func inferredInitialTradeRecordID(for code: String) -> String {
    "inferred-new-fund-\(code)"
}

private func isInferredInitialTradeRecord(_ record: FundTradeRecord) -> Bool {
    record.id == inferredInitialTradeRecordID(for: record.code)
}

private func tradeRecordTimeDescending(_ lhs: FundTradeRecord, _ rhs: FundTradeRecord) -> Bool {
    if lhs.tradeDate != rhs.tradeDate {
        return lhs.tradeDate > rhs.tradeDate
    }
    if lhs.tradeTimeType != rhs.tradeTimeType {
        return lhs.tradeTimeType.sortOrder > rhs.tradeTimeType.sortOrder
    }
    if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt > rhs.createdAt
    }
    return lhs.id > rhs.id
}

private extension PositionTimeType {
    var sortOrder: Int {
        switch self {
        case .before15:
            0
        case .after15:
            1
        }
    }
}

private struct MainPopoverNativeScrollConfiguration: NSViewRepresentable {
    @MainActor
    func makeNSView(context: Context) -> NativeScrollConfigurationView {
        NativeScrollConfigurationView(frame: .zero)
    }

    @MainActor
    func updateNSView(_ view: NativeScrollConfigurationView, context: Context) {
        view.configureEnclosingScrollView()
    }
}

@MainActor
private final class NativeScrollConfigurationView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                scrollView.drawsBackground = false
                scrollView.hasVerticalScroller = true
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.scrollerStyle = .overlay
                scrollView.scrollerInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 2)
                scrollView.verticalScroller?.controlSize = .small
                scrollView.verticalScroller?.knobStyle = .default
                return
            }
            ancestor = current.superview
        }
    }
}

private let refreshTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm:ss"
    return formatter
}()

private func refreshTimeText(_ date: Date) -> String {
    refreshTimeFormatter.string(from: date)
}
