import SwiftUI

struct PortfolioPerformanceView: View {
    let portfolioStore: PortfolioStore
    let store: PortfolioPerformanceStore
    let betaFeaturesEnabled: Bool
    let onOpenJDFinanceSync: () -> Void
    let onNavigationChange: (
        HoldingPerformancePage,
        IncomeRankingMetric,
        PortfolioPerformanceRange,
        Date
    ) -> Void
    let onBack: () -> Void

    @AppStorage(AppPreferenceKey.hideHeaderAmounts) private var hidesAmounts = false
    @State private var page: HoldingPerformancePage
    @State private var rankingMetric: IncomeRankingMetric
    @State private var range: PortfolioPerformanceRange
    @State private var displayedMonth: Date

    init(
        portfolioStore: PortfolioStore,
        store: PortfolioPerformanceStore,
        initialPage: HoldingPerformancePage = HoldingPerformancePresentation.defaultPage,
        initialRankingMetric: IncomeRankingMetric = .amount,
        initialRange: PortfolioPerformanceRange = HoldingPerformancePresentation.defaultRange,
        initialDisplayedMonth: Date? = nil,
        betaFeaturesEnabled: Bool,
        onOpenJDFinanceSync: @escaping () -> Void,
        onNavigationChange: @escaping (
            HoldingPerformancePage,
            IncomeRankingMetric,
            PortfolioPerformanceRange,
            Date
        ) -> Void = { _, _, _, _ in },
        onBack: @escaping () -> Void
    ) {
        self.portfolioStore = portfolioStore
        self.store = store
        self.betaFeaturesEnabled = betaFeaturesEnabled
        self.onOpenJDFinanceSync = onOpenJDFinanceSync
        self.onNavigationChange = onNavigationChange
        self.onBack = onBack
        _page = State(initialValue: initialPage)
        _rankingMetric = State(initialValue: initialRankingMetric)
        _range = State(initialValue: initialRange)
        _displayedMonth = State(
            initialValue: initialDisplayedMonth
                ?? store.snapshot.days.last
                .flatMap { DateOnlyFormatter.parse($0.date) }
                ?? .now
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "持仓收益",
                subtitle: headerSubtitle,
                accessoryText: hasVisibleEstimate ? "含估值" : nil,
                accessoryColor: .orange,
                actionSystemImage: showsJDFinanceCompletionAction ? "arrow.down.circle" : nil,
                actionTitle: showsJDFinanceCompletionAction ? "京东补全" : nil,
                actionTint: .blue,
                actionHelp: showsJDFinanceCompletionAction ? "从京东金融补全历史收益" : nil,
                onAction: showsJDFinanceCompletionAction ? onOpenJDFinanceSync : nil,
                onClose: onBack
            )

            Divider()

            VStack(spacing: 10) {
                PanelSegmentedPicker(
                    values: HoldingPerformancePage.allCases,
                    selection: $page,
                    title: { $0.title },
                    accessibilityLabelText: "持仓收益模块"
                )
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PanelDesign.panelBackground)
        .onChange(of: page) { _, newValue in
            onNavigationChange(newValue, rankingMetric, range, displayedMonth)
        }
        .onChange(of: rankingMetric) { _, newValue in
            onNavigationChange(page, newValue, range, displayedMonth)
        }
        .onChange(of: range) { _, newValue in
            onNavigationChange(page, rankingMetric, newValue, displayedMonth)
        }
        .onChange(of: displayedMonth) { _, newValue in
            onNavigationChange(page, rankingMetric, range, newValue)
        }
    }

    private var showsJDFinanceCompletionAction: Bool {
        HoldingPerformancePresentation.showsJDFinanceCompletionAction(
            page: page,
            betaFeaturesEnabled: betaFeaturesEnabled,
            accountKind: portfolioStore.accountKind
        )
    }

