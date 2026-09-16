import AppKit
import SwiftUI

private struct TodayIncomeRankItem: Identifiable {
    let rank: Int
    let fund: FundPosition

    var id: String { fund.code }
}

private enum TodayIncomeRankingMode: String, CaseIterable, Identifiable {
    case gain
    case loss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gain:
            "涨幅榜"
        case .loss:
            "跌幅榜"
        }
    }

    var emptyTitle: String {
        switch self {
        case .gain:
            "暂无上涨基金"
        case .loss:
            "暂无下跌基金"
        }
    }

    var summaryTitle: String {
        switch self {
        case .gain:
            "上涨合计"
        case .loss:
            "下跌合计"
        }
    }

    var tint: Color {
        switch self {
        case .gain:
            Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255)
        case .loss:
            Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255)
        }
    }
}

enum IncomeRankingKind: Equatable {
    case today
    case holding

    func title(for metric: IncomeRankingMetric) -> String {
        switch self {
        case .today where metric == .amount:
            return "实时收益排行"
        case .today:
            return "实时收益率排行"
        case .holding where metric == .amount:
            return "持仓收益排行"
        case .holding:
            return "持仓收益率排行"
        }
    }

    var unavailableTitle: String {
        switch self {
        case .today:
            "暂无实时收益"
        case .holding:
            "暂无持仓收益"
        }
    }

    var unavailableSystemImage: String {
        switch self {
        case .today:
            "chart.line.uptrend.xyaxis"
        case .holding:
            "chart.bar.xaxis"
        }
    }

    func gainTitle(for metric: IncomeRankingMetric) -> String {
        metric == .amount ? "收益榜" : "涨幅榜"
    }

    func lossTitle(for metric: IncomeRankingMetric) -> String {
        metric == .amount ? "亏损榜" : "跌幅榜"
    }

    var gainEmptyTitle: String {
        switch self {
        case .today:
            "暂无上涨基金"
        case .holding:
            "暂无盈利基金"
        }
    }

    var lossEmptyTitle: String {
        switch self {
        case .today:
            "暂无下跌基金"
        case .holding:
            "暂无亏损基金"
        }
    }

    var gainSummaryTitle: String {
        switch self {
        case .today:
            "涨"
        case .holding:
            "盈"
        }
    }

    var lossSummaryTitle: String {
        switch self {
        case .today:
            "跌"
        case .holding:
            "亏"
        }
    }
}

enum IncomeRankingMetric: String, CaseIterable, Identifiable {
    case amount
    case rate

    var id: String { rawValue }

    var holdingPickerTitle: String {
        switch self {
        case .amount:
            "按金额"
        case .rate:
            "按收益率"
        }
    }
}

private struct TodayIncomeRankPalette {
    let foreground: Color
    let deep: Color
    let background: Color
    let border: Color
}

private struct TodayIncomeRankMedalPalette {
    let foreground: Color
    let deep: Color
    let light: Color
    let border: Color
}

struct TodayIncomeRankingPanelView: View {
    let store: PortfolioStore
    let kind: IncomeRankingKind
    let metric: IncomeRankingMetric
    let onClose: () -> Void
    var isEmbedded = false
    var metricSelection: Binding<IncomeRankingMetric>? = nil

    @State private var rankingMode: TodayIncomeRankingMode = .gain
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if !isEmbedded {
                PanelHeader(
                    systemImage: "list.number",
                    title: kind.title(for: metric),
                    subtitle: rankingHeaderSubtitle,
                    subtitleWeight: .semibold,
                    tint: toneColor(for: totalValue),
                    accessoryText: updatedHeaderTagText,
                    accessoryColor: .orange,
                    onClose: onClose
                )
            }

