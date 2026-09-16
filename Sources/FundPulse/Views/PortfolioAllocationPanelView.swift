import AppKit
import SwiftUI

private struct PortfolioAllocationItem: Identifiable {
    let rank: Int
    let fund: FundPosition
    let amount: Double
    let share: Double
    let color: Color

    var id: String { fund.code }
}

private struct PortfolioTreemapSlice: Identifiable {
    let item: PortfolioAllocationItem
    let rect: CGRect

    var id: String { item.id }
}

private struct PortfolioTreemapHoverState {
    let itemID: String
    let location: CGPoint
}

private enum PortfolioTreemapLayout {
    static func slices(for items: [PortfolioAllocationItem], in rect: CGRect) -> [PortfolioTreemapSlice] {
        split(items.filter { $0.amount > 0 }, in: rect)
    }

    private static func split(_ items: [PortfolioAllocationItem], in rect: CGRect) -> [PortfolioTreemapSlice] {
        guard !items.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        guard items.count > 1 else {
            return [PortfolioTreemapSlice(item: items[0], rect: inset(rect))]
        }

        let total = items.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let splitIndex = balancedSplitIndex(for: items, total: total)
        let leadingItems = Array(items.prefix(splitIndex))
        let trailingItems = Array(items.dropFirst(splitIndex))
        let leadingTotal = leadingItems.reduce(0) { $0 + $1.amount }
        let leadingRatio = min(max(leadingTotal / total, 0.05), 0.95)

        let leadingRect: CGRect
        let trailingRect: CGRect
        if rect.width >= rect.height {
            let leadingWidth = rect.width * leadingRatio
            leadingRect = CGRect(x: rect.minX, y: rect.minY, width: leadingWidth, height: rect.height)
            trailingRect = CGRect(x: rect.minX + leadingWidth, y: rect.minY, width: rect.width - leadingWidth, height: rect.height)
        } else {
            let leadingHeight = rect.height * leadingRatio
            leadingRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: leadingHeight)
            trailingRect = CGRect(x: rect.minX, y: rect.minY + leadingHeight, width: rect.width, height: rect.height - leadingHeight)
        }

        return split(leadingItems, in: leadingRect) + split(trailingItems, in: trailingRect)
    }

    private static func balancedSplitIndex(for items: [PortfolioAllocationItem], total: Double) -> Int {
        guard items.count > 2 else { return 1 }

        var runningTotal = 0.0
        var bestIndex = 1
        var bestDelta = Double.greatestFiniteMagnitude

        for index in 1..<items.count {
            runningTotal += items[index - 1].amount
            let delta = abs(total / 2 - runningTotal)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            }
        }

        return min(max(bestIndex, 1), items.count - 1)
    }

    private static func inset(_ rect: CGRect) -> CGRect {
        let insetX = min(rect.width / 8, 1.5)
        let insetY = min(rect.height / 8, 1.5)
        return rect.insetBy(dx: insetX, dy: insetY)
    }
}

private struct PortfolioTreemapChart: View {
    let items: [PortfolioAllocationItem]
    let accountKind: PortfolioAccountKind

    private enum LabelDensity {
        case full
        case stacked
        case compact

        var padding: CGFloat {
            switch self {
            case .full:
                6
            case .stacked:
                5
            case .compact:
                4
            }
        }

