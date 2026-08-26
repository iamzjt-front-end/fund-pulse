import SwiftUI

enum PortfolioAccountPresentation {
    static func showsAccountBar(accountCount: Int) -> Bool {
        accountCount > 0
    }
}

struct PortfolioAccountTabBar: View {
    let accountsStore: PortfolioAccountsStore
    let onSelect: (PortfolioAccountSelection) -> Void
    let onManageAccounts: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAccountListPresented = false

    var body: some View {
        HStack(spacing: 7) {
            scopeButton(title: "全部", isSelected: accountsStore.selection == .all) {
                onSelect(.all)
            }
            .fixedSize(horizontal: true, vertical: false)

            Divider()
                .frame(height: 19)

            accountTabs
                .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 19)

            accountActionButton(
                systemName: "list.bullet.rectangle",
                help: "查找或切换账户"
            ) {
                isAccountListPresented.toggle()
            }
            .popover(isPresented: $isAccountListPresented, arrowEdge: .bottom) {
                PortfolioAccountPickerPopover(
                    accountsStore: accountsStore,
                    onSelect: { selection in
                        isAccountListPresented = false
                        onSelect(selection)
                    },
                    onManage: {
                        isAccountListPresented = false
                        onManageAccounts()
                    }
                )
            }

            accountActionButton(
                systemName: "gearshape",
                help: "设置",
                action: onOpenSettings
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(tabBarBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(colorScheme == .dark ? 0.42 : 0.52)
        }
    }

    private var accountTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(accountsStore.accounts) { account in
                        let isSelected = accountsStore.selection == .account(account.id)
                        Button {
                            onSelect(.account(account.id))
                        } label: {
                            HStack(spacing: 5) {
                                Text(account.name)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                                accountKindBadge(account.kind, isSelected: isSelected)
                            }
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(tabBackground(isSelected: isSelected), in: Capsule())
                            .overlay(tabBorder(isSelected: isSelected))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .id(account.id)
                        .help("切换到\(account.name)")
                        .accessibilityLabel("\(account.name)，\(account.kind.title)账户")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 3)
            }
            .overlay(alignment: .leading) {
                scrollEdgeFade(startPoint: .leading, endPoint: .trailing)
            }
            .overlay(alignment: .trailing) {
                scrollEdgeFade(startPoint: .trailing, endPoint: .leading)
            }
            .onAppear {
                centerSelectedAccount(using: proxy, animated: false)
            }
            .onChange(of: accountsStore.selection) { _, _ in
                centerSelectedAccount(using: proxy, animated: true)
            }
            .onChange(of: accountsStore.accounts.map(\.id)) { _, _ in
                centerSelectedAccount(using: proxy, animated: true)
            }
        }
    }

    private func centerSelectedAccount(using proxy: ScrollViewProxy, animated: Bool) {
        guard let accountID = accountsStore.selection.accountID else { return }
        let action = {
            proxy.scrollTo(accountID, anchor: .center)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private func scopeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(tabBackground(isSelected: isSelected), in: Capsule())
                .overlay(tabBorder(isSelected: isSelected))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("查看全部账户汇总")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accountKindBadge(_ kind: PortfolioAccountKind, isSelected: Bool) -> some View {
        Text(kind.title)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(kindColor(kind).opacity(isSelected ? 1 : 0.80))
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(kindColor(kind).opacity(colorScheme == .dark ? 0.16 : 0.10), in: Capsule())
    }

    private func accountActionButton(
        systemName: String,
        help: String,
        tone: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(tone == nil ? .hierarchical : .monochrome)
                .foregroundStyle(tone ?? Color.primary.opacity(0.82))
                .frame(width: 28, height: 28)
                .background(actionButtonBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke((tone ?? Color.primary).opacity(colorScheme == .dark ? 0.16 : 0.12), lineWidth: 0.7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }

    private func tabBackground(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.94)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025)
    }

    private func tabBorder(isSelected: Bool) -> some View {
        Capsule()
            .stroke(
                isSelected
                    ? Color.primary.opacity(colorScheme == .dark ? 0.19 : 0.13)
                    : Color.primary.opacity(0.055),
                lineWidth: 0.7
            )
    }

    private func kindColor(_ kind: PortfolioAccountKind) -> Color {
        switch kind {
        case .offExchange:
            Color.orange
        case .onExchange:
            Color(nsColor: .systemBlue)
        }
    }

    private func scrollEdgeFade(startPoint: UnitPoint, endPoint: UnitPoint) -> some View {
        LinearGradient(
            colors: [tabBarSolidColor, tabBarSolidColor.opacity(0)],
            startPoint: startPoint,
            endPoint: endPoint
        )
        .frame(width: 10)
        .allowsHitTesting(false)
    }

    private var actionButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.78)
    }

    private var tabBarSolidColor: Color {
        colorScheme == .dark
            ? Color(red: 21 / 255, green: 23 / 255, blue: 28 / 255)
            : Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255)
    }

    private var tabBarBackground: some View {
        ZStack {
            tabBarSolidColor
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.025 : 0.25), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct PortfolioAccountPickerPopover: View {
    let accountsStore: PortfolioAccountsStore
    let onSelect: (PortfolioAccountSelection) -> Void
    let onManage: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索账户", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 8))
            .padding(10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    pickerRow(
                        title: "全部账户",
                        subtitle: "只汇总展示，不合并交易记录",
                        systemName: "square.grid.2x2",
                        isSelected: accountsStore.selection == .all
                    ) {
                        onSelect(.all)
                    }

                    ForEach(filteredAccounts) { account in
                        pickerRow(
                            title: account.name,
                            subtitle: accountSubtitle(account),
                            systemName: account.kind == .offExchange ? "banknote" : "chart.line.uptrend.xyaxis",
                            isSelected: accountsStore.selection == .account(account.id)
                        ) {
                            onSelect(.account(account.id))
                        }
                    }

                    if filteredAccounts.isEmpty {
                        Text("没有匹配的账户")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(7)
            }

            Divider()

            Button(action: onManage) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("管理账户")
                    Spacer()
                    Text("\(accountsStore.accounts.count) 个")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .frame(width: 270, height: 310)
        .background(PanelDesign.panelBackground)
    }

    private var filteredAccounts: [PortfolioAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return accountsStore.accounts }
        return accountsStore.accounts.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.kind.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func accountSubtitle(_ account: PortfolioAccount) -> String {
        let snapshot = accountsStore.store(for: account.id)?.snapshot ?? .empty
        return "\(account.kind.title) · \(snapshot.funds.count) 只基金"
    }

    private func pickerRow(
        title: String,
        subtitle: String,
        systemName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? PanelDesign.accent : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background((isSelected ? PanelDesign.accent : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PanelDesign.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 43)
            .background(isSelected ? PanelDesign.accent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct AllAccountsOverviewView: View {
    let accountsStore: PortfolioAccountsStore
    let onSelectAccount: (String) -> Void
    let onRefresh: (() async -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferenceKey.hideHeaderAmounts) private var hidesAmounts = false
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            overviewHeader

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(accountsStore.accounts) { account in
                        accountCard(account)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }

            overviewToolbar
        }
        .background(surfaceBackground)
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("全部账户")
                        .font(.system(size: 14, weight: .semibold))
                    Text("仅汇总资产与收益，交易记录仍按账户隔离")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(accountsStore.accounts.count) 个账户")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.primary.opacity(0.055), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("总资产")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(money(accountsStore.summary.totalAmount))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(totalAmountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            HStack(spacing: 7) {
                summaryMetric(
                    title: "持仓收益",
                    value: signedMoney(accountsStore.summary.holdingIncome),
                    rate: percent(accountsStore.summary.holdingIncomeRate),
                    tone: accountsStore.summary.holdingIncome
                )
                summaryMetric(
                    title: "今日收益",
                    value: signedMoney(accountsStore.summary.todayIncome),
                    rate: percent(accountsStore.summary.todayIncomeRate),
                    tone: accountsStore.summary.todayIncome
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .background(headerBackground)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private func summaryMetric(title: String, value: String, rate: String, tone: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(toneColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            HStack(spacing: 4) {
                Circle()
                    .fill(toneColor(tone))
                    .frame(width: 4, height: 4)

                Text(rate)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(toneColor(tone).opacity(0.86))
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private func accountCard(_ account: PortfolioAccount) -> some View {
        let snapshot = accountsStore.store(for: account.id)?.snapshot ?? .empty
        return Button {
            onSelectAccount(account.id)
        } label: {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: account.kind == .offExchange ? "banknote" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accountKindColor(account.kind))
                        .frame(width: 27, height: 27)
                        .background(accountKindColor(account.kind).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(account.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(account.kind.title)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(accountKindColor(account.kind))
                                .padding(.horizontal, 4)
                                .frame(height: 14)
                                .background(accountKindColor(account.kind).opacity(0.10), in: Capsule())
                        }
                        Text("\(snapshot.funds.count) 只基金\(snapshot.pendingCount > 0 ? " · \(snapshot.pendingCount) 笔待确认" : "")")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    accountRateSummary(snapshot)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline) {
                    accountValue(title: "资产", value: money(snapshot.totalAmount), tone: nil)
                    Spacer()
                    accountValue(
                        title: "持仓",
                        value: signedHoldingIncome(snapshot.holdingIncome, accountKind: account.kind),
                        tone: snapshot.holdingIncome
                    )
                    Spacer()
                    accountValue(title: "今日", value: signedMoney(snapshot.todayIncome), tone: snapshot.todayIncome, alignment: .trailing)
                }
            }
            .padding(10)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("打开\(account.name)")
    }

    private func accountRateSummary(_ snapshot: PortfolioSnapshot) -> some View {
        HStack(spacing: 9) {
            accountRateMetric(title: "持有", rate: snapshot.holdingIncomeRate)

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.17 : 0.10))
                .frame(width: 1, height: 27)

            accountRateMetric(title: "今日", rate: snapshot.todayIncomeRate)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
    }

    private func accountRateMetric(title: String, rate: Double) -> some View {
        let color = toneColor(rate)
        return VStack(alignment: .trailing, spacing: 1.5) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)

                Text(percent(rate))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minWidth: 49, alignment: .trailing)
        .help("\(title)收益率 \(percent(rate))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)收益率")
        .accessibilityValue(percent(rate))
    }

    private func accountValue(
        title: String,
        value: String,
        tone: Double?,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone.map(toneColor) ?? Color.primary)
                .lineLimit(1)
        }
    }

    private var overviewToolbar: some View {
        HStack {
            Text("共 \(accountsStore.summary.fundCount) 只基金")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await onRefresh?()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    .frame(width: 27, height: 27)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(isRefreshing)
            .help("刷新全部账户")

        }
        .padding(.horizontal, 11)
        .frame(height: 42)
        .background(toolbarBackground)
        .overlay(alignment: .top) { Divider().opacity(0.48) }
    }

    private func money(_ value: Double) -> String {
        hidesAmounts ? "••••••" : MoneyFormatter.plainMoney(value)
    }

    private func signedMoney(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.money(value, signed: true)
    }

    private func signedHoldingIncome(_ value: Double, accountKind: PortfolioAccountKind) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.holdingIncome(value, accountKind: accountKind)
    }

    private func percent(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.percent(value, signed: true)
    }

    private func toneColor(_ value: Double) -> Color {
        if hidesAmounts { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .fundPulseGreen }
        return .secondary
    }

    private func accountKindColor(_ kind: PortfolioAccountKind) -> Color {
        kind == .offExchange ? .orange : Color(nsColor: .systemBlue)
    }

    private var totalAmountColor: Color {
        hidesAmounts ? .secondary : (colorScheme == .dark ? Color(red: 1, green: 0.82, blue: 0.49) : Color(red: 0.62, green: 0.38, blue: 0.07))
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.73)
    }

    private var surfaceBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 16 / 255, green: 18 / 255, blue: 22 / 255), Color(red: 12 / 255, green: 14 / 255, blue: 18 / 255)]
                : [Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255), Color(red: 244 / 255, green: 241 / 255, blue: 235 / 255)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var headerBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 31 / 255, green: 35 / 255, blue: 42 / 255), Color(red: 20 / 255, green: 23 / 255, blue: 29 / 255)]
                : [Color(red: 255 / 255, green: 250 / 255, blue: 240 / 255), Color(red: 255 / 255, green: 239 / 255, blue: 224 / 255)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var toolbarBackground: Color {
        colorScheme == .dark
            ? Color(red: 16 / 255, green: 18 / 255, blue: 22 / 255)
            : Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255)
    }
}