            ScrollView {
                if rankableFunds.isEmpty {
                    ContentUnavailableView(kind.unavailableTitle, systemImage: kind.unavailableSystemImage)
                        .frame(height: 420)
                } else {
                    LazyVStack(spacing: 10) {
                        rankingSummary
                        if let metricSelection {
                            rankingControls(metricSelection: metricSelection)
                        } else {
                            rankingModePicker
                        }
                        if rankingItems.isEmpty {
                            ContentUnavailableView(emptyTitle(for: rankingMode), systemImage: rankingMode == .gain ? "arrow.up.right" : "arrow.down.right")
                                .frame(height: 260)
                        } else {
                            ForEach(rankingItems) { item in
                                rankingRow(item)
                            }
                        }
                    }
                    .padding(.horizontal, isEmbedded ? 0 : 14)
                    .padding(.bottom, 14)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
        .onAppear {
            selectAvailableRankingModeIfNeeded()
        }
        .onChange(of: metric) { _, _ in
            selectAvailableRankingModeIfNeeded()
        }
    }

    private var rankableFunds: [FundPosition] {
        store.snapshot.funds.filter { fund in
            switch kind {
            case .today:
                !fund.status.isPendingDisplay && (fund.isIncomeActive ?? true)
            case .holding:
                fund.status == .holding && (fund.isIncomeActive ?? true)
            }
        }
    }

    private var rankingItems: [TodayIncomeRankItem] {
        let funds = rankableFunds
            .filter { fund in
                switch rankingMode {
                case .gain:
                    rankingValue(for: fund) > 0
                case .loss:
                    rankingValue(for: fund) < 0
                }
            }
            .sorted { lhs, rhs in
                let lhsValue = rankingValue(for: lhs)
                let rhsValue = rankingValue(for: rhs)
                if lhsValue != rhsValue {
                    return rankingMode == .gain ? lhsValue > rhsValue : lhsValue < rhsValue
                }
                let lhsTieValue = tieBreakValue(for: lhs)
                let rhsTieValue = tieBreakValue(for: rhs)
                if lhsTieValue != rhsTieValue {
                    return rankingMode == .gain ? lhsTieValue > rhsTieValue : lhsTieValue < rhsTieValue
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return funds.enumerated().map { index, fund in
            TodayIncomeRankItem(rank: index + 1, fund: fund)
        }
    }

    private var updatedFundsCount: Int {
        rankingItems.filter {
            FundUpdatePresentationPolicy.showsOfficialUpdateMarker(for: $0.fund, accountKind: store.accountKind)
        }.count
    }

    private var rankingHeaderSubtitle: String {
        guard !rankableFunds.isEmpty else { return "暂无持仓基金" }
        return "\(rankableFunds.count)只基金 · \(summaryValueText(totalValue))"
    }

    private var updatedHeaderTagText: String? {
        let updatedCount = rankableFunds.filter {
            FundUpdatePresentationPolicy.showsOfficialUpdateMarker(for: $0, accountKind: store.accountKind)
        }.count
        guard updatedCount > 0 else { return nil }
        if updatedCount == rankableFunds.count {
            return "全部已更新"
        }
        return "\(updatedCount)只已更新"
    }

    private var rankingModePicker: some View {
        PanelSegmentedPicker(
            values: TodayIncomeRankingMode.allCases,
            selection: $rankingMode,
            title: { title(for: $0) },
            tint: rankingMode.tint
        )
    }

    private func rankingControls(metricSelection: Binding<IncomeRankingMetric>) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(IncomeRankingMetric.allCases) { value in
                    Button {
                        metricSelection.wrappedValue = value
                    } label: {
                        if value == metricSelection.wrappedValue {
                            Label(value.holdingPickerTitle, systemImage: "checkmark")
                        } else {
                            Text(value.holdingPickerTitle)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(metric.holdingPickerTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(PanelDesign.selectorBackground, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.6)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusEffectDisabled()
            .accessibilityLabel("排行指标")
            .accessibilityValue(metric.holdingPickerTitle)
            .help("切换按金额或按收益率排行")

            rankingModePicker
        }
    }

    private var gainFunds: [FundPosition] {
        rankableFunds.filter { rankingValue(for: $0) > 0 }
    }

    private var lossFunds: [FundPosition] {
        rankableFunds.filter { rankingValue(for: $0) < 0 }
    }

    private func selectAvailableRankingModeIfNeeded() {
        if rankingMode == .gain, gainFunds.isEmpty, !lossFunds.isEmpty {
            rankingMode = .loss
        } else if rankingMode == .loss, lossFunds.isEmpty, !gainFunds.isEmpty {
            rankingMode = .gain
        }
    }

    private var gainSummaryValue: Double {
        summaryGroupValue(for: gainFunds)
    }

    private var lossSummaryValue: Double {
        summaryGroupValue(for: lossFunds)
    }

    private var totalValue: Double {
        switch kind {
        case .today where metric == .amount:
            store.snapshot.todayIncome
        case .today:
            store.snapshot.todayIncomeRate
        case .holding where metric == .amount:
            store.snapshot.holdingIncome
        case .holding:
            store.snapshot.holdingIncomeRate
        }
    }

    private func rankingValue(for fund: FundPosition) -> Double {
        switch metric {
        case .amount:
            income(for: fund)
        case .rate:
            rate(for: fund)
        }
    }

    private func tieBreakValue(for fund: FundPosition) -> Double {
        switch metric {
        case .amount:
            rate(for: fund)
        case .rate:
            income(for: fund)
        }
    }

    private func income(for fund: FundPosition) -> Double {
        switch kind {
        case .today:
            return fund.todayIncome
        case .holding:
            if let holdingIncome = fund.holdingIncome {
                return holdingIncome
            }
            guard let holdingRate = fund.holdingRate else { return 0 }
            return principal(for: fund) * holdingRate / 100
        }
    }

    private func rate(for fund: FundPosition) -> Double {
        switch kind {
        case .today:
            fund.todayRate
        case .holding:
            fund.holdingRate ?? 0
        }
    }

    private func principal(for fund: FundPosition) -> Double {
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

    private func title(for mode: TodayIncomeRankingMode) -> String {
        switch mode {
        case .gain:
            kind.gainTitle(for: metric)
        case .loss:
            kind.lossTitle(for: metric)
        }
    }

    private func emptyTitle(for mode: TodayIncomeRankingMode) -> String {
        switch mode {
        case .gain:
            kind.gainEmptyTitle
        case .loss:
            kind.lossEmptyTitle
        }
    }

    private var rankingSummary: some View {
        HStack(spacing: 0) {
            rankingSummaryMetric(
                "合计",
                summaryValueText(totalValue),
                tone: totalValue,
                footnote: "\(rankableFunds.count)只"
            )
            summaryDivider
            rankingSummaryMetric(
                groupSummaryTitle(isGain: true),
                summaryValueText(gainSummaryValue),
                tone: gainSummaryValue,
                footnote: "\(gainFunds.count)只"
            )
            summaryDivider
            rankingSummaryMetric(
                groupSummaryTitle(isGain: false),
                summaryValueText(lossSummaryValue),
                tone: lossSummaryValue,
                footnote: "\(lossFunds.count)只"
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func summaryGroupValue(for funds: [FundPosition]) -> Double {
        guard !funds.isEmpty else { return 0 }
        switch metric {
        case .amount:
            return funds.reduce(0) { $0 + income(for: $1) }
        case .rate:
            return funds.reduce(0) { $0 + rate(for: $1) } / Double(funds.count)
        }
    }

    private func groupSummaryTitle(isGain: Bool) -> String {
        if kind == .holding, metric == .rate {
            return isGain ? "盈利均值" : "亏损均值"
        }
        return isGain ? kind.gainSummaryTitle : kind.lossSummaryTitle
    }

    private func summaryValueText(_ value: Double) -> String {
        switch metric {
        case .amount:
            incomeMoneyText(value)
        case .rate:
            MoneyFormatter.percent(value, signed: true)
        }
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.30 : 0.22))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 10)
    }

    private func rankingSummaryMetric(_ title: String, _ value: String, tone: Double?, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(footnote)
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone.map(toneColor(for:)) ?? Color.secondary)
                    .padding(.horizontal, 4)
                    .frame(height: 13)
                    .background((tone.map(toneColor(for:)) ?? Color.secondary).opacity(colorScheme == .dark ? 0.14 : 0.08), in: Capsule())
            }
            .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .foregroundStyle(tone.map(toneColor(for:)) ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankingRow(_ item: TodayIncomeRankItem) -> some View {
        let isTopRank = item.rank <= 3
        let palette = rankPalette(for: item)
        return HStack(spacing: 10) {
            rankBadge(for: item)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.fund.name)
                        .font(.system(size: isTopRank ? 12.5 : 12, weight: .semibold))
                        .lineLimit(1)
                    if FundUpdatePresentationPolicy.showsOfficialUpdateMarker(
                        for: item.fund,
                        accountKind: store.accountKind
                    ) {
                        updatedTag
                    }
                }

                HStack(spacing: 7) {
                    Text(FundCodeFormatter.display(item.fund.code))
                        .fontWeight(.semibold)
                    Text(item.fund.dateText)
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(primaryValueText(for: item.fund))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .foregroundStyle(palette.foreground)
                Text(secondaryValueText(for: item.fund))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 6)
                    .frame(height: 19)
                    .background(palette.foreground.opacity(colorScheme == .dark ? 0.18 : 0.10), in: Capsule())
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, isTopRank ? 12 : 10)
        .frame(minHeight: isTopRank ? 70 : 62)
        .background(rowBackground(for: item), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(rowBorder(for: item))
        .shadow(
            color: item.rank <= 3 ? palette.foreground.opacity(colorScheme == .dark ? 0.22 : 0.14) : .clear,
            radius: item.rank <= 3 ? 8 : 0,
            x: 0,
            y: item.rank <= 3 ? 3 : 0
        )
    }

    private func primaryValueText(for fund: FundPosition) -> String {
        switch metric {
        case .amount:
            incomeMoneyText(income(for: fund))
        case .rate:
            MoneyFormatter.percent(rate(for: fund), signed: true)
        }
    }

    private func secondaryValueText(for fund: FundPosition) -> String {
        switch metric {
        case .amount:
            MoneyFormatter.percent(rate(for: fund), signed: true)
        case .rate:
            incomeMoneyText(income(for: fund))
        }
    }

    private func incomeMoneyText(_ value: Double) -> String {
        if kind == .holding {
            return MoneyFormatter.holdingIncome(value, accountKind: store.accountKind)
        }
        return MoneyFormatter.money(value, signed: true)
    }

    private func rankBadge(for item: TodayIncomeRankItem) -> some View {
        let rank = item.rank
        let palette = rankPalette(for: item)
        if rank <= 3 {
            let medal = medalPalette(for: rank)
            return AnyView(
                VStack(spacing: 1) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("\(rank)")
                        .font(.system(size: 15, weight: .heavy))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.white)
                .shadow(color: medal.deep.opacity(0.30), radius: 1.5, x: 0, y: 0.8)
                .frame(width: 38, height: 38)
                .background(
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        medal.light.opacity(colorScheme == .dark ? 0.78 : 0.96),
                                        medal.foreground.opacity(colorScheme == .dark ? 0.88 : 0.94),
                                        medal.deep.opacity(colorScheme == .dark ? 0.82 : 0.90)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.54), lineWidth: 1.0)
                            .padding(2.5)
                    }
                )
                .overlay(Circle().stroke(medal.border.opacity(colorScheme == .dark ? 0.52 : 0.72), lineWidth: 0.9))
                .shadow(color: medal.deep.opacity(colorScheme == .dark ? 0.24 : 0.16), radius: 6, x: 0, y: 2)
            )
        }

        return AnyView(
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.foreground)
                .frame(width: 28, height: 28)
                .background(circleBackground(for: palette), in: Circle())
                .overlay(Circle().stroke(borderColor(for: palette, isTopRank: false), lineWidth: 0.75))
        )
    }

