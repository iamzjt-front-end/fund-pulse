import SwiftUI
import WebKit

private enum JDFinanceSyncFlowState: Equatable {
    case checkingSession
    case needsLogin
    case syncing
    case preview
    case error
}

private enum JDFinanceSyncApplyScope: Hashable {
    case newHoldings
    case changedHoldings
    case pendingHoldings
    case reconciliations
    case unrecordedOrders
}

private struct JDFinanceManualPendingInput: Equatable {
    var tradeDate: Date?
    var timeType: PositionTimeType?

    init(tradeDate: Date? = nil, timeType: PositionTimeType? = nil) {
        self.tradeDate = tradeDate
        self.timeType = timeType
    }
}

struct JDFinanceHoldingsSyncView: View {
    private static let syncTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    let portfolioStore: PortfolioStore
    let onRequestLogin: (@escaping (String?) -> Void) -> Void
    let onRequestNetworkProbe: (JDFinanceNetworkProbe) -> Void
    let onMainPanelRefreshNeeded: @MainActor () -> Void
    let onClose: () -> Void

    @State private var syncStore: JDFinanceHoldingsSyncStore
    @State private var networkProbe: JDFinanceNetworkProbe
    @State private var isCheckingExistingSession = true
    @State private var needsLogin = false
    @State private var isRequestingLogin = false
    @State private var loginToastMessage: String?
    @State private var isShowingBaselineResetConfirmation = false
    @State private var isShowingClearanceConfirmation = false
    @State private var clearanceCandidate: JDFinanceMissingLocalHolding?
    @State private var selectedApplyScopes: Set<JDFinanceSyncApplyScope> = []
    @State private var manualPendingInputs: [String: JDFinanceManualPendingInput] = [:]

