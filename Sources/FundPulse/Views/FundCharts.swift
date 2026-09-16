import AppKit
import SwiftUI

struct FundIntradayRateChart: View {
    let points: [FundIntradayRatePoint]

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?

    private static let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = chinaTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                yAxisLabels
                    .frame(width: 36, height: 108)

                GeometryReader { proxy in
                    ZStack {
                        gridLines(in: proxy.size)
                            .stroke(gridColor, lineWidth: 0.7)
                        zeroLine(in: proxy.size)
                            .stroke(zeroLineColor, style: StrokeStyle(lineWidth: 0.9, dash: [6, 5]))
                        chartBorder(in: proxy.size)
                            .stroke(borderColor, lineWidth: 0.75)

                        if renderedPoints.count >= 2 {
                            areaPath(in: proxy.size)
                                .fill(areaFill)
                            linePath(in: proxy.size)
                                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        } else if let point = renderedPoints.first {
                            singlePointPath(for: point, in: proxy.size)
                                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                            Circle()
                                .fill(lineColor)
                                .frame(width: 7, height: 7)
                                .overlay(
                                    Circle()
                                        .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.9 : 0.96), lineWidth: 1.4)
                                )
                                .position(pointPosition(for: point, in: proxy.size))
                        }

                        if let hoveredIndex,
                           renderedPoints.indices.contains(hoveredIndex) {
                            hoverOverlay(for: hoveredIndex, in: proxy.size)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            hoveredIndex = nearestIndex(for: location.x, width: proxy.size.width)
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
                }
                .frame(height: 108)
            }

            xAxisLabels
        }
        .accessibilityLabel("盘中预估实时涨跌走势图")
    }

    private var sortedPoints: [FundIntradayRatePoint] {
        points.sorted { $0.timestamp < $1.timestamp }
    }

    private var renderedPoints: [FundIntradayRatePoint] {
        sortedPoints
    }

    private var yAxisBounds: (min: Double, max: Double) {
        let rates = sortedPoints.map(\.rate)
        let rawMin = min(rates.min() ?? 0, 0)
        let rawMax = max(rates.max() ?? 0, 0)
        var minValue = floor(rawMin)
        var maxValue = ceil(rawMax)

        if minValue >= rawMin, rawMin < 0 {
            minValue -= 1
        }
        if maxValue <= rawMax, rawMax > 0 {
            maxValue += 1
        }

        if minValue == maxValue {
            minValue -= 0.5
            maxValue += 0.5
        }

        return (minValue, maxValue)
    }

    private var lineColor: Color {
        toneColor(for: sortedPoints.last?.rate ?? 0)
    }

    private var areaFill: LinearGradient {
        LinearGradient(
            colors: [
                lineColor.opacity(colorScheme == .dark ? 0.26 : 0.18),
                lineColor.opacity(colorScheme == .dark ? 0.08 : 0.035)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var gridColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.14)
    }

    private var zeroLineColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.38 : 0.32)
    }

    private var borderColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.16)
    }

    private var yAxisLabels: some View {
        let bounds = yAxisBounds
        return VStack(alignment: .trailing, spacing: 0) {
            Text(MoneyFormatter.percent(bounds.max, signed: true))
            Spacer()
            Text(MoneyFormatter.percent(bounds.min, signed: true))
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var xAxisLabels: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Spacer()
                .frame(width: 42)
            Text("09:30")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("11:30/13:00")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("15:00")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func gridLines(in size: CGSize) -> Path {
        Path { path in
            for ratio in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
                let x = size.width * ratio
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for ratio in [CGFloat(0), 1] {
                let y = size.height * ratio
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    private func zeroLine(in size: CGSize) -> Path {
        Path { path in
            let y = yPosition(for: 0, height: size.height)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
    }

    private func chartBorder(in size: CGSize) -> Path {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let points = renderedPoints
        return Path { path in
            for (index, point) in points.enumerated() {
                let position = pointPosition(for: point, in: size)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        let points = renderedPoints
        return Path { path in
            guard let first = points.first,
                  let last = points.last
            else {
                return
            }

            for (index, point) in points.enumerated() {
                let position = pointPosition(for: point, in: size)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }

            let zeroY = yPosition(for: 0, height: size.height)
            path.addLine(to: CGPoint(x: xPosition(for: last, width: size.width), y: zeroY))
            path.addLine(to: CGPoint(x: xPosition(for: first, width: size.width), y: zeroY))
            path.closeSubpath()
        }
    }

    private func singlePointPath(for point: FundIntradayRatePoint, in size: CGSize) -> Path {
        Path { path in
            let position = pointPosition(for: point, in: size)
            let startX: CGFloat
            let endX: CGFloat
            if position.x >= size.width / 2 {
                startX = max(0, position.x - 28)
                endX = position.x
            } else {
                startX = position.x
                endX = min(size.width, position.x + 28)
            }
            path.move(to: CGPoint(x: startX, y: position.y))
            path.addLine(to: CGPoint(x: endX, y: position.y))
        }
    }

    private func hoverOverlay(for index: Int, in size: CGSize) -> some View {
        let points = renderedPoints
        let point = points[index]
        let position = pointPosition(for: point, in: size)
        let xLabelX = min(max(position.x, 24), max(size.width - 24, 24))
        let yLabelY = min(max(position.y, 9), max(size.height - 9, 9))

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: position.x, y: 0))
                path.addLine(to: CGPoint(x: position.x, y: size.height))
                path.move(to: CGPoint(x: 0, y: position.y))
                path.addLine(to: CGPoint(x: size.width, y: position.y))
            }
            .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 0.9, dash: [4, 3]))

            Circle()
                .fill(lineColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.9 : 0.96), lineWidth: 1.4)
                )
                .position(position)

            hoverAxisLabel(MoneyFormatter.percent(point.rate, signed: true), width: 54)
                .position(x: -31, y: yLabelY)

            hoverAxisLabel(Self.timeFormatter.string(from: date(from: point.timestamp)), width: 42)
                .position(x: xLabelX, y: size.height - 10)
        }
        .allowsHitTesting(false)
    }

    private func hoverAxisLabel(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(lineColor)
            .frame(width: width, height: 18)
            .background(hoverAxisLabelBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(lineColor.opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 0.65)
            )
    }

    private var hoverAxisLabelBackground: Color {
        colorScheme == .dark
            ? PanelDesign.cardBackground.opacity(0.92)
            : Color.white.opacity(0.94)
    }

    private func pointPosition(for point: FundIntradayRatePoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: xPosition(for: point, width: size.width),
            y: yPosition(for: point.rate, height: size.height)
        )
    }

    private func xPosition(for point: FundIntradayRatePoint, width: CGFloat) -> CGFloat {
        sessionProgress(for: point.timestamp) * width
    }

    private func yPosition(for rate: Double, height: CGFloat) -> CGFloat {
        let bounds = yAxisBounds
        let range = bounds.max - bounds.min
        guard range > 0 else { return height / 2 }
        let clampedRate = min(max(rate, bounds.min), bounds.max)
        return CGFloat((bounds.max - clampedRate) / range) * height
    }

    private func sessionProgress(for timestamp: Int64) -> CGFloat {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = Self.chinaTimeZone

        let date = date(from: timestamp)
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double((components.hour ?? 0) * 60 + (components.minute ?? 0)) + Double(components.second ?? 0) / 60

        let morningOpen = 9.0 * 60 + 30
        let morningClose = 11.0 * 60 + 30
        let afternoonOpen = 13.0 * 60
        let afternoonClose = 15.0 * 60
        let activeMinutes = (morningClose - morningOpen) + (afternoonClose - afternoonOpen)

        if minute <= morningOpen {
            return 0
        }
        if minute <= morningClose {
            return CGFloat((minute - morningOpen) / activeMinutes)
        }
        if minute < afternoonOpen {
            return 0.5
        }
        if minute <= afternoonClose {
            return CGFloat((morningClose - morningOpen + minute - afternoonOpen) / activeMinutes)
        }
        return 1
    }

    private func nearestIndex(for x: CGFloat, width: CGFloat) -> Int? {
        let points = renderedPoints
        guard !points.isEmpty, width > 0 else { return nil }
        return points.indices.min { lhs, rhs in
            abs(xPosition(for: points[lhs], width: width) - x) < abs(xPosition(for: points[rhs], width: width) - x)
        }
    }

    private func date(from timestamp: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }
}

