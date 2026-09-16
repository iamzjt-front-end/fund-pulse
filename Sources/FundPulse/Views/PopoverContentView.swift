import AppKit
import SwiftUI

struct PopoverContentView: View {
    let store: PortfolioStore
    let settingsStore: AppSettingsStore
    let marketIndexStore: MarketIndexStore
    let updateStore: AppUpdateStore
    let selectedFundCode: String?
    let onRefresh: (() async -> Void)?
    let onOpenPortfolioBreakdown: () -> Void
    let onOpenTodayIncomeRanking: () -> Void
    let onOpenTodayRateRanking: () -> Void
    let onOpenHoldingIncome: () -> Void
    let onOpenHoldingRate: () -> Void
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
    @AppStorage(AppPreferenceKey.dismissedPendingActivityNoticeIDs)
    private var dismissedPendingActivityNoticeIDsRawValue = ""
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
        .onAppear {
            normalizePendingActivityNoticeDismissal()
            normalizeFilterForAccount()
        }
        .onChange(of: pendingActivityIDs) { _, _ in
            normalizePendingActivityNoticeDismissal()
        }
        .onChange(of: store.accountKind) { _, _ in
            normalizeFilterForAccount()
        }
    }

    private var usesExchangeFirstDayReconciliation: Bool {
        guard store.accountKind == .onExchange,
              let reconciliation = store.snapshot.exchangeAccountReconciliation
        else {
            return false
        }
        return reconciliation.date == DateOnlyFormatter.string(from: store.snapshot.updateTime)
    }

    private var todayIncomeTitle: String {
        if usesExchangeFirstDayReconciliation { return "当日参考盈亏" }
        return store.accountKind == .onExchange ? "今日收益(元)" : "实时收益(元)"
    }

    private var todayRateTitle: String {
        if usesExchangeFirstDayReconciliation { return "当日收益率" }
        return store.accountKind == .onExchange ? "今日收益率" : "实时收益率"
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
                        "持仓金额",
                        headerMoneyText(store.snapshot.totalAmount),
                        isTotal: true
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help("查看持仓占比")
                Button(action: onOpenHoldingIncome) {
                    metricCard(
                        "持仓收益",
                        headerHoldingIncomeText(store.snapshot.holdingIncome),
                        tone: headerMetricTone(store.snapshot.holdingIncome)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help("打开持仓收益")

                Button(action: onOpenHoldingRate) {
                    metricCard(
                        "持仓收益率",
                        headerPercentText(store.snapshot.holdingIncomeRate),
                        tone: store.snapshot.holdingIncomeRate
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help("打开持仓收益率")
            }

            if store.accountKind == .offExchange, let pendingHeaderImpact {
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
                            Text(todayIncomeTitle)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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
                .help("查看\(todayIncomeTitle)排行")

                Button(action: onOpenTodayRateRanking) {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(todayRateTitle)
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
                .fixedSize(horizontal: true, vertical: false)
                .help("查看\(todayRateTitle)排行")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
            .opacity(filter == .pending ? 0 : 1)
            .allowsHitTesting(filter != .pending)
            .accessibilityHidden(filter == .pending)

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
        return !confirmedFunds.isEmpty && confirmedFunds.allSatisfy {
            FundUpdatePresentationPolicy.showsOfficialUpdateMarker(for: $0, accountKind: store.accountKind)
        }
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
            return "下载完成后会显示“现在更新”。"
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
            if filter == .pending {
                VStack(spacing: 0) {
                    MainPopoverNativeScrollConfiguration()
                        .frame(height: 0)
                    pendingActivityList
                }
                .frame(maxWidth: .infinity, alignment: .top)
            } else {
                LazyVStack(spacing: 0) {
                    MainPopoverNativeScrollConfiguration()
                        .frame(height: 0)
                    fundRows
                }
                .frame(maxWidth: .infinity, alignment: .top)
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
            ContentUnavailableView(
                "暂无基金数据",
                systemImage: "tray",
                description: Text("点击上方 + 添加第一只基金，或在设置中重新查看使用引导。")
            )
                .frame(height: 300)
        } else {
            ForEach(filteredFunds) { fund in
                let isClosedZeroPosition = PendingFundDisplayRules.isClosedZeroPosition(
                    fund,
                    tradeRecords: tradeRecords
                )
                FundRowView(
                    fund: fund,
                    accountKind: store.accountKind,
                    sortMode: sortMode,
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
                if showsPendingActivityNotice {
                    PendingActivityNotice(onDismiss: dismissPendingActivityNotice)
                    Divider()
                }
                ForEach(pendingActivities) { activity in
                    PendingTradeActivityRow(
                        activity: activity,
                        isSelected: selectedFundCode == activity.code,
                        onDelete: {
                            deletingPendingActivity = activity
                        }
                    ) {
                        onOpenPendingActivity(activity)
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
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
            VStack(spacing: 0) {
                if let breadth = marketIndexStore.marketBreadth {
                    marketBreadthMiniSummary(breadth)
                        .padding(.horizontal, 8)
                        .padding(.top, 7)
                }

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
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
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
                .frame(height: marketIndexStore.marketBreadth == nil ? 30 : 25)
            }
            .frame(height: marketIndexStore.marketBreadth == nil ? 30 : 50)
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

            if let breadth = marketIndexStore.marketBreadth {
                marketBreadthSummary(breadth)
                    .padding(.horizontal, 14)
            }

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

    private func marketBreadthSummary(_ breadth: MarketBreadth) -> some View {
        let sentiment = marketBreadthSentiment(for: breadth)

        return VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("大盘")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(sentiment.title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(sentiment.color)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(
                                sentiment.color.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                in: Capsule()
                            )
                    }

                    Text(sentiment.detail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                marketBreadthMetric(title: "上涨", count: breadth.risingCount, color: toneColor(for: 1))

                Rectangle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.20 : 0.14))
                    .frame(width: 0.7, height: 24)

                marketBreadthMetric(title: "下跌", count: breadth.fallingCount, color: toneColor(for: -1))
            }

            marketBreadthBar(breadth)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            marketBreadthSummaryBackground(sentiment.color),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(sentiment.color.opacity(colorScheme == .dark ? 0.14 : 0.09), lineWidth: 0.7)
        )
        .accessibilityLabel("A股全市场上涨\(breadth.risingCount)家，下跌\(breadth.fallingCount)家")
    }

    private func marketBreadthMetric(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(count.formatted())
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(width: 56, alignment: .trailing)
    }

    private func marketBreadthBar(_ breadth: MarketBreadth) -> some View {
        let total = max(breadth.activeCount, 1)
        let risingRatio = min(max(CGFloat(breadth.risingCount) / CGFloat(total), 0), 1)
        let fallingRatio = 1 - risingRatio

        return GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(toneColor(for: 1).opacity(colorScheme == .dark ? 0.88 : 0.78))
                        .frame(width: width * risingRatio)
                    Rectangle()
                        .fill(toneColor(for: -1).opacity(colorScheme == .dark ? 0.88 : 0.78))
                        .frame(width: width * fallingRatio)
                }
                .clipShape(Capsule())

                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.26 : 0.18))
                    .frame(width: 0.7)
                    .offset(x: width / 2)
            }
        }
        .frame(height: 5)
    }

    private func marketBreadthMiniSummary(_ breadth: MarketBreadth) -> some View {
        HStack(spacing: 4) {
            Text("大盘")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            marketBreadthMiniChip(
                systemName: "arrowtriangle.up.fill",
                count: breadth.risingCount,
                color: toneColor(for: 1)
            )
            .fixedSize(horizontal: true, vertical: false)

            marketBreadthMiniChip(
                systemName: "arrowtriangle.down.fill",
                count: breadth.fallingCount,
                color: toneColor(for: -1)
            )
            .fixedSize(horizontal: true, vertical: false)

            marketBreadthMiniBar(breadth)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(
            Color.secondary.opacity(colorScheme == .dark ? 0.12 : 0.06),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.7)
        )
        .accessibilityLabel("大盘上涨\(breadth.risingCount)家，下跌\(breadth.fallingCount)家")
    }

    private func marketBreadthMiniChip(
        systemName: String,
        count: Int,
        color: Color
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 6.8, weight: .bold))
                .frame(width: 7, height: 7)
            Text(count.formatted())
                .font(.system(size: 8.5, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(color.opacity(colorScheme == .dark ? 0.92 : 0.84))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, 4)
        .frame(height: 14)
        .background(
            color.opacity(colorScheme == .dark ? 0.14 : 0.08),
            in: Capsule()
        )
    }

    private func marketBreadthMiniBar(_ breadth: MarketBreadth) -> some View {
        let total = max(breadth.activeCount, 1)
        let risingRatio = min(max(CGFloat(breadth.risingCount) / CGFloat(total), 0), 1)
        let fallingRatio = 1 - risingRatio

        return GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.13 : 0.09))
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(toneColor(for: 1).opacity(colorScheme == .dark ? 0.78 : 0.66))
                        .frame(width: width * risingRatio)
                    Rectangle()
                        .fill(toneColor(for: -1).opacity(colorScheme == .dark ? 0.78 : 0.66))
                        .frame(width: width * fallingRatio)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func marketBreadthSentiment(for breadth: MarketBreadth) -> (title: String, detail: String, color: Color) {
        let activeCount = max(breadth.activeCount, 1)
        let risingShare = Double(breadth.risingCount) / Double(activeCount)
        let risingShareText = (risingShare * 100).formatted(.number.precision(.fractionLength(0)))
        let detail = "涨占比 \(risingShareText)%"

        if risingShare >= 0.58 {
            return ("偏强", detail, toneColor(for: 1))
        }
        if risingShare <= 0.42 {
            return ("偏弱", detail, toneColor(for: -1))
        }
        return ("均衡", detail, Color.secondary)
    }

    private func marketBreadthSummaryBackground(_ tone: Color) -> some ShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    tone.opacity(colorScheme == .dark ? 0.12 : 0.065),
                    Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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

    private func headerHoldingIncomeText(_ value: Double) -> String {
        hidesHeaderAmounts
            ? hiddenMoneyPlaceholder
            : MoneyFormatter.holdingIncome(value, accountKind: store.accountKind)
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
            store.quoteRefreshWarning ?? TradingCalendar.coverageWarning(on: .now)
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
        if store.quoteRefreshWarning != nil { return .orange }
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
        if let warning = store.quoteRefreshWarning { return warning }
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

    private var listPresentation: PortfolioListPresentation {
        store.listPresentation(filter: filter, sort: sortMode)
    }

    private var filteredFunds: [FundPosition] { listPresentation.funds }

    private func count(for value: FundListFilter) -> Int {
        value == .holding ? listPresentation.holdingCount : displayPendingCount
    }

    private var displayPendingCount: Int { listPresentation.pendingActivities.count }

    private var pendingHeaderImpact: PendingHeaderImpact? { listPresentation.pendingImpact }

    private var visibleFilters: [FundListFilter] {
        FundListFilterPolicy.visibleFilters(for: store.accountKind)
    }

    private func normalizeFilterForAccount() {
        guard !visibleFilters.contains(filter) else { return }
        filter = .holding
        isSortMenuPresented = false
    }

    private var tradeRecords: [FundTradeRecord] {
        store.snapshot.tradeRecords ?? []
    }

    private var pendingActivities: [PendingTradeActivity] {
        listPresentation.pendingActivities
    }

    private var pendingActivityIDs: [String] {
        pendingActivities.map(\.id)
    }

    private var dismissedPendingActivityNoticeIDs: Set<String> {
        PendingActivityNoticePolicy.decodeDismissedActivityIDs(
            from: dismissedPendingActivityNoticeIDsRawValue
        )
    }

    private var showsPendingActivityNotice: Bool {
        PendingActivityNoticePolicy.shouldShow(
            activityIDs: pendingActivityIDs,
            dismissedActivityIDs: dismissedPendingActivityNoticeIDs
        )
    }

    private func dismissPendingActivityNotice() {
        dismissedPendingActivityNoticeIDsRawValue = PendingActivityNoticePolicy.encodeDismissedActivityIDs(
            Set(pendingActivityIDs)
        )
    }

    private func normalizePendingActivityNoticeDismissal() {
        let normalized = PendingActivityNoticePolicy.normalizedDismissedActivityIDs(
            activityIDs: pendingActivityIDs,
            dismissedActivityIDs: dismissedPendingActivityNoticeIDs
        )
        let rawValue = PendingActivityNoticePolicy.encodeDismissedActivityIDs(normalized)
        if rawValue != dismissedPendingActivityNoticeIDsRawValue {
            dismissedPendingActivityNoticeIDsRawValue = rawValue
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
        if activity.recordID == nil {
            return "确定删除“\(activity.name)”这条待确认基金吗？删除后会移除这条待确认记录，且无法撤销。"
        }
        return "确定删除 \(activity.tradeDate) \(activity.tradeTimeType.title) 的\(activity.kind.title)待确认记录吗？删除后会移除这笔待确认交易，且无法撤销。"
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
