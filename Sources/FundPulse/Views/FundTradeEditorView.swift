import SwiftUI

struct FundTradeEditorView: View {
    let store: PortfolioStore
    let fund: FundPosition
    let action: FundTradeAction
    let editingRecord: FundTradeRecord?
    let onSaved: (() async -> Void)?
    let onClose: (() -> Void)?

    @State private var mode: PositionMode
    @State private var amount: String = ""
    @State private var shares: String = ""
    @State private var buyFeeRate: String = "0"
    @State private var sellFeeMode: TradeFeeMode = .rate
    @State private var sellFeeValue: String = "0"
    @State private var tradeDate: Date = .now
    @State private var tradeTimeType: PositionTimeType = TradingCalendar.defaultPositionTimeType()
    @State private var isSaving = false
    @State private var isConfirming = false
    @State private var referenceNetValue: Double?
    @State private var referenceNetValueDate: String?
    @State private var isLoadingReferenceNetValue = false
    @State private var referenceTask: Task<Void, Never>?
    @State private var errorMessage: String?

    init(
        store: PortfolioStore,
        fund: FundPosition,
        action: FundTradeAction,
        editingRecord: FundTradeRecord? = nil,
        onSaved: (() async -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.fund = fund
        self.action = action
        self.editingRecord = editingRecord
        self.onSaved = onSaved
        self.onClose = onClose
        let isEditingInitialFund = editingRecord?.kind == .newFund
        let initialMode: PositionMode = action == .buy && !isEditingInitialFund
            ? .amount
            : (editingRecord?.mode ?? (action == .buy ? .amount : .share))
        _mode = State(initialValue: initialMode)
        _amount = State(initialValue: editingRecord?.amount.map { Self.initialNumberText($0, places: 2) } ?? "")
        _shares = State(initialValue: (editingRecord?.shares ?? editingRecord?.confirmedShares).map { Self.initialNumberText($0, places: 2) } ?? "")
        _buyFeeRate = State(initialValue: editingRecord?.buyFeeRate.map { Self.initialNumberText($0, places: 2) } ?? "0")
        _sellFeeMode = State(initialValue: editingRecord?.sellFeeMode ?? .rate)
        _sellFeeValue = State(initialValue: editingRecord?.sellFeeValue.map { Self.initialNumberText($0, places: 2) } ?? "0")
        _tradeDate = State(initialValue: editingRecord.flatMap { DateOnlyFormatter.parse($0.tradeDate) } ?? .now)
        _tradeTimeType = State(initialValue: editingRecord?.tradeTimeType ?? TradingCalendar.defaultPositionTimeType())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .layoutPriority(1)
            content
            Spacer(minLength: 0)
            footer
                .layoutPriority(1)
        }
        .frame(width: PopoverLayout.editorWidth, height: PopoverLayout.tradeEditorHeight)
        .background(PanelDesign.panelBackground)
        .onAppear {
            scheduleReferenceNetValueLookup()
        }
        .onChange(of: tradeDate) { _, _ in
            isConfirming = false
            scheduleReferenceNetValueLookup()
        }
        .onChange(of: tradeTimeType) { _, _ in
            isConfirming = false
            scheduleReferenceNetValueLookup()
        }
        .onDisappear {
            referenceTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerSystemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(actionColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("取消")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private var content: some View {
        ScrollView {
            Group {
                if isConfirming {
                    confirmationContent
                } else {
                    formContent
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            fundSummary
            tradeInputSection
            tradeConfirmSection

            if let errorMessage {
                errorText(errorMessage)
            }
        }
    }

    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            confirmationSummary
            positionPreview

            if let errorMessage {
                errorText(errorMessage)
            }
        }
    }

    private var fundSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fund.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(FundCodeFormatter.display(fund.code))
                        .fontWeight(.semibold)
                    Text("当前份额 \(numberText(fund.migratedShares ?? 0, places: 2))")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("成本价")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(fund.migratedCost.map { numberText($0, places: 4) } ?? "暂无")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(cardBorder(cornerRadius: 10))
    }

    private var tradeInputSection: some View {
        section("交易录入") {
            if canChooseTradeMode {
                modeSelector
            }
            if effectiveMode == .amount {
                field(action == .buy ? "加仓金额" : "卖出金额") {
                    plainTextField(
                        action == .buy ? "请输入加仓金额" : "请输入卖出金额",
                        text: $amount,
                        suffix: "元"
                    )
                }
                if action == .buy {
                    field("买入费率") {
                        plainTextField("例如 0.12", text: $buyFeeRate, suffix: "%")
                    }
                }
            } else {
                field(action == .buy ? "加仓份额" : "卖出份额") {
                    plainTextField(
                        action == .buy ? "请输入加仓份额" : availableSharePlaceholder,
                        text: $shares,
                        suffix: "份"
                    )
                }
                if action == .sell {
                    sellShareQuickControls
                    sellFeeInput
                }
            }
        }
    }

    private var tradeConfirmSection: some View {
        section("交易确认") {
            HStack(spacing: 10) {
                Text("交易日期")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                PanelNativeDatePicker(selection: $tradeDate, elements: [.yearMonthDay])
                    .frame(width: 122, height: 24)
            }
            timeSelector
            referenceNetValueRow
            tradeDateTip
        }
    }

    private var referenceNetValueRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(action == .buy ? "参考净值" : "预估卖出单价")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(referenceFootnote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingReferenceNetValue {
                ProgressView()
                    .controlSize(.small)
            } else if let referenceNetValue {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(numberText(referenceNetValue, places: 4))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PanelDesign.accent)
                        .monospacedDigit()
                    if let referenceNetValueDate {
                        Text(referenceNetValueDate)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("待确认")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(availableModes) { value in
                selectorButton(title: value.title, isSelected: mode == value) {
                    mode = value
                }
            }
        }
        .padding(2)
        .background(selectorBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.36), lineWidth: 0.6)
        )
    }

