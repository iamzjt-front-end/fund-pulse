import SwiftUI

struct FundPositionEditorView: View {
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
    @State private var cost: String
    @State private var isSameDayNewFund: Bool
    @State private var positionDate: Date
    @State private var positionTimeType: PositionTimeType
    @State private var zdfRange: String
    @State private var jzNotice: String
    @State private var memo: String
    @State private var lookupTask: Task<Void, Never>?
    @State private var autoResolvedName: String?
    @State private var latestQuote: FundQuote?
    @State private var isLookingUpMetadata = false
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

        let mode = fund?.positionMode ?? .amount
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
        _cost = State(initialValue: fund?.migratedCost.map { Self.text($0, places: 4) } ?? "")
        _isSameDayNewFund = State(initialValue: false)
        _positionDate = State(initialValue: date)
        _positionTimeType = State(initialValue: fund?.positionTimeType ?? TradingCalendar.defaultPositionTimeType())
        _zdfRange = State(initialValue: fund?.zdfRange.map { Self.text($0) } ?? "")
        _jzNotice = State(initialValue: fund?.jzNotice.map { Self.text($0, places: 4) } ?? "")
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
                        PanelSegmentedPicker(
                            values: Array(PositionMode.allCases),
                            selection: $positionMode,
                            title: { $0.title }
                        )

                        if positionMode == .amount {
                            field("持有金额") {
                                PanelTextInput("请输入持有总金额", text: $positionAmount, suffix: "元")
                            }
                            field("累计收益") {
                                PanelTextInput("可为负，默认为 0", text: $positionProfit, suffix: "元")
                            }
                        } else {
                            field("持有份额") {
                                PanelTextInput("可精确 2 位小数", text: $shares, suffix: "份")
                            }
                            field("持仓成本价") {
                                PanelTextInput("可精确 4 位小数", text: $cost)
                            }
                        }

                        if fund == nil {
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

                    PanelSection(title: "提醒与备注") {
                        field("涨跌幅提醒") {
                            PanelTextInput("百分比，可选", text: $zdfRange, suffix: "%")
                        }
                        field("净值提醒") {
                            PanelTextInput("目标净值，可选", text: $jzNotice)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("备注")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $memo)
                                .frame(height: 58)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(PanelDesign.border(cornerRadius: 8))
                        }
                    }

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
        .onChange(of: code) { _, newValue in
            scheduleFundMetadataLookup(for: newValue)
        }
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
            scheduleFundMetadataLookup(for: code)
        }
        .onDisappear {
            lookupTask?.cancel()
        }
    }

    private var header: some View {
        PanelHeader(
            systemImage: fund == nil ? "plus" : "pencil",
            title: fund == nil ? "添加基金" : "修改基金",
            subtitle: fund == nil ? "记录一只新的基金持仓" : "调整基金持仓与提醒",
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
                Text("最新净值")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(latestQuote?.netValueDate.isEmpty == false ? "净值日期 \(latestQuote?.netValueDate ?? "")" : "输入基金代码后自动读取")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLookingUpMetadata {
                ProgressView()
                    .controlSize(.small)
            } else if let latestQuote {
                Text(Self.text(latestQuote.netValue, places: 4))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelDesign.accent)
                    .monospacedDigit()
            } else {
                Text("暂无")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(9)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

            Text(isSameDayNewFund ? "开启后表示今天刚买入，需选择 15:00 前后；净值未确认前进入待确认。" : "关闭时按已有历史持仓补录，使用最新确认净值入持有，不进入待确认。")
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
        fund == nil && isSameDayNewFund
    }

    private var shouldShowTradeTimeControls: Bool {
        isTodayNewFund
    }

    private var canSubmit: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (
            positionMode == .amount
                ? (Self.number(positionAmount) ?? 0) > 0
                : (Self.number(shares) ?? 0) > 0 && (Self.number(cost) ?? 0) > 0
        )
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
        let resolvedPositionTimeType = isTodayNewFund
            ? positionTimeType
            : .before15

        let draft = FundPositionDraft(
            code: code,
            name: name,
            positionMode: positionMode,
            positionAmount: Self.number(positionAmount),
            positionProfit: Self.number(positionProfit) ?? 0,
            shares: Self.number(shares),
            cost: Self.number(cost),
            positionDate: resolvedPositionDate,
            positionTimeType: resolvedPositionTimeType,
            zdfRange: Self.number(zdfRange),
            jzNotice: Self.number(jzNotice),
            memo: memo,
            requiresTradeConfirmation: isTodayNewFund
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

    private func scheduleFundMetadataLookup(for rawCode: String) {
        lookupTask?.cancel()
        let trimmedCode = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6, trimmedCode.allSatisfy(\.isNumber) else {
            isLookingUpMetadata = false
            latestQuote = nil
            return
        }

        isLookingUpMetadata = true
        lookupTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let fetchedQuote = await store.fetchLatestQuote(code: trimmedCode)
            let fetchedName: String?
            if let fetchedQuote, fetchedQuote.name != trimmedCode {
                fetchedName = fetchedQuote.name
            } else {
                fetchedName = await store.lookupFundName(code: trimmedCode)
            }
            await MainActor.run {
                guard !Task.isCancelled,
                      code.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedCode
                else {
                    return
                }

                latestQuote = fetchedQuote
                if fund == nil,
                   let fetchedName,
                   name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == autoResolvedName {
                    name = fetchedName
                    autoResolvedName = fetchedName
                }
                isLookingUpMetadata = false
            }
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