        var titleFontSize: CGFloat {
            switch self {
            case .full:
                10
            case .stacked:
                9.5
            case .compact:
                8.5
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverState: PortfolioTreemapHoverState?

    var body: some View {
        GeometryReader { proxy in
            let slices = PortfolioTreemapLayout.slices(
                for: items,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack(alignment: .topLeading) {
                ForEach(slices) { slice in
                    treemapBlock(slice, isHovered: hoverState?.itemID == slice.id)
                        .frame(width: max(slice.rect.width, 0), height: max(slice.rect.height, 0))
                        .position(x: slice.rect.midX, y: slice.rect.midY)
                }

                if let hoverState,
                   let slice = slices.first(where: { $0.id == hoverState.itemID }) {
                    PortfolioTreemapHoverWindowBridge(
                        item: slice.item,
                        location: hoverState.location,
                        chartSize: proxy.size,
                        colorScheme: colorScheme,
                        accountKind: accountKind
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                } else {
                    PortfolioTreemapHoverWindowBridge(
                        item: nil,
                        location: nil,
                        chartSize: proxy.size,
                        colorScheme: colorScheme,
                        accountKind: accountKind
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    updateHoverState(for: slices.first { $0.rect.contains(location) }, location: location)
                case .ended:
                    updateHoverState(for: nil, location: nil)
                }
            }
        }
        .accessibilityLabel("持仓占比方块图")
    }

    private func updateHoverState(for slice: PortfolioTreemapSlice?, location: CGPoint?) {
        guard let slice, let location else {
            if hoverState != nil {
                hoverState = nil
            }
            return
        }

        let movementThreshold: CGFloat = 10
        if let hoverState,
           hoverState.itemID == slice.id,
           hypot(hoverState.location.x - location.x, hoverState.location.y - location.y) < movementThreshold {
            return
        }
        hoverState = PortfolioTreemapHoverState(itemID: slice.id, location: location)
    }

    private func treemapBlock(_ slice: PortfolioTreemapSlice, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(blockFill(for: slice.item))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isHovered ? Color.white.opacity(0.86) : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.36),
                        lineWidth: isHovered ? 1.5 : 0.65
                    )
            )
            .overlay(alignment: .topLeading) {
                treemapLabel(for: slice)
                    .frame(width: max(slice.rect.width, 0), height: max(slice.rect.height, 0), alignment: .topLeading)
                    .clipped()
            }
            .shadow(
                color: isHovered ? slice.item.color.opacity(colorScheme == .dark ? 0.36 : 0.24) : .clear,
                radius: isHovered ? 9 : 0,
                x: 0,
                y: isHovered ? 3 : 0
            )
    }

    @ViewBuilder
    private func treemapLabel(for slice: PortfolioTreemapSlice) -> some View {
        if let density = labelDensity(for: slice.rect) {
            VStack(alignment: .leading, spacing: 1) {
                Text(treemapTitle(for: slice.item, density: density, width: slice.rect.width))
                    .font(.system(size: density.titleFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .truncationMode(.tail)

                Text(treemapPercentText(for: slice.item, density: density))
                    .font(.system(size: percentFontSize(for: density), weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.32), radius: 2, x: 0, y: 1)
            .padding(density.padding)
        }
    }

    private func labelDensity(for rect: CGRect) -> LabelDensity? {
        guard rect.width >= 16, rect.height >= 28 else {
            return nil
        }
        if rect.width >= 76, rect.height >= 42 {
            return .full
        }
        if rect.width >= 54, rect.height >= 34 {
            return .stacked
        }
        return .compact
    }

    private func treemapTitle(for item: PortfolioAllocationItem, density: LabelDensity, width: CGFloat) -> String {
        let name = item.fund.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = name.isEmpty ? FundCodeFormatter.display(item.fund.code) : name
        guard density != .full else {
            return source
        }

        let availableWidth = max(width - density.padding * 2, 8)
        let estimatedCharacterWidth: CGFloat = density == .compact ? 8 : 9
        let maxCharacters = max(Int(availableWidth / estimatedCharacterWidth), 1)
        return String(source.prefix(maxCharacters))
    }

    private func treemapPercentText(for item: PortfolioAllocationItem, density: LabelDensity) -> String {
        let value = item.share * 100
        if density == .compact {
            return value.formatted(.number.precision(.fractionLength(0))) + "%"
        }
        return MoneyFormatter.percent(value)
    }

    private func percentFontSize(for density: LabelDensity) -> CGFloat {
        switch density {
        case .full:
            10
        case .stacked:
            9
        case .compact:
            7.5
        }
    }

    private func blockFill(for item: PortfolioAllocationItem) -> LinearGradient {
        LinearGradient(
            colors: [
                item.color.opacity(colorScheme == .dark ? 0.96 : 0.90),
                item.color.opacity(colorScheme == .dark ? 0.70 : 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

}

private struct PortfolioTreemapHoverWindowBridge: NSViewRepresentable {
    let item: PortfolioAllocationItem?
    let location: CGPoint?
    let chartSize: CGSize
    let colorScheme: ColorScheme
    let accountKind: PortfolioAccountKind

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(
            item: item,
            location: location,
            chartSize: chartSize,
            colorScheme: colorScheme,
            accountKind: accountKind,
            anchorView: view
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var panel: NSPanel?
        private var hostingView: NSHostingView<AnyView>?
        private var lastItemID: String?
        private var lastLocation: CGPoint?

        private let contentSize = CGSize(width: 238, height: 156)
        private let shadowMargin: CGFloat = 22
        private let gap: CGFloat = 14

        @MainActor
        func update(
            item: PortfolioAllocationItem?,
            location: CGPoint?,
            chartSize: CGSize,
            colorScheme: ColorScheme,
            accountKind: PortfolioAccountKind,
            anchorView: NSView
        ) {
            guard let item, let location, chartSize.width > 0, chartSize.height > 0 else {
                close()
                return
            }

            let movementThreshold: CGFloat = 6
            if lastItemID == item.id,
               let lastLocation,
               hypot(lastLocation.x - location.x, lastLocation.y - location.y) < movementThreshold {
                return
            }

            lastItemID = item.id
            lastLocation = location

            let panel = ensurePanel()
            let content = PortfolioTreemapTooltipWindowContent(
                item: item,
                colorScheme: colorScheme,
                accountKind: accountKind
            )
            .padding(shadowMargin)
            .frame(
                width: contentSize.width + shadowMargin * 2,
                height: contentSize.height + shadowMargin * 2
            )

            if let hostingView {
                hostingView.rootView = PanelFocusAppearance.suppressedRoot(content)
            } else {
                let hostingView = PanelFocusAppearance.hostingView(content)
                hostingView.frame = NSRect(
                    origin: .zero,
                    size: NSSize(
                        width: contentSize.width + shadowMargin * 2,
                        height: contentSize.height + shadowMargin * 2
                    )
                )
                hostingView.autoresizingMask = [.width, .height]
                panel.contentView = hostingView
                self.hostingView = hostingView
            }

            guard let frame = frame(for: location, chartSize: chartSize, anchorView: anchorView) else {
                close()
                return
            }
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }

        @MainActor
        func close() {
            panel?.orderOut(nil)
            lastItemID = nil
            lastLocation = nil
        }

        @MainActor
        private func ensurePanel() -> NSPanel {
            if let panel {
                return panel
            }

            let windowSize = NSSize(
                width: contentSize.width + shadowMargin * 2,
                height: contentSize.height + shadowMargin * 2
            )
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            self.panel = panel
            return panel
        }

        @MainActor
        private func frame(for location: CGPoint, chartSize: CGSize, anchorView: NSView) -> NSRect? {
            let panelSize = NSSize(
                width: contentSize.width + shadowMargin * 2,
                height: contentSize.height + shadowMargin * 2
            )
            guard let screenPoint = screenPoint(for: location, in: anchorView) else {
                return nil
            }
            let horizontalDirection: CGFloat = location.x > chartSize.width * 0.58 ? -1 : 1
            let verticalDirection: CGFloat = location.y > chartSize.height * 0.55 ? -1 : 1
            let center = CGPoint(
                x: screenPoint.x + horizontalDirection * (contentSize.width / 2 + gap),
                y: screenPoint.y - verticalDirection * (contentSize.height / 2 + gap)
            )
            var frame = NSRect(
                x: center.x - panelSize.width / 2,
                y: center.y - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            )

            if let visibleFrame = screen(for: frame)?.visibleFrame {
                let inset: CGFloat = 8
                frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + inset), visibleFrame.maxX - frame.width - inset)
                frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + inset), visibleFrame.maxY - frame.height - inset)
            }
            return frame
        }

        @MainActor
        private func screenPoint(for location: CGPoint, in anchorView: NSView) -> CGPoint? {
            guard let window = anchorView.window else {
                return nil
            }
            let localPoint = NSPoint(x: location.x, y: anchorView.bounds.height - location.y)
            let windowPoint = anchorView.convert(localPoint, to: nil)
            return window.convertPoint(toScreen: windowPoint)
        }

        @MainActor
        private func screen(for frame: NSRect) -> NSScreen? {
            NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        }
    }
}

private struct PortfolioTreemapTooltipWindowContent: View {
    let item: PortfolioAllocationItem
    let colorScheme: ColorScheme
    let accountKind: PortfolioAccountKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.color)
                    .frame(width: 7, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.fund.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(FundCodeFormatter.display(item.fund.code))
                        Text("第\(item.rank)大持仓")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 7
            ) {
                tooltipMetric("持仓占比", MoneyFormatter.percent(item.share * 100), color: item.color)
                tooltipMetric("持仓金额", MoneyFormatter.plainMoney(item.amount), color: .primary)
                tooltipMetric("今日涨幅", MoneyFormatter.percent(item.fund.todayRate, signed: true), color: toneColor(for: item.fund.todayRate))
                tooltipMetric("今日收益", MoneyFormatter.money(item.fund.todayIncome, signed: true), color: toneColor(for: item.fund.todayIncome))
                tooltipMetric(
                    "持仓收益",
                    MoneyFormatter.holdingIncome(
                        PortfolioPanelDisplay.holdingIncome(for: item.fund),
                        accountKind: accountKind
                    ),
                    color: toneColor(for: PortfolioPanelDisplay.holdingIncome(for: item.fund))
                )
                tooltipMetric(
                    "持仓收益率",
                    item.fund.holdingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "--",
                    color: item.fund.holdingRate.map(toneColor(for:)) ?? .secondary
                )
            }
        }
        .padding(11)
        .frame(width: 238, height: 156, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tooltipBaseColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tooltipAccentOverlay)
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.color.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.17), radius: 14, x: 0, y: 8)
    }