    private var updatedTag: some View {
        Text("已更新")
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.orange.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 0.6)
            )
    }

    private func rowBackground(for item: TodayIncomeRankItem) -> some ShapeStyle {
        let palette = rankPalette(for: item)
        if item.rank <= 3 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        cardBackgroundColor(for: palette, isTopRank: true),
                        palette.foreground.opacity(colorScheme == .dark ? 0.18 : 0.095),
                        PanelDesign.cardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    cardBackgroundColor(for: palette, isTopRank: false),
                    PanelDesign.cardBackground
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func rowBorder(for item: TodayIncomeRankItem) -> some View {
        let palette = rankPalette(for: item)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                borderColor(for: palette, isTopRank: item.rank <= 3),
                lineWidth: item.rank <= 3 ? 1.05 : 0.75
            )
    }

    private func rankPalette(for item: TodayIncomeRankItem) -> TodayIncomeRankPalette {
        let isLoss = rankingMode == .loss
        switch item.rank {
        case 1:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255),
                    deep: Color(red: 3 / 255, green: 84 / 255, blue: 63 / 255),
                    background: Color(red: 220 / 255, green: 252 / 255, blue: 231 / 255),
                    border: Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 166 / 255, green: 31 / 255, blue: 23 / 255),
                    deep: Color(red: 122 / 255, green: 28 / 255, blue: 20 / 255),
                    background: Color(red: 255 / 255, green: 224 / 255, blue: 219 / 255),
                    border: Color(red: 240 / 255, green: 68 / 255, blue: 56 / 255)
                )
        case 2:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255),
                    deep: Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255),
                    background: Color(red: 229 / 255, green: 253 / 255, blue: 237 / 255),
                    border: Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255),
                    deep: Color(red: 166 / 255, green: 31 / 255, blue: 23 / 255),
                    background: Color(red: 255 / 255, green: 234 / 255, blue: 228 / 255),
                    border: Color(red: 249 / 255, green: 112 / 255, blue: 102 / 255)
                )
        case 3:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 18 / 255, green: 183 / 255, blue: 106 / 255),
                    deep: Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255),
                    background: Color(red: 237 / 255, green: 253 / 255, blue: 243 / 255),
                    border: Color(red: 167 / 255, green: 243 / 255, blue: 208 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255),
                    deep: Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255),
                    background: Color(red: 255 / 255, green: 241 / 255, blue: 236 / 255),
                    border: Color(red: 253 / 255, green: 162 / 255, blue: 155 / 255)
                )
        default:
            return isLoss
                ? TodayIncomeRankPalette(
                    foreground: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255),
                    deep: Color(red: 18 / 255, green: 183 / 255, blue: 106 / 255),
                    background: Color(red: 240 / 255, green: 253 / 255, blue: 244 / 255),
                    border: Color(red: 187 / 255, green: 247 / 255, blue: 208 / 255)
                )
                : TodayIncomeRankPalette(
                    foreground: Color(red: 239 / 255, green: 96 / 255, blue: 87 / 255),
                    deep: Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255),
                    background: Color(red: 255 / 255, green: 245 / 255, blue: 243 / 255),
                    border: Color(red: 254 / 255, green: 205 / 255, blue: 202 / 255)
                )
        }
    }

    private func cardBackgroundColor(for palette: TodayIncomeRankPalette, isTopRank: Bool) -> Color {
        if colorScheme == .dark {
            return palette.foreground.opacity(isTopRank ? 0.28 : 0.16)
        }
        return isTopRank ? palette.background : palette.background.opacity(0.86)
    }

    private func circleBackground(for palette: TodayIncomeRankPalette) -> Color {
        colorScheme == .dark ? palette.foreground.opacity(0.20) : palette.background
    }

    private func borderColor(for palette: TodayIncomeRankPalette, isTopRank: Bool) -> Color {
        if colorScheme == .dark {
            return palette.foreground.opacity(isTopRank ? 0.54 : 0.32)
        }
        return isTopRank ? palette.border.opacity(0.88) : palette.border.opacity(0.72)
    }

    private func medalPalette(for rank: Int) -> TodayIncomeRankMedalPalette {
        switch rank {
        case 1:
            return TodayIncomeRankMedalPalette(
                foreground: Color(red: 228 / 255, green: 163 / 255, blue: 45 / 255),
                deep: Color(red: 169 / 255, green: 101 / 255, blue: 20 / 255),
                light: Color(red: 255 / 255, green: 223 / 255, blue: 112 / 255),
                border: Color(red: 217 / 255, green: 157 / 255, blue: 45 / 255)
            )
        case 2:
            return TodayIncomeRankMedalPalette(
                foreground: Color(red: 147 / 255, green: 158 / 255, blue: 171 / 255),
                deep: Color(red: 96 / 255, green: 110 / 255, blue: 128 / 255),
                light: Color(red: 234 / 255, green: 238 / 255, blue: 243 / 255),
                border: Color(red: 157 / 255, green: 168 / 255, blue: 183 / 255)
            )
        case 3:
            return TodayIncomeRankMedalPalette(
                foreground: Color(red: 190 / 255, green: 111 / 255, blue: 52 / 255),
                deep: Color(red: 139 / 255, green: 73 / 255, blue: 36 / 255),
                light: Color(red: 242 / 255, green: 181 / 255, blue: 118 / 255),
                border: Color(red: 192 / 255, green: 112 / 255, blue: 56 / 255)
            )
        default:
            return TodayIncomeRankMedalPalette(
                foreground: .secondary,
                deep: .secondary,
                light: .secondary,
                border: .secondary
            )
        }
    }
}