struct PortfolioAccountEditorView: View {
    let accountsStore: PortfolioAccountsStore
    let onSaved: (PortfolioAccount) -> Void
    let onClose: () -> Void

    @State private var name = ""
    @State private var kind: PortfolioAccountKind = .offExchange
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "person.crop.circle.badge.plus",
                title: "新建账户",
                subtitle: "每个账户使用独立的持仓与收益数据",
                onClose: onClose
            )

            Divider()

            VStack(spacing: 12) {
                PanelSection(title: "账户名称") {
                    PanelTextInput(kind.accountTitle, text: $name)
                    Text("例如：京东基金、证券账户、长期定投")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                PanelSection(title: "账户类型") {
                    PanelSegmentedPicker(
                        values: PortfolioAccountKind.allCases,
                        selection: $kind,
                        title: { $0.title },
                        accessibilityLabelText: "账户类型"
                    )

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: kind == .offExchange ? "banknote" : "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(kind == .offExchange ? Color.orange : Color(nsColor: .systemBlue))
                        Text(kind.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PanelDesign.inputBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text("新账户会创建独立目录；基金、交易记录和收益历史不会与其他账户混合。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 9))
                .overlay(PanelDesign.border(cornerRadius: 9))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onClose) {
                        PanelButtonLabel(title: "取消")
                    }
                    .buttonStyle(.plain)

                    Button(action: save) {
                        PanelButtonLabel(
                            title: "创建并切换",
                            systemImage: "checkmark",
                            style: .primary,
                            isEnabled: !trimmedName.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedName.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .background(PanelDesign.panelBackground)
        .onAppear {
            if name.isEmpty {
                name = suggestedName
            }
        }
        .onChange(of: kind) { _, _ in
            if name == PortfolioAccountKind.offExchange.accountTitle
                || name == PortfolioAccountKind.onExchange.accountTitle {
                name = suggestedName
            }
            errorMessage = nil
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestedName: String {
        let base = kind.accountTitle
        guard accountsStore.accounts.contains(where: { $0.name == base }) else { return base }
        var index = 2
        while accountsStore.accounts.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func save() {
        do {
            let account = try accountsStore.createAccount(name: trimmedName, kind: kind)
            onSaved(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PortfolioAccountManagementView: View {
    let accountsStore: PortfolioAccountsStore
    let onAddAccount: () -> Void
    let onSelected: (String) -> Void
    let onAccountsChanged: () -> Void
    let onClose: () -> Void

    @State private var editingAccountID: String?
    @State private var editingName = ""
    @State private var accountPendingArchive: PortfolioAccount?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "person.2",
                title: "账户管理",
                subtitle: "管理独立账户",
                actionSystemImage: "plus",
                actionTitle: "新建账户",
                actionTint: PanelDesign.accent,
                actionHelp: "新建账户",
                onAction: onAddAccount,
                onClose: onClose
            )

            Divider()

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.secondary)
                    Text("默认账户继续使用升级前的文件位置。移除其他账户时，数据会移到 Archived Accounts，便于恢复。")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 9))
                .overlay(PanelDesign.border(cornerRadius: 9))

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(accountsStore.accounts.enumerated()), id: \.element.id) { index, account in
                            accountManagementRow(account, index: index)
                        }
                    }
                    .padding(.vertical, 1)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .background(PanelDesign.panelBackground)
        .alert("移除账户", isPresented: archiveConfirmationBinding, presenting: accountPendingArchive) { account in
            Button("取消", role: .cancel) {
                accountPendingArchive = nil
            }
            Button("移除账户", role: .destructive) {
                archive(account)
            }
        } message: { account in
            Text("“\(account.name)”会从账户列表移除，数据将保留在 Archived Accounts 目录中。")
        }
    }

    private func accountManagementRow(_ account: PortfolioAccount, index: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onSelected(account.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: account.kind == .offExchange ? "banknote" : "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(account.kind == .offExchange ? Color.orange : Color(nsColor: .systemBlue))
                            .frame(width: 25, height: 25)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(account.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                if account.isDefault {
                                    Text("默认")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .frame(height: 14)
                                        .background(Color.secondary.opacity(0.10), in: Capsule())
                                }
                            }
                            Text(accountRowSubtitle(account))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                Spacer(minLength: 6)

                compactActionButton("arrow.up", help: "向前移动", isDisabled: index == 0) {
                    move(account, by: -1)
                }
                compactActionButton("arrow.down", help: "向后移动", isDisabled: index == accountsStore.accounts.count - 1) {
                    move(account, by: 1)
                }
                compactActionButton("pencil", help: "重命名") {
                    editingAccountID = account.id
                    editingName = account.name
                    errorMessage = nil
                }
                if !account.isDefault {
                    compactActionButton(
                        "archivebox",
                        help: accountsStore.isRefreshing ? "刷新完成后可移除账户" : "移除账户",
                        tone: .red,
                        isDisabled: accountsStore.isRefreshing
                    ) {
                        accountPendingArchive = account
                    }
                }
            }

            if editingAccountID == account.id {
                HStack(spacing: 7) {
                    PanelTextInput("账户名称", text: $editingName)
                    Button("取消") {
                        editingAccountID = nil
                    }
                    .buttonStyle(.borderless)
                    Button("保存") {
                        rename(account)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PanelDesign.accent)
                    .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(9)
        .background(
            accountsStore.selection == .account(account.id)
                ? PanelDesign.accent.opacity(0.065)
                : PanelDesign.cardBackground,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func accountRowSubtitle(_ account: PortfolioAccount) -> String {
        let snapshot = accountsStore.store(for: account.id)?.snapshot ?? .empty
        return "\(account.kind.title) · \(snapshot.funds.count) 只基金"
    }

    private func compactActionButton(
        _ systemName: String,
        help: String,
        tone: Color = .secondary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 24, height: 24)
                .background(PanelDesign.buttonBackground, in: RoundedRectangle(cornerRadius: 7))
                .overlay(PanelDesign.border(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
    }

    private var archiveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { accountPendingArchive != nil },
            set: { if !$0 { accountPendingArchive = nil } }
        )
    }

    private func rename(_ account: PortfolioAccount) {
        do {
            try accountsStore.renameAccount(id: account.id, name: editingName)
            editingAccountID = nil
            errorMessage = nil
            onAccountsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ account: PortfolioAccount, by offset: Int) {
        do {
            try accountsStore.moveAccount(id: account.id, by: offset)
            errorMessage = nil
            onAccountsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive(_ account: PortfolioAccount) {
        do {
            try accountsStore.archiveAccount(id: account.id)
            accountPendingArchive = nil
            editingAccountID = nil
            errorMessage = nil
            onAccountsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