    private func tooltipMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var tooltipBaseColor: Color {
        colorScheme == .dark
            ? Color(red: 26 / 255, green: 29 / 255, blue: 35 / 255).opacity(0.99)
            : Color(nsColor: .windowBackgroundColor).opacity(0.99)
    }

    private var tooltipAccentOverlay: LinearGradient {
        LinearGradient(
            colors: [
                item.color.opacity(colorScheme == .dark ? 0.10 : 0.055),
                item.color.opacity(colorScheme == .dark ? 0.05 : 0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PortfolioAllocationPanelView: View {
    let store: PortfolioStore
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "square.grid.3x3.fill",
                title: "持仓占比",
                subtitle: allocationHeaderSubtitle,
                subtitleWeight: .semibold,
                tint: Color(nsColor: .systemBlue),
                onClose: onClose
            )

            ScrollView {
                if allocationItems.isEmpty {
                    ContentUnavailableView("暂无持仓占比", systemImage: "chart.pie")
                        .frame(height: 420)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        allocationSummary
                        allocationChartSection
                        allocationBreakdownList
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
    }

    private var allocationItems: [PortfolioAllocationItem] {
        let funds = PortfolioPanelDisplay.holdingFunds(in: store.snapshot)
            .sorted {
                let lhsAmount = PortfolioPanelDisplay.currentAmount(for: $0)
                let rhsAmount = PortfolioPanelDisplay.currentAmount(for: $1)
                if lhsAmount != rhsAmount {
                    return lhsAmount > rhsAmount
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        let total = funds.reduce(0) { $0 + PortfolioPanelDisplay.currentAmount(for: $1) }
        guard total > 0 else { return [] }

        return funds.enumerated().map { index, fund in
            let amount = PortfolioPanelDisplay.currentAmount(for: fund)
            return PortfolioAllocationItem(
                rank: index + 1,
                fund: fund,
                amount: amount,
                share: amount / total,
                color: PortfolioPanelDisplay.allocationPalette[index % PortfolioPanelDisplay.allocationPalette.count]
            )
        }
    }

    private var allocationTotal: Double {
        allocationItems.reduce(0) { $0 + $1.amount }
    }

    private var allocationHeaderSubtitle: String {
        guard !allocationItems.isEmpty else { return "暂无持仓基金" }
        return "\(allocationItems.count)只基金 · \(MoneyFormatter.plainMoney(allocationTotal))"
    }

    private var largestAllocationText: String {
        allocationItems.first.map { MoneyFormatter.percent($0.share * 100) } ?? "--"
    }

    private var allocationSummary: some View {
        HStack(spacing: 0) {
            allocationSummaryMetric("持仓金额", MoneyFormatter.plainMoney(allocationTotal), color: .primary)
            summaryDivider
            allocationSummaryMetric("基金数量", "\(allocationItems.count)只", color: .primary)
            summaryDivider
            allocationSummaryMetric("最大占比", largestAllocationText, color: allocationItems.first?.color ?? .secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var allocationChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelSectionTitle("持仓方块图")
            PortfolioTreemapChart(items: allocationItems, accountKind: store.accountKind)
                .frame(height: 190)
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var allocationBreakdownList: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelSectionTitle("占比明细")
            VStack(spacing: 7) {
                ForEach(allocationItems) { item in
                    allocationRow(item)
                }
            }
        }
        .padding(12)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func allocationSummaryMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.30 : 0.22))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 10)
    }

    private func allocationRow(_ item: PortfolioAllocationItem) -> some View {
        HStack(spacing: 10) {
            rankBadge(item.rank, color: item.color)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.fund.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(FundCodeFormatter.display(item.fund.code))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                allocationBar(item)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(MoneyFormatter.percent(item.share * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.color)
                Text(MoneyFormatter.plainMoney(item.amount))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(item.color.opacity(colorScheme == .dark ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func allocationBar(_ item: PortfolioAllocationItem) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055))
                Capsule()
                    .fill(item.color.opacity(colorScheme == .dark ? 0.86 : 0.74))
                    .frame(width: max(proxy.size.width * item.share, 3))
            }
        }
        .frame(height: 6)
    }

    private func rankBadge(_ rank: Int, color: Color) -> some View {
        Text("\(rank)")
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(colorScheme == .dark ? 0.16 : 0.10), in: Circle())
            .overlay(Circle().stroke(color.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 0.7))
    }

    private func panelSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
    }
}