    private var timeSelector: some View {
        HStack(spacing: 4) {
            ForEach(PositionTimeType.allCases) { value in
                selectorButton(title: value.title, isSelected: tradeTimeType == value) {
                    tradeTimeType = value
                }
            }
        }
        .padding(2)
        .background(selectorBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.36), lineWidth: 0.6)
        )
    }

    private var sellShareQuickControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                quickSellShareButton("1/4", fraction: 0.25)
                quickSellShareButton("1/3", fraction: 1.0 / 3.0)
                quickSellShareButton("1/2", fraction: 0.5)
                quickSellShareButton("全部", fraction: 1)
            }

            Text("当前持仓：\(numberText(fund.migratedShares ?? 0, places: 2)) 份")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var sellFeeInput: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(sellFeeMode == .rate ? "卖出费率" : "卖出费用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    sellFeeMode = sellFeeMode == .rate ? .amount : .rate
                    sellFeeValue = "0"
                } label: {
                    Text("切换为\(sellFeeMode == .rate ? "金额" : "费率")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(actionColor)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            plainTextField(
                sellFeeMode == .rate ? "例如 0.50" : "请输入卖出费用",
                text: $sellFeeValue,
                suffix: sellFeeMode == .rate ? "%" : "元"
            )
        }
    }

    private func quickSellShareButton(_ title: String, fraction: Double) -> some View {
        Button {
            let currentShares = fund.migratedShares ?? 0
            shares = numberText(currentShares * fraction, places: 2)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(PanelDesign.border(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var tradeDateTip: some View {
        let dateText = DateOnlyFormatter.string(from: tradeDate)
        let acceptedDate = TradingCalendar.acceptedTradeDate(positionDate: dateText, timeType: tradeTimeType)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("确认净值日")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(action == .buy ? "按该日净值确认加仓份额" : "按该日净值确认卖出")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(acceptedDate)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .padding(9)
        .background(actionColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(actionColor.opacity(0.13), lineWidth: 0.6)
        )
    }

    private var confirmationSummary: some View {
        section(action == .buy ? "买入确认" : "卖出确认") {
            VStack(spacing: 9) {
                confirmationRow("基金名称", fund.name)
                if action == .buy {
                    confirmationRow("买入金额", inputAmount.map { MoneyFormatter.plainMoney($0) } ?? "--")
                    confirmationRow("买入费率", "\(numberText(inputBuyFeeRate ?? 0, places: 2))%")
                    confirmationRow("预估手续费", estimatedBuyFee.map { MoneyFormatter.plainMoney($0) } ?? "0.00")
                    confirmationRow("参考净值", referencePriceText)
                    confirmationRow("预估份额", estimatedBuyShares.map { "\(numberText($0, places: 2)) 份" } ?? "待确认")
                    confirmationRow("买入日期", tradeDateText)
                } else {
                    confirmationRow("卖出份额", "\(numberText(inputShares ?? 0, places: 2)) 份")
                    confirmationRow("预估卖出单价") {
                        sellPriceDisplayValue
                    }
                    confirmationRow("卖出费率/费用", sellFeeValueText)
                    confirmationRow("预估手续费") {
                        sellFeeDisplayValue
                    }
                    confirmationRow("预计回款") {
                        sellReturnDisplayValue
                    }
                    confirmationRow("卖出日期", tradeDateText)
                }
                Divider().opacity(0.55)
                confirmationRow("交易时段", tradeTimeType.title)
                Text(referenceBasisText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var positionPreview: some View {
        section("持仓变化预览") {
            VStack(spacing: 8) {
                previewTile(
                    title: "持有份额",
                    before: numberText(fund.migratedShares ?? 0, places: 2),
                    after: previewShares.map { numberText($0, places: 2) } ?? "待确认"
                )
                previewTile(
                    title: "持有市值（估）",
                    before: {
                        previewCurrentValueBeforeDisplayValue
                    },
                    after: {
                        previewCurrentValueAfterDisplayValue
                    }
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                if isConfirming {
                    isConfirming = false
                    errorMessage = nil
                } else {
                    close()
                }
            } label: {
                Text(isConfirming ? "返回修改" : "取消")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 78, height: 30)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(cardBorder(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button {
                submit()
            } label: {
                Text(submitTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSubmit ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(canSubmit ? actionColor : Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || !canSubmit || (isConfirming && isLoadingReferenceNetValue))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .overlay(alignment: .top) {
            Divider().opacity(0.55)
        }
    }

    private var canSubmit: Bool {
        switch effectiveMode {
        case .amount:
            let hasAmount = (Self.number(amount) ?? 0) > 0
            if action == .buy {
                return hasAmount && inputBuyFeeRate != nil
            }
            return hasAmount
        case .share:
            let hasShares = (Self.number(shares) ?? 0) > 0
            if action == .sell {
                return hasShares && inputSellFeeValue != nil
            }
            return hasShares
        }
    }

    private var headerSubtitle: String {
        if isConfirming {
            return "确认后写入交易记录并更新持仓"
        }
        if editingRecord != nil {
            return "修改后会重新计算持仓"
        }
        return action == .buy ? "记录一笔追加买入" : "记录一笔卖出赎回"
    }

    private var headerTitle: String {
        if isEditingInitialFund {
            return isConfirming ? "新增基金确认" : "新增基金"
        }
        if isConfirming {
            return action == .buy ? "买入确认" : "卖出确认"
        }
        return action.title
    }

    private var headerSystemImage: String {
        if isConfirming {
            return action == .buy ? "tray.and.arrow.down.fill" : "tray.and.arrow.up.fill"
        }
        return action == .buy ? "plus" : "minus"
    }

    private var submitTitle: String {
        if editingRecord != nil {
            return isSaving ? "保存中" : (isConfirming ? "确认保存" : "保存确认")
        }
        if isConfirming {
            if isLoadingReferenceNetValue {
                return "请稍候"
            }
            return isSaving ? "处理中" : "确认\(action == .buy ? "买入" : "卖出")"
        }
        return action == .buy ? "买入确认" : "卖出确认"
    }

    private var actionColor: Color {
        action == .buy ? Color(nsColor: .systemRed) : .fundPulseGreen
    }

    private var cardBackground: Color {
        PanelDesign.cardBackground
    }

    private var selectorBackground: Color {
        PanelDesign.selectorBackground
    }

    private var canChooseTradeMode: Bool {
        isEditingInitialFund
    }

    private var isEditingInitialFund: Bool {
        editingRecord?.kind == .newFund
    }

    private var availableModes: [PositionMode] {
        canChooseTradeMode ? Array(PositionMode.allCases) : [.amount]
    }

    private var effectiveMode: PositionMode {
        if canChooseTradeMode {
            return mode
        }
        return action == .buy ? .amount : .share
    }

    private var tradeDateText: String {
        DateOnlyFormatter.string(from: tradeDate)
    }

    private var acceptedDateText: String {
        TradingCalendar.acceptedTradeDate(positionDate: tradeDateText, timeType: tradeTimeType)
    }

    private var inputAmount: Double? {
        Self.number(amount)
    }

    private var inputShares: Double? {
        Self.number(shares)
    }

    private var inputBuyFeeRate: Double? {
        guard action == .buy, effectiveMode == .amount else { return nil }
        guard let value = Self.number(buyFeeRate), value >= 0 else { return nil }
        return value
    }

    private var inputSellFeeValue: Double? {
        guard action == .sell else { return nil }
        guard let value = Self.number(sellFeeValue), value >= 0 else { return nil }
        return value
    }

    private var estimatedBuyNetAmount: Double? {
        guard let amount = inputAmount else { return nil }
        let feeRate = inputBuyFeeRate ?? 0
        return amount / (1 + feeRate / 100)
    }

    private var estimatedBuyFee: Double? {
        guard let amount = inputAmount,
              let netAmount = estimatedBuyNetAmount
        else { return nil }
        return max(0, amount - netAmount)
    }

    private var estimatedBuyShares: Double? {
        guard action == .buy,
              let netAmount = estimatedBuyNetAmount,
              let referenceNetValue,
              referenceNetValue > 0
        else { return nil }
        return rounded(netAmount / referenceNetValue, places: 2)
    }

    private var estimatedSellReturn: Double? {
        guard let grossAmount = estimatedSellGrossAmount,
              let fee = estimatedSellFee
        else { return nil }
        return grossAmount - fee
    }

    private var estimatedSellGrossAmount: Double? {
        guard action == .sell,
              let shares = inputShares,
              let referenceNetValue,
              referenceNetValue > 0
        else { return nil }
        return shares * referenceNetValue
    }

    private var estimatedSellFee: Double? {
        guard let grossAmount = estimatedSellGrossAmount,
              let feeValue = inputSellFeeValue
        else { return nil }
        switch sellFeeMode {
        case .rate:
            return grossAmount * feeValue / 100
        case .amount:
            return feeValue
        }
    }

    // Display-only approximation; keep it out of persisted trades and position math.
    private var displayOnlyApproximateSellReturn: Double? {
        guard referenceNetValue == nil,
              let grossAmount = displayOnlyApproximateSellGrossAmount,
              let fee = displayOnlyApproximateSellFee
        else { return nil }
        return max(0, grossAmount - fee)
    }

    private var displayOnlyApproximateSellGrossAmount: Double? {
        guard action == .sell,
              let shares = inputShares,
              let price = displayOnlyApproximateSellPrice,
              price > 0
        else { return nil }
        return shares * price
    }

    private var displayOnlyApproximateSellPrice: Double? {
        guard action == .sell,
              fund.todayRate.isFinite
        else { return nil }
        let basePrice: Double?
        if let currentAmount = fund.currentAmount,
           let totalShares = fund.migratedShares,
           currentAmount > 0,
           totalShares > 0 {
            basePrice = currentAmount / totalShares
        } else if let cost = fund.migratedCost,
                  cost > 0 {
            basePrice = cost
        } else {
            basePrice = nil
        }
        guard let basePrice, basePrice > 0 else { return nil }
        if fund.isUpdated {
            return basePrice
        }
        guard fund.todayRate != 0 else { return nil }
        return basePrice * (1 + fund.todayRate / 100)
    }

    private var displayOnlyApproximateSellFee: Double? {
        guard let grossAmount = displayOnlyApproximateSellGrossAmount,
              let feeValue = inputSellFeeValue
        else { return nil }
        switch sellFeeMode {
        case .rate:
            return grossAmount * feeValue / 100
        case .amount:
            return feeValue
        }
    }

    private var sellFeeValueText: String {
        let value = inputSellFeeValue ?? 0
        switch sellFeeMode {
        case .rate:
            return "\(numberText(value, places: 2))%"
        case .amount:
            return MoneyFormatter.plainMoney(value)
        }
    }

    @ViewBuilder
    private var sellPriceDisplayValue: some View {
        if let referenceNetValue {
            Text(MoneyFormatter.plainMoney(referenceNetValue))
        } else if let displayOnlyApproximateSellPrice {
            Text("≈ \(MoneyFormatter.plainMoney(displayOnlyApproximateSellPrice))")
                .foregroundStyle(Color(nsColor: .systemOrange))
        } else {
            Text("待确认")
        }
    }

    @ViewBuilder
    private var sellFeeDisplayValue: some View {
        if let estimatedSellFee {
            Text(MoneyFormatter.plainMoney(estimatedSellFee))
        } else if let displayOnlyApproximateSellFee {
            Text("≈ \(MoneyFormatter.plainMoney(displayOnlyApproximateSellFee))")
                .foregroundStyle(Color(nsColor: .systemOrange))
        } else {
            Text("待计算")
        }
    }

    @ViewBuilder
    private var sellReturnDisplayValue: some View {
        if let estimatedSellReturn {
            Text(MoneyFormatter.plainMoney(estimatedSellReturn))
        } else if let displayOnlyApproximateSellReturn {
            Text("≈ \(MoneyFormatter.plainMoney(displayOnlyApproximateSellReturn))")
                .foregroundStyle(Color(nsColor: .systemOrange))
        } else {
            Text("待计算")
        }
    }

    private var previewShares: Double? {
        let currentShares = fund.migratedShares ?? 0
        switch action {
        case .buy:
            guard let estimatedBuyShares else { return nil }
            return currentShares + estimatedBuyShares
        case .sell:
            guard let inputShares else { return nil }
            return max(0, currentShares - inputShares)
        }
    }

    private var previewCurrentValueBefore: Double? {
        guard let referenceNetValue else { return nil }
        return (fund.migratedShares ?? 0) * referenceNetValue
    }

    private var previewCurrentValueAfter: Double? {
        guard let previewShares, let referenceNetValue else { return nil }
        return previewShares * referenceNetValue
    }

    private var displayOnlyApproximateCurrentValueBefore: Double? {
        guard referenceNetValue == nil,
              let price = displayOnlyApproximateSellPrice
        else { return nil }
        return (fund.migratedShares ?? 0) * price
    }

    private var displayOnlyApproximateCurrentValueAfter: Double? {
        guard referenceNetValue == nil,
              let previewShares,
              let price = displayOnlyApproximateSellPrice
        else { return nil }
        return previewShares * price
    }

    @ViewBuilder
    private var previewCurrentValueBeforeDisplayValue: some View {
        if let previewCurrentValueBefore {
            Text(MoneyFormatter.plainMoney(previewCurrentValueBefore))
                .foregroundStyle(.secondary)
        } else if let displayOnlyApproximateCurrentValueBefore {
            Text("≈ \(MoneyFormatter.plainMoney(displayOnlyApproximateCurrentValueBefore))")
                .foregroundStyle(Color(nsColor: .systemOrange))
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewCurrentValueAfterDisplayValue: some View {
        if let previewCurrentValueAfter {
            Text(MoneyFormatter.plainMoney(previewCurrentValueAfter))
        } else if let displayOnlyApproximateCurrentValueAfter {
            Text("≈ \(MoneyFormatter.plainMoney(displayOnlyApproximateCurrentValueAfter))")
                .foregroundStyle(Color(nsColor: .systemOrange))
        } else {
            Text("待计算")
        }
    }

    private var referencePriceText: String {
        referenceNetValue.map { MoneyFormatter.plainMoney($0) } ?? "待确认"
    }

    private var referenceFootnote: String {
        if let referenceNetValueDate {
            return "使用 \(referenceNetValueDate) 净值测算"
        }
        return "该日净值未取到时会加入待确认"
    }

    private var referenceBasisText: String {
        if referenceNetValue == nil {
            return "*净值未取到，确认后将保持待确认"
        }
        return "*基于当前参考净值测算"
    }

    private var availableSharePlaceholder: String {
        if action == .sell {
            return "最多 \(numberText(fund.migratedShares ?? 0, places: 2)) 份"
        }
        return "请输入加仓份额"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(cardBorder(cornerRadius: 10))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func confirmationRow(_ title: String, _ value: String) -> some View {
        confirmationRow(title) {
            Text(value)
        }
    }

    private func confirmationRow<Value: View>(
        _ title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            value()
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .lineLimit(2)
        }
    }

    private func previewTile(title: String, before: String, after: String) -> some View {
        previewTile(title: title) {
            Text(before)
                .foregroundStyle(.secondary)
        } after: {
            Text(after)
        }
    }

    private func previewTile<Before: View, After: View>(
        title: String,
        @ViewBuilder before: () -> Before,
        @ViewBuilder after: () -> After
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                before()
                Text("→")
                    .foregroundStyle(.tertiary)
                after()
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 8))
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.red)
            .lineLimit(2)
    }

    private func selectorButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? actionColor : Color.primary.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    isSelected ? Color(nsColor: .textBackgroundColor).opacity(0.94) : PanelDesign.inputBackground.opacity(0.88),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected ? actionColor.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.42),
                            lineWidth: 0.6
                        )
                }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func plainTextField(_ placeholder: String, text: Binding<String>, suffix: String) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .monospacedDigit()
            Text(suffix)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.6)
        )
    }

    private func cardBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.6)
    }

    private func submit() {
        guard canSubmit else { return }
        if isConfirming {
            save()
        } else {
            errorMessage = nil
            isConfirming = true
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let draftMode = effectiveMode
        let draft = FundTradeDraft(
            action: action,
            code: fund.code,
            mode: draftMode,
            amount: draftMode == .amount ? Self.number(amount) : nil,
            shares: draftMode == .share ? Self.number(shares) : nil,
            tradeDate: DateOnlyFormatter.string(from: tradeDate),
            tradeTimeType: tradeTimeType,
            buyFeeRate: action == .buy && draftMode == .amount ? inputBuyFeeRate : nil,
            sellFeeMode: action == .sell ? sellFeeMode : nil,
            sellFeeValue: action == .sell ? inputSellFeeValue : nil
        )

        Task {
            do {
                if let editingRecord {
                    try await store.editTradeRecord(id: editingRecord.id, with: draft)
                } else {
                    try await store.adjustFundPosition(draft)
                }
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
        referenceTask?.cancel()
        onClose?()
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }

    private static func initialNumberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }

    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: ""))
    }

    private func scheduleReferenceNetValueLookup() {
        referenceTask?.cancel()
        let code = fund.code
        let tradeDate = tradeDateText
        let timeType = tradeTimeType
        isLoadingReferenceNetValue = true
        referenceNetValue = nil
        referenceNetValueDate = nil
        referenceTask = Task {
            let result = await store.fetchTradeReferenceNetValue(
                code: code,
                tradeDate: tradeDate,
                timeType: timeType
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                referenceNetValue = result?.value
                referenceNetValueDate = result?.date
                isLoadingReferenceNetValue = false
            }
        }
    }

    private func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}