    @MainActor
    init(
        portfolioStore: PortfolioStore,
        onRequestLogin: @escaping (@escaping (String?) -> Void) -> Void,
        onRequestNetworkProbe: @escaping (JDFinanceNetworkProbe) -> Void,
        onMainPanelRefreshNeeded: @escaping @MainActor () -> Void,
        onClose: @escaping () -> Void
    ) {
#if DEBUG
        let probe = JDFinanceNetworkProbe(persistsEntriesToDisk: true)
#else
        let probe = JDFinanceNetworkProbe(persistsEntriesToDisk: false)
#endif
        self.portfolioStore = portfolioStore
        self.onRequestLogin = onRequestLogin
        self.onRequestNetworkProbe = onRequestNetworkProbe
        self.onMainPanelRefreshNeeded = onMainPanelRefreshNeeded
        self.onClose = onClose
        _networkProbe = State(initialValue: probe)
        _syncStore = State(initialValue: JDFinanceHoldingsSyncStore(
            service: JDFinanceHoldingsService(networkProbe: probe)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "arrow.triangle.2.circlepath",
                title: "京东金融同步",
                subtitle: headerSubtitle,
                tint: PanelDesign.accent,
                onClose: onClose
            )

            VStack(spacing: 10) {
                topActionBar
                contentPanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.panelBackground)
        .overlay(alignment: .top) {
            if let loginToastMessage {
                loginToast(loginToastMessage)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await checkExistingSessionOnAppear()
        }
        .confirmationDialog(
            "重置京东同步基线？",
            isPresented: $isShowingBaselineResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("重置基线", role: .destructive) {
                syncStore.resetSyncBaseline(in: portfolioStore)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下次同步会把当前京东持仓重新作为初始基线；不会删除本地持仓或交易记录。")
        }
        .confirmationDialog(
            "确认清仓对账？",
            isPresented: $isShowingClearanceConfirmation,
            titleVisibility: .visible
        ) {
            if let clearanceCandidate {
                Button("清空 \(clearanceCandidate.name) 的本地持仓", role: .destructive) {
                    applyFullClearance(clearanceCandidate)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅在京东已有最终卖出或转换出流水时可执行。若京东未返回份额，将按本地当前全部剩余份额清仓，并保留完整对账记录。")
        }
    }

    private var headerSubtitle: String {
        if syncStore.isSyncing { return "正在拉取京东持仓..." }
        if syncStore.isApplying { return "导入中" }
        if isCheckingExistingSession { return "检查京东登录态" }
        if needsLogin { return "需要登录后同步" }
        return syncStore.statusMessage
    }

    private var flowState: JDFinanceSyncFlowState {
        if isCheckingExistingSession { return .checkingSession }
        if syncStore.isSyncing { return .syncing }
        if needsLogin { return .needsLogin }
        if syncStore.preview != nil { return .preview }
        if syncStore.errorMessage != nil { return .error }
        return .needsLogin
    }

    private var topActionBar: some View {
        HStack(spacing: 10) {
            primaryFlowControl

            Spacer(minLength: 8)

            compactToolButton(
                systemImage: "list.bullet.rectangle",
                help: "交易记录",
                action: requestNetworkProbe
            )
            .disabled(syncStore.isSyncing || syncStore.isApplying)

            jdFinanceLinkButton

            compactToolButton(
                systemImage: "arrow.counterclockwise",
                help: "重置同步基线",
                role: .destructive,
                action: { isShowingBaselineResetConfirmation = true }
            )
            .disabled(syncStore.isSyncing || syncStore.isApplying || portfolioStore.snapshot.jdFinanceSyncState == nil)

            compactToolButton(
                systemImage: "trash",
                help: "清除登录",
                role: .destructive,
                action: resetLoginSession
            )
            .disabled(syncStore.isSyncing || syncStore.isApplying)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 1)
    }

    @ViewBuilder
    private var primaryFlowControl: some View {
        switch flowState {
        case .checkingSession:
            statusPill("检查登录态", systemImage: "person.crop.circle.badge.checkmark")
        case .needsLogin:
            flowButton("登录京东", systemImage: "person.crop.circle.badge.plus", action: requestLogin)
                .disabled(isRequestingLogin)
        case .syncing:
            statusPill("正在拉取", systemImage: "arrow.triangle.2.circlepath")
        case .preview:
            flowButton("重新同步", systemImage: "arrow.triangle.2.circlepath", action: retrySync)
        case .error:
            HStack(spacing: 7) {
                flowButton("重试同步", systemImage: "arrow.triangle.2.circlepath", action: retrySync)
                flowButton("登录", systemImage: "person.crop.circle.badge.clock", action: requestLogin)
                    .disabled(isRequestingLogin)
            }
        }
    }

    private var jdFinanceLinkButton: some View {
        Button {
            NSWorkspace.shared.open(JDFinanceWebSession.holdingsURL)
        } label: {
            HStack(spacing: 3) {
                Text("jdjr.jd.com")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PanelDesign.accent)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(PanelDesign.accent.opacity(0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(PanelDesign.accent.opacity(0.18), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("在浏览器打开京东金融")
    }

    @ViewBuilder
    private var contentPanel: some View {
        switch flowState {
        case .checkingSession:
            progressPanel("正在检查京东登录态...", subtitle: "如果已登录，将直接同步持仓")
        case .needsLogin:
            needsLoginPanel
        case .syncing:
            progressPanel("正在拉取京东持仓...", subtitle: "登录态已获取，正在读取基金持仓")
        case .preview:
            if let preview = syncStore.preview {
                previewPanel(preview)
            }
        case .error:
            errorPanel
        }
    }

    private var needsLoginPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(PanelDesign.warningAccent)
            Text("需要登录京东")
                .font(.system(size: 15, weight: .semibold))
            Text("登录完成后会自动关闭登录窗口，并继续拉取最新持仓。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button {
                requestLogin()
            } label: {
                PanelButtonLabel(
                    title: isRequestingLogin ? "等待登录" : "登录京东",
                    systemImage: "person.crop.circle.badge.plus",
                    style: .primary,
                    isEnabled: !isRequestingLogin
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(width: 180)
            .disabled(isRequestingLogin)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PanelDesign.warningBorder, lineWidth: 0.8)
        )
    }

    private func progressPanel(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func loginToast(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
    }

    private func previewPanel(_ preview: JDFinanceHoldingsSyncPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            previewOverview(preview)

            if let errorMessage = syncStore.errorMessage {
                inlineSyncError(errorMessage)
            }

            if preview.isEmpty {
                emptyPreviewPanel
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        quietPreviewSummary(preview)

                        if !preview.newHoldings.isEmpty {
                            previewSection(
                                title: "持仓差异 · 新增",
                                count: preview.newHoldings.count,
                                tone: PanelDesign.accent
                            ) {
                                ForEach(preview.newHoldings) { candidate in
                                    newHoldingCard(candidate)
                                }
                            }
                        }

                        if !preview.changedHoldings.isEmpty {
                            previewSection(
                                title: "持仓差异 · 金额/收益",
                                count: preview.changedHoldings.count,
                                tone: .orange
                            ) {
                                ForEach(preview.changedHoldings) { difference in
                                    differenceCard(difference)
                                }
                            }
                        }

                        if !preview.unrecordedOrders.isEmpty {
                            previewSection(
                                title: "京东未入账流水",
                                count: preview.unrecordedOrders.count,
                                tone: .purple
                            ) {
                                ForEach(preview.unrecordedOrders) { order in
                                    unrecordedOrderCard(order)
                                }
                            }
                        }

                        if !preview.reconciliationNotices.isEmpty {
                            previewSection(
                                title: "待覆盖",
                                count: preview.reconciliationNotices.count,
                                tone: PanelDesign.accent
                            ) {
                                ForEach(preview.reconciliationNotices) { notice in
                                    reconciliationNoticeCard(notice)
                                }
                            }
                        }

                        if !preview.missingLocalHoldings.isEmpty {
                            previewSection(
                                title: "可能清仓",
                                count: preview.missingLocalHoldings.count,
                                tone: .green
                            ) {
                                ForEach(preview.missingLocalHoldings) { holding in
                                    missingHoldingCard(holding)
                                }
                            }
                        }

                        if !preview.unresolvedHoldings.isEmpty {
                            previewSection(
                                title: "无法自动识别",
                                count: preview.unresolvedHoldings.count,
                                tone: PanelDesign.warningAccent
                            ) {
                                ForEach(preview.unresolvedHoldings) { holding in
                                    unresolvedHoldingCard(holding)
                                }
                            }
                        }

                        if !preview.pendingNotices.isEmpty {
                            previewSection(
                                title: "京东订单 · 待确认",
                                count: preview.pendingTradeCount,
                                tone: PanelDesign.warningAccent
                            ) {
                                ForEach(preview.pendingNotices) { notice in
                                    pendingNoticeCard(notice)
                                }
                            }
                        }

                        if !preview.warnings.isEmpty || !preview.informationalOrders.isEmpty {
                            previewSection(
                                title: "冲突/提示",
                                count: preview.warnings.count + preview.informationalOrders.count,
                                tone: PanelDesign.warningAccent
                            ) {
                                warningAndInformationCards(preview)
                            }
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func previewOverview(_ preview: JDFinanceHoldingsSyncPreview) -> some View {
        let canApply = canApplySelectedData(preview)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("总资产")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(moneyOrDash(preview.remoteSnapshot.totalAssets))
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    overviewMetric("持有收益", signedMoneyOrDash(preview.remoteSnapshot.holdIncome), tone: toneColor(preview.remoteSnapshot.holdIncome))
                    overviewMetric("昨日收益", signedMoneyOrDash(preview.remoteSnapshot.yesterdayIncome), tone: toneColor(preview.remoteSnapshot.yesterdayIncome))
                    overviewMetric("产品", "\(preview.remoteSnapshot.products.count)", tone: .secondary)
                    tradeOrderCompletenessLabel(preview.remoteSnapshot.tradeOrderFetchState)
                }
            }

            HStack(spacing: 7) {
                countPill("自动确认", preview.autoConfirmedCount, tone: .green)
                countPill("新增", preview.newHoldings.count, tone: PanelDesign.accent)
                countPill("差异", preview.changedHoldings.count, tone: .orange)
                countPill("未入账", preview.unrecordedOrders.count, tone: .purple)
            }
            HStack(spacing: 7) {
                countPill("覆盖", preview.reconciliationNotices.count, tone: PanelDesign.accent)
                countPill("清仓", preview.missingLocalHoldings.count, tone: .green)
                countPill("冲突", preview.unresolvedHoldings.count, tone: PanelDesign.warningAccent)
                countPill("提示", preview.pendingTradeCount + preview.warnings.count, tone: PanelDesign.warningAccent)
            }

            if preview.baselineRepresentedCount > 0 {
                Label(
                    "首次建立同步基线：当前持仓已包含 \(preview.baselineRepresentedCount) 笔历史成功流水，未重复导入。",
                    systemImage: "checkmark.shield"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.48)

            HStack(spacing: 8) {
                if let lastSyncedAt = syncStore.lastSyncedAt {
                    Label(Self.syncTimeFormatter.string(from: lastSyncedAt), systemImage: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if canApply {
                    Button {
                        applySelectedData()
                    } label: {
                        PanelButtonLabel(
                            title: "同步选中",
                            systemImage: "checkmark.circle",
                            style: .primary,
                            isEnabled: true
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .frame(width: 122)
                } else {
                    Label("暂无可同步项", systemImage: "checkmark.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if hasSelectableScopes(preview) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("同步范围")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 6
                    ) {
                        syncScopeToggle(
                            scope: .newHoldings,
                            title: "新增",
                            count: preview.newHoldings.count,
                            tone: PanelDesign.accent
                        )
                        syncScopeToggle(
                            scope: .changedHoldings,
                            title: "金额/收益",
                            count: preview.changedHoldings.count,
                            tone: .orange
                        )
                        syncScopeToggle(
                            scope: .pendingHoldings,
                            title: "待确认",
                            count: preview.importablePendingTradeCount,
                            tone: PanelDesign.warningAccent
                        )
                        syncScopeToggle(
                            scope: .reconciliations,
                            title: "待覆盖",
                            count: preview.overwritableReconciliationNotices.count,
                            tone: PanelDesign.accent
                        )
                        syncScopeToggle(
                            scope: .unrecordedOrders,
                            title: "未入账",
                            count: preview.importableUnrecordedOrders.count,
                            tone: .purple
                        )
                    }
                }
            } else if !preview.missingLocalHoldings.isEmpty || !preview.pendingNotices.isEmpty || !preview.unresolvedHoldings.isEmpty || !preview.warnings.isEmpty {
                Label("未选中的清仓、冲突和处理中记录仅作为提示，不会写入本地。", systemImage: "info.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 12))
    }

    private func overviewMetric(_ title: String, _ value: String, tone: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func tradeOrderCompletenessLabel(_ state: JDFinanceTradeOrderFetchState) -> some View {
        let title: String
        let color: Color
        switch state {
        case .complete:
            title = "流水完整"
            color = .green
        case .incomplete:
            title = "流水不完整"
            color = PanelDesign.warningAccent
        case .notRequested:
            title = "流水未拉取"
            color = .secondary
        }
        return Label(title, systemImage: state.isComplete ? "checkmark.circle" : "exclamationmark.circle")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
    }

    private func countPill(_ title: String, _ count: Int, tone: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tone.opacity(count == 0 ? 0.28 : 0.86))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .medium))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(count == 0 ? Color.secondary.opacity(0.66) : tone)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(PanelDesign.inputBackground.opacity(count == 0 ? 0.42 : 0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(count == 0 ? 0.12 : 0.22), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func quietPreviewSummary(_ preview: JDFinanceHoldingsSyncPreview) -> some View {
        let quietItems = [
            ("无新增", preview.newHoldings.isEmpty),
            ("无金额差异", preview.changedHoldings.isEmpty),
            ("无未入账流水", preview.unrecordedOrders.isEmpty),
            ("无待覆盖", preview.reconciliationNotices.isEmpty),
            ("无清仓提示", preview.missingLocalHoldings.isEmpty),
            ("无识别问题", preview.unresolvedHoldings.isEmpty)
        ].filter(\.1).map(\.0)

        if !quietItems.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(quietItems.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(PanelDesign.inputBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 8))
        }
    }

    private func hasSelectableScopes(_ preview: JDFinanceHoldingsSyncPreview) -> Bool {
        !preview.newHoldings.isEmpty ||
            !preview.changedHoldings.isEmpty ||
            !preview.importablePendingNotices.isEmpty ||
            !preview.overwritableReconciliationNotices.isEmpty ||
            !preview.importableUnrecordedOrders.isEmpty
    }

    private func syncScopeToggle(
        scope: JDFinanceSyncApplyScope,
        title: String,
        count: Int,
        tone: Color
    ) -> some View {
        let isAvailable = count > 0
        let isSelected = isAvailable && selectedApplyScopes.contains(scope)

        return Button {
            guard isAvailable else { return }
            if selectedApplyScopes.contains(scope) {
                selectedApplyScopes.remove(scope)
            } else {
                selectedApplyScopes.insert(scope)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isAvailable ? (isSelected ? tone : .secondary) : .secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                (isSelected ? tone.opacity(0.13) : PanelDesign.inputBackground.opacity(0.68)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tone.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 0.7)
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isAvailable)
    }

    private var emptyPreviewPanel: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.green)
            Text("已同步，暂无差异")
                .font(.system(size: 14, weight: .semibold))
            Text(syncStore.preview?.autoConfirmedCount ?? 0 > 0
                ? "已自动确认 \(syncStore.preview?.autoConfirmedCount ?? 0) 笔一致流水。"
                : "京东持仓、交易流水和本地记录当前一致。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func inlineSyncError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PanelDesign.warningAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("本次操作失败，预览已保留")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(PanelDesign.warningBorder, lineWidth: 0.8)
        )
    }

    private var errorPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PanelDesign.warningAccent)

            Text(syncStore.errorMessage ?? "同步失败")
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    retrySync()
                } label: {
                    PanelButtonLabel(title: "重试同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(width: 140)

                Button {
                    requestLogin()
                } label: {
                    PanelButtonLabel(title: "登录京东", systemImage: "person.crop.circle.badge.clock")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(width: 140)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PanelDesign.warningBorder, lineWidth: 0.8)
        )
    }

    private func previewSection<Content: View>(
        title: String,
        count: Int,
        tone: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tone.opacity(count == 0 ? 0.36 : 0.86))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tone)
            }

            if count == 0 {
                Text("无")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground.opacity(count == 0 ? 0.56 : 0.84), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func newHoldingCard(_ candidate: JDFinanceHoldingImportCandidate) -> some View {
        comparisonCardHeader(code: candidate.code, name: candidate.name, badge: "新增", tone: PanelDesign.accent) {
            metricPair("京东金额", MoneyFormatter.plainMoney(candidate.amount), tone: .primary)
            metricPair("持有收益", MoneyFormatter.money(candidate.holdingIncome, signed: true), tone: toneColor(candidate.holdingIncome))
        }
    }

    private func differenceCard(_ difference: JDFinanceHoldingDifference) -> some View {
        let amountDelta = difference.jdAmount - (difference.localAmount ?? 0)
        let incomeDelta = optionalDelta(difference.jdHoldingIncome, difference.localHoldingIncome)

        return comparisonCardHeader(code: difference.code, name: difference.name, badge: "对比", tone: .orange) {
            HStack(spacing: 8) {
                metricPair("京东", MoneyFormatter.plainMoney(difference.jdAmount), tone: .primary)
                metricPair("本地", moneyOrDash(difference.localAmount), tone: .secondary)
                metricPair("差额", MoneyFormatter.money(amountDelta, signed: true), tone: toneColor(amountDelta))
            }

            Divider().opacity(0.55)

            HStack(spacing: 8) {
                metricPair("京东收益", signedMoneyOrDash(difference.jdHoldingIncome), tone: toneColor(difference.jdHoldingIncome))
                metricPair("本地收益", signedMoneyOrDash(difference.localHoldingIncome), tone: toneColor(difference.localHoldingIncome))
                metricPair("收益差", incomeDelta.map { MoneyFormatter.money($0, signed: true) } ?? "--", tone: toneColor(incomeDelta))
            }
        }
    }

    private func missingHoldingCard(_ holding: JDFinanceMissingLocalHolding) -> some View {
        comparisonCardHeader(code: holding.code, name: holding.name, badge: "本地有", tone: .green) {
            HStack(spacing: 8) {
                metricPair("京东金额", "--", tone: .secondary)
                metricPair("本地金额", moneyOrDash(holding.localAmount), tone: .primary)
            }
            if let order = holding.finalOutflowOrder {
                tradeRecordsList(title: "京东最终卖出/转换出证据", records: [order])
                HStack {
                    Text("确认后按本地全部剩余份额清仓")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清仓对账", role: .destructive) {
                        clearanceCandidate = holding
                        isShowingClearanceConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(syncStore.isSyncing || syncStore.isApplying)
                }
            } else {
                Text("未找到京东最终卖出或转换出流水，仅提示可能清仓，不会自动删除。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func unresolvedHoldingCard(_ holding: JDFinanceUnresolvedHolding) -> some View {
        comparisonCardHeader(code: holding.skuID, name: holding.name, badge: "待识别", tone: PanelDesign.warningAccent) {
            HStack(spacing: 8) {
                metricPair("京东金额", MoneyFormatter.plainMoney(holding.amount), tone: .primary)
                metricPair("持有收益", signedMoneyOrDash(holding.holdingIncome), tone: toneColor(holding.holdingIncome))
            }

            Text(holding.message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unrecordedOrderCard(_ order: JDFinanceUnrecordedOrder) -> some View {
        let badge: String = if order.isImportable {
            "可导入"
        } else if order.blockingReason != nil {
            "匹配冲突"
        } else if let firstMissingField = order.missingFields.first {
            "缺少\(firstMissingField)"
        } else {
            "不可导入"
        }
        return comparisonCardHeader(
            code: order.code.isEmpty ? "代码缺失" : order.code,
            name: order.name,
            badge: badge,
            tone: order.isImportable ? .purple : PanelDesign.warningAccent
        ) {
            tradeRecordsList(title: "京东最终流水", records: [order.record])
            if !order.missingFields.isEmpty {
                Text("缺少字段：\(order.missingFields.joined(separator: "、"))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PanelDesign.warningAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(order.message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                if order.isImportable {
                    Button("导入此笔") {
                        applyUnrecordedOrder(order)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(syncStore.isSyncing || syncStore.isApplying)
                }
                Button("标记为当前持仓已包含") {
                    syncStore.markUnrecordedOrderAsIncluded(order, in: portfolioStore)
                    onMainPanelRefreshNeeded()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(syncStore.isSyncing || syncStore.isApplying)
            }
        }
    }

    @ViewBuilder
    private func warningAndInformationCards(_ preview: JDFinanceHoldingsSyncPreview) -> some View {
        ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(PanelDesign.warningAccent)
                Text(warning)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }

        ForEach(Array(preview.informationalOrders.enumerated()), id: \.offset) { index, order in
            tradeRecordsList(title: "不参与写入的流水 \(index + 1)", records: [order])
        }
    }

    private func reconciliationNoticeCard(_ notice: JDFinanceReconciliationNotice) -> some View {
        comparisonCardHeader(
            code: notice.code,
            name: notice.name,
            badge: reconciliationBadge(for: notice),
            tone: notice.isOverwritable ? PanelDesign.accent : PanelDesign.warningAccent
        ) {
            HStack(spacing: 8) {
                metricPair("方向", reconciliationActionTitle(for: notice), tone: .primary)
                metricPair("交易日", notice.tradeDate, tone: .primary)
                metricPair("时段", notice.tradeTimeType.title, tone: .primary)
            }

            HStack(spacing: 8) {
                metricPair("本地金额", moneyOrDash(notice.localAmount), tone: .secondary)
                metricPair("京东金额", moneyOrDash(notice.jdAmount), tone: notice.jdAmount == nil ? .secondary : .primary)
                metricPair("差额", differenceText(for: notice), tone: notice.isOverwritable ? PanelDesign.accent : .secondary)
            }

            HStack(spacing: 8) {
                metricPair("本地份额", notice.localShares.map(shareText) ?? "--", tone: .secondary)
                metricPair("京东份额", notice.jdShares.map(shareText) ?? "--", tone: notice.jdShares == nil ? .secondary : .primary)
            }

            if let linkedName = notice.linkedName {
                Text("目标：\(linkedName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let conflictMessage = reconciliationConflictMessage(for: notice) {
                Text(conflictMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PanelDesign.warningAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !notice.matchedTradeRecords.isEmpty {
                tradeRecordsList(title: "京东最终流水", records: notice.matchedTradeRecords)
            }
        }
    }

    private func reconciliationBadge(for notice: JDFinanceReconciliationNotice) -> String {
        switch notice.state {
        case .jdConfirmedNeedsOverwrite:
            "京东已确认 · 待覆盖"
        case .localConfirmedJDPending:
            "本地已确认"
        case .conflict:
            "同步冲突"
        }
    }

    private func reconciliationActionTitle(for notice: JDFinanceReconciliationNotice) -> String {
        switch notice.kind {
        case .trade(_, let action):
            action.title
        case .conversion:
            "转换"
        }
    }

    private func reconciliationConflictMessage(for notice: JDFinanceReconciliationNotice) -> String? {
        if case .conflict(let message) = notice.state {
            return message
        }
        return nil
    }

    private func differenceText(for notice: JDFinanceReconciliationNotice) -> String {
        switch notice.state {
        case .jdConfirmedNeedsOverwrite(let difference), .localConfirmedJDPending(let difference):
            return differenceText(for: difference)
        case .conflict:
            return "--"
        }
    }

    private func differenceText(for difference: JDFinanceSyncDifference) -> String {
        var parts: [String] = []
        if let amountDelta = difference.amountDelta {
            parts.append(signedMoneyOrDash(amountDelta))
        }
        if let sharesDelta = difference.sharesDelta {
            parts.append(shareText(sharesDelta))
        }
        if let priceDelta = difference.priceDelta {
            parts.append(String(format: "%+.6f", priceDelta))
        }
        return parts.isEmpty ? "无" : parts.joined(separator: " / ")
    }

    private func pendingNoticeCard(_ notice: JDFinanceHoldingPendingNotice) -> some View {
        comparisonCardHeader(
            code: notice.code,
            name: notice.name,
            badge: pendingNoticeBadge(for: notice),
            tone: PanelDesign.warningAccent
        ) {
            HStack(spacing: 8) {
                metricPair("方向", notice.actionTitle, tone: .primary)
                metricPair(
                    pendingNoticeAmountLabel(for: notice),
                    pendingNoticeAmountText(for: notice),
                    tone: .primary
                )
                metricPair("笔数", notice.tradeCountText ?? "--", tone: .secondary)
            }

            HStack(spacing: 8) {
                metricPair("预计更新", notice.yesterdayIncomeNotice ?? "--", tone: .secondary)
                metricPair("交易日", notice.pendingDetail?.tradeDate ?? "--", tone: notice.pendingDetail?.tradeDate == nil ? .secondary : .primary)
                metricPair("时段", notice.pendingDetail?.tradeTimeType?.title ?? "--", tone: notice.pendingDetail?.tradeTimeType == nil ? .secondary : .primary)
            }

            if let detailStatusText = notice.detailStatusText {
                Text(detailStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .localConfirmedJDPending(let difference) = notice.syncState {
                Text("与本地确认差额：\(differenceText(for: difference))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !notice.logicalMatchedTradeRecords.isEmpty {
                tradeRecordsList(title: "已匹配买入批次", records: notice.logicalMatchedTradeRecords)
            } else if !notice.candidateTradeRecords.isEmpty {
                tradeRecordsList(title: "候选交易记录", records: notice.candidateTradeRecords)
            }

            Text(notice.message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            pendingNoticeImportControls(notice)
        }
    }

    private func pendingNoticeBadge(for notice: JDFinanceHoldingPendingNotice) -> String {
        if case .localConfirmedJDPending = notice.syncState {
            return "本地已确认 · 京东待确认"
        }
        if notice.isImportable { return "可同步" }
        if notice.requiresManualCompletion { return "需补全" }
        return "京东待确认"
    }

    private func pendingNoticeAmountLabel(for notice: JDFinanceHoldingPendingNotice) -> String {
        if case .conversion = notice.importKind {
            return "转换份额"
        }
        if (notice.pendingDetail?.action ?? notice.transactionTip?.action) == .conversion {
            return "转换份额"
        }
        return "交易金额"
    }

    private func pendingNoticeAmountText(for notice: JDFinanceHoldingPendingNotice) -> String {
        if case .conversion = notice.importKind {
            let shares = notice.conversionDraft()?.shares ?? notice.pendingDetail?.shares ?? notice.amount
            return shares > 0 ? shareText(shares) : "--"
        }
        if (notice.pendingDetail?.action ?? notice.transactionTip?.action) == .conversion {
            let shares = notice.pendingDetail?.shares ?? notice.amount
            return shares > 0 ? shareText(shares) : "--"
        }
        return notice.amount > 0 ? MoneyFormatter.plainMoney(notice.amount) : "--"
    }

    @ViewBuilder
    private func pendingNoticeImportControls(_ notice: JDFinanceHoldingPendingNotice) -> some View {
        if notice.isImportable {
            Button {
                applyPendingNotice(notice, manualCompletion: nil)
            } label: {
                PanelButtonLabel(
                    title: notice.logicalMatchedTradeRecords.count > 1
                        ? "同步 \(notice.logicalMatchedTradeRecords.count) 笔"
                        : "同步待确认",
                    systemImage: "checkmark.circle",
                    style: .primary,
                    isEnabled: !syncStore.isApplying
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(maxWidth: 142)
            .disabled(syncStore.isApplying)
        } else if notice.requiresManualCompletion {
            manualPendingCompletionControls(notice)
        }
    }

    private func tradeRecordsList(title: String, records: [JDFinanceTradeOrderRecord]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                tradeRecordRow(index: index, record: record)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 7))
    }

    private func tradeRecordRow(index: Int, record: JDFinanceTradeOrderRecord) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1).")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tradeRecordTimingText(record))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(tradeRecordValueText(record))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }

                if let statusText = record.statusText, !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let targetName = record.conversionTargetName, !targetName.isEmpty {
                    Text("→ \(targetName)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tradeRecordTimingText(_ record: JDFinanceTradeOrderRecord) -> String {
        [record.tradeDate, record.tradeTimeType?.title]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func tradeRecordValueText(_ record: JDFinanceTradeOrderRecord) -> String {
        if record.action == .conversion {
            return shareText(record.shares ?? record.amount ?? 0)
        }
        return record.amount.map(MoneyFormatter.plainMoney) ?? "--"
    }

    private func shareText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))份"
    }

    private func manualPendingCompletionControls(_ notice: JDFinanceHoldingPendingNotice) -> some View {
        let input = manualPendingInputBinding(for: notice)
        let manualCompletion = manualCompletion(for: input.wrappedValue)
        let canImport = notice.canBuildLocalDraft(manualCompletion: manualCompletion) && !syncStore.isApplying

        return VStack(alignment: .leading, spacing: 7) {
            Text(pendingMissingFieldsText(for: notice))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    manualTradeDateControl(input)

                    Picker("时段", selection: Binding(
                        get: { input.wrappedValue.timeType },
                        set: { newValue in
                            var next = input.wrappedValue
                            next.timeType = newValue
                            input.wrappedValue = next
                        }
                    )) {
                        Text("时段").tag(Optional<PositionTimeType>.none)
                        ForEach(PositionTimeType.allCases) { timeType in
                            Text(timeType.title).tag(Optional(timeType))
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)

                    Spacer(minLength: 0)
                }

                Button {
                    applyPendingNotice(notice, manualCompletion: manualCompletion)
                } label: {
                    PanelButtonLabel(
                        title: "补全后导入",
                        systemImage: "square.and.arrow.down",
                        isEnabled: canImport
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: 142)
                .disabled(!canImport)
            }
        }
    }

    @ViewBuilder
    private func manualTradeDateControl(_ input: Binding<JDFinanceManualPendingInput>) -> some View {
        if input.wrappedValue.tradeDate == nil {
            Button {
                var next = input.wrappedValue
                next.tradeDate = .now
                input.wrappedValue = next
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text("选择交易日")
                }
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(PanelDesign.buttonBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(PanelDesign.border(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(width: 112)
        } else {
            DatePicker(
                "交易日",
                selection: Binding(
                    get: { input.wrappedValue.tradeDate ?? .now },
                    set: { newValue in
                        var next = input.wrappedValue
                        next.tradeDate = newValue
                        input.wrappedValue = next
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .frame(width: 112)
        }
    }

    private func comparisonCardHeader<Content: View>(
        code: String,
        name: String,
        badge: String,
        tone: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        Text(name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tone)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(tone.opacity(0.12), in: Capsule())
            }

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.selectorBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.20), lineWidth: 0.6)
        )
    }

    private func metricPair(_ title: String, _ value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(PanelDesign.inputBackground.opacity(0.70), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 0.6)
            )
    }

    private func flowButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(PanelDesign.buttonBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func compactToolButton(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(role == .destructive ? Color.red : Color.primary.opacity(0.80))
                .frame(width: 28, height: 26)
                .background(PanelDesign.buttonBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(PanelDesign.border(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    private func checkExistingSessionOnAppear() async {
        guard isCheckingExistingSession else { return }

        let cookieHeader = await JDFinanceWebSession.cookieHeader()
        isCheckingExistingSession = false

        await synchronize(cookieHeader: cookieHeader)
    }

    private func retrySync() {
        Task {
            let cookieHeader = await JDFinanceWebSession.cookieHeader()
            await synchronize(cookieHeader: cookieHeader)
        }
    }

    private func requestNetworkProbe() {
        networkProbe.clear()
        networkProbe.setTargets(networkProbeTargets())
        onRequestNetworkProbe(networkProbe)
    }

    private func networkProbeTargets() -> [JDFinanceNetworkProbeTarget] {
        syncStore.preview?.pendingNotices.map {
            JDFinanceNetworkProbeTarget(
                code: $0.code,
                name: $0.name,
                amount: $0.amount
            )
        } ?? []
    }

    private func requestLogin() {
        guard !isRequestingLogin else { return }

        isRequestingLogin = true
        onRequestLogin { cookieHeader in
            Task { @MainActor in
                isRequestingLogin = false
                guard JDFinanceWebSession.hasUsableCookieHeader(cookieHeader) else {
                    needsLogin = true
                    return
                }
                showLoginToast()
                await synchronize(cookieHeader: cookieHeader)
            }
        }
    }

    private func synchronize(cookieHeader: String?) async {
        needsLogin = false
        JDFinanceWebSession.rememberCookieHeader(cookieHeader)
        await syncStore.synchronize(portfolioStore: portfolioStore, cookieHeader: cookieHeader)
        if syncStore.lastError == .notLoggedIn {
            needsLogin = true
        }
        onMainPanelRefreshNeeded()
    }

    private func canApplySelectedData(_ preview: JDFinanceHoldingsSyncPreview) -> Bool {
        guard !syncStore.isSyncing, !syncStore.isApplying else { return false }
        let canImportNew = selectedApplyScopes.contains(.newHoldings) && !preview.newHoldings.isEmpty
        let canUpdateChanged = selectedApplyScopes.contains(.changedHoldings) && !preview.changedHoldings.isEmpty
        let canImportPending = selectedApplyScopes.contains(.pendingHoldings) && !preview.importablePendingNotices.isEmpty
        let canReconcile = selectedApplyScopes.contains(.reconciliations) && !preview.overwritableReconciliationNotices.isEmpty
        let canImportUnrecorded = selectedApplyScopes.contains(.unrecordedOrders) && !preview.importableUnrecordedOrders.isEmpty
        return canImportNew || canUpdateChanged || canImportPending || canReconcile || canImportUnrecorded
    }

    private func applySelectedData() {
        Task {
            await syncStore.applySelectedHoldings(
                to: portfolioStore,
                importNew: selectedApplyScopes.contains(.newHoldings),
                updateChanged: selectedApplyScopes.contains(.changedHoldings),
                importPending: selectedApplyScopes.contains(.pendingHoldings),
                reconcileConfirmed: selectedApplyScopes.contains(.reconciliations),
                importUnrecorded: selectedApplyScopes.contains(.unrecordedOrders)
            )
            onMainPanelRefreshNeeded()
        }
    }

    private func applyFullClearance(_ holding: JDFinanceMissingLocalHolding) {
        Task {
            await syncStore.applyFullClearance(holding, to: portfolioStore)
            clearanceCandidate = nil
            onMainPanelRefreshNeeded()
        }
    }

    private func applyUnrecordedOrder(_ order: JDFinanceUnrecordedOrder) {
        Task {
            await syncStore.applyUnrecordedOrder(order, to: portfolioStore)
            onMainPanelRefreshNeeded()
        }
    }

    private func applyPendingNotice(
        _ notice: JDFinanceHoldingPendingNotice,
        manualCompletion: JDFinancePendingManualCompletion?
    ) {
        Task {
            await syncStore.applyPendingNotice(
                notice,
                to: portfolioStore,
                manualCompletion: manualCompletion
            )
            onMainPanelRefreshNeeded()
        }
    }

    private func manualPendingInputBinding(for notice: JDFinanceHoldingPendingNotice) -> Binding<JDFinanceManualPendingInput> {
        Binding(
            get: {
                manualPendingInputs[notice.id] ?? defaultManualPendingInput(for: notice)
            },
            set: { newValue in
                manualPendingInputs[notice.id] = newValue
            }
        )
    }

    private func defaultManualPendingInput(for notice: JDFinanceHoldingPendingNotice) -> JDFinanceManualPendingInput {
        JDFinanceManualPendingInput(
            tradeDate: notice.pendingDetail?.tradeDate.flatMap(DateOnlyFormatter.parse),
            timeType: notice.pendingDetail?.tradeTimeType
        )
    }

    private func manualCompletion(for input: JDFinanceManualPendingInput) -> JDFinancePendingManualCompletion? {
        guard let tradeDate = input.tradeDate,
              let timeType = input.timeType
        else {
            return nil
        }

        return JDFinancePendingManualCompletion(
            tradeDate: DateOnlyFormatter.string(from: tradeDate),
            tradeTimeType: timeType
        )
    }

    private func pendingMissingFieldsText(for notice: JDFinanceHoldingPendingNotice) -> String {
        var missingFields: [String] = []
        if notice.pendingDetail?.tradeDate == nil {
            missingFields.append("交易日")
        }
        if notice.pendingDetail?.tradeTimeType == nil {
            missingFields.append("15点前后")
        }
        if case .some(.trade(.sell)) = notice.importKind,
           notice.pendingDetail?.shares == nil
        {
            missingFields.append("卖出份额")
        }

        guard !missingFields.isEmpty else {
            return "京东已返回完整交易信息，可以同步为本地待确认。"
        }

        if missingFields == ["卖出份额"] {
            return "京东未返回卖出份额，暂不能自动导入；可先在交易记录里手动录入。"
        }

        return "京东未返回\(missingFields.joined(separator: "、"))，请补全后再导入为本地待确认。"
    }

    private func resetLoginSession() {
        Task {
            await JDFinanceWebSession.clearSession()
            syncStore.markSessionCleared()
            needsLogin = true
            isCheckingExistingSession = false
            isRequestingLogin = false
            loginToastMessage = nil
        }
    }

    private func showLoginToast() {
        let message = "已登录，正在拉取持仓..."
        withAnimation(.easeOut(duration: 0.18)) {
            loginToastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard loginToastMessage == message else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                loginToastMessage = nil
            }
        }
    }

    private func optionalDelta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    private func toneColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .secondary
    }

    private func moneyOrDash(_ value: Double?) -> String {
        value.map(MoneyFormatter.plainMoney) ?? "--"
    }

    private func signedMoneyOrDash(_ value: Double?) -> String {
        value.map { MoneyFormatter.money($0, signed: true) } ?? "--"
    }
}

struct JDFinanceLoginPanelView: View {
    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 " +
        "Mobile/15E148 Safari/604.1"

    let title: String
    let initialURL: URL
    let reloadButtonTitle: String
    let autoCompleteLogin: Bool
    let networkProbe: JDFinanceNetworkProbe?
    let onLoggedIn: (String) -> Void
    let onClose: () -> Void

    @State private var targetURL: URL
    @State private var reloadID = 0
    @State private var currentURLText = ""
    @State private var hasCompletedLogin = false
    @State private var isCheckingLoginCompletion = false

    init(
        title: String = "登录京东",
        initialURL: URL = JDFinanceWebSession.loginURL,
        reloadButtonTitle: String = "刷新登录页",
        autoCompleteLogin: Bool = true,
        networkProbe: JDFinanceNetworkProbe? = nil,
        onLoggedIn: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.initialURL = initialURL
        self.reloadButtonTitle = reloadButtonTitle
        self.autoCompleteLogin = autoCompleteLogin
        self.networkProbe = networkProbe
        self.onLoggedIn = onLoggedIn
        self.onClose = onClose
        _targetURL = State(initialValue: initialURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "person.crop.circle.badge.plus",
                title: title,
                subtitle: currentHostText,
                tint: PanelDesign.accent,
                onClose: onClose
            )

            VStack(spacing: 10) {
                topActionBar
                loginPanel
                networkProbeFooter
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.panelBackground)
    }

    private var currentHostText: String {
        guard let url = URL(string: currentURLText),
              let host = url.host()
        else {
            return currentURLText.isEmpty ? (initialURL.host() ?? initialURL.absoluteString) : currentURLText
        }
        return host
    }

    private var topActionBar: some View {
        HStack(spacing: 8) {
            smallButton(reloadButtonTitle, systemImage: "arrow.clockwise", action: reloadLoginPage)
            if networkProbe != nil {
                smallButton("持仓页", systemImage: "chart.pie", action: openHoldingsPage)
                smallButton("交易记录", systemImage: "list.bullet.rectangle", action: openTradeOrderPage)
            }
            Spacer()
            Text(currentHostText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private var loginPanel: some View {
        JDFinanceLoginWebView(
            url: targetURL,
            reloadID: reloadID,
            customUserAgent: Self.mobileUserAgent,
            networkProbe: networkProbe,
            currentURLText: $currentURLText,
            onNavigationFinished: handleNavigationFinished
        )
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var networkProbeFooter: some View {
        if let networkProbe {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Label("脱敏捕获", systemImage: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("\(networkProbe.entries.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PanelDesign.accent)
                    Button("清空") {
                        networkProbe.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                }

                if networkProbe.entries.isEmpty {
                    Text("打开或点击基金交易记录后，会显示接口路径、状态和交易字段。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(networkProbe.entries.suffix(3)) { entry in
                        networkProbeRow(entry)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 10))
        }
    }

    private func networkProbeRow(_ entry: JDFinanceNetworkProbeEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.source.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PanelDesign.accent)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.method)
                        .font(.system(size: 10, weight: .semibold))
                    Text(entry.path)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text((entry.fieldSummaries.isEmpty ? entry.topLevelKeys.map { "key:\($0)" } : entry.fieldSummaries).joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let statusCode = entry.statusCode {
                Text("\(statusCode)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle((200..<300).contains(statusCode) ? .green : PanelDesign.warningAccent)
            }
        }
    }

    private func smallButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(PanelDesign.buttonBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func reloadLoginPage() {
        hasCompletedLogin = false
        isCheckingLoginCompletion = false
        targetURL = initialURL
        reloadID += 1
    }

    private func openHoldingsPage() {
        hasCompletedLogin = false
        isCheckingLoginCompletion = false
        targetURL = JDFinanceWebSession.holdingsPCURL
        reloadID += 1
    }

    private func openTradeOrderPage() {
        hasCompletedLogin = false
        isCheckingLoginCompletion = false
        targetURL = JDFinanceWebSession.tradeOrderURL
        reloadID += 1
    }

    private func handleNavigationFinished(_ url: URL?) {
        guard autoCompleteLogin,
              JDFinanceWebSession.isLoginReturnURL(url),
              !hasCompletedLogin,
              !isCheckingLoginCompletion
        else {
            return
        }

        isCheckingLoginCompletion = true
        Task { @MainActor in
            let cookieHeader = await waitForLoginCookieHeader()
            isCheckingLoginCompletion = false

            guard let cookieHeader,
                  JDFinanceWebSession.didCompleteLoginNavigation(url: url, cookieHeader: cookieHeader),
                  !hasCompletedLogin
            else {
                return
            }

            hasCompletedLogin = true
            JDFinanceWebSession.rememberCookieHeader(cookieHeader)
            onLoggedIn(cookieHeader)
        }
    }

    private func waitForLoginCookieHeader() async -> String? {
        for attempt in 0..<6 {
            if let cookieHeader = await JDFinanceWebSession.cookieHeader(),
               JDFinanceWebSession.hasUsableCookieHeader(cookieHeader)
            {
                return cookieHeader
            }

            if attempt < 5 {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }

        return nil
    }
}

private struct JDFinanceLoginWebView: NSViewRepresentable {
    private static let probeMessageHandler = "jdNetworkProbe"
    private static let networkProbeScript = """
    (function() {
      if (window.__fundPulseJDProbeInstalled) { return; }
      window.__fundPulseJDProbeInstalled = true;

      function post(payload) {
        try {
          window.webkit.messageHandlers.jdNetworkProbe.postMessage(payload);
        } catch (error) {}
      }

      function captureBody(body) {
        if (typeof body !== 'string') { return ''; }
        return body.length > 250000 ? body.slice(0, 250000) : body;
      }

      function captureRequestBody(body) {
        try {
          if (!body) { return ''; }
          if (typeof body === 'string') { return captureBody(body); }
          if (body instanceof URLSearchParams) { return captureBody(body.toString()); }
          if (body instanceof FormData) {
            const pairs = [];
            body.forEach(function(value, key) {
              if (typeof value === 'string') {
                pairs.push(encodeURIComponent(key) + '=' + encodeURIComponent(value));
              }
            });
            return captureBody(pairs.join('&'));
          }
          if (typeof body.toString === 'function') { return captureBody(body.toString()); }
        } catch (error) {}
        return '';
      }

      if (window.fetch) {
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
          const requestURL = typeof input === 'string' ? input : (input && input.url) || '';
          const method = (init && init.method) || (input && input.method) || 'GET';
          const requestBody = captureRequestBody(init && init.body);
          return originalFetch.apply(this, arguments).then(function(response) {
            try {
              const clone = response.clone();
              clone.text().then(function(text) {
                post({
                  source: 'fetch',
                  url: response.url || requestURL,
                  method: method,
                  status: response.status,
                  requestBody: requestBody,
                  body: captureBody(text)
                });
              }).catch(function() {});
            } catch (error) {}
            return response;
          });
        };
      }

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__fundPulseJDProbeMethod = method || 'GET';
        this.__fundPulseJDProbeURL = url || '';
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        const requestBody = captureRequestBody(arguments.length > 0 ? arguments[0] : null);
        this.addEventListener('load', function() {
          let body = '';
          try {
            if (typeof this.responseText === 'string') { body = this.responseText; }
          } catch (error) {}
          post({
            source: 'xhr',
            url: this.responseURL || this.__fundPulseJDProbeURL || '',
            method: this.__fundPulseJDProbeMethod || 'GET',
            status: this.status,
            requestBody: requestBody,
            body: captureBody(body)
          });
        });
        return originalSend.apply(this, arguments);
      };
    })();
    """

    let url: URL
    let reloadID: Int
    var customUserAgent: String?
    var networkProbe: JDFinanceNetworkProbe?
    @Binding var currentURLText: String
    var onNavigationFinished: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            networkProbe: networkProbe,
            installedProbeHandler: networkProbe != nil,
            currentURLText: $currentURLText,
            onNavigationFinished: onNavigationFinished
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if networkProbe != nil {
            let contentController = WKUserContentController()
            contentController.addUserScript(WKUserScript(
                source: Self.networkProbeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
            contentController.add(context.coordinator, name: Self.probeMessageHandler)
            configuration.userContentController = contentController
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = customUserAgent
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(url, reloadID: reloadID, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.networkProbe = networkProbe
        context.coordinator.currentURLText = $currentURLText
        context.coordinator.onNavigationFinished = onNavigationFinished
        if webView.customUserAgent != customUserAgent {
            webView.customUserAgent = customUserAgent
        }
        if context.coordinator.reloadID != reloadID || context.coordinator.loadedURL != url {
            context.coordinator.load(url, reloadID: reloadID, in: webView)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        if coordinator.installedProbeHandler {
            nsView.configuration.userContentController.removeScriptMessageHandler(forName: Self.probeMessageHandler)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var networkProbe: JDFinanceNetworkProbe?
        let installedProbeHandler: Bool
        var currentURLText: Binding<String>
        var onNavigationFinished: (URL?) -> Void
        var loadedURL: URL?
        var reloadID = -1

        init(
            networkProbe: JDFinanceNetworkProbe?,
            installedProbeHandler: Bool,
            currentURLText: Binding<String>,
            onNavigationFinished: @escaping (URL?) -> Void
        ) {
            self.networkProbe = networkProbe
            self.installedProbeHandler = installedProbeHandler
            self.currentURLText = currentURLText
            self.onNavigationFinished = onNavigationFinished
        }

        func load(_ url: URL, reloadID: Int, in webView: WKWebView) {
            loadedURL = url
            self.reloadID = reloadID
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url
            currentURLText.wrappedValue = url?.absoluteString ?? ""
            onNavigationFinished(url)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == JDFinanceLoginWebView.probeMessageHandler else { return }
            let payload = message.body
            Task { @MainActor [weak self] in
                self?.networkProbe?.recordWebViewPayload(payload)
            }
        }
    }
}