private let fundTrendCostReferenceColor = Color.blue

struct FundTrendMiniChart: View {
    let points: [FundNetValuePoint]
    let holdingCost: Double?

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                yAxisLabels
                    .frame(width: 42, height: 90)

                GeometryReader { proxy in
                    ZStack {
                        chartGrid
                        chartAxes
                        linePath(in: proxy.size)
                            .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        if let costReference = trendScale.costReference {
                            costReferenceOverlay(costReference, in: proxy.size)
                        }
                        if let hoveredIndex,
                           points.indices.contains(hoveredIndex) {
                            hoverOverlay(for: hoveredIndex, in: proxy.size)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            hoveredIndex = nearestIndex(for: location.x, width: proxy.size.width)
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
                }
                .frame(height: 90)
            }

            HStack {
                Spacer()
                    .frame(width: 48)
                Text(dateText(points.first?.timestamp))
                Spacer()
                Text(dateText(points.last?.timestamp))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var chartGrid: some View {
        GeometryReader { proxy in
            Path { path in
                let rows: [CGFloat] = [0, 0.5, 1]
                for row in rows {
                    let y = row * proxy.size.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
        }
    }

    private var chartAxes: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
            }
            .stroke(Color.secondary.opacity(0.24), lineWidth: 0.8)
        }
    }

    private var lineColor: Color {
        toneColor(for: points.last?.equityReturn ?? 0)
    }

    private var trendScale: FundNetValueTrendScale {
        FundNetValueTrendScale(
            pointValues: points.map(\.value),
            holdingCost: holdingCost
        )
    }

    private var yValueBounds: (min: Double, max: Double) {
        (trendScale.minimum, trendScale.maximum)
    }

    private var yAxisLabels: some View {
        let bounds = yValueBounds
        let middleValue = (bounds.min + bounds.max) / 2

        return VStack(alignment: .trailing, spacing: 0) {
            Text(numberText(bounds.max))
            Spacer()
            Text(numberText(middleValue))
            Spacer()
            Text(numberText(bounds.min))
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func hoverOverlay(for index: Int, in size: CGSize) -> some View {
        let point = points[index]
        let pointPosition = pointPosition(for: index, in: size)
        let xLabelX = min(max(pointPosition.x, 24), max(size.width - 24, 24))
        let yLabelY = min(max(pointPosition.y, 9), max(size.height - 9, 9))

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: pointPosition.x, y: 0))
                path.addLine(to: CGPoint(x: pointPosition.x, y: size.height))
                path.move(to: CGPoint(x: 0, y: pointPosition.y))
                path.addLine(to: CGPoint(x: size.width, y: pointPosition.y))
            }
            .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 0.9, dash: [4, 3]))

            Circle()
                .fill(lineColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.9 : 0.96), lineWidth: 1.4)
                )
                .position(pointPosition)

            hoverAxisLabel(numberText(point.value), width: 54)
                .position(x: -31, y: yLabelY)

            hoverAxisLabel(dateText(point.timestamp), width: 42)
                .position(x: xLabelX, y: size.height - 10)
        }
        .allowsHitTesting(false)
    }

    private func hoverAxisLabel(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(lineColor)
            .frame(width: width, height: 18)
            .background(hoverAxisLabelBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(lineColor.opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 0.65)
            )
    }

    private var hoverAxisLabelBackground: Color {
        colorScheme == .dark
            ? PanelDesign.cardBackground.opacity(0.92)
            : Color.white.opacity(0.94)
    }

    private func costReferenceOverlay(_ cost: Double, in size: CGSize) -> some View {
        let y = yPosition(for: cost, height: size.height)
        let pointX = min(CGFloat(4), size.width)

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(
                costReferenceColor.opacity(colorScheme == .dark ? 0.38 : 0.26),
                style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
            )

            Circle()
                .fill(costReferenceColor)
                .frame(width: 5, height: 5)
                .overlay(
                    Circle()
                        .stroke(PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.88 : 0.96), lineWidth: 1)
                )
                .position(x: pointX, y: y)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var costReferenceColor: Color {
        fundTrendCostReferenceColor
    }

    private func nearestIndex(for x: CGFloat, width: CGFloat) -> Int? {
        guard points.count > 1, width > 0 else { return nil }
        let ratio = min(max(x / width, 0), 1)
        return min(max(Int((ratio * CGFloat(points.count - 1)).rounded()), 0), points.count - 1)
    }

    private func pointPosition(for index: Int, in size: CGSize) -> CGPoint {
        guard points.indices.contains(index),
              points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return .zero
        }
        let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
        let y = yPosition(for: points[index].value, height: size.height)
        return CGPoint(x: x, y: y)
    }

    private func yPosition(for value: Double, height: CGFloat) -> CGFloat {
        CGFloat(trendScale.normalizedY(for: value)) * height
    }

    private func linePath(in size: CGSize) -> Path {
        guard points.count > 1,
              size.width > 0,
              size.height > 0
        else {
            return Path()
        }

        var path = Path()
        for (index, point) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(points.count - 1) * size.width
            let y = yPosition(for: point.value, height: size.height)
            let cgPoint = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }
        return path
    }

    private func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }

    private func dateText(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

let panelBorderColor = Color(nsColor: .separatorColor).opacity(0.12)

