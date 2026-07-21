import SwiftUI

struct JDFinancePerformanceSyncView: View {
    let portfolioStore: PortfolioStore
    let performanceStore: PortfolioPerformanceStore
    let onRequestLogin: (@escaping (String?) -> Void) -> Void
    let onClose: () -> Void

    @AppStorage(AppPreferenceKey.hideHeaderAmounts) private var hidesAmounts = false
    @State private var syncStore: JDFinancePerformanceSyncStore
    @State private var overwritesConflicts = false
    @State private var isRequestingLogin = false
    @State private var isShowingClearConfirmation = false
    @State private var localErrorMessage: String?
    @State private var retryTask: Task<Void, Never>?
    @State private var isPresented = false

    init(
        portfolioStore: PortfolioStore,
        performanceStore: PortfolioPerformanceStore,
        onRequestLogin: @escaping (@escaping (String?) -> Void) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.portfolioStore = portfolioStore
        self.performanceStore = performanceStore
        self.onRequestLogin = onRequestLogin
        self.onClose = onClose
        _syncStore = State(initialValue: JDFinancePerformanceSyncStore())
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "icloud.and.arrow.down",
                title: "京东历史收益",
                subtitle: syncStore.statusMessage,
                tint: .blue,
                accessoryText: "仅读取京东",
                accessoryColor: .green,
                onClose: onClose
            )

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
        }
        .background(PanelDesign.panelBackground)
        .onAppear {
            isPresented = true
        }
        .task {
            let cookieHeader = await JDFinanceWebSession.cookieHeader()
            await synchronize(cookieHeader: cookieHeader)
        }
        .onDisappear {
            isPresented = false
            retryTask?.cancel()
            retryTask = nil
            syncStore.cancel()
        }
        .alert("清除旧账号的京东收益？", isPresented: $isShowingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除并重新同步", role: .destructive) {
                clearHistoryAndRetry()
            }
        } message: {
            Text("会删除所有来源为京东的补全、升级或覆盖记录与账号指纹；仍标记为本地来源的记录会保留。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if syncStore.isSyncing {
            loadingState
        } else if syncStore.needsLogin {
            loginState
        } else if let plan = syncStore.plan {
            if syncStore.didApply {
                successState(plan)
            } else {
                previewState(plan)
            }
        } else if let errorMessage = localErrorMessage ?? syncStore.errorMessage {
            errorState(errorMessage)
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(syncStore.statusMessage)
                .font(.system(size: 14, weight: .semibold))
            Text("首次补全会从 2000 年起按年度分段读取，只同步到昨天。可随时关闭取消，写入前会先展示预览。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330)
        }
        .accessibilityElement(children: .combine)
    }

    private var loginState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.blue)
            Text("登录京东后补全")
                .font(.system(size: 16, weight: .semibold))
            Text("使用现有京东网页会话读取基金历史收益；Cookie 只发送给京东相关服务。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            Button(action: requestLogin) {
                PanelButtonLabel(
                    title: isRequestingLogin ? "等待登录..." : "登录京东",
                    systemImage: "person.crop.circle.badge.plus",
                    style: .primary,
                    tint: .blue,
                    isEnabled: !isRequestingLogin
                )
            }
            .buttonStyle(.plain)
            .disabled(isRequestingLogin)
            .frame(width: 180)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func previewState(_ plan: PortfolioPerformanceMergePlan) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                rangeCard(plan)
                changeSummary(plan)

                if !plan.conflicts.isEmpty {
                    conflictSection(plan)
                }

                if plan.zeroValueSkippedCount > 0 || plan.invalidValueSkippedCount > 0 {
                    skippedRowsNotice(plan)
                }

                if let errorMessage = localErrorMessage ?? syncStore.errorMessage {
                    inlineError(errorMessage)
                }

                applyControl(plan)
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.never)
    }

    private func rangeCard(_ plan: PortfolioPerformanceMergePlan) -> some View {
        PanelSection(title: "同步范围") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.coveredFrom)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(plan.coveredThrough)
                    Spacer()
                    Text(plan.isComplete ? "完整" : "部分")
                        .foregroundStyle(plan.isComplete ? Color.green : PanelDesign.warningAccent)
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()

                Label("账户级每日基金收益；未读取今天的未结算数据", systemImage: "checkmark.shield")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func changeSummary(_ plan: PortfolioPerformanceMergePlan) -> some View {
        PanelSection(title: "写入预览") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2), spacing: 7) {
                previewMetric("新增", value: plan.insertedCount, tint: .blue)
                previewMetric("估值升级", value: plan.upgradedCount, tint: .green)
                previewMetric("京东修正", value: plan.updatedCount, tint: .orange)
                previewMetric("冲突", value: plan.conflicts.count, tint: PanelDesign.warningAccent)
            }

            if !plan.hasDayChanges, !plan.metadataChanged {
                Label("本地历史收益已是最新", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else if plan.unchangedCount > 0 {
                Text("另有 \(plan.unchangedCount) 天与本地记录一致，不会重复写入。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func conflictSection(_ plan: PortfolioPerformanceMergePlan) -> some View {
        PanelSection(title: "已确认记录冲突") {
            VStack(alignment: .leading, spacing: 8) {
                Text("默认保留本地已确认值。只有打开下方开关后，才会以京东为准。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(plan.conflicts.prefix(6)) { conflict in
                    HStack(spacing: 8) {
                        Text(conflict.date)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Text("本地 \(amountText(conflict.existing.profit))")
                            .foregroundStyle(ValueTone.color(for: conflict.existing.profit))
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.secondary)
                        Text("京东 \(amountText(conflict.incoming.profit))")
                            .foregroundStyle(ValueTone.color(for: conflict.incoming.profit))
                    }
                    .font(.system(size: 10, weight: .medium))
                }

                if plan.conflicts.count > 6 {
                    Text("另有 \(plan.conflicts.count - 6) 天冲突")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Toggle("冲突日期以京东为准", isOn: $overwritesConflicts)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }

    private func skippedRowsNotice(_ plan: PortfolioPerformanceMergePlan) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
            Text(skippedRowsText(plan))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private func applyControl(_ plan: PortfolioPerformanceMergePlan) -> some View {
        let selectedCount = plan.selectedDayChangeCount(overwriteConflicts: overwritesConflicts)
        let canApply = plan.canApply(overwriteConflicts: overwritesConflicts)

        return Button {
            _ = syncStore.apply(
                to: performanceStore,
                overwriteConflicts: overwritesConflicts,
                expectedAccountKey: portfolioStore.snapshot.jdFinanceSyncState?.accountKey
            )
        } label: {
            PanelButtonLabel(
                title: applyTitle(selectedCount: selectedCount, plan: plan),
                systemImage: "checkmark.circle",
                style: .primary,
                tint: .blue,
                isEnabled: canApply && !syncStore.isApplying
            )
        }
        .buttonStyle(.plain)
        .disabled(!canApply || syncStore.isApplying)
        .keyboardShortcut(.defaultAction)
    }

    private func successState(_ plan: PortfolioPerformanceMergePlan) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.green)
            Text(successTitle(plan))
                .font(.system(size: 17, weight: .semibold))
            Text(successText(plan))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onClose) {
                PanelButtonLabel(
                    title: "返回持仓收益",
                    systemImage: "chart.xyaxis.line",
                    style: .primary,
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .frame(width: 190)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func errorState(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 13) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(PanelDesign.warningAccent)
                Text(syncStore.hasAccountMismatch ? "京东账号不一致" : "暂时无法补全")
                    .font(.system(size: 16, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)

                if syncStore.canClearPerformanceHistoryForAccountMismatch {
                    Button(role: .destructive) {
                        isShowingClearConfirmation = true
                    } label: {
                        PanelButtonLabel(
                            title: "清除旧账号收益",
                            systemImage: "trash",
                            style: .destructive
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 190)
                }

                if syncStore.accountMismatchSource?.involvesHoldingsBaseline == true {
                    Button(action: onClose) {
                        PanelButtonLabel(
                            title: "返回持仓收益",
                            systemImage: "arrow.left",
                            style: .primary,
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 190)
                }

                Button(action: retrySync) {
                    PanelButtonLabel(
                        title: syncStore.hasAccountMismatch ? "重新检查当前账号" : "重试",
                        systemImage: "arrow.clockwise",
                        style: syncStore.hasAccountMismatch ? .secondary : .primary,
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)
                .frame(width: 190)

            }
            .frame(maxWidth: .infinity, minHeight: 400)
        }
        .scrollIndicators(.never)
    }

    private func previewMetric(_ title: String, value: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(value == 0 ? Color.secondary : tint)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(PanelDesign.inputBackground.opacity(0.56), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 8))
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(PanelDesign.warningAccent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func skippedRowsText(_ plan: PortfolioPerformanceMergePlan) -> String {
        var parts: [String] = []
        if plan.zeroValueSkippedCount > 0 {
            parts.append("已忽略 \(plan.zeroValueSkippedCount) 个零收益日，避免周末和节假日挤满日历")
        }
        if plan.invalidValueSkippedCount > 0 {
            parts.append("已跳过 \(plan.invalidValueSkippedCount) 条异常记录")
        }
        return parts.joined(separator: "；")
    }

    private func applyTitle(
        selectedCount: Int,
        plan: PortfolioPerformanceMergePlan
    ) -> String {
        if selectedCount > 0 {
            return "补全 \(selectedCount) 天"
        }
        if plan.metadataChanged {
            return "保存同步范围"
        }
        if !plan.conflicts.isEmpty {
            return "需处理冲突"
        }
        return "已是最新"
    }

    private func successTitle(_ plan: PortfolioPerformanceMergePlan) -> String {
        let changed = plan.selectedDayChangeCount(overwriteConflicts: overwritesConflicts)
        if changed == 0, !plan.conflicts.isEmpty {
            return "同步完成，冲突已保留"
        }
        if changed == 0 {
            return "同步范围已更新"
        }
        if !overwritesConflicts, !plan.conflicts.isEmpty {
            return "可补全收益已写入"
        }
        return "历史收益已补全"
    }

    private func successText(_ plan: PortfolioPerformanceMergePlan) -> String {
        let changed = plan.selectedDayChangeCount(overwriteConflicts: overwritesConflicts)
        if changed == 0 {
            if !plan.conflicts.isEmpty {
                return "已更新同步范围，并保留 \(plan.conflicts.count) 天本地已确认冲突。"
            }
            return "没有需要改写的收益日，同步范围已更新到 \(plan.coveredThrough)。"
        }
        if !overwritesConflicts, !plan.conflicts.isEmpty {
            return "已写入或更新 \(changed) 个收益日，并保留 \(plan.conflicts.count) 天本地已确认冲突。"
        }
        return "已写入或更新 \(changed) 个收益日；之后本地刷新会继续记录最新数据。"
    }

    private func amountText(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.money(value, signed: true)
    }

    private func requestLogin() {
        guard isPresented, !isRequestingLogin else { return }
        isRequestingLogin = true
        onRequestLogin { cookieHeader in
            Task { @MainActor in
                guard isPresented else { return }
                isRequestingLogin = false
                await synchronize(cookieHeader: cookieHeader)
            }
        }
    }

    private func retrySync() {
        localErrorMessage = nil
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            let cookieHeader = await JDFinanceWebSession.cookieHeader()
            guard !Task.isCancelled, isPresented else { return }
            await synchronize(cookieHeader: cookieHeader)
        }
    }

    private func clearHistoryAndRetry() {
        guard syncStore.canClearPerformanceHistoryForAccountMismatch else {
            localErrorMessage = syncStore.accountMismatchSource?.message
                ?? "当前账号冲突不能通过清除历史收益解决，请先处理持仓同步基线。"
            return
        }
        do {
            try JDFinancePerformanceSyncStore.clearJDFinanceHistory(in: performanceStore)
            localErrorMessage = nil
            retrySync()
        } catch {
            localErrorMessage = "清除旧账号收益失败：\(error.localizedDescription)"
        }
    }

    private func synchronize(cookieHeader: String?) async {
        JDFinanceWebSession.rememberCookieHeader(cookieHeader)
        await syncStore.synchronize(
            performanceStore: performanceStore,
            cookieHeader: cookieHeader,
            expectedAccountKey: portfolioStore.snapshot.jdFinanceSyncState?.accountKey
        )
    }
}
