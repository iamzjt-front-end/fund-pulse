import AppKit
import SwiftUI

private enum FundDetailTrendTab: String, CaseIterable, Identifiable {
    case intraday
    case netValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intraday:
            "盘中预估实时涨跌"
        case .netValue:
            "净值业绩走势"
        }
    }
}

private enum FundNetValueTrendRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case threeYears

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth:
            "近1月"
        case .threeMonths:
            "近3月"
        case .sixMonths:
            "近6月"
        case .oneYear:
            "近1年"
        case .threeYears:
            "近3年"
        }
    }

    var months: Int {
        switch self {
        case .oneMonth:
            1
        case .threeMonths:
            3
        case .sixMonths:
            6
        case .oneYear:
            12
        case .threeYears:
            36
        }
    }
}

private struct FundDailyIncomeDisplayRow: Identifiable {
    let id: String
    let dateText: String
    let amount: Double
}

func unavailableRoutedFund(code: String) -> FundPosition {
    FundPosition(
        code: code,
        name: "",
        dateText: "--",
        todayIncome: 0,
        todayRate: 0,
        holdingRate: nil,
        status: .watch,
        isUpdated: false
    )
}

struct FundDailyIncomePanelView: View {
    let store: PortfolioStore
    private let fundCode: String
    let onClose: () -> Void

    @State private var supplement: FundDetailSupplement = .empty
    @State private var isSupplementLoading = false
    @State private var didLoadSupplement = false
    @Environment(\.colorScheme) private var colorScheme

    private let supplementService = FundQuoteService()

    init(
        store: PortfolioStore,
        fundCode: String,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.fundCode = fundCode
        self.onClose = onClose
    }

    private var fund: FundPosition {
        store.snapshot.funds.first { $0.code == fundCode } ?? unavailableRoutedFund(code: fundCode)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "calendar.badge.clock",
                title: "每日收益",
                subtitle: FundCodeFormatter.display(fund.code),
                subtitleWeight: .semibold,
                tint: toneColor(for: latestDailyIncome),
                accessoryText: rowsAccessoryText,
                accessoryColor: .orange,
                onClose: onClose
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isSupplementLoading && !didLoadSupplement {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 360)
                    } else if dailyIncomeRows.isEmpty {
                        ContentUnavailableView("暂无每日收益", systemImage: "chart.bar.doc.horizontal")
                            .frame(height: 360)
                    } else {
                        dailyIncomeTable
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
        .task(id: fund.code) {
            await loadSupplement()
        }
    }

