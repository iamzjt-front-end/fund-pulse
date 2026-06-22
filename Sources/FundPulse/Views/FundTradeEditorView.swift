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
    @State private var tradeDate: Date = .now
    @State private var tradeTimeType: PositionTimeType = TradingCalendar.defaultPositionTimeType()
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
        self.action = action
        self.editingRecord = editingRecord
        self.onSaved = onSaved
        self.onClose = onClose
        _mode = State(initialValue: editingRecord?.mode ?? (action == .buy ? .amount : .share))
        _amount = State(initialValue: editingRecord?.amount.map { Self.initialNumberText($0, places: 2) } ?? "")
        _shares = State(initialValue: (editingRecord?.shares ?? editingRecord?.confirmedShares).map { Self.initialNumberText($0, places: 2) } ?? "")
        _tradeDate = State(initialValue: editingRecord.flatMap { DateOnlyFormatter.parse($0.tradeDate) } ?? .now)
        _tradeTimeType = State(initialValue: editingRecord?.tradeTimeType ?? TradingCalendar.defaultPositionTimeType())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 12) {
                fundSummary
                tradeInputSection
                tradeConfirmSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
            Spacer(minLength: 0)
            footer
                .layoutPriority(1)
        }
        .frame(width: PopoverLayout.editorWidth, height: PopoverLayout.tradeEditorHeight)
        .background(PanelDesign.panelBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: action == .buy ? "plus" : "minus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(actionColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
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

    private var fundSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fund.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(FundCodeFormatter.display(fund.code))
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
            modeSelector
            if mode == .amount {
                field(action == .buy ? "加仓金额" : "卖出金额") {
                    plainTextField(
                        action == .buy ? "请输入加仓金额" : "请输入卖出金额",
                        text: $amount,
                        suffix: "元"
                    )
                }
            } else {
                field(action == .buy ? "加仓份额" : "卖出份额") {
                    plainTextField(
                        action == .buy ? "请输入加仓份额" : availableSharePlaceholder,
                        text: $shares,
                        suffix: "份"
                    )
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
            tradeDateTip
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(PositionMode.allCases) { value in
                selectorButton(title: value.title, isSelected: mode == value) {
                    mode = value
                }
            }
        }
        .padding(2)
        .background(selectorBackground, in: Capsule())
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

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                close()
            } label: {
                Text("取消")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 78, height: 30)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(cardBorder(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button {
                save()
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
            .disabled(isSaving || !canSubmit)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .overlay(alignment: .top) {
            Divider().opacity(0.55)
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .amount:
            return (Self.number(amount) ?? 0) > 0
        case .share:
            return (Self.number(shares) ?? 0) > 0
        }
    }

    private var headerSubtitle: String {
        if editingRecord != nil {
            return "修改后会重新计算持仓"
        }
        return action == .buy ? "记录一笔追加买入" : "记录一笔卖出赎回"
    }

    private var submitTitle: String {
        if editingRecord != nil {
            return isSaving ? "保存中" : "保存修改"
        }
        return isSaving ? "处理中" : "确认\(action.title)"
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

    private func selectorButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? actionColor : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    isSelected ? Color(nsColor: .textBackgroundColor).opacity(0.92) : Color.clear,
                    in: Capsule()
                )
                .overlay {
                    if isSelected {
                        Capsule()
                            .stroke(actionColor.opacity(0.18), lineWidth: 0.6)
                    }
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

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let draft = FundTradeDraft(
            action: action,
            code: fund.code,
            mode: mode,
            amount: Self.number(amount),
            shares: Self.number(shares),
            tradeDate: DateOnlyFormatter.string(from: tradeDate),
            tradeTimeType: tradeTimeType
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
}
