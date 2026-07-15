import SwiftUI

struct SampleExperienceView: View {
    let experience: SampleExperience
    let onClose: () -> Void

    @State private var section: SampleExperienceSection = .portfolio
    @State private var selectedPointID: Date?
    @State private var visibleMonth: Date

    init(
        experience: SampleExperience = SampleExperienceFactory.make(),
        onClose: @escaping () -> Void = {}
    ) {
        self.experience = experience
        self.onClose = onClose
        let calendar = Self.chinaCalendar
        let lastDate = experience.dailyPerformance.last?.date ?? experience.generatedAt
        _visibleMonth = State(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: lastDate)) ?? lastDate)
        _selectedPointID = State(initialValue: experience.dailyPerformance.last?.date)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "sparkles.rectangle.stack.fill",
                title: "组合体验",
                subtitle: "虚构数据 · 可自由查看",
                accessoryText: "示例数据",
                accessoryColor: .orange,
                onClose: onClose
            )

            VStack(spacing: 10) {
                sampleNotice
                PanelSegmentedPicker(
                    values: SampleExperienceSection.allCases,
                    selection: $section,
                    title: \SampleExperienceSection.title,
                    tint: .orange
                )

                Group {
                    switch section {
                    case .portfolio:
                        portfolioContent
                    case .curve:
                        curveContent
                    case .calendar:
                        calendarContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(PanelDesign.panelBackground)
    }

    private var sampleNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill")
            Text("以下内容仅用于体验，不联网，也不会写入 portfolio.json 或真实收益历史。")
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.7)
        )
    }

    private var portfolioContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    sampleMetric(
                        title: "总资产",
                        value: MoneyFormatter.money(experience.portfolio.totalAmount, signed: false),
                        tone: .primary
                    )
                    sampleMetric(
                        title: "累计收益",
                        value: MoneyFormatter.money(experience.portfolio.holdingIncome, signed: true),
                        tone: toneColor(experience.portfolio.holdingIncome)
                    )
                    sampleMetric(
                        title: "今日收益",
                        value: MoneyFormatter.money(experience.portfolio.todayIncome, signed: true),
                        tone: toneColor(experience.portfolio.todayIncome)
                    )
                }

                PanelSection(title: "示例组合") {
                    VStack(spacing: 0) {
                        ForEach(Array(experience.portfolio.funds.enumerated()), id: \.element.id) { index, fund in
                            sampleFundRow(fund)
                            if index < experience.portfolio.funds.count - 1 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var curveContent: some View {
        let selected = selectedPoint
        return ScrollView {
            VStack(spacing: 10) {
                PanelSection(title: "近 90 天累计收益") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.map { MoneyFormatter.money($0.cumulativeIncome, signed: true) } ?? "--")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(toneColor(selected?.cumulativeIncome ?? 0))
                                Text(selected.map { Self.fullDateFormatter.string(from: $0.date) } ?? "拖动曲线查看每日数据")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let selected {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("当日 \(MoneyFormatter.money(selected.dailyIncome, signed: true))")
                                        .foregroundStyle(toneColor(selected.dailyIncome))
                                    Text(MoneyFormatter.percent(selected.dailyIncomeRate, signed: true))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                            }
                        }

                        SampleIncomeChart(
                            points: experience.dailyPerformance,
                            selectedID: $selectedPointID
                        )
                        .frame(height: 230)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                PanelSection(title: "每日盈亏日历") {
                    VStack(spacing: 9) {
                        HStack {
                            calendarNavigationButton(systemImage: "chevron.left", monthOffset: -1)
                            Spacer()
                            Text(Self.monthFormatter.string(from: visibleMonth))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            calendarNavigationButton(systemImage: "chevron.right", monthOffset: 1)
                        }

                        LazyVGrid(columns: calendarColumns, spacing: 5) {
                            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                                Text(weekday)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }

                            ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                                calendarCell(date)
                            }
                        }
                    }
                }

                if let selected = selectedPoint {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.fullDateFormatter.string(from: selected.date))
                                .font(.system(size: 11, weight: .semibold))
                            Text("累计 \(MoneyFormatter.money(selected.cumulativeIncome, signed: true))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(MoneyFormatter.money(selected.dailyIncome, signed: true))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(toneColor(selected.dailyIncome))
                            Text(MoneyFormatter.percent(selected.dailyIncomeRate, signed: true))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(PanelDesign.border(cornerRadius: 10))
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var selectedPoint: SampleDailyPerformance? {
        guard let selectedPointID else { return experience.dailyPerformance.last }
        return experience.dailyPerformance.first { Self.chinaCalendar.isDate($0.date, inSameDayAs: selectedPointID) }
            ?? experience.dailyPerformance.last
    }

    private func sampleMetric(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private func sampleFundRow(_ fund: FundPosition) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fund.name)
                    .font(.system(size: 11, weight: .semibold))
                Text(fund.code)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyFormatter.money(fund.currentAmount ?? 0, signed: false))
                    .font(.system(size: 11, weight: .semibold))
                Text(MoneyFormatter.money(fund.todayIncome, signed: true))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(toneColor(fund.todayIncome))
            }
            .monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private func calendarNavigationButton(systemImage: String, monthOffset: Int) -> some View {
        let target = Self.chinaCalendar.date(byAdding: .month, value: monthOffset, to: visibleMonth)
        let isEnabled = target.map(monthIsWithinSample) ?? false
        return Button {
            if let target {
                visibleMonth = target
                selectLastPoint(in: target)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    @ViewBuilder
    private func calendarCell(_ date: Date?) -> some View {
        if let date {
            let point = performanceByDay[Self.chinaCalendar.startOfDay(for: date)]
            let isSelected = selectedPointID.map { Self.chinaCalendar.isDate($0, inSameDayAs: date) } ?? false
            Button {
                if point != nil {
                    selectedPointID = date
                }
            } label: {
                VStack(spacing: 2) {
                    Text("\(Self.chinaCalendar.component(.day, from: date))")
                        .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    Text(point.map { compactIncome($0.dailyIncome) } ?? "")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(point.map { toneColor($0.dailyIncome) } ?? .secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    (point.map { toneColor($0.dailyIncome).opacity(0.09) } ?? Color.clear),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? Color.orange.opacity(0.75) : Color.secondary.opacity(point == nil ? 0.08 : 0.14), lineWidth: isSelected ? 1.2 : 0.6)
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(point == nil)
        } else {
            Color.clear.frame(height: 38)
        }
    }

    private var performanceByDay: [Date: SampleDailyPerformance] {
        Dictionary(
            uniqueKeysWithValues: experience.dailyPerformance.map {
                (Self.chinaCalendar.startOfDay(for: $0.date), $0)
            }
        )
    }

    private var calendarDays: [Date?] {
        let calendar = Self.chinaCalendar
        guard let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) else {
            return []
        }
        let mondayBasedLeading = (calendar.component(.weekday, from: firstDay) + 5) % 7
        var days = Array<Date?>(repeating: nil, count: mondayBasedLeading)
        days.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        })
        while !days.count.isMultiple(of: 7) {
            days.append(nil)
        }
        return days
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    }

    private func monthIsWithinSample(_ month: Date) -> Bool {
        guard let first = experience.dailyPerformance.first?.date,
              let last = experience.dailyPerformance.last?.date else { return false }
        let calendar = Self.chinaCalendar
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let start = calendar.date(from: components),
              let next = calendar.date(byAdding: .month, value: 1, to: start) else { return false }
        return next > first && start <= last
    }

    private func selectLastPoint(in month: Date) {
        let calendar = Self.chinaCalendar
        let matches = experience.dailyPerformance.filter {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
        selectedPointID = matches.last?.date
    }

    private func compactIncome(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(Int(value.rounded()))"
    }

    private func toneColor(_ value: Double) -> Color {
        if value > 0.005 { return .red }
        if value < -0.005 { return .green }
        return .secondary
    }

    private static var chinaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年 M月"
        return formatter
    }()
}

private enum SampleExperienceSection: String, CaseIterable, Identifiable {
    case portfolio
    case curve
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portfolio: "组合"
        case .curve: "收益曲线"
        case .calendar: "盈亏日历"
        }
    }
}

