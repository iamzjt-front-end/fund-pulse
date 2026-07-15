import SwiftUI

struct PortfolioPerformanceView: View {
    let portfolioStore: PortfolioStore
    let store: PortfolioPerformanceStore
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
        initialPage: HoldingPerformancePage = .ranking,
        initialRankingMetric: IncomeRankingMetric = .amount,
        initialRange: PortfolioPerformanceRange = .threeMonths,
        initialDisplayedMonth: Date? = nil,
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
                title: "持有收益",
                subtitle: headerSubtitle,
                accessoryText: hasVisibleEstimate ? "含估值" : nil,
                accessoryColor: .orange,
                actionSystemImage: page == .ranking ? nil : "arrow.down.circle",
                actionTitle: page == .ranking ? nil : "京东补全",
                actionTint: .blue,
                actionHelp: "从京东金融补全历史收益",
                onAction: page == .ranking ? nil : onOpenJDFinanceSync,
                onClose: onBack
            )

            Divider()

            VStack(spacing: 10) {
                PanelSegmentedPicker(
                    values: HoldingPerformancePage.allCases,
                    selection: $page,
                    title: { $0.title },
                    accessibilityLabelText: "持有收益模块"
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
                hidesAmounts: hidesAmounts
            )
        }
        guard let start = store.snapshot.trackingStartDate else { return "按日记录组合净收益" }
        return "自 \(start) 起 · \(store.snapshot.days.count) 个记录日"
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .ranking:
            TodayIncomeRankingPanelView(
                store: portfolioStore,
                kind: .holding,
                metric: rankingMetric,
                onClose: {},
                isEmbedded: true,
                metricSelection: $rankingMetric
            )
        case .curve, .calendar:
            performancePageContent
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
                    sourceSummary
                    if page == .curve {
                        curveContent
                    } else {
                        calendarContent
                    }
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
        case .curve:
            visiblePoints.contains { $0.day.status == .estimated }
        case .calendar:
            PortfolioPerformanceCalendar.summary(
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
        HStack(spacing: 8) {
            PerformanceMetric(
                title: "记录期累计收益",
                value: amountText(allPoints.last?.cumulativeProfit ?? 0),
                color: PortfolioPerformanceSemanticColor.color(for: allPoints.last?.cumulativeProfit ?? 0)
            )
            PerformanceMetric(
                title: "最近记录日",
                value: amountText(store.snapshot.days.last?.profit ?? 0),
                color: PortfolioPerformanceSemanticColor.color(for: store.snapshot.days.last?.profit ?? 0),
                detail: store.snapshot.days.last?.returnRate.map {
                    MoneyFormatter.percent($0, signed: true)
                }
            )
            PerformanceMetric(
                title: "记录天数",
                value: "\(store.snapshot.days.count)",
                color: .primary
            )
        }
    }

    @ViewBuilder
    private var sourceSummary: some View {
        let jdCount = store.snapshot.days.count { $0.source == .jdFinance }
        if jdCount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.icloud")
                Text("京东补全 \(jdCount) 天")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if store.snapshot.days.count > jdCount {
                    Text("· 本地记录 \(store.snapshot.days.count - jdCount) 天")
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                if let through = store.snapshot.jdFinanceSync?.coveredThrough {
                    Text("截至 \(through)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(PanelDesign.inputBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    private var curveContent: some View {
        PanelSection(title: "累计收益曲线") {
            VStack(spacing: 10) {
                PanelSegmentedPicker(
                    values: PortfolioPerformanceRange.allCases,
                    selection: $range,
                    title: { $0.title },
                    accessibilityLabelText: "收益曲线时间范围"
                )

                if visiblePoints.isEmpty {
                    ContentUnavailableView("该区间暂无记录", systemImage: "chart.xyaxis.line")
                        .frame(height: 210)
                } else {
                    PortfolioCumulativeProfitChart(points: visiblePoints, hidesAmounts: hidesAmounts)
                        .frame(height: 220)

                    HStack {
                        Text(visiblePoints.first?.day.date ?? "--")
                        Spacer()
                        chartLegendItem(
                            "正收益",
                            color: PortfolioPerformanceSemanticColor.positive
                        )
                        chartLegendItem(
                            "负收益",
                            color: PortfolioPerformanceSemanticColor.negative
                        )
                        Spacer()
                        Text(visiblePoints.last?.day.date ?? "--")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chartLegendItem(_ title: String, color: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .accessibilityElement(children: .combine)
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
}

enum HoldingPerformancePresentation {
    static func rankingSubtitle(
        holdingCount: Int,
        holdingIncome: Double,
        holdingIncomeRate: Double,
        metric: IncomeRankingMetric,
        hidesAmounts: Bool
    ) -> String {
        let value: String
        switch metric {
        case .amount:
            value = hidesAmounts ? "••••" : MoneyFormatter.money(holdingIncome, signed: true)
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
    case ranking
    case curve
    case calendar

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ranking:
            "持有收益排行"
        case .curve:
            "收益曲线"
        case .calendar:
            "收益日历"
        }
    }
}

private struct PerformanceMetric: View {
    let title: String
    let value: String
    let color: Color
    var detail: String? = nil

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
                    .foregroundStyle(color.opacity(0.84))
                    .monospacedDigit()
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }
}

private struct PortfolioCumulativeProfitChart: View {
    let points: [PortfolioPerformancePoint]
    let hidesAmounts: Bool

    var body: some View {
        let values = points.map(\.cumulativeProfit)
        let scale = PortfolioPerformanceChartScale(values: values)
        let axisLabels = PortfolioPerformanceChartAxisLabels(values: values, scale: scale)

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
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("累计收益曲线")
        .accessibilityValue(chartAccessibilityValue)
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
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(cellColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(PanelDesign.border(cornerRadius: 7))
                .accessibilityLabel(accessibilityText(date))
            } else {
                Color.clear.frame(height: 42)
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

    private func accessibilityText(_ date: String) -> String {
        guard let record else { return "\(date)，无记录" }
        let amount = hidesAmounts ? "金额已隐藏" : MoneyFormatter.money(record.profit, signed: true)
        return "\(date)，\(amount)，\(record.status.title)，\(record.source.title)"
    }
}
