import SwiftUI

struct ExchangeFundTradeEditorView: View {
    let store: PortfolioStore
    let fund: FundPosition
    let action: FundTradeAction
    let editingRecord: FundTradeRecord?
    let onSaved: (() async -> Void)?
    let onClose: (() -> Void)?

    @State private var shares: String
    @State private var price: String
    @State private var feeAmount: String
    @State private var tradeDate: Date
    @State private var referenceQuote: FundQuote?
    @State private var quoteTask: Task<Void, Never>?
    @State private var isLoadingQuote = false
    @State private var isConfirming = false
    @State private var isSaving = false
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
        self.action = editingRecord?.kind == .sell ? .sell : action
        self.editingRecord = editingRecord
        self.onSaved = onSaved
        self.onClose = onClose

        let initialShares = editingRecord?.confirmedShares ?? editingRecord?.shares
        let initialPrice = editingRecord?.price
        let initialDate = editingRecord.flatMap { DateOnlyFormatter.parse($0.tradeDate) } ?? Date.now
        _shares = State(initialValue: initialShares.map { Self.numberText($0, places: 2) } ?? "")
        _price = State(initialValue: initialPrice.map { Self.numberText($0, places: 4) } ?? "")
        _feeAmount = State(initialValue: editingRecord?.feeAmount.map { Self.numberText($0, places: 2) } ?? "0")
        _tradeDate = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: headerSystemImage,
                title: headerTitle,
                subtitle: headerSubtitle,
                onClose: close
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    securitySummary