private struct SampleIncomeChart: View {
    let points: [SampleDailyPerformance]
    @Binding var selectedID: Date?

    var body: some View {
        GeometryReader { proxy in
            let scale = PortfolioPerformanceChartScale(values: points.map(\.cumulativeIncome))
            let zeroY = chartY(for: 0, size: proxy.size, scale: scale)
            ZStack(alignment: .topLeading) {
                chartGrid(size: proxy.size)
                    .stroke(Color.secondary.opacity(0.13), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))

                Path { path in
                    path.move(to: CGPoint(x: 8, y: zeroY))
                    path.addLine(to: CGPoint(x: proxy.size.width - 8, y: zeroY))
                }
                .stroke(
                    Color.secondary.opacity(0.48),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )

                if points.count == 1 {
                    let location = pointLocation(index: 0, size: proxy.size, scale: scale)
                    Circle()
                        .fill(color(for: PortfolioPerformanceChartTone(value: points[0].cumulativeIncome)))
                        .frame(width: 6, height: 6)
                        .position(location)
                } else if points.count > 1 {
                    ForEach(1..<points.count, id: \.self) { index in
                        let startValue = points[index - 1].cumulativeIncome
                        let endValue = points[index].cumulativeIncome
                        let start = pointLocation(index: index - 1, size: proxy.size, scale: scale)
                        let end = pointLocation(index: index, size: proxy.size, scale: scale)
                        let portions = PortfolioPerformanceChartColor.segmentPortions(
                            from: startValue,
                            to: endValue
                        )
                        ForEach(Array(portions.enumerated()), id: \.offset) { _, portion in
                            Path { path in
                                path.move(to: interpolatedPoint(
                                    from: start,
                                    to: end,
                                    fraction: portion.startFraction
                                ))
                                path.addLine(to: interpolatedPoint(
                                    from: start,
                                    to: end,
                                    fraction: portion.endFraction
                                ))
                            }
                            .stroke(
                                color(for: portion.tone),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                }

                Text("¥0")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .background(PanelDesign.cardBackground.opacity(0.92), in: Capsule())
                    .position(x: 22, y: min(max(zeroY - 8, 8), proxy.size.height - 8))

                if let selectedIndex, points.indices.contains(selectedIndex) {
                    let location = pointLocation(index: selectedIndex, size: proxy.size, scale: scale)
                    Path { path in
                        path.move(to: CGPoint(x: location.x, y: 4))
                        path.addLine(to: CGPoint(x: location.x, y: proxy.size.height - 18))
                    }
                    .stroke(Color.secondary.opacity(0.34), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))

                    Circle()
                        .fill(color(for: PortfolioPerformanceChartTone(
                            value: points[selectedIndex].cumulativeIncome
                        )))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .position(location)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !points.isEmpty else { return }
                        let width = max(proxy.size.width - 16, 1)
                        let progress = min(max((value.location.x - 8) / width, 0), 1)
                        let index = Int((progress * Double(max(points.count - 1, 0))).rounded())
                        selectedID = points[index].date
                    }
            )
            .accessibilityLabel("示例累计收益曲线")
            .accessibilityValue(selectedIndex.map { MoneyFormatter.money(points[$0].cumulativeIncome, signed: true) } ?? "")
        }
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return points.indices.last }
        return points.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: selectedID) }
    }

    private func chartGrid(size: CGSize) -> Path {
        Path { path in
            for row in 0 ... 3 {
                let y = 8 + (size.height - 28) * CGFloat(row) / 3
                path.move(to: CGPoint(x: 8, y: y))
                path.addLine(to: CGPoint(x: size.width - 8, y: y))
            }
        }
    }

    private func pointLocation(
        index: Int,
        size: CGSize,
        scale: PortfolioPerformanceChartScale
    ) -> CGPoint {
        let plotWidth = max(size.width - 16, 1)
        let x = 8 + plotWidth * CGFloat(index) / CGFloat(max(points.count - 1, 1))
        return CGPoint(
            x: x,
            y: chartY(for: points[index].cumulativeIncome, size: size, scale: scale)
        )
    }

    private func chartY(
        for value: Double,
        size: CGSize,
        scale: PortfolioPerformanceChartScale
    ) -> CGFloat {
        let plotHeight = max(size.height - 28, 1)
        return 8 + plotHeight * CGFloat(scale.normalizedY(for: value))
    }

    private func interpolatedPoint(
        from start: CGPoint,
        to end: CGPoint,
        fraction: Double
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * CGFloat(fraction),
            y: start.y + (end.y - start.y) * CGFloat(fraction)
        )
    }

    private func color(for tone: PortfolioPerformanceChartTone) -> Color {
        switch tone {
        case .positive:
            .red
        case .negative:
            .fundPulseGreen
        case .neutral:
            .secondary
        }
    }
}
