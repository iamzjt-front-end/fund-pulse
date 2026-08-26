import SwiftUI

enum FundPositionEntryPolicy {
    static func modes(for accountKind: PortfolioAccountKind) -> [PositionMode] {
        switch accountKind {
        case .offExchange:
            [.amount, .share]
        case .onExchange:
            [.share]
        }
    }

    static func defaultMode(
        for accountKind: PortfolioAccountKind,
        existingMode: PositionMode?
    ) -> PositionMode {
        if accountKind == .onExchange {
            return .share
        }
        if let existingMode {
            return existingMode
        }
        return .amount
    }
}

struct FundPositionEditorView: View {
    private enum MetadataLookupState: Equatable {
        case idle
        case loading
        case loaded(FundQuote)
        case failed(String)
    }

    private struct MetadataLookupRequest: Equatable {
        var code: String
        var attempt: Int
    }

    let store: PortfolioStore
    let fund: FundPosition?
    let onSaved: (() async -> Void)?
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var name: String
    @State private var positionMode: PositionMode
    @State private var positionAmount: String
    @State private var positionProfit: String
    @State private var shares: String
    @State private var sellableShares: String
    @State private var cost: String
    @State private var isSameDayNewFund: Bool
    @State private var positionDate: Date
    @State private var positionTimeType: PositionTimeType
    @State private var exchangeTurnaroundRule: ExchangeTurnaroundRule
    @State private var memo: String
    @State private var autoResolvedName: String?
    @State private var metadataLookupState: MetadataLookupState = .idle
    @State private var metadataLookupAttempt = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        store: PortfolioStore,
        fund: FundPosition? = nil,
        onSaved: (() async -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.fund = fund
        self.onSaved = onSaved
        self.onClose = onClose

        let mode = FundPositionEntryPolicy.defaultMode(
            for: store.accountKind,
            existingMode: fund?.positionMode
        )
        let date = fund?.positionDate.flatMap(DateOnlyFormatter.parse) ?? .now
        let netValue: Double? = {
            guard let principal = fund?.migratedPrincipal,
                  let shares = fund?.migratedShares,
                  shares > 0
            else { return nil }
            return principal / shares
        }()
        let amount: Double? = {
            if let pendingAmount = fund?.pendingAmount {
                return pendingAmount
            }
            if let currentAmount = fund?.currentAmount {
                return currentAmount
            }
            if let principal = fund?.migratedPrincipal {
                return principal + (fund?.holdingIncome ?? 0)
            }
            guard let netValue, let shares = fund?.migratedShares else { return nil }
            return shares * netValue
        }()
        let initialSellableShares: String = {
            guard store.accountKind == .onExchange else { return "" }
            guard let fund else { return "0" }
            return Self.text(store.exchangeShareAvailability(for: fund.code).sellableShares, places: 2)
        }()
        let profit: Double? = {
            if let pendingProfit = fund?.pendingProfit {
                return pendingProfit
            }
            if let holdingIncome = fund?.holdingIncome {
                return holdingIncome
            }
            guard let netValue,
                  let shares = fund?.migratedShares,
                  let cost = fund?.migratedCost
            else { return nil }
            return (netValue - cost) * shares
        }()

        _code = State(initialValue: fund?.code ?? "")
        _name = State(initialValue: fund?.name ?? "")
        _positionMode = State(initialValue: mode)
        _positionAmount = State(initialValue: amount.map { Self.fixedText($0, places: PortfolioPrecision.moneyPlaces) } ?? "")
        _positionProfit = State(initialValue: profit.map { Self.fixedText($0, places: PortfolioPrecision.moneyPlaces) } ?? "")
        _shares = State(initialValue: fund?.migratedShares.map { Self.text($0, places: 2) } ?? "")
        _sellableShares = State(initialValue: initialSellableShares)
        _cost = State(initialValue: fund?.migratedCost.map { Self.text($0, places: 4) } ?? "")
        _isSameDayNewFund = State(initialValue: false)
        _positionDate = State(initialValue: date)
        _positionTimeType = State(initialValue: fund?.positionTimeType ?? TradingCalendar.defaultPositionTimeType())
        _exchangeTurnaroundRule = State(initialValue: fund?.resolvedExchangeTurnaroundRule ?? .nextTradingDay)
        _memo = State(initialValue: fund?.memo ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .layoutPriority(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PanelSection(title: "基金识别") {
                        field("基金代码") {
                            PanelTextInput("例如 588760", text: $code, isDisabled: fund != nil)
                            if hasInvalidFundCode {
                                Text("请输入 6 位基金代码")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 2)
                            }
                        }
                        field("基金名称") {
                            PanelTextInput("可选，留空则自动读取", text: $name)
                            if isLookingUpMetadata && fund == nil {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("正在读取基金名称")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                        latestNetValueRow
                    }

                    PanelSection(title: "持仓录入") {
                        if FundPositionEntryPolicy.modes(for: store.accountKind).count > 1 {
                            PanelSegmentedPicker(
                                values: FundPositionEntryPolicy.modes(for: store.accountKind),
                                selection: $positionMode,
                                title: { $0.title }
                            )
                        }

                        if isOnExchange {
                            HStack(spacing: 8) {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(PanelDesign.accent)
                                Text(exchangePositionModeSummary)
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer(minLength: 0)
                                Text("精确录入")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(PanelDesign.accent)
                                    .padding(.horizontal, 6)
                                    .frame(height: 18)
                                    .background(PanelDesign.accent.opacity(0.10), in: Capsule())
                            }
                            .padding(9)
                            .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(PanelDesign.border(cornerRadius: 9))
                        }

                        if isOnExchange {
                            field("持仓份额") {
                                PanelTextInput("请输入券商显示的实际持仓份额", text: $shares, suffix: "份")
                            }
                            field("可卖份额") {
                                PanelTextInput("请输入当前可卖份额", text: $sellableShares, suffix: "份")
                            }
                            if let validationMessage = exchangeSellableValidationMessage {
                                Text(validationMessage)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            field("平均成本价") {
                                PanelTextInput("含历史交易费用的平均成本", text: $cost, suffix: "元")
                            }
                        } else if positionMode == .amount {
                            field(isOnExchange ? "持仓市值" : "持仓金额") {
                                PanelTextInput(
                                    isOnExchange ? "请输入券商显示的当前市值" : "请输入持仓金额",
                                    text: $positionAmount,
                                    suffix: "元"
                                )
                            }
                            field(isOnExchange ? "持仓盈亏" : "持仓收益") {
                                PanelTextInput(
                                    isOnExchange ? "请输入券商显示的累计盈亏，可为负" : "可为负，默认为 0",
                                    text: $positionProfit,
                                    suffix: "元"
                                )
                            }
                            if isOnExchange, let preview = exchangeAmountPreview {
                                exchangeAmountPreviewRow(preview)
                            }
                        } else {
                            field("持仓份额") {
                                PanelTextInput("可精确 2 位小数", text: $shares, suffix: "份")
                            }
                            field("持仓成本价") {
                                PanelTextInput("可精确 4 位小数", text: $cost, suffix: "元")
                            }
                        }

                        if isOnExchange {
                            field("可卖规则") {
                                PanelSegmentedPicker(
                                    values: Array(ExchangeTurnaroundRule.allCases),
                                    selection: $exchangeTurnaroundRule,
                                    title: { $0.shortTitle }
                                )
                            }
                            Text(exchangeTurnaroundHelp)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            field("持仓起始日") {
                                PanelNativeDatePicker(selection: $positionDate, elements: [.yearMonthDay])
                            }
                            Text(exchangePositionHelp)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if fund == nil {
                            sameDayNewFundRow
                            if shouldShowTradeTimeControls {
                                field("交易时点") {
                                    PanelSegmentedPicker(
                                        values: Array(PositionTimeType.allCases),
                                        selection: $positionTimeType,
                                        title: { $0.title }
                                    )
                                }
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: shouldShowTradeTimeControls)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            footer
                .layoutPriority(1)
        }
        .frame(width: PopoverLayout.editorWidth, height: PopoverLayout.editorHeight)
        .background(PanelDesign.panelBackground)
        .onChange(of: isSameDayNewFund) { _, newValue in
            guard newValue else { return }
            positionDate = .now
            positionTimeType = TradingCalendar.defaultPositionTimeType()
        }
        .onAppear {
            if isSameDayNewFund {
                positionDate = .now
                positionTimeType = TradingCalendar.defaultPositionTimeType()
            }
        }
        .task(id: metadataLookupRequest) {
            await loadFundMetadata(for: metadataLookupRequest)
        }
    }

    private var header: some View {
        PanelHeader(
            systemImage: fund == nil ? "plus" : "pencil",
            title: headerTitle,
            subtitle: headerSubtitle,
            onClose: close
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                close()
            } label: {
                PanelButtonLabel(title: "取消")
                    .frame(width: 82)
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button {
                save()
            } label: {
                PanelButtonLabel(
                    title: isSaving ? "处理中" : (fund == nil ? "确认添加" : "保存修改"),
                    style: .primary,
                    isEnabled: canSubmit && !isSaving
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || !canSubmit)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .overlay(alignment: .top) {
            Divider().opacity(0.55)
        }
    }

    private var latestNetValueRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isOnExchange ? "最新成交价" : "最新净值")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(latestQuoteSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch metadataLookupState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .loaded(let latestQuote):
                Text(Self.text(latestQuote.netValue, places: 4))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelDesign.accent)
                    .monospacedDigit()
            case .failed(let reason):
                Button {
                    metadataLookupAttempt &+= 1
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("重试")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("行情读取失败：\(reason)。点击重试")
                .accessibilityLabel("行情读取失败，重试")
            case .idle:
                Text("暂无")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(9)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func exchangeAmountPreviewRow(
        _ preview: (shares: Double, cost: Double, price: Double)
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("系统自动推算")
                    .font(.system(size: 11, weight: .semibold))
                Text("按最新成交价 \(Self.text(preview.price, places: 4)) 元")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("约 \(Self.text(preview.shares, places: 4)) 份")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                Text("平均成本 \(Self.text(preview.cost, places: 4)) 元")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(9)
        .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var confirmNetValueTip: some View {
        let dateText = DateOnlyFormatter.string(from: positionDate)
        let acceptedDate = TradingCalendar.acceptedTradeDate(positionDate: dateText, timeType: positionTimeType)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("确认净值日")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("按该日净值确认份额和成本")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(acceptedDate)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .padding(9)
        .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.10), lineWidth: 0.6)
        )
    }

    private var sameDayNewFundRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelDesign.warningAccent)
                Text("是否当日新增")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelDesign.warningAccent)
                Spacer()
                Toggle("", isOn: $isSameDayNewFund)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Text(isSameDayNewFund ? "开启后表示今天刚买入，需选择 15:00 前后；净值未确认前进入待确认。" : "关闭时按已有历史持仓补录，使用最新确认净值进入持仓，不进入待确认。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PanelDesign.warningBorder, lineWidth: 1)
        )
    }

    private var isTodayNewFund: Bool {
        !isOnExchange && fund == nil && isSameDayNewFund
    }

    private var shouldShowTradeTimeControls: Bool {
        isTodayNewFund
    }

    private var canSubmit: Bool {
        guard isValidFundCode else { return false }
        switch positionMode {
        case .amount:
            let amount = Self.number(positionAmount) ?? 0
            let profit = Self.number(positionProfit) ?? 0
            guard amount > 0, amount - profit > 0 else { return false }
            return !isOnExchange || (latestQuote?.netValue ?? 0) > 0
        case .share:
            let shares = Self.number(shares) ?? 0
            let cost = Self.number(cost) ?? 0
            guard shares > 0, cost > 0 else { return false }
            guard isOnExchange else { return true }
            let sellableShares = Self.number(sellableShares) ?? -1
            return sellableShares >= 0
                && sellableShares <= shares + PortfolioPrecision.shareAvailabilityTolerance
                && exchangeSellableValidationMessage == nil
        }
    }

    private var exchangeSellableValidationMessage: String? {
        guard isOnExchange else { return nil }
        guard let heldShares = Self.number(shares), heldShares > 0 else { return nil }
        guard let sellableShares = Self.number(sellableShares) else {
            return "请填写当前可卖份额"
        }
        if sellableShares < 0 {
            return "可卖份额不能为负数"
        }
        if sellableShares > heldShares + PortfolioPrecision.shareAvailabilityTolerance {
            return "可卖份额不能大于持仓份额"
        }
        if exchangeTurnaroundRule == .sameDay,
           sellableShares + PortfolioPrecision.shareAvailabilityTolerance < heldShares {
            return "T+0 基金的可卖份额应等于持仓份额"
        }
        return nil
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let resolvedPositionDate = DateOnlyFormatter.string(from: isTodayNewFund ? .now : positionDate)
        let resolvedPositionTimeType = isTodayNewFund ? positionTimeType : .before15
        let resolvedMode = positionMode

        let draft = FundPositionDraft(
            code: code,
            name: name,
            positionMode: resolvedMode,
            positionAmount: resolvedMode == .amount ? Self.number(positionAmount) : nil,
            positionProfit: resolvedMode == .amount ? (Self.number(positionProfit) ?? 0) : 0,
            shares: resolvedMode == .share ? Self.number(shares) : nil,
            cost: resolvedMode == .share ? Self.number(cost) : nil,
            positionDate: resolvedPositionDate,
            positionTimeType: resolvedPositionTimeType,
            memo: memo,
            requiresTradeConfirmation: !isOnExchange && isTodayNewFund,
            exchangeTurnaroundRule: isOnExchange ? exchangeTurnaroundRule : nil,
            exchangeSellableShares: isOnExchange ? Self.number(sellableShares) : nil
        )

        Task {
            do {
                try await store.upsertFund(draft, replacing: fund?.code)
                if let onSaved {
                    await onSaved()
                }
                await MainActor.run {
                    close()
                }
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func loadFundMetadata(for request: MetadataLookupRequest) async {
        let trimmedCode = request.code
        guard trimmedCode.count == 6, trimmedCode.allSatisfy(\.isNumber) else {
            metadataLookupState = .idle
            return
        }

        metadataLookupState = .loading
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()

            let fetchedQuote = try await store.fetchLatestQuoteThrowing(code: trimmedCode)
            let fetchedName: String?
            if fetchedQuote.name != trimmedCode {
                fetchedName = fetchedQuote.name
            } else {
                fetchedName = await store.lookupFundName(code: trimmedCode)
            }
            try Task.checkCancellation()
            guard code.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedCode else {
                return
            }

            applyResolvedName(fetchedName)
            metadataLookupState = .loaded(fetchedQuote)
        } catch is CancellationError {
            return
        } catch {
            let reason = error.localizedDescription
            let fetchedName = await store.lookupFundName(code: trimmedCode)
            guard !Task.isCancelled,
                  code.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedCode
            else {
                return
            }

            applyResolvedName(fetchedName)
            metadataLookupState = .failed(reason)
        }
    }

    private func applyResolvedName(_ fetchedName: String?) {
        guard fund == nil,
              let fetchedName,
              name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == autoResolvedName
        else {
            return
        }
        name = fetchedName
        autoResolvedName = fetchedName
    }

    private var metadataLookupRequest: MetadataLookupRequest {
        MetadataLookupRequest(
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            attempt: metadataLookupAttempt
        )
    }

    private var isLookingUpMetadata: Bool {
        metadataLookupState == .loading
    }

    private var latestQuote: FundQuote? {
        guard case .loaded(let quote) = metadataLookupState else { return nil }
        return quote
    }

    private var exchangeAmountPreview: (shares: Double, cost: Double, price: Double)? {
        guard isOnExchange,
              positionMode == .amount,
              let price = latestQuote?.netValue,
              price > 0,
              let amount = Self.number(positionAmount),
              amount > 0
        else {
            return nil
        }
        let profit = Self.number(positionProfit) ?? 0
        let principal = amount - profit
        guard principal > 0 else { return nil }
        let shares = amount / price
        guard shares > 0 else { return nil }
        return (shares, principal / shares, price)
    }

    private var isValidFundCode: Bool {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCode.count == 6 && trimmedCode.allSatisfy(\.isNumber)
    }

    private var hasInvalidFundCode: Bool {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedCode.isEmpty && !isValidFundCode
    }

    private var isOnExchange: Bool {
        store.accountKind == .onExchange
    }

    private var exchangePositionModeSummary: String {
        switch positionMode {
        case .amount:
            "兼容旧数据的金额录入"
        case .share:
            "按持仓份额、可卖份额与平均成本价记录"
        }
    }

    private var exchangePositionHelp: String {
        switch positionMode {
        case .amount:
            "旧数据仍可读取，但新建场内基金请按份额录入。"
        case .share:
            "首次录入直接建立券商持仓基线；锁定份额按 T+1 默认于下一交易日解锁，之后的买卖按成交价和手续费即时更新。"
        }
    }

    private var exchangeTurnaroundHelp: String {
        switch exchangeTurnaroundRule {
        case .nextTradingDay:
            "境内股票 ETF 通常选择 T+1：买入即时计入持有，但要到下一交易日才转为可卖份额。"
        case .sameDay:
            "仅当该基金支持当日回转交易时选择 T+0，例如符合规则的债券、货币、黄金、跨境或商品期货 ETF。"
        }
    }

    private var headerTitle: String {
        if isOnExchange {
            return fund == nil ? "添加场内基金" : "修改场内基金"
        }
        return fund == nil ? "添加基金" : "修改基金"
    }

    private var headerSubtitle: String {
        if isOnExchange {
            return fund == nil ? "建立独立的交易所基金持仓" : "调整场内基金持仓基线"
        }
        return fund == nil ? "记录一只新的基金持仓" : "调整基金持仓与提醒"
    }

    private var latestQuoteSubtitle: String {
        switch metadataLookupState {
        case .idle:
            return "输入基金代码后自动读取"
        case .loading:
            return "正在读取基金行情"
        case .failed:
            return "行情读取失败，请重试"
        case .loaded(let latestQuote):
            if isOnExchange, let marketPriceTime = latestQuote.marketPriceTime, !marketPriceTime.isEmpty {
                return "行情时间 \(marketPriceTime)"
            }
            if !latestQuote.netValueDate.isEmpty {
                return "净值日期 \(latestQuote.netValueDate)"
            }
            return "已读取行情"
        }
    }

    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    private static func text(_ value: Double, places: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }

    private static func fixedText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }
}
