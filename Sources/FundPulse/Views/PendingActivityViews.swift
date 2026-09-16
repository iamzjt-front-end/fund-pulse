import AppKit
import SwiftUI

struct PendingActivityNotice: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(PendingActivityPresentation.noticeText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("关闭提示，出现新的待确认交易时重新显示")
            .offset(y: -3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(colorScheme == .dark ? 0.10 : 0.055))
    }
}

struct PendingTradeActivityRow: View {
    let activity: PendingTradeActivity
    let isSelected: Bool
    let onDelete: (() -> Void)?
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onOpen) {
                rowContent
            }
            .buttonStyle(.plain)
            .focusable(false)

            if let onDelete {
                deleteButton(action: onDelete)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: rowMinHeight)
        .background(selectionBackground)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accentColor)
                .frame(width: 3, height: selectionBarHeight)
                .opacity(isSelected ? 1 : 0)
                .padding(.leading, 4)
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            leftColumn
            Spacer(minLength: 6)
            amountColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            tagRow
            titleBlock
            metaContent
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            tag(kindTagTitle, color: kindTagColor)
            tag("待确认", color: .orange)
        }
    }

    private var amountColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(primaryValueText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            Text(valueCaption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 98, alignment: .trailing)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 24, height: 24)
                .background(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(activity.isConversion ? "删除这笔转换待确认记录" : "删除这笔待确认记录")
    }

    private var rowMinHeight: CGFloat {
        activity.isConversion ? 116 : 88
    }

    private var verticalPadding: CGFloat {
        6
    }

    private var selectionBarHeight: CGFloat {
        activity.isConversion ? 82 : 60
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let route = conversionRoute {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.sourceName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(kindTagColor)
                    .frame(height: 10)
                    .accessibilityHidden(true)
                Text(route.targetName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 14, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(titleText)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var metaContent: some View {
        if let route = conversionRoute {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversionMetaText(route))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                waitingStatusText
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.orderText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                waitingStatusText
            }
        }
    }

    private var waitingStatusText: some View {
        Text(presentation.waitingText)
            .foregroundStyle(.orange)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .allowsTightening(true)
    }

    private var accentColor: Color {
        switch activity.kind {
        case .sell, .conversionOut:
            .fundPulseGreen
        case .newFund, .buy, .conversionIn:
            .red
        }
    }

    private var kindTagColor: Color {
        if activity.isConversion {
            return Color.orange
        }
        if activity.kind == .newFund {
            return .blue
        }
        return accentColor
    }

    private var kindTagTitle: String {
        if activity.isConversion {
            return "转换"
        }
        if activity.kind == .newFund {
            return "新增"
        }
        return activity.kind.title
    }

    private var titleText: String {
        guard let route = conversionRoute else {
            return activity.name
        }
        return "\(route.sourceName)\n→ \(route.targetName)"
    }

    private var valueCaption: String {
        guard activity.isConversion else {
            return activity.mode.title
        }
        switch activity.displayAmount?.source {
        case .estimatedNetValue, .latestNetValue:
            return "估算金额"
        case .confirmedNetValue:
            return "确认金额"
        case .enteredAmount, nil:
            return "金额"
        }
    }

    private var conversionSharesText: String? {
        let shares = activity.shares ?? activity.displayAmount?.shares
        guard let shares, shares > 0 else { return nil }
        return "\(numberText(shares, places: 2))份"
    }

    private var presentation: PendingActivityPresentation {
        PendingActivityPresentation(activity: activity)
    }

    private func conversionMetaText(_ route: (sourceName: String, sourceCode: String, targetName: String, targetCode: String)) -> String {
        let routeText = "\(FundCodeFormatter.display(route.sourceCode)) → \(FundCodeFormatter.display(route.targetCode))"
        guard let conversionSharesText else {
            return routeText
        }
        return "\(routeText) · \(conversionSharesText)"
    }

    private var conversionRoute: (sourceName: String, sourceCode: String, targetName: String, targetCode: String)? {
        guard activity.isConversion else { return nil }
        let currentName = clean(activity.name) ?? FundCodeFormatter.display(activity.code)
        let currentCode = clean(activity.code) ?? activity.code
        let linkedCode = clean(activity.linkedCode) ?? "--"
        let linkedName = clean(activity.linkedName) ?? FundCodeFormatter.display(linkedCode)

        if activity.kind == .conversionIn {
            return (
                sourceName: linkedName,
                sourceCode: linkedCode,
                targetName: currentName,
                targetCode: currentCode
            )
        }
        return (
            sourceName: currentName,
            sourceCode: currentCode,
            targetName: linkedName,
            targetCode: linkedCode
        )
    }

    private var selectionBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
                    : Color.clear
            )
    }

    private var primaryValueText: String {
        guard let displayAmount = activity.displayAmount else {
            return "--"
        }
        return MoneyFormatter.plainMoney(displayAmount.value)
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .fixedSize()
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }
}