    private var headerSubtitle: String {
        if page == .ranking {
            let holdingCount = portfolioStore.snapshot.funds.count {
                $0.status == .holding && ($0.isIncomeActive ?? true)
            }
            return HoldingPerformancePresentation.rankingSubtitle(
                holdingCount: holdingCount,
                holdingIncome: portfolioStore.snapshot.holdingIncome,
                holdingIncomeRate: portfolioStore.snapshot.holdingIncomeRate,
                metric: rankingMetric,
                hidesAmounts: hidesAmounts,
                accountKind: portfolioStore.accountKind
            )
        }
        guard let start = store.snapshot.trackingStartDate else { return "按日记录组合净收益" }
        return "自 \(start) 起 · \(store.snapshot.days.count) 个记录日"
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .calendar:
            performancePageContent
        case .ranking:
            TodayIncomeRankingPanelView(
                store: portfolioStore,
                kind: .holding,
                metric: rankingMetric,
                onClose: {},
                isEmbedded: true,
                metricSelection: $rankingMetric
            )
        }
    }

    @ViewBuilder
    private var performancePageContent: some View {
        if store.snapshot.days.isEmpty {
            VStack(spacing: 12) {
                if let lastError = store.lastError {
                    performanceErrorBanner(lastError)
                }
                ContentUnavailableView {
                    Label("暂无收益记录", systemImage: "calendar.badge.clock")
                } description: {
                    Text("点击右上角“京东补全”读取过去收益；之后也会从首次有效刷新开始按日记录。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if let lastError = store.lastError {
                        performanceErrorBanner(lastError)
                    }
                    summaryRow
                    curveContent
                    calendarContent
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    private var allPoints: [PortfolioPerformancePoint] {
        PortfolioPerformanceSeries.cumulativePoints(in: store.snapshot)
    }

    private var hasVisibleEstimate: Bool {
        switch page {
        case .ranking:
            false
        case .calendar:
            visiblePoints.contains { $0.day.status == .estimated }
                || PortfolioPerformanceCalendar.summary(
                    in: store.snapshot,
                    monthContaining: displayedMonth
                ).estimatedDays > 0
        }
    }

    private var visiblePoints: [PortfolioPerformancePoint] {
        PortfolioPerformanceSeries.points(
            in: store.snapshot,
            range: range,
            through: store.snapshot.days.last.flatMap { DateOnlyFormatter.parse($0.date) } ?? .now
        )
    }

    private var summaryRow: some View {
        let summary = HoldingPerformancePresentation.summary(
            portfolio: portfolioStore.snapshot,
            performance: store.snapshot
        )
        let latestDetail = [
            summary.latestDate.map(shortDateText),
            summary.latestReturnRate.map { MoneyFormatter.percent($0, signed: true) }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("当前总金额")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(totalAmountText(summary.totalAmount))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("截至 \(summary.asOfDate)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 0) {
                PerformanceSummaryMetric(
                    title: "最近收益",
                    value: amountText(summary.latestProfit),
                    color: PortfolioPerformanceSemanticColor.color(for: summary.latestProfit),
                    detail: latestDetail.isEmpty ? "--" : latestDetail,
                    detailColor: summary.latestReturnRate.map {
                        PortfolioPerformanceSemanticColor.color(for: $0)
                    }
                )
                summaryDivider
                PerformanceSummaryMetric(
                    title: "持有收益",
                    value: holdingIncomeText(summary.holdingIncome),
                    color: PortfolioPerformanceSemanticColor.color(for: summary.holdingIncome),
                    detail: MoneyFormatter.percent(summary.holdingIncomeRate, signed: true),
                    detailColor: PortfolioPerformanceSemanticColor.color(for: summary.holdingIncomeRate)
                )
                summaryDivider
                PerformanceSummaryMetric(
                    title: "累计收益",
                    value: amountText(summary.cumulativeProfit),
                    color: PortfolioPerformanceSemanticColor.color(for: summary.cumulativeProfit),
                    detail: summary.trackingStartDate.map { "自 \($0) 起" } ?? "--",
                    detailColor: .secondary
                )
            }
        }
        .padding(10)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
        .accessibilityElement(children: .contain)
    }

    private var summaryDivider: some View {
        Divider()
            .frame(height: 48)
            .padding(.horizontal, 7)
    }

    private var curveContent: some View {
        PanelSection(title: "累计收益走势") {
            VStack(spacing: 8) {
                PanelSegmentedPicker(
                    values: PortfolioPerformanceRange.allCases,
                    selection: $range,
                    title: { $0.title },
                    accessibilityLabelText: "收益曲线时间范围"
                )

                if visiblePoints.isEmpty {
                    ContentUnavailableView("该区间暂无记录", systemImage: "chart.xyaxis.line")
                        .frame(height: 133)
                } else {
                    PortfolioCumulativeProfitChart(points: visiblePoints, hidesAmounts: hidesAmounts)
                        .frame(height: 133)

                    HStack {
                        Text(visiblePoints.first?.day.date ?? "--")
                        Spacer()
                        Text(visiblePoints.last?.day.date ?? "--")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var calendarContent: some View {
        let grid = PortfolioPerformanceCalendar.grid(monthContaining: displayedMonth)
        let summary = PortfolioPerformanceCalendar.summary(in: store.snapshot, monthContaining: displayedMonth)
        let records = Dictionary(uniqueKeysWithValues: summary.days.map { ($0.date, $0) })

        return PanelSection(title: "每日盈亏日历") {
            VStack(spacing: 10) {
                HStack {
                    monthButton(systemImage: "chevron.left", offset: -1)
                    Spacer()
                    Text(PortfolioPerformanceCalendar.monthTitle(for: displayedMonth))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    monthButton(systemImage: "chevron.right", offset: 1)
                }

                HStack(spacing: 8) {
                    Label(amountText(summary.totalProfit), systemImage: "sum")
                        .foregroundStyle(PortfolioPerformanceSemanticColor.color(for: summary.totalProfit))
                    Spacer()
                    Text("涨 \(summary.riseDays) 天")
                        .foregroundStyle(PortfolioPerformanceSemanticColor.positive)
                    Text("跌 \(summary.fallDays) 天")
                        .foregroundStyle(PortfolioPerformanceSemanticColor.negative)
                    if summary.estimatedDays > 0 {
                        Text("估值 \(summary.estimatedDays) 天")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 2)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { title in
                        Text(title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(Array(grid.cells.enumerated()), id: \.offset) { _, date in
                        PerformanceCalendarCell(date: date, record: date.flatMap { records[$0] }, hidesAmounts: hidesAmounts)
                    }
                }

                if summary.days.isEmpty {
                    Text("本月暂无收益记录")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func monthButton(systemImage: String, offset: Int) -> some View {
        Button {
            displayedMonth = PortfolioPerformanceCalendar.shiftedMonth(from: displayedMonth, by: offset)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(PanelDesign.buttonBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(PanelDesign.border(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!canShiftMonth(by: offset))
        .accessibilityLabel(offset < 0 ? "上个月" : "下个月")
        .help(offset < 0 ? "上个月" : "下个月")
    }

    private func canShiftMonth(by offset: Int) -> Bool {
        let target = PortfolioPerformanceCalendar.shiftedMonth(from: displayedMonth, by: offset)
        guard let targetStart = PortfolioPerformanceCalendar.monthStart(containing: target) else { return false }

        let firstMonth = store.snapshot.days.first
            .flatMap { DateOnlyFormatter.parse($0.date) }
            .flatMap { PortfolioPerformanceCalendar.monthStart(containing: $0) }
        let latestRecordMonth = store.snapshot.days.last
            .flatMap { DateOnlyFormatter.parse($0.date) }
            .flatMap { PortfolioPerformanceCalendar.monthStart(containing: $0) }
        let currentMonth = PortfolioPerformanceCalendar.monthStart(containing: .now)

        if let firstMonth, targetStart < firstMonth { return false }
        let upperBound = [latestRecordMonth, currentMonth].compactMap { $0 }.max()
        if let upperBound, targetStart > upperBound { return false }
        return true
    }

    private func performanceErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(PanelDesign.warningAccent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.warningBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(PanelDesign.warningBorder, lineWidth: 0.7)
            )
    }

    private func amountText(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.money(value, signed: true)
    }

    private func holdingIncomeText(_ value: Double) -> String {
        hidesAmounts
            ? "••••"
            : MoneyFormatter.holdingIncome(value, accountKind: portfolioStore.accountKind)
    }

    private func totalAmountText(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.money(value)
    }

    private func shortDateText(_ date: String) -> String {
        date.count >= 5 ? String(date.suffix(5)) : date
    }
}

struct HoldingPerformanceSummary: Equatable {
    var totalAmount: Double
    var asOfDate: String
    var latestDate: String?
    var latestProfit: Double
    var latestReturnRate: Double?
    var holdingIncome: Double
    var holdingIncomeRate: Double
    var cumulativeProfit: Double
    var trackingStartDate: String?
}

struct HoldingPerformanceEntry: Equatable {
    var page: HoldingPerformancePage
    var rankingMetric: IncomeRankingMetric
    var range: PortfolioPerformanceRange
}

enum HoldingPerformancePresentation {
    static let defaultPage: HoldingPerformancePage = .calendar
    static let defaultRange: PortfolioPerformanceRange = .threeMonths

    static func defaultEntry(rankingMetric: IncomeRankingMetric) -> HoldingPerformanceEntry {
        HoldingPerformanceEntry(
            page: defaultPage,
            rankingMetric: rankingMetric,
            range: defaultRange
        )
    }

    static func summary(
        portfolio: PortfolioSnapshot,
        performance: PortfolioPerformanceSnapshot
    ) -> HoldingPerformanceSummary {
        let normalized = PortfolioPerformanceRecorder.normalized(performance)
        let latest = normalized.days.last
        return HoldingPerformanceSummary(
            totalAmount: portfolio.totalAmount,
            asOfDate: DateOnlyFormatter.string(from: portfolio.updateTime),
            latestDate: latest?.date,
            latestProfit: latest?.profit ?? 0,
            latestReturnRate: latest?.returnRate,
            holdingIncome: portfolio.holdingIncome,
            holdingIncomeRate: portfolio.holdingIncomeRate,
            cumulativeProfit: normalized.days.reduce(0) { $0 + $1.profit },
            trackingStartDate: normalized.trackingStartDate ?? normalized.days.first?.date
        )
    }

    static func showsJDFinanceCompletionAction(
        page: HoldingPerformancePage,
        betaFeaturesEnabled: Bool,
        accountKind: PortfolioAccountKind = .offExchange
    ) -> Bool {
        accountKind == .offExchange && betaFeaturesEnabled && page != .ranking
    }

    static func rankingSubtitle(
        holdingCount: Int,
        holdingIncome: Double,
        holdingIncomeRate: Double,
        metric: IncomeRankingMetric,
        hidesAmounts: Bool,
        accountKind: PortfolioAccountKind = .offExchange
    ) -> String {
        let value: String
        switch metric {
        case .amount:
            value = hidesAmounts
                ? "••••"
                : MoneyFormatter.holdingIncome(holdingIncome, accountKind: accountKind)
        case .rate:
            value = MoneyFormatter.percent(holdingIncomeRate, signed: true)
        }
        return "\(holdingCount) 只持仓 · \(value)"
    }
}

private enum PortfolioPerformanceSemanticColor {
    static let positive = Color.red
    static let negative = Color.fundPulseGreen

    static func color(for value: Double) -> Color {
        color(for: PortfolioPerformanceChartTone(value: value))
    }

    static func color(for tone: PortfolioPerformanceChartTone) -> Color {
        switch tone {
        case .positive:
            positive
        case .negative:
            negative
        case .neutral:
            .secondary
        }
    }
}

enum HoldingPerformancePage: String, CaseIterable, Identifiable {
    case calendar
    case ranking

    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar:
            "收益日历"
        case .ranking:
            "持仓收益排行"
        }
    }
}

private struct PerformanceSummaryMetric: View {
    let title: String
    let value: String
    let color: Color
    var detail: String? = nil
    var detailColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle((detailColor ?? color).opacity(0.84))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

private struct PortfolioCumulativeProfitChart: View {
    let points: [PortfolioPerformancePoint]
    let hidesAmounts: Bool
    @State private var hoveredIndex: Int?

    var body: some View {
        let values = points.map(\.cumulativeProfit)
        let scale = PortfolioPerformanceChartScale(values: values)
        let axisLabels = PortfolioPerformanceChartAxisLabels(values: values, scale: scale)

        VStack(spacing: 4) {
            hoverReadout

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = size.height * fraction
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(.secondary.opacity(0.13)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                    }

                    let location: (Int, Double) -> CGPoint = { index, value in
                        let x = points.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(points.count - 1)
                        let y = size.height * CGFloat(scale.normalizedY(for: value))
                        return CGPoint(x: x, y: y)
                    }

                    let zeroY = size.height * CGFloat(scale.normalizedY(for: 0))
                    var zeroLine = Path()
                    zeroLine.move(to: CGPoint(x: 0, y: zeroY))
                    zeroLine.addLine(to: CGPoint(x: size.width, y: zeroY))
                    context.stroke(
                        zeroLine,
                        with: .color(.secondary.opacity(0.48)),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )

                    if points.count == 1 {
                        let center = location(0, points[0].cumulativeProfit)
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                            with: .color(PortfolioPerformanceSemanticColor.color(for: points[0].cumulativeProfit))
                        )
                    } else {
                        for index in 1..<points.count {
                            let startValue = points[index - 1].cumulativeProfit
                            let endValue = points[index].cumulativeProfit
                            let startPoint = location(index - 1, startValue)
                            let endPoint = location(index, endValue)
                            for portion in PortfolioPerformanceChartColor.segmentPortions(
                                from: startValue,
                                to: endValue
                            ) {
                                var segment = Path()
                                segment.move(to: interpolatedPoint(
                                    from: startPoint,
                                    to: endPoint,
                                    fraction: portion.startFraction
                                ))
                                segment.addLine(to: interpolatedPoint(
                                    from: startPoint,
                                    to: endPoint,
                                    fraction: portion.endFraction
                                ))
                                context.stroke(
                                    segment,
                                    with: .color(color(for: portion.tone)),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 15)

                GeometryReader { geometry in
                    let plotHeight = max(geometry.size.height - 30, 1)
                    let zeroY = 15 + plotHeight * CGFloat(scale.normalizedY(for: 0))
                    Text("¥0")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(PanelDesign.cardBackground.opacity(0.92), in: Capsule())
                        .position(x: 14, y: min(max(zeroY - 8, 8), geometry.size.height - 8))
                }
                .allowsHitTesting(false)

                VStack(alignment: .leading) {
                    if let maximum = axisLabels.maximum {
                        Text(axisText(maximum))
                    }
                    Spacer()
                    if let minimum = axisLabels.minimum {
                        Text(axisText(minimum))
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    hoverLayer(in: geometry, scale: scale)
                }
            }
        }
        .onChange(of: points.map(\.id)) { _, _ in
            hoveredIndex = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("累计收益曲线")
        .accessibilityValue(chartAccessibilityValue)
        .accessibilityHint("将鼠标移动到曲线上可查看日期、收益和收益率")
    }

    private var hoverReadout: some View {
        HStack(spacing: 9) {
            if let hoveredIndex, points.indices.contains(hoveredIndex) {
                let point = points[hoveredIndex]
                Text(point.day.date)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text("收益 \(hoverProfitText(point.day.profit))")
                    .foregroundStyle(PortfolioPerformanceSemanticColor.color(for: point.day.profit))
                Text("收益率 \(hoverReturnRateText(point.day.returnRate))")
                    .foregroundStyle(hoverReturnRateColor(point.day.returnRate))
            } else {
                Image(systemName: "cursorarrow")
                Text("移动鼠标查看单日收益")
            }
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 6))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hoverLayer(
        in geometry: GeometryProxy,
        scale: PortfolioPerformanceChartScale
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if let hoveredIndex, points.indices.contains(hoveredIndex) {
                let point = points[hoveredIndex]
                let pointX = points.count == 1
                    ? geometry.size.width / 2
                    : geometry.size.width * CGFloat(hoveredIndex) / CGFloat(points.count - 1)
                let plotHeight = max(geometry.size.height - 30, 1)
                let pointY = 15 + plotHeight * CGFloat(scale.normalizedY(for: point.cumulativeProfit))

                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: pointX, y: 15))
                        path.addLine(to: CGPoint(x: pointX, y: geometry.size.height - 15))
                    }
                    .stroke(
                        .secondary.opacity(0.48),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )

                    Circle()
                        .fill(PortfolioPerformanceSemanticColor.color(for: point.cumulativeProfit))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(PanelDesign.cardBackground, lineWidth: 2))
                        .position(x: pointX, y: pointY)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let normalizedX = geometry.size.width > 0
                    ? Double(location.x / geometry.size.width)
                    : .nan
                let index = PortfolioPerformanceChartHover.nearestIndex(
                    pointCount: points.count,
                    normalizedX: normalizedX
                )
                if hoveredIndex != index {
                    hoveredIndex = index
                }
            case .ended:
                hoveredIndex = nil
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func hoverProfitText(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.money(value, signed: true)
    }

    private func hoverReturnRateText(_ value: Double?) -> String {
        value.map { MoneyFormatter.percent($0, signed: true) } ?? "--"
    }

    private func hoverReturnRateColor(_ value: Double?) -> Color {
        value.map { PortfolioPerformanceSemanticColor.color(for: $0) } ?? .secondary
    }

    private func axisText(_ value: Double) -> String {
        hidesAmounts ? "••••" : MoneyFormatter.money(value, signed: true)
    }

    private func interpolatedPoint(
        from start: CGPoint,
        to end: CGPoint,
        fraction: Double
    ) -> CGPoint {
        let fraction = CGFloat(fraction)
        return CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    private func color(for tone: PortfolioPerformanceChartTone) -> Color {
        PortfolioPerformanceSemanticColor.color(for: tone)
    }

    private var chartAccessibilityValue: String {
        if let hoveredIndex, points.indices.contains(hoveredIndex) {
            let point = points[hoveredIndex]
            let profit = hidesAmounts
                ? "金额已隐藏"
                : MoneyFormatter.money(point.day.profit, signed: true)
            let returnRate = point.day.returnRate.map {
                MoneyFormatter.percent($0, signed: true)
            } ?? "暂无数据"
            return "\(point.day.date)，当日收益 \(profit)，收益率 \(returnRate)"
        }
        guard let first = points.first, let last = points.last else { return "暂无数据" }
        let amount = hidesAmounts ? "金额已隐藏" : MoneyFormatter.money(last.cumulativeProfit, signed: true)
        return "从 \(first.day.date) 到 \(last.day.date)，累计收益 \(amount)"
    }
}

private struct PerformanceCalendarCell: View {
    let date: String?
    let record: PortfolioPerformanceDay?
    let hidesAmounts: Bool

    var body: some View {
        Group {
            if let date {
                VStack(spacing: 3) {
                    HStack(spacing: 2) {
                        Text(String(Int(date.suffix(2)) ?? 0))
                        if record?.status == .estimated {
                            Circle().fill(.orange).frame(width: 4, height: 4)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))

                    Text(record.map { compactAmount($0.profit) } ?? "—")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(record.map { PortfolioPerformanceSemanticColor.color(for: $0.profit) } ?? .secondary.opacity(0.6))

                    Text(returnRateText)
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .foregroundStyle(returnRateColor)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(cellColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(PanelDesign.border(cornerRadius: 7))
                .accessibilityLabel(accessibilityText(date))
            } else {
                Color.clear.frame(height: 50)
            }
        }
    }

    private var cellColor: Color {
        guard let record else { return PanelDesign.inputBackground.opacity(0.42) }
        return PortfolioPerformanceSemanticColor.color(for: record.profit).opacity(0.09)
    }

    private func compactAmount(_ value: Double) -> String {
        guard !hidesAmounts else { return "••" }
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        return sign + abs(value).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    private var returnRateText: String {
        guard let record else { return "" }
        return record.returnRate.map { MoneyFormatter.percent($0, signed: true) } ?? "--"
    }

    private var returnRateColor: Color {
        guard let returnRate = record?.returnRate else { return .secondary.opacity(0.6) }
        return PortfolioPerformanceSemanticColor.color(for: returnRate).opacity(0.84)
    }

    private func accessibilityText(_ date: String) -> String {
        guard let record else { return "\(date)，无记录" }
        let amount = hidesAmounts ? "金额已隐藏" : MoneyFormatter.money(record.profit, signed: true)
        let returnRate = record.returnRate.map {
            "收益率 \(MoneyFormatter.percent($0, signed: true))"
        } ?? "收益率暂无数据"
        return "\(date)，\(amount)，\(returnRate)，\(record.status.title)，\(record.source.title)"
    }
}
