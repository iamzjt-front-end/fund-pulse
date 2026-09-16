import AppKit
import SwiftUI

struct FundRowView: View {
    let fund: FundPosition
    let accountKind: PortfolioAccountKind
    let sortMode: FundSortMode
    let isSelected: Bool
    let isClosedZeroPosition: Bool
    let masksAmounts: Bool
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            summaryRow
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(fund.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    tag(statusTagTitle, color: statusTagColor)
                    if !isClosedZeroPosition && fund.status == .holding {
                        tag(rowHoldingRateText, color: toneColor(for: rowHoldingRate ?? rowConfirmedHoldingIncome))
                    }
                }

                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        if showsUpdateStar {
                            updatedInlineTag
                        }
                        Text(FundCodeFormatter.display(fund.code))
                            .fontWeight(.semibold)
                            .foregroundStyle(codeTextColor)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if showsUpdateStar {
                            updateStar
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                    Text(rowHoldingAmountText)
                        .foregroundStyle(amountTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.leading, showsUpdateStar ? 5 : 2)
                    Text(rowConfirmedHoldingIncomeText)
                        .foregroundStyle(toneColor(for: rowConfirmedHoldingIncome))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(primaryMetricText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: primaryMetricMinimumWidth, maxWidth: 86, minHeight: 24)
                .background(rateBadgeBackground(primaryMetricTone), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(rateBadgeBorderColor(primaryMetricTone), lineWidth: 1.1)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.28), lineWidth: 0.8)
                        .blendMode(.plusLighter)
                }
                .shadow(color: toneColor(for: primaryMetricTone).opacity(primaryMetricTone == 0 ? 0 : 0.24), radius: 7, x: 0, y: 3)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(selectionBackground)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(selectionAccent)
                .frame(width: 3, height: 34)
                .opacity(isSelected ? 1 : 0)
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
    }

    private var selectionAccent: Color {
        toneColor(for: primaryMetricTone)
    }

    private var selectionBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? selectionAccent.opacity(colorScheme == .dark ? 0.16 : 0.10)
                    : Color.clear
            )
    }

    private var updateStarColor: Color {
        Color(nsColor: StatusBarTone.menuBarColor(forRate: fund.todayRate))
    }

    private var updatedTagColor: Color {
        Color(red: 239 / 255, green: 168 / 255, blue: 36 / 255)
    }

    private var codeTextColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.72 : 0.58)
    }

    private var amountTextColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.92 : 0.78)
    }

    private var updateStar: some View {
        UpdatedFundStarShape()
            .fill(updateStarColor)
            .frame(width: 10.4, height: 10.4)
            .frame(width: 11, height: 14, alignment: .center)
            .shadow(color: updateStarColor.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 2, x: 0, y: 1)
            .accessibilityLabel("净值已更新")
    }

    private var updatedInlineTag: some View {
        Text("已更新")
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(updatedTagColor)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(updatedTagColor.opacity(colorScheme == .dark ? 0.20 : 0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(updatedTagColor.opacity(colorScheme == .dark ? 0.38 : 0.26), lineWidth: 0.6)
            )
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("已更新")
    }

    private var showsUpdateStar: Bool {
        FundUpdatePresentationPolicy.showsOfficialUpdateMarker(for: fund, accountKind: accountKind)
    }

    private var statusTagTitle: String {
        isClosedZeroPosition ? "已清仓" : fund.status.title
    }

    private var statusTagColor: Color {
        if isClosedZeroPosition {
            return .secondary
        }
        return fund.status.isPendingDisplay ? .orange : .blue
    }

    private var rowHoldingIncome: Double {
        if let holdingIncome = fund.holdingIncome {
            return holdingIncome
        }
        guard let holdingRate = fund.holdingRate else {
            return 0
        }
        return principal * holdingRate / 100
    }

    private var rowConfirmedHoldingIncome: Double {
        if let confirmedHoldingIncome = fund.confirmedHoldingIncome {
            return confirmedHoldingIncome
        }
        guard let confirmedHoldingRate = fund.confirmedHoldingRate else {
            return rowHoldingIncome
        }
        return principal * confirmedHoldingRate / 100
    }

    private var rowHoldingRate: Double? {
        fund.confirmedHoldingRate ?? fund.holdingRate
    }

    private var rowHoldingRateText: String {
        rowHoldingRate.map { MoneyFormatter.percent($0, signed: true) } ?? "0.00%"
    }

    private var primaryMetricText: String {
        switch sortMode {
        case .todayIncome:
            return FundRowAmountPrivacyFormatter.signedCompactMoney(fund.todayIncome, isMasked: masksAmounts)
        case .holdingIncome:
            return FundRowAmountPrivacyFormatter.signedCompactHoldingIncome(
                rowHoldingIncome,
                accountKind: accountKind,
                isMasked: masksAmounts
            )
        case .holdingRate:
            return MoneyFormatter.percent(rowHoldingRate ?? 0, signed: true)
        case .costAmount:
            return compactUnsignedMoney(principal)
        case .todayTotal:
            return compactUnsignedMoney(rowHoldingAmount)
        case .todayRate, .name:
            return MoneyFormatter.percent(fund.todayRate, signed: true)
        }
    }

    private var primaryMetricTone: Double {
        switch sortMode {
        case .todayIncome:
            return fund.todayIncome
        case .holdingIncome:
            return rowHoldingIncome
        case .holdingRate:
            return rowHoldingRate ?? 0
        case .costAmount, .todayTotal:
            return 0
        case .todayRate, .name:
            return fund.todayRate
        }
    }

    private var primaryMetricMinimumWidth: CGFloat {
        switch sortMode {
        case .todayIncome, .holdingIncome, .costAmount, .todayTotal:
            return 70
        case .todayRate, .holdingRate, .name:
            return 60
        }
    }

    private func compactUnsignedMoney(_ value: Double) -> String {
        FundRowAmountPrivacyFormatter.plainMoney(value, isMasked: masksAmounts)
            .replacingOccurrences(of: "¥ ", with: "")
    }

    private var rowHoldingAmountText: String {
        FundRowAmountPrivacyFormatter.plainMoney(rowHoldingAmount, isMasked: masksAmounts)
    }

    private var rowConfirmedHoldingIncomeText: String {
        FundRowAmountPrivacyFormatter.signedCompactHoldingIncome(
            rowConfirmedHoldingIncome,
            accountKind: accountKind,
            isMasked: masksAmounts
        )
    }

    private var rowHoldingAmount: Double {
        if let currentAmount = fund.currentAmount {
            return currentAmount
        }
        return principal + rowHoldingIncome
    }

    private var principal: Double {
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

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.6)
            )
    }

    private func rateBadgeBackground(_ value: Double) -> AnyShapeStyle {
        if value == 0 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.secondary.opacity(colorScheme == .dark ? 0.48 : 0.54),
                        Color.secondary.opacity(colorScheme == .dark ? 0.34 : 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        let color = toneColor(for: value)
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    color.opacity(colorScheme == .dark ? 0.98 : 0.93),
                    color.opacity(colorScheme == .dark ? 0.76 : 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func rateBadgeBorderColor(_ value: Double) -> Color {
        if value == 0 {
            return Color.primary.opacity(colorScheme == .dark ? 0.30 : 0.22)
        }

        return toneColor(for: value).opacity(colorScheme == .dark ? 0.76 : 0.60)
    }
}

struct UpdatedFundStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.56
        let points = (0..<10).map { index in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        var path = Path()

        for index in points.indices {
            let current = points[index]
            let previous = points[(index + points.count - 1) % points.count]
            let next = points[(index + 1) % points.count]
            let cornerLength = index.isMultiple(of: 2) ? outerRadius * 0.18 : outerRadius * 0.12
            let start = point(from: current, toward: previous, distance: cornerLength)
            let end = point(from: current, toward: next, distance: cornerLength)

            if index == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }
            path.addQuadCurve(to: end, control: current)
        }

        path.closeSubpath()
        return path
    }

    private func point(from start: CGPoint, toward end: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let scale = min(distance / length, 0.45)
        return CGPoint(x: start.x + dx * scale, y: start.y + dy * scale)
    }
}

