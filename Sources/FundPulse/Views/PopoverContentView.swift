import AppKit
import SwiftUI

struct MainPanelWindowView: View {
    let store: PortfolioStore
    let updateStore: AppUpdateStore
    let uiState: PopoverUIState
    let mainPanelHeight: CGFloat
    let selectedFundCode: String?
    let onRefresh: (() async -> Void)?
    let onOpenSettings: () -> Void
    let onAddFund: () -> Void
    let onOpenFundDetail: (FundPosition) -> Void
    let onBuyFund: (FundPosition) -> Void
    let onSellFund: (FundPosition) -> Void
    let onEditFund: (FundPosition) -> Void
    let onDeleteFund: (FundPosition) async -> Void
    let onCheckUpdate: (() async -> Void)?
    let onOpenUpdate: (() -> Void)?

    var body: some View {
        let contentHeight = PopoverLayout.clampedMainPanelHeight(mainPanelHeight)

        ZStack(alignment: .top) {
            PopoverChromeShape(arrowX: uiState.arrowX)
                .fill(popoverChromeFillColor)
                .overlay(
                    PopoverChromeShape(arrowX: uiState.arrowX)
                        .stroke(panelBorderColor, lineWidth: 0.5)
                )
            
            PopoverContentView(
                store: store,
                updateStore: updateStore,
                selectedFundCode: selectedFundCode,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
                onAddFund: onAddFund,
                onOpenFundDetail: onOpenFundDetail,
                onBuyFund: onBuyFund,
                onSellFund: onSellFund,
                onEditFund: onEditFund,
                onDeleteFund: onDeleteFund,
                onCheckUpdate: onCheckUpdate,
                onOpenUpdate: onOpenUpdate
            )
            .frame(width: PopoverLayout.mainWidth, height: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: PopoverLayout.cornerRadius, style: .continuous))
            .offset(y: PopoverLayout.arrowHeight)
        }
        .frame(width: PopoverLayout.mainWidth, height: PopoverLayout.mainWindowHeight(forHeight: contentHeight), alignment: .top)
        .background(Color.clear)
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
    let updateStore: AppUpdateStore
    let selectedFundCode: String?
    let onRefresh: (() async -> Void)?
    let onOpenSettings: () -> Void
    let onAddFund: () -> Void
    let onOpenFundDetail: (FundPosition) -> Void
    let onBuyFund: (FundPosition) -> Void
    let onSellFund: (FundPosition) -> Void
    let onEditFund: (FundPosition) -> Void
    let onDeleteFund: (FundPosition) async -> Void
    let onCheckUpdate: (() async -> Void)?
    let onOpenUpdate: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isRefreshing = false
    @State private var filter: FundListFilter = .holding
    @State private var sortMode: FundSortMode = .todayRate
    @State private var isSortMenuPresented = false
    @Namespace private var filterSwitchNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)
            toolbar
                .zIndex(3)
            fundList
                .zIndex(0)
        }
        .background(panelSurfaceBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 6) {
                    refreshStatusIndicator
                    Text("刷新 \(refreshTimeText(store.snapshot.updateTime))")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer()
                marketBadge
                if displayPendingCount > 0 {
                    Text("待确认 \(displayPendingCount)笔")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(pendingBadgeForeground)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(pendingBadgeBackground, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(pendingBadgeForeground.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 0.6)
                        )
                }
            }

            if let statusMessage {
                statusBanner(statusMessage)
            }

            if shouldShowAppUpdateRow {
                appUpdateRow
            }

            HStack(spacing: 6) {
                metricCard(
                    "总金额",
                    MoneyFormatter.plainMoney(store.snapshot.totalAmount),
                    footnote: pendingAmountSummaryText,
                    isTotal: true
                )
                metricCard(
                    "持有收益",
                    MoneyFormatter.money(store.snapshot.holdingIncome, signed: true),
                    tone: store.snapshot.holdingIncome
                )
                metricCard(
                    "持有收益率",
                    MoneyFormatter.percent(store.snapshot.holdingIncomeRate, signed: true),
                    tone: store.snapshot.holdingIncomeRate
                )
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日收益(元)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    todayIncomeAmount(store.snapshot.todayIncome)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(toneColor(for: store.snapshot.todayIncome))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("今日收益率")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(MoneyFormatter.percent(store.snapshot.todayIncomeRate, signed: true))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(toneColor(for: store.snapshot.todayIncomeRate))
                }
                .padding(.bottom, 3)
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
        HStack(spacing: 6) {
            filterSwitchControl

            Spacer(minLength: 6)

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
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 44)
        .background(toolbarSurfaceBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(colorScheme == .dark ? 0.45 : 0.55)
        }
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
        .background(listSurfaceBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.24 : 0.18))
                .frame(height: 0.6)
                .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var appUpdateRowIcon: some View {
        switch updateStore.status {
        case .available:
            appUpdateIconShell(systemName: "arrow.down", color: appUpdateRowAccentColor)
        case .downloading:
            UpdateProgressRing(progress: updateStore.downloadProgress)
                .frame(width: 26, height: 26)
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
            HStack(spacing: 6) {
                UpdateProgressRing(progress: updateStore.downloadProgress, lineWidth: 3.4, showsGlyph: false)
                    .frame(width: 30, height: 30)
                Text("\(Int(updateStore.downloadProgress * 100))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.leading, 2)
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
        HStack(spacing: 8) {
            addFundToolbarButton
            refreshToolbarButton
            toolbarRefreshStateButton
            toolbarIconButton("gearshape", "设置", action: onOpenSettings)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var refreshToolbarButton: some View {
        toolbarIconButton("arrow.clockwise", isRefreshing ? "刷新中" : "刷新") {
            refresh()
        }
        .disabled(isRefreshing)
    }

    @ViewBuilder
    private var toolbarRefreshStateButton: some View {
        if case .failed(let reason) = store.loadState {
            Button {
                refresh()
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(toolbarControlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(toolbarControlBorder(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(isRefreshing)
            .help("基金数据刷新失败：\(reason)。点击重试")
        }
    }

    private func toolbarIconButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(toolbarIconForeground)
                .frame(width: 28, height: 28)
                .background(toolbarControlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(toolbarControlBorder(cornerRadius: 8))
                .overlay(toolbarControlInnerHighlight(cornerRadius: 7.4))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.025), radius: 3, x: 0, y: 1)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    private var addFundToolbarButton: some View {
        Button(action: onAddFund) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(PanelDesign.accent)
                .frame(width: 28, height: 28)
                .background(addFundToolbarButtonBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(addFundToolbarButtonBorder)
                .overlay(toolbarControlInnerHighlight(cornerRadius: 7.4))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.025), radius: 3, x: 0, y: 1)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("新增基金")
    }

    private var addFundToolbarButtonBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(PanelDesign.accent.opacity(colorScheme == .dark ? 0.68 : 0.52), lineWidth: 0.85)
    }

    private var addFundToolbarButtonBackground: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    PanelDesign.accent.opacity(0.18),
                    PanelDesign.accent.opacity(0.10)
                ]
                : [
                    PanelDesign.accent.opacity(0.10),
                    PanelDesign.accent.opacity(0.05)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            withAnimation(.easeInOut(duration: 0.12)) {
                filter = value
                isSortMenuPresented = false
            }
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

    private var sortMenuLabel: some View {
        HStack(spacing: 5) {
            Text(sortMode.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(minWidth: 80, minHeight: 26)
        .fixedSize(horizontal: true, vertical: false)
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
                if filter == .pending {
                    pendingActivityList
                } else {
                    fundRows
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await refreshAsync()
        }
        .background(listSurfaceBackground)
    }

    @ViewBuilder
    private var fundRows: some View {
        if filteredFunds.isEmpty {
            ContentUnavailableView("暂无基金数据", systemImage: "tray")
                .frame(height: 300)
        } else {
            ForEach(filteredFunds) { fund in
                FundRowView(
                    fund: fund,
                    isSelected: selectedFundCode == fund.code,
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
            ForEach(pendingActivities) { activity in
                PendingTradeActivityRow(activity: activity) {
                    if let fund = activity.fund {
                        onOpenFundDetail(fund)
                    }
                }
                Divider()
            }
        }
    }

    private var refreshStatusIndicator: some View {
        Circle()
            .fill(refreshStatusColor)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.55), lineWidth: 0.6)
            )
            .shadow(color: refreshStatusColor.opacity(0.28), radius: 3, x: 0, y: 1)
            .help(refreshStatusHelp)
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

    private var refreshStatusColor: Color {
        if isRefreshing { return .orange }
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
        if isRefreshing { return "正在刷新基金数据" }
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
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(isTotal ? totalAmountAccentColor : (tone.map(toneColor(for:)) ?? Color.primary))

            if let footnote {
                Text(footnote)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(pendingAmountFootnoteColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: pendingAmountSummaryText == nil ? 42 : 52)
        .background(metricCardBackground(tone, isTotal: isTotal), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(metricCardBorder)
        .overlay(metricCardInnerHighlight)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035), radius: 8, x: 0, y: 4)
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

    private func toolbarControlBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.12)
                    : Color(red: 213 / 255, green: 204 / 255, blue: 190 / 255).opacity(0.44),
                lineWidth: 0.85
            )
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
        let funds = store.snapshot.funds.filter { fund in
            switch filter {
            case .holding:
                fund.status == .holding
            case .pending:
                isPendingStatus(fund.status)
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
            store.snapshot.funds.filter { $0.status == .holding }.count
        case .pending:
            displayPendingCount
        }
    }

    private var displayPendingCount: Int {
        pendingActivities.count
    }

    private var pendingAmountSummaryText: String? {
        var buyAmount: Double = 0
        var sellAmount: Double = 0
        var buyShares: Double = 0
        var sellShares: Double = 0

        for activity in pendingActivities {
            switch activity.kind {
            case .newFund, .buy:
                if let amount = activity.amount, amount > 0 {
                    buyAmount += amount
                } else if let shares = activity.shares, shares > 0 {
                    buyShares += shares
                }
            case .sell:
                if let amount = activity.amount, amount > 0 {
                    sellAmount += amount
                } else if let shares = activity.shares, shares > 0 {
                    sellShares += shares
                }
            }
        }

        var parts: [String] = []
        if buyAmount > 0 {
            parts.append("+\(compactPendingMoney(buyAmount))")
        }
        if sellAmount > 0 {
            parts.append("-\(compactPendingMoney(sellAmount))")
        }
        if buyShares > 0 {
            parts.append("+\(compactPendingShares(buyShares))份")
        }
        if sellShares > 0 {
            parts.append("-\(compactPendingShares(sellShares))份")
        }

        guard !parts.isEmpty else { return nil }
        return "待确认 \(parts.joined(separator: " / "))"
    }

    private var visibleFilters: [FundListFilter] {
        FundListFilter.allCases
    }

    private func isPendingStatus(_ status: FundHoldingStatus) -> Bool {
        status.isPendingDisplay
    }

    private var pendingActivities: [PendingTradeActivity] {
        let fundsByCode = Dictionary(uniqueKeysWithValues: store.snapshot.funds.map { ($0.code, $0) })
        let records = store.snapshot.tradeRecords ?? []
        let pendingTrades = store.snapshot.pendingTrades ?? []
        let pendingTradeRecordIDs = Set(pendingTrades.compactMap(\.recordID))

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
                kind: record?.kind ?? tradeKind(for: pendingTrade.action),
                code: pendingTrade.code,
                name: record?.name ?? fund?.name ?? pendingTrade.code,
                mode: record?.mode ?? pendingTrade.mode,
                amount: record?.amount ?? pendingTrade.amount,
                shares: record?.shares ?? pendingTrade.shares,
                tradeDate: pendingTrade.tradeDate,
                tradeTimeType: pendingTrade.tradeTimeType,
                acceptedDate: acceptedDate,
                createdAt: pendingTrade.createdAt,
                fund: fund
            )
        }

        let pendingRecords = records.filter {
            $0.status == .pending && !pendingTradeRecordIDs.contains($0.id)
        }
        activities.append(contentsOf: pendingRecords.map { record in
            PendingTradeActivity(
                id: "pending-record-\(record.id)",
                kind: record.kind,
                code: record.code,
                name: record.name,
                mode: record.mode,
                amount: record.amount,
                shares: record.shares,
                tradeDate: record.tradeDate,
                tradeTimeType: record.tradeTimeType,
                acceptedDate: record.acceptedDate,
                createdAt: record.createdAt,
                fund: fundsByCode[record.code]
            )
        })

        let pendingNewFundCodes = Set(
            activities
                .filter { $0.kind == .newFund }
                .map(\.code)
        )
        let legacyPendingFunds = store.snapshot.funds.filter {
            isPendingStatus($0.status) && !pendingNewFundCodes.contains($0.code)
        }
        activities.append(contentsOf: legacyPendingFunds.map { fund in
            let tradeDate = fund.positionDate ?? DateOnlyFormatter.string(from: .now)
            let timeType = fund.positionTimeType ?? .before15
            return PendingTradeActivity(
                id: "pending-fund-\(fund.code)",
                kind: .newFund,
                code: fund.code,
                name: fund.name,
                mode: fund.positionMode ?? .amount,
                amount: fund.pendingAmount,
                shares: fund.migratedShares,
                tradeDate: tradeDate,
                tradeTimeType: timeType,
                acceptedDate: TradingCalendar.acceptedTradeDate(positionDate: tradeDate, timeType: timeType),
                createdAt: .distantPast,
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

    private func tradeKind(for action: FundTradeAction) -> FundTradeKind {
        switch action {
        case .buy:
            .buy
        case .sell:
            .sell
        }
    }

    private func compactPendingMoney(_ value: Double) -> String {
        "¥\(value.formatted(.number.precision(.fractionLength(0))))"
    }

    private func compactPendingShares(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await refreshAsync()
            await MainActor.run {
                isRefreshing = false
            }
        }
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

private struct PendingTradeActivity: Identifiable {
    var id: String
    var kind: FundTradeKind
    var code: String
    var name: String
    var mode: PositionMode
    var amount: Double?
    var shares: Double?
    var tradeDate: String
    var tradeTimeType: PositionTimeType
    var acceptedDate: String
    var createdAt: Date
    var fund: FundPosition?
}

private struct PendingTradeActivityRow: View {
    let activity: PendingTradeActivity
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        tag(activity.kind.title, color: accentColor)
                        Text(activity.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        tag("待确认", color: .orange)
                    }

                    HStack(alignment: .top, spacing: 7) {
                        Text(FundCodeFormatter.display(activity.code))
                            .frame(width: 58, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(activity.tradeDate) \(activity.tradeTimeType.title)")
                            Text("确认 \(activity.acceptedDate)")
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(primaryValueText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accentColor)
                    Text(activity.mode.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var accentColor: Color {
        activity.kind == .sell ? .fundPulseGreen : .red
    }

    private var primaryValueText: String {
        if let amount = activity.amount {
            return MoneyFormatter.plainMoney(amount)
        }
        if let shares = activity.shares {
            return "\(numberText(shares, places: 2))份"
        }
        return "--"
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }
}

struct FundRowView: View {
    let fund: FundPosition
    let isSelected: Bool
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
                    if fund.isUpdated {
                        tag("已更新", color: updatedTagColor)
                    }
                    Text(fund.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    tag(fund.status.title, color: fund.status.isPendingDisplay ? .orange : .blue)
                    if fund.status == .holding {
                        tag(rowHoldingRateText, color: toneColor(for: rowHoldingRate ?? rowConfirmedHoldingIncome))
                    }
                }

                HStack(spacing: 6) {
                    Text(FundCodeFormatter.display(fund.code))
                    Text(rowHoldingAmountText)
                    Text(compactMoney(rowConfirmedHoldingIncome))
                        .foregroundStyle(toneColor(for: rowConfirmedHoldingIncome))
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
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

    private var updatedTagColor: Color {
        Color(red: 254 / 255, green: 143 / 255, blue: 37 / 255)
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
        MoneyFormatter.plainMoney(rowHoldingAmount)
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

    private func compactMoney(_ value: Double) -> String {
        MoneyFormatter.money(value, signed: true)
            .replacingOccurrences(of: "¥ ", with: "")
            .replacingOccurrences(of: "+¥", with: "+")
            .replacingOccurrences(of: "-¥", with: "-")
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

struct FundDetailView: View {
    let fund: FundPosition
    let totalAmount: Double
    let pendingTradeCount: Int
    let tradeRecords: [FundTradeRecord]
    let onBuy: (FundPosition) -> Void
    let onSell: (FundPosition) -> Void
    let onEdit: (FundPosition) -> Void
    let onOpenTradeRecords: (FundPosition) -> Void
    let onDelete: (FundPosition) async -> Void
    let onClose: () -> Void

    @State private var isDeleteConfirmationPresented = false
    @State private var supplement: FundDetailSupplement = .empty
    @State private var isSupplementLoading = false
    @State private var didLoadSupplement = false
    @Environment(\.colorScheme) private var colorScheme

    private let supplementService = FundQuoteService()

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "基金详情",
                subtitle: FundCodeFormatter.display(fund.code),
                tint: toneColor(for: fund.todayRate),
                accessoryText: zdfRangeReminderText,
                accessoryColor: .orange,
                actionSystemImage: "list.bullet.rectangle",
                actionTitle: "交易记录",
                actionBadgeText: tradeRecordsBadgeText,
                actionTint: .blue,
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
                    extraPills
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
            Button("确认删除", role: .destructive) {
                Task {
                    await onDelete(fund)
                    onClose()
                }
            }
        } message: {
            Text("确定删除“\(fund.name)”吗？这会移除它的持仓记录。")
        }
    }

    private var fundTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fund.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 7) {
                Text(FundCodeFormatter.display(fund.code))
                Text(fund.dateText)
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
            metric("持有收益", signedNumberText(holdingIncome), tone: holdingIncome)
            metric("持有收益率", fund.holdingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "0.00%", tone: fund.holdingRate)
            metric("持有天数", holdingDaysText)
            metric("昨日收益", yesterdayIncomeText, tone: yesterdayIncome)
            metric("昨日收益率", yesterdayRateText, tone: yesterdayRate)
            metric("持仓占比", holdingRatioText)
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "近90日净值走势",
                trailing: supplement.trend.last.map { "最新净值 \(numberText($0.value, places: 4))" }
            )

            if supplement.trend.count >= 2 {
                FundTrendMiniChart(points: supplement.trend)
                    .frame(height: 116)
            } else {
                emptySupplementView(isSupplementLoading ? "走势加载中..." : "暂无走势数据")
                    .frame(height: 86)
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("历史净值", trailing: historyTrailingText)

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
            sectionHeader("前10重仓股", trailing: topHoldingsTrailingText)

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

    @ViewBuilder
    private var extraPills: some View {
        if (pendingTradeCount > 0 && pendingTradeRecords.isEmpty) || fund.jzNotice != nil {
            HStack(spacing: 6) {
                if pendingTradeCount > 0 && pendingTradeRecords.isEmpty {
                    detailPill("待确认交易 \(pendingTradeCount)笔")
                }
                if let jzNotice = fund.jzNotice {
                    detailPill("净值提醒 \(numberText(jzNotice, places: 4))")
                }
            }
        }
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

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            if isSupplementLoading {
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
        return records
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.tradeDate > $1.tradeDate
            }
    }

    private var pendingTradeRecords: [FundTradeRecord] {
        recentTradeRecords.filter { $0.status == .pending }
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
        if summary.buyShares > 0 {
            parts.append("+\(compactPendingShares(summary.buyShares))份")
        }
        if summary.sellShares > 0 {
            parts.append("-\(compactPendingShares(summary.sellShares))份")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " / ")
    }

    private var pendingTradeSummaryDetail: String? {
        guard !pendingTradeRecords.isEmpty else { return nil }
        var parts: [String] = []
        let buyCount = pendingTradeRecords.filter { $0.kind == .newFund || $0.kind == .buy }.count
        let sellCount = pendingTradeRecords.filter { $0.kind == .sell }.count
        if buyCount > 0 {
            parts.append("加仓 \(buyCount)笔")
        }
        if sellCount > 0 {
            parts.append("减仓 \(sellCount)笔")
        }
        if let acceptedDate = pendingTradeRecords.map(\.acceptedDate).sorted().first {
            parts.append("确认 \(acceptedDate)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var pendingTradeSummaryTone: Color {
        pendingTradeSummaryValues.buyAmount > 0 || pendingTradeSummaryValues.buyShares > 0
            ? .red
            : .fundPulseGreen
    }

    private var pendingTradeSummaryBackground: Color {
        Color.orange.opacity(0.08)
    }

    private var pendingTradeSummaryValues: (buyAmount: Double, sellAmount: Double, buyShares: Double, sellShares: Double) {
        var buyAmount: Double = 0
        var sellAmount: Double = 0
        var buyShares: Double = 0
        var sellShares: Double = 0

        for record in pendingTradeRecords {
            switch record.kind {
            case .newFund, .buy:
                if let amount = record.amount, amount > 0 {
                    buyAmount += amount
                } else if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    buyShares += shares
                }
            case .sell:
                if let amount = record.amount, amount > 0 {
                    sellAmount += amount
                } else if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    sellShares += shares
                }
            }
        }

        return (buyAmount, sellAmount, buyShares, sellShares)
    }

    private var tradeRecordsEntrySubtitle: String {
        let pendingCount = recentTradeRecords.filter { $0.status == .pending }.count
        guard pendingCount > 0 else { return "查看新增、加仓、减仓流水" }
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
                if !holding.code.isEmpty {
                    Text(holding.code)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
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

    private func metric(_ title: String, _ value: String, tone: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func detailPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(PanelDesign.selectorBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 0.5)
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

    private var yesterdayRate: Double? {
        supplement.yesterdayPoint?.equityReturn
    }

    private var yesterdayIncome: Double? {
        guard let yesterdayPoint = supplement.yesterdayPoint,
              let rate = yesterdayPoint.equityReturn,
              yesterdayEligibleShares > 0
        else {
            return nil
        }
        let denominator = 100 + rate
        guard denominator != 0 else { return 0 }
        return yesterdayEligibleShares * yesterdayPoint.value * rate / denominator
    }

    private var yesterdayIncomeText: String {
        guard let yesterdayIncome else { return "--" }
        return signedNumberText(yesterdayIncome)
    }

    private var yesterdayRateText: String {
        guard yesterdayEligibleShares > 0,
              let yesterdayRate
        else {
            return "--"
        }
        return MoneyFormatter.percent(yesterdayRate, signed: true)
    }

    private var yesterdayEligibleShares: Double {
        guard let yesterdayDateText else { return 0 }
        return effectiveLots.reduce(0) { total, lot in
            lot.incomeStartDate < yesterdayDateText ? total + lot.shares : total
        }
    }

    private var yesterdayDateText: String? {
        guard let timestamp = supplement.yesterdayPoint?.timestamp else {
            return nil
        }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        return DateOnlyFormatter.string(from: date)
    }

    private var topHoldingsTrailingText: String? {
        supplement.topHoldings.isEmpty ? nil : "\(supplement.topHoldings.count)只"
    }

    private var zdfRangeReminderText: String? {
        fund.zdfRange.map { "涨跌幅提醒 \(MoneyFormatter.percent($0, signed: false))" }
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

    private var holdingRatioText: String {
        guard totalAmount > 0 else { return "0.00%" }
        return MoneyFormatter.percent(currentTotal / totalAmount * 100)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
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
        }
    }
}

struct FundTradeRecordsPanelView: View {
    let fund: FundPosition
    let tradeRecords: [FundTradeRecord]
    let onEdit: (FundTradeRecord) -> Void
    let onDelete: (FundTradeRecord) async -> Void
    let onClose: () -> Void

    @State private var filter: TradeRecordFilter = .all
    @State private var deletingRecord: FundTradeRecord?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "clock.arrow.circlepath",
                title: "交易记录",
                subtitle: FundCodeFormatter.display(fund.code),
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
        .alert("删除交易记录", isPresented: deleteConfirmationBinding) {
            Button("取消", role: .cancel) {
                deletingRecord = nil
            }
            Button("删除", role: .destructive) {
                guard let record = deletingRecord else { return }
                Task {
                    await onDelete(record)
                    deletingRecord = nil
                }
            }
        } message: {
            Text("删除后会重新计算这只基金的持有金额、持有份额和成本。")
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
        return records
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.tradeDate > $1.tradeDate
            }
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

    private func tradeRecordRow(_ record: FundTradeRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(recordKindTitle(record.kind))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(tradeKindColor(record.kind))
                .frame(width: 46, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(tradeDateTimeText(record))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(recordMetaText(record))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(tradeRecordAmountText(record))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tradeKindColor(record.kind))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(record.status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tradeStatusColor(record.status))

                Text(record.mode.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 4) {
                    if canEdit(record) {
                        recordActionButton(systemName: "pencil", title: "编辑") {
                            onEdit(record)
                        }
                    }
                    if !isInferredInitialTradeRecord(record) {
                        recordActionButton(systemName: "trash", title: "删除", color: .red) {
                            deletingRecord = record
                        }
                    }
                }
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 74)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
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
                .frame(width: 22, height: 20)
                .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(title)
    }

    private func canEdit(_ record: FundTradeRecord) -> Bool {
        record.kind == .buy || record.kind == .sell
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
        }
    }

    private func tradeDateTimeText(_ record: FundTradeRecord) -> String {
        "\(record.tradeDate) \(record.tradeTimeType.title)"
    }

    private func recordMetaText(_ record: FundTradeRecord) -> String {
        var parts = ["确认 \(record.acceptedDate)"]
        if let price = record.price {
            parts.append("净值 \(numberText(price, places: 4))")
        }
        if let shares = record.confirmedShares ?? record.shares {
            parts.append("\(numberText(shares, places: 2))份")
        }
        return parts.joined(separator: "  ")
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
        kind == .sell ? .fundPulseGreen : .red
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

private struct FundTrendMiniChart: View {
    let points: [FundNetValuePoint]

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

    private var yAxisLabels: some View {
        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let middleValue = (minValue + maxValue) / 2

        return VStack(alignment: .trailing, spacing: 0) {
            Text(numberText(maxValue))
            Spacer()
            Text(numberText(middleValue))
            Spacer()
            Text(numberText(minValue))
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func hoverOverlay(for index: Int, in size: CGSize) -> some View {
        let point = points[index]
        let pointPosition = pointPosition(for: index, in: size)
        let tooltipWidth: CGFloat = 104
        let tooltipHeight: CGFloat = 48
        let tooltipX = min(
            max(pointPosition.x + 12 + tooltipWidth / 2, tooltipWidth / 2),
            max(size.width - tooltipWidth / 2, tooltipWidth / 2)
        )
        let tooltipY = min(max(pointPosition.y - 8, tooltipHeight / 2), max(size.height - tooltipHeight / 2, tooltipHeight / 2))

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: pointPosition.x, y: 0))
                path.addLine(to: CGPoint(x: pointPosition.x, y: size.height))
            }
            .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 0.9, dash: [4, 3]))

            Circle()
                .fill(lineColor)
                .frame(width: 5, height: 5)
                .position(pointPosition)

            VStack(alignment: .leading, spacing: 4) {
                Text(fullDateText(point.timestamp))
                    .font(.system(size: 11, weight: .medium))
                Text("净值：\(numberText(point.value))")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(width: tooltipWidth, height: tooltipHeight, alignment: .leading)
            .background(tooltipBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.30 : 0.22), lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 8, x: 0, y: 4)
            .position(x: tooltipX, y: tooltipY)
        }
    }

    private var tooltipBackground: Color {
        colorScheme == .dark
            ? Color(red: 31 / 255, green: 34 / 255, blue: 40 / 255).opacity(0.98)
            : Color.white.opacity(0.98)
    }

    private func nearestIndex(for x: CGFloat, width: CGFloat) -> Int? {
        guard points.count > 1, width > 0 else { return nil }
        let ratio = min(max(x / width, 0), 1)
        return min(max(Int((ratio * CGFloat(points.count - 1)).rounded()), 0), points.count - 1)
    }

    private func pointPosition(for index: Int, in size: CGSize) -> CGPoint {
        let values = points.map(\.value)
        guard let minValue = values.min(),
              let maxValue = values.max(),
              points.indices.contains(index),
              points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return .zero
        }
        let range = max(maxValue - minValue, 0.0001)
        let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
        let y = (1 - CGFloat((points[index].value - minValue) / range)) * size.height
        return CGPoint(x: x, y: y)
    }

    private func linePath(in size: CGSize) -> Path {
        let values = points.map(\.value)
        guard let minValue = values.min(),
              let maxValue = values.max(),
              points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return Path()
        }

        let range = max(maxValue - minValue, 0.0001)
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
            let y = (1 - CGFloat((point.value - minValue) / range)) * size.height
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

    private func fullDateText(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

let panelBorderColor = Color(nsColor: .separatorColor).opacity(0.12)

private func toneColor(for value: Double) -> Color {
    if value > 0 { return Color(red: 239 / 255, green: 77 / 255, blue: 98 / 255) }
    if value < 0 { return .fundPulseGreen }
    return Color.secondary
}

private func todayIncomeAmount(_ value: Double) -> Text {
    let sign = value > 0 ? "+" : value < 0 ? "-" : ""
    let amount = abs(value).formatted(.number.precision(.fractionLength(2)))
    return Text("\(sign)\(amount)")
        .font(.system(size: 30, weight: .semibold))
}

private func inferredInitialTradeRecord(for fund: FundPosition) -> FundTradeRecord? {
    let shares = fund.migratedShares ?? 0
    let amount = fund.migratedPrincipal ?? fund.pendingAmount
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
        shares: shares > 0 ? shares : nil,
        confirmedShares: status == .confirmed && shares > 0 ? shares : nil,
        price: fund.migratedCost,
        tradeDate: tradeDate,
        tradeTimeType: fund.positionTimeType ?? .before15,
        acceptedDate: acceptedDate,
        createdAt: .distantPast,
        confirmedAt: status == .confirmed ? .distantPast : nil,
        failureReason: nil
    )
}

private func inferredInitialTradeRecordID(for code: String) -> String {
    "inferred-new-fund-\(code)"
}

private func isInferredInitialTradeRecord(_ record: FundTradeRecord) -> Bool {
    record.id == inferredInitialTradeRecordID(for: record.code)
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