    private var dailyIncomeTable: some View {
        VStack(spacing: 0) {
            dailyIncomeTableHeader
            ForEach(dailyIncomeDisplayRows) { row in
                Divider()
                    .opacity(0.45)
                dailyIncomeRow(row)
            }
        }
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var dailyIncomeTableHeader: some View {
        HStack(spacing: 12) {
            tableHeaderText("日期", alignment: .leading)
            tableHeaderText("日收益", alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func dailyIncomeRow(_ row: FundDailyIncomeDisplayRow) -> some View {
        HStack(spacing: 12) {
            tableValueText(row.dateText, alignment: .leading)
            tableValueText(MoneyFormatter.money(row.amount, signed: true), alignment: .trailing, tone: row.amount)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func tableHeaderText(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func tableValueText(
        _ text: String,
        alignment: Alignment,
        tone: Double? = nil
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.64)
            .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var rowsAccessoryText: String? {
        dailyIncomeRows.isEmpty ? nil : "\(dailyIncomeRows.count)天"
    }

    private var latestDailyIncome: Double {
        dailyIncomeRows.first?.dailyIncome ?? 0
    }

    private var dailyIncomeDisplayRows: [FundDailyIncomeDisplayRow] {
        dailyIncomeRows.flatMap { row -> [FundDailyIncomeDisplayRow] in
            guard isMeaningfulAmount(row.entryIncome) else {
                return [
                    FundDailyIncomeDisplayRow(
                        id: row.id,
                        dateText: row.dateText,
                        amount: row.dailyIncome
                    )
                ]
            }

            let entryRow = FundDailyIncomeDisplayRow(
                id: "\(row.id)-entry",
                dateText: "\(row.dateText) 录入",
                amount: row.entryIncome
            )
            guard isMeaningfulAmount(row.dailyIncome) else {
                return [entryRow]
            }

            return [
                FundDailyIncomeDisplayRow(
                    id: row.id,
                    dateText: row.dateText,
                    amount: row.dailyIncome
                ),
                entryRow
            ]
        }
    }

    private func isMeaningfulAmount(_ value: Double) -> Bool {
        abs(value) >= 0.005
    }

    private var dailyIncomeRows: [FundDailyIncomeRow] {
        FundDailyIncomeCalculator.rows(lots: effectiveLots, points: sourceNetValuePoints)
    }

    private var sourceNetValuePoints: [FundNetValuePoint] {
        supplement.history.isEmpty ? supplement.trend : supplement.history
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
                id: "\(fund.code)-daily-income",
                shares: shares,
                cost: fund.migratedCost ?? 0,
                incomeStartDate: fund.incomeStartDate ?? fund.positionDate ?? "",
                positionDate: fund.positionDate ?? "",
                positionTimeType: fund.positionTimeType ?? .before15
            )
        ]
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

enum FundRowAmountPrivacyFormatter {
    static let maskedText = "***"

    static func plainMoney(_ value: Double, isMasked: Bool) -> String {
        isMasked ? maskedText : MoneyFormatter.plainMoney(value)
    }

    static func signedCompactMoney(_ value: Double, isMasked: Bool) -> String {
        guard !isMasked else { return maskedText }
        return compact(MoneyFormatter.money(value, signed: true))
    }

    static func signedCompactHoldingIncome(
        _ value: Double,
        accountKind: PortfolioAccountKind,
        isMasked: Bool
    ) -> String {
        guard !isMasked else { return maskedText }
        return MoneyFormatter.compactHoldingIncome(value, accountKind: accountKind)
    }

    private static func compact(_ value: String) -> String {
        value
            .replacingOccurrences(of: "¥ ", with: "")
            .replacingOccurrences(of: "+¥", with: "+")
            .replacingOccurrences(of: "-¥", with: "-")
    }
}

struct FundDetailView: View {
    let store: PortfolioStore
    private let fundCode: String
    private let allowsConversion: Bool
    let onBuy: (FundPosition) -> Void
    let onSell: (FundPosition) -> Void
    let onConvert: (FundPosition) -> Void
    let onEdit: (FundPosition) -> Void
    let onOpenTradeRecords: (FundPosition) -> Void
    let onOpenDailyIncome: (FundPosition) -> Void
    let onDelete: (FundPosition) async -> Void
    let onClose: () -> Void

    @State private var isDeleteConfirmationPresented = false
    @State private var supplement: FundDetailSupplement = .empty
    @State private var isSupplementLoading = false
    @State private var didLoadSupplement = false
    @State private var trendTab: FundDetailTrendTab = .intraday
    @State private var netValueTrendRange: FundNetValueTrendRange = .threeMonths
    @Environment(\.colorScheme) private var colorScheme

    private let supplementService = FundQuoteService()

    init(
        store: PortfolioStore,
        fundCode: String,
        allowsConversion: Bool = true,
        onBuy: @escaping (FundPosition) -> Void,
        onSell: @escaping (FundPosition) -> Void,
        onConvert: @escaping (FundPosition) -> Void,
        onEdit: @escaping (FundPosition) -> Void,
        onOpenTradeRecords: @escaping (FundPosition) -> Void,
        onOpenDailyIncome: @escaping (FundPosition) -> Void,
        onDelete: @escaping (FundPosition) async -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.fundCode = fundCode
        self.allowsConversion = allowsConversion
        self.onBuy = onBuy
        self.onSell = onSell
        self.onConvert = onConvert
        self.onEdit = onEdit
        self.onOpenTradeRecords = onOpenTradeRecords
        self.onOpenDailyIncome = onOpenDailyIncome
        self.onDelete = onDelete
        self.onClose = onClose
    }

    private var fund: FundPosition {
        store.snapshot.funds.first { $0.code == fundCode } ?? unavailableRoutedFund(code: fundCode)
    }

    private var tradeRecords: [FundTradeRecord] {
        store.snapshot.tradeRecords ?? []
    }

    private var detailUpdateStarColor: Color {
        Color(nsColor: StatusBarTone.menuBarColor(forRate: fund.todayRate))
    }

    private var detailUpdateStar: some View {
        UpdatedFundStarShape()
            .fill(detailUpdateStarColor)
            .frame(width: 14.5, height: 14.5)
            .frame(width: 17, height: 18, alignment: .center)
            .shadow(color: detailUpdateStarColor.opacity(colorScheme == .dark ? 0.30 : 0.20), radius: 2.5, x: 0, y: 1)
            .accessibilityLabel(isOnExchange ? "行情已更新" : "净值已更新")
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "基金详情",
                subtitle: FundCodeFormatter.display(fund.code),
                subtitleWeight: .semibold,
                tint: toneColor(for: fund.todayRate),
                actionSystemImage: "list.bullet.rectangle",
                actionTitle: "交易记录",
                actionBadgeText: tradeRecordsBadgeText,
                actionTint: Color(nsColor: .systemGray),
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
            Button("删除基金", role: .destructive) {
                Task {
                    await onDelete(fund)
                    onClose()
                }
            }
        } message: {
            Text(deleteFundConfirmationMessage)
        }
    }

    private var deleteFundConfirmationMessage: String {
        "确定删除“\(fund.name)”吗？这会同时删除该基金的持仓、待确认交易和全部交易记录，删除后无法撤销。"
    }

    private var fundTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fund.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                if isOnExchange {
                    detailTag("场内", color: Color(nsColor: .systemBlue))
                    detailTag(fund.resolvedExchangeTurnaroundRule.shortTitle, color: PanelDesign.accent)
                }
                if FundUpdatePresentationPolicy.showsOfficialUpdateMarker(
                    for: fund,
                    accountKind: store.accountKind
                ) {
                    detailUpdateStar
                        .fixedSize()
                }
            }
            HStack(spacing: 7) {
                Text(FundCodeFormatter.display(fund.code))
                    .fontWeight(.semibold)
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
                    Text(isOnExchange ? "当日涨跌" : "当日涨幅")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if FundUpdatePresentationPolicy.showsOfficialUpdateMarker(
                        for: fund,
                        accountKind: store.accountKind
                    ) {
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
            if isOnExchange {
                metric("持仓市值", numberText(currentTotal, places: 2))
                metric("持有份额", totalShares > 0 ? numberText(totalShares, places: 2) : "--")
                metric("可卖份额", numberText(exchangeShareAvailability.sellableShares, places: 2))
                metric("持仓成本", fund.migratedCost.map { numberText($0, places: 4) } ?? "--")
                dailyIncomeMetricButton(
                    "持仓收益",
                    MoneyFormatter.compactHoldingIncome(
                        holdingIncome,
                        accountKind: store.accountKind
                    ),
                    tone: holdingIncome
                )
                metric("持仓收益率", fund.holdingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "0.00%", tone: fund.holdingRate)
            } else {
                metric("持仓金额", numberText(currentTotal, places: 2))
                metric("持仓份额", totalShares > 0 ? numberText(totalShares, places: 2) : "--")
                metric("持仓成本", fund.migratedCost.map { numberText($0, places: 4) } ?? "--")
                dailyIncomeMetricButton(
                    "持仓收益",
                    MoneyFormatter.compactHoldingIncome(
                        holdingIncome,
                        accountKind: store.accountKind
                    ),
                    tone: holdingIncome
                )
                metric("持仓收益率", fund.holdingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "0.00%", tone: fund.holdingRate)
                metric("持仓天数", holdingDaysText)
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSegmentedPicker(
                values: FundDetailTrendTab.allCases,
                selection: $trendTab,
                title: { tab in
                    isOnExchange && tab == .intraday ? "盘中成交实时涨跌" : tab.title
                },
                tint: toneColor(for: fund.todayRate)
            )

            switch trendTab {
            case .intraday:
                intradayTrendContent
            case .netValue:
                netValueTrendContent
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var intradayTrendContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                isOnExchange ? "盘中成交实时涨跌" : "盘中预估实时涨跌",
                trailing: intradayTrendTrailingText
            )

            if visibleIntradayRatePoints.isEmpty {
                emptySupplementView(intradayTrendEmptyText)
                    .frame(height: 116)
            } else {
                FundIntradayRateChart(points: visibleIntradayRatePoints)
                    .frame(height: 138)
            }
        }
    }

    private var netValueTrendContent: some View {
        let trendPoints = netValueTrendPoints
        let costReference = FundNetValueTrendScale.costReference(from: fund.migratedCost)
        return VStack(alignment: .leading, spacing: 8) {
            netValueTrendHeader(costReference: costReference)

            if trendPoints.count >= 2 {
                FundTrendMiniChart(points: trendPoints, holdingCost: fund.migratedCost)
                    .frame(height: 116)
            } else {
                emptySupplementView(isSupplementLoading ? "走势加载中..." : "暂无走势数据")
                    .frame(height: 86)
            }

            netValueTrendRangePicker
        }
    }

    private func netValueTrendHeader(costReference: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 5) {
                Text("净值业绩走势")
                    .font(.system(size: 12, weight: .semibold))
                if isSupplementLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                if let latestNetValuePoint {
                    Text("最新 \(numberText(latestNetValuePoint.value, places: 4))")
                }

                if latestNetValuePoint != nil, costReference != nil {
                    Text("·")
                        .foregroundStyle(.tertiary)
                }

                if let costReference {
                    Text("成本 \(numberText(costReference, places: 4))")
                }
            }
            .font(.system(size: 9.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("历史净值", trailing: historyTrailingText, showsLoading: isSupplementLoading)

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
            sectionHeader("前10重仓股", trailing: topHoldingsTrailingText, showsLoading: isSupplementLoading)

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

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.45)

            HStack(spacing: 8) {
                Button {
                    onBuy(fund)
                } label: {
                    PanelButtonLabel(title: isOnExchange ? "买入" : "加仓", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button {
                    onSell(fund)
                } label: {
                    PanelButtonLabel(title: isOnExchange ? "卖出" : "减仓", systemImage: "minus.circle")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled((fund.migratedShares ?? 0) <= 0)

                if allowsConversion {
                    Button {
                        onConvert(fund)
                    } label: {
                        PanelButtonLabel(title: "转换", systemImage: "arrow.left.arrow.right.circle")
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled((fund.migratedShares ?? 0) <= 0)
                }

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

    private func sectionHeader(_ title: String, trailing: String? = nil, showsLoading: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            if showsLoading {
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
        return records.sorted(by: tradeRecordTimeDescending)
    }

    private var pendingTradeRecords: [FundTradeRecord] {
        recentTradeRecords.filter { $0.status == .pending }
    }

    private var netValueSourcePoints: [FundNetValuePoint] {
        let source = supplement.history.isEmpty ? supplement.trend : supplement.history
        return source.sorted { $0.timestamp < $1.timestamp }
    }

    private var latestNetValuePoint: FundNetValuePoint? {
        netValueSourcePoints.last
    }

    private var netValueTrendPoints: [FundNetValuePoint] {
        let source = netValueSourcePoints
        guard let latestTimestamp = source.last?.timestamp else { return [] }

        let calendar = Calendar.current
        let latestDate = Date(timeIntervalSince1970: TimeInterval(latestTimestamp) / 1000)
        let latestDay = calendar.startOfDay(for: latestDate)
        guard let cutoff = calendar.date(byAdding: .month, value: -netValueTrendRange.months, to: latestDay) else {
            return source
        }

        return source.filter { point in
            let pointDate = Date(timeIntervalSince1970: TimeInterval(point.timestamp) / 1000)
            return calendar.startOfDay(for: pointDate) >= cutoff
        }
    }

    private var netValueTrendRangePicker: some View {
        HStack(spacing: 4) {
            ForEach(FundNetValueTrendRange.allCases) { value in
                let isSelected = netValueTrendRange == value
                Button {
                    netValueTrendRange = value
                } label: {
                    Text(value.title)
                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? netValueTrendRangeTint : Color.secondary.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? netValueTrendRangeTint.opacity(colorScheme == .dark ? 0.22 : 0.15) : Color.clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isSelected ? netValueTrendRangeTint.opacity(0.18) : Color.clear, lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(.top, 1)
    }

    private var netValueTrendRangeTint: Color {
        toneColor(for: fund.todayRate)
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
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " / ")
    }

    private var pendingTradeSummaryDetail: String? {
        guard !pendingTradeRecords.isEmpty else { return nil }
        var parts: [String] = []
        let buyCount = pendingTradeRecords.filter { $0.kind == .newFund || $0.kind == .buy }.count
        let sellCount = pendingTradeRecords.filter { $0.kind == .sell }.count
        let conversionCount = Set(pendingTradeRecords.filter { $0.kind == .conversionOut || $0.kind == .conversionIn }.compactMap(\.conversionID)).count
        if buyCount > 0 {
            parts.append("加仓 \(buyCount)笔")
        }
        if sellCount > 0 {
            parts.append("减仓 \(sellCount)笔")
        }
        if conversionCount > 0 {
            parts.append("转换 \(conversionCount)笔")
        }
        if let acceptedDate = pendingTradeRecords.map(\.acceptedDate).sorted().first {
            parts.append("确认 \(acceptedDate)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var pendingTradeSummaryTone: Color {
        pendingTradeSummaryValues.buyAmount > 0
            ? .red
            : .fundPulseGreen
    }

    private var pendingTradeSummaryBackground: Color {
        Color.orange.opacity(0.08)
    }

    private var pendingTradeSummaryValues: (buyAmount: Double, sellAmount: Double) {
        var buyAmount: Double = 0
        var sellAmount: Double = 0

        for record in pendingTradeRecords {
            switch record.kind {
            case .newFund, .buy:
                if let amount = record.amount, amount > 0 {
                    buyAmount += amount
                } else if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    buyAmount += pendingTradeSummaryAmount(shares: shares, acceptedDate: record.acceptedDate)
                }
            case .sell:
                if let amount = record.amount, amount > 0 {
                    sellAmount += amount
                } else if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    sellAmount += pendingTradeSummaryAmount(shares: shares, acceptedDate: record.acceptedDate)
                }
            case .conversionOut:
                if let shares = record.confirmedShares ?? record.shares, shares > 0 {
                    sellAmount += pendingTradeSummaryAmount(shares: shares, acceptedDate: record.acceptedDate)
                }
            case .conversionIn:
                if let amount = record.amount, amount > 0 {
                    buyAmount += amount
                }
            }
        }

        return (buyAmount, sellAmount)
    }

    private func pendingTradeSummaryAmount(shares: Double, acceptedDate: String) -> Double {
        guard let price = pendingTradeSummaryReferencePrice(acceptedDate: acceptedDate) else {
            return 0
        }
        return shares * price
    }

    private func pendingTradeSummaryReferencePrice(acceptedDate: String) -> Double? {
        let shares = fund.migratedShares ?? 0
        let currentAmount = PortfolioPanelDisplay.currentAmount(for: fund)
        let basePrice: Double
        if shares > 0, currentAmount > 0 {
            basePrice = currentAmount / shares
        } else if let migratedCost = fund.migratedCost, migratedCost > 0 {
            basePrice = migratedCost
        } else {
            return nil
        }

        let today = DateOnlyFormatter.string(from: .now)
        if acceptedDate == today, !fund.isUpdated, fund.todayRate != 0 {
            return basePrice * (1 + fund.todayRate / 100)
        }
        return basePrice
    }

    private var tradeRecordsEntrySubtitle: String {
        let pendingCount = recentTradeRecords.filter { $0.status == .pending }.count
        guard pendingCount > 0 else { return "查看新增、加仓、减仓、转换流水" }
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
                if let detail = stockHoldingDetailText(holding) {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    private func stockHoldingDetailText(_ holding: FundStockHolding) -> String? {
        var parts: [String] = []
        if !holding.code.isEmpty {
            parts.append(holding.code)
        }
        if let industryName = holding.industryName, !industryName.isEmpty {
            parts.append(industryName)
        }
        if let positionChangeType = holding.positionChangeType, !positionChangeType.isEmpty {
            if let positionChangeRate = holding.positionChangeRate, positionChangeRate != 0 {
                parts.append("\(positionChangeType) \(MoneyFormatter.percent(positionChangeRate, signed: false))")
            } else {
                parts.append(positionChangeType)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func metric(_ title: String, _ value: String, tone: Double? = nil, isInteractive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if isInteractive {
                    detailDisclosureIndicator
                }
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dailyIncomeMetricButton(_ title: String, _ value: String, tone: Double? = nil) -> some View {
        Button {
            onOpenDailyIncome(fund)
        } label: {
            metric(title, value, tone: tone, isInteractive: true)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(Rectangle())
        .help("查看每日收益")
    }

    private var detailDisclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
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

    private var exchangeShareAvailability: ExchangeShareAvailability {
        store.exchangeShareAvailability(for: fund.code)
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

    private var topHoldingsTrailingText: String? {
        guard !supplement.topHoldings.isEmpty else { return nil }
        guard let date = supplement.holdingDisclosureDate else {
            return "\(supplement.topHoldings.count)只"
        }
        return "\(supplement.topHoldings.count)只 · \(date)"
    }

    private var intradayRatePoints: [FundIntradayRatePoint] {
        FundIntradayRateHistoryRecorder.activePoints(for: fund)
    }

    private var visibleIntradayRatePoints: [FundIntradayRatePoint] {
        if !intradayRatePoints.isEmpty {
            return intradayRatePoints
        }

        switch TradingCalendar.marketSessionState() {
        case .open:
            return intradayCurrentValueFallbackPoints
        case .middayBreak, .closed:
            guard fund.intradayRateDate == FundIntradayRateHistoryRecorder.tradingDayString(from: .now) else {
                return intradayCurrentValueFallbackPoints
            }
            let storedPoints = (fund.intradayRateHistory ?? []).sorted { $0.timestamp < $1.timestamp }
            return storedPoints.isEmpty ? intradayCurrentValueFallbackPoints : storedPoints
        }
    }

    private var intradayTrendTrailingText: String? {
        guard let lastPoint = visibleIntradayRatePoints.last else { return nil }
        return "\(MoneyFormatter.percent(lastPoint.rate, signed: true)) · \(dateText(lastPoint.timestamp, format: "HH:mm"))"
    }

    private var intradayTrendEmptyText: String {
        switch TradingCalendar.marketSessionState() {
        case .open:
            isOnExchange ? "等待下一次交易所行情刷新" : "等待下一次盘中估值刷新"
        case .middayBreak:
            "午休中，盘中曲线暂停更新"
        case .closed:
            "休市中，盘中曲线停止更新"
        }
    }

    private var isOnExchange: Bool {
        store.accountKind == .onExchange
    }

    private var intradayCurrentValueFallbackPoints: [FundIntradayRatePoint] {
        guard fund.todayRate.isFinite,
              fund.todayRate != 0
        else {
            return []
        }

        return [
            FundIntradayRatePoint(
                timestamp: intradayFallbackTimestamp,
                rate: fund.todayRate,
                estimateTime: fund.dateText
            )
        ]
    }

    private var intradayFallbackTimestamp: Int64 {
        if let parsedDate = parseFundDateText(fund.dateText) {
            return Int64((parsedDate.timeIntervalSince1970 * 1000).rounded())
        }
        return Int64((Date().timeIntervalSince1970 * 1000).rounded())
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

    private func parseFundDateText(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 11 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        let year = calendar.component(.year, from: .now)
        let fullText = "\(year)-\(trimmed)"
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: fullText)
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