                    if isConfirming {
                        confirmationSection
                    } else {
                        transactionEntrySection
                        transactionPreviewSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: PopoverLayout.editorWidth, height: PopoverLayout.standardChildPanelHeight)
        .background(PanelDesign.panelBackground)
        .onAppear(perform: loadReferenceQuote)
        .onDisappear {
            quoteTask?.cancel()
        }
    }

    private var securitySummary: some View {
        PanelSection(title: "场内基金") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fund.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(fund.code)
                        Text("场内")
                            .foregroundStyle(PanelDesign.accent)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(fund.resolvedExchangeTurnaroundRule.shortTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelDesign.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(PanelDesign.accent.opacity(0.10), in: Capsule())
                    Text(fund.resolvedExchangeTurnaroundRule == .sameDay ? "当日可卖" : "下一交易日可卖")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                shareMetric("持有份额", value: currentAvailability.heldShares)
                Divider().frame(height: 27)
                shareMetric("可卖份额", value: currentAvailability.sellableShares, emphasized: true)
                if fund.resolvedExchangeTurnaroundRule == .nextTradingDay
                    || currentAvailability.lockedShares > PortfolioPrecision.shareAvailabilityTolerance {
                    Divider().frame(height: 27)
                    shareMetric("T+1 锁定", value: currentAvailability.lockedShares)
                }
            }
            .padding(.vertical, 8)
            .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))

            if currentAvailability.lockedShares > PortfolioPrecision.shareAvailabilityTolerance,
               let nextUnlockDate = currentAvailability.nextUnlockDate {
                Label("锁定份额将在 \(nextUnlockDate) 转为可卖", systemImage: "clock")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最新成交价")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(referenceTimeText)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                if isLoadingQuote {
                    ProgressView()
                        .controlSize(.small)
                } else if let referenceQuote {
                    Text(Self.numberText(referenceQuote.netValue, places: 4))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Button("使用") {
                        price = Self.numberText(referenceQuote.netValue, places: 4)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    .focusable(false)
                } else {
                    Text("暂无")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(9)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        }
    }

    private var transactionEntrySection: some View {
        PanelSection(title: editingRecord?.kind == .newFund ? "持仓基线" : "成交信息") {
            field(action == .buy ? "买入份额" : "卖出份额") {
                PanelTextInput(
                    action == .sell ? "最多 \(Self.numberText(sellableSharesForTrade, places: 2))" : "请输入实际成交份额",
                    text: $shares,
                    suffix: "份"
                )
            }

            field(editingRecord?.kind == .newFund ? "平均成本价" : "实际成交价") {
                PanelTextInput("请输入券商成交价", text: $price, suffix: "元")
            }

            field("交易手续费") {
                PanelTextInput("没有则填 0", text: $feeAmount, suffix: "元")
            }

            field(editingRecord?.kind == .newFund ? "持仓日期" : "成交日期") {
                PanelNativeDatePicker(selection: $tradeDate, elements: [.yearMonthDay])
            }

            Text(transactionHelp)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var transactionPreviewSection: some View {
        PanelSection(title: "交易预览") {
            metricRow("成交金额", grossAmount.map(MoneyFormatter.plainMoney) ?? "--")
            metricRow(action == .buy ? "预计支出" : "预计到账", cashAmount.map(MoneyFormatter.plainMoney) ?? "--")
            metricRow("交易后份额", sharesAfter.map { "\(Self.numberText($0, places: 2)) 份" } ?? "--")

            if action == .sell, let inputShares, inputShares > sellableSharesForTrade {
                Label("卖出份额超过该交易日的可卖份额", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
    }

    private var confirmationSection: some View {
        PanelSection(title: "确认交易") {
            metricRow("基金", "\(fund.name)（\(fund.code)）")
            metricRow("操作", editingRecord?.kind == .newFund ? "修改持仓基线" : (action == .buy ? "场内买入" : "场内卖出"))
            metricRow("成交份额", inputShares.map { "\(Self.numberText($0, places: 2)) 份" } ?? "--")
            metricRow(editingRecord?.kind == .newFund ? "平均成本价" : "实际成交价", inputPrice.map { "\(Self.numberText($0, places: 4)) 元" } ?? "--")
            metricRow("手续费", inputFeeAmount.map(MoneyFormatter.plainMoney) ?? "--")
            metricRow("成交日期", DateOnlyFormatter.string(from: tradeDate))
            metricRow("可卖规则", fund.resolvedExchangeTurnaroundRule.title)
            Divider().opacity(0.45)
            metricRow(action == .buy ? "总支出" : "净到账", cashAmount.map(MoneyFormatter.plainMoney) ?? "--", emphasized: true)

            Text(confirmationHelp)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                if isConfirming {
                    errorMessage = nil
                    isConfirming = false
                } else {
                    close()
                }
            } label: {
                PanelButtonLabel(title: isConfirming ? "返回修改" : "取消")
                    .frame(width: 82)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(isSaving)

            Button {
                if isConfirming {
                    save()
                } else {
                    errorMessage = nil
                    isConfirming = true
                }
            } label: {
                PanelButtonLabel(
                    title: submitTitle,
                    style: .primary,
                    isEnabled: canSubmit && !isSaving
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit || isSaving)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .overlay(alignment: .top) {
            Divider().opacity(0.55)
        }
    }

    private var headerTitle: String {
        if editingRecord?.kind == .newFund { return "编辑持仓基线" }
        if editingRecord != nil { return action == .buy ? "编辑场内买入" : "编辑场内卖出" }
        return action == .buy ? "场内买入" : "场内卖出"
    }

    private var headerSubtitle: String {
        editingRecord == nil ? "按券商实际成交数据记录" : "修改后会重新计算持仓"
    }

    private var headerSystemImage: String {
        if editingRecord != nil { return "pencil" }
        return action == .buy ? "plus" : "minus"
    }

    private var submitTitle: String {
        if isSaving { return "保存中" }
        if !isConfirming { return "核对交易" }
        return editingRecord == nil ? "确认记账" : "保存修改"
    }

    private var currentAvailability: ExchangeShareAvailability {
        store.exchangeShareAvailability(for: fund.code)
    }

    private var tradeDateAvailability: ExchangeShareAvailability {
        store.exchangeShareAvailability(for: fund.code, on: tradeDate)
    }

    private var sellableSharesForTrade: Double {
        let restoredShares: Double
        if editingRecord?.kind == .sell {
            restoredShares = editingRecord?.confirmedShares ?? editingRecord?.shares ?? 0
        } else {
            restoredShares = 0
        }
        return tradeDateAvailability.sellableShares + restoredShares
    }

    private var sharesBeforeEditedRecord: Double {
        let current = currentAvailability.heldShares
        guard let editingRecord else { return current }
        let editedShares = editingRecord.confirmedShares ?? editingRecord.shares ?? 0
        switch editingRecord.kind {
        case .newFund, .buy, .conversionIn:
            return max(current - editedShares, 0)
        case .sell, .conversionOut:
            return current + editedShares
        }
    }

    private var inputShares: Double? {
        Self.number(shares)
    }

    private var inputPrice: Double? {
        Self.number(price)
    }

    private var inputFeeAmount: Double? {
        Self.number(feeAmount)
    }

    private var grossAmount: Double? {
        guard let inputShares, inputShares > 0,
              let inputPrice, inputPrice > 0
        else { return nil }
        return inputShares * inputPrice
    }

    private var cashAmount: Double? {
        guard let grossAmount,
              let inputFeeAmount,
              inputFeeAmount >= 0
        else { return nil }
        return action == .buy ? grossAmount + inputFeeAmount : grossAmount - inputFeeAmount
    }

    private var sharesAfter: Double? {
        guard let inputShares, inputShares > 0 else { return nil }
        return action == .buy ? sharesBeforeEditedRecord + inputShares : sharesBeforeEditedRecord - inputShares
    }

    private var canSubmit: Bool {
        guard let inputShares, inputShares > 0,
              let inputPrice, inputPrice > 0,
              let inputFeeAmount, inputFeeAmount >= 0,
              let cashAmount, cashAmount >= 0
        else {
            return false
        }
        return action == .buy || inputShares <= sellableSharesForTrade + PortfolioPrecision.shareAvailabilityTolerance
    }

    private var transactionHelp: String {
        if action == .buy, fund.resolvedExchangeTurnaroundRule == .nextTradingDay {
            return "买入按实际成交价即时确认并计入持有；新买份额将在下一交易日转为可卖，不进入待确认。"
        }
        return "按实际成交价即时记账，不使用场外基金净值，也没有 15:00 前后或待确认状态。"
    }

    private var confirmationHelp: String {
        if action == .buy, fund.resolvedExchangeTurnaroundRule == .nextTradingDay {
            return "保存后立即写入已确认交易记录并重算成本；该笔买入份额下一交易日才可卖。"
        }
        return "保存后立即写入已确认交易记录，并按成交价与手续费重算持仓成本。"
    }

    private var referenceTimeText: String {
        referenceQuote?.marketPriceTime.map { "行情时间 \($0)" } ?? "仅作填写参考，请以券商成交回报为准"
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func shareMetric(_ title: String, value: Double, emphasized: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(Self.numberText(value, places: 2))
                .font(.system(size: 11, weight: emphasized ? .bold : .semibold))
                .foregroundStyle(emphasized ? PanelDesign.accent : Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: emphasized ? 13 : 12, weight: emphasized ? .bold : .semibold))
                .foregroundStyle(emphasized ? actionColor : Color.primary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .lineLimit(2)
        }
    }

    private var actionColor: Color {
        action == .buy ? Color(nsColor: .systemRed) : .fundPulseGreen
    }

    private func loadReferenceQuote() {
        quoteTask?.cancel()
        isLoadingQuote = true
        quoteTask = Task {
            let quote = await store.fetchLatestQuote(code: fund.code)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                referenceQuote = quote
                isLoadingQuote = false
            }
        }
    }

    private func save() {
        guard canSubmit, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let draft = FundTradeDraft(
            action: action,
            code: fund.code,
            mode: .share,
            amount: nil,
            shares: inputShares,
            tradeDate: DateOnlyFormatter.string(from: tradeDate),
            tradeTimeType: .before15,
            price: inputPrice,
            feeAmount: inputFeeAmount
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
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func close() {
        quoteTask?.cancel()
        onClose?()
    }

    private static func number(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private static func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }
}
