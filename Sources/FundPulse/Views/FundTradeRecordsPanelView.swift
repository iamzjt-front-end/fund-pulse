import AppKit
import SwiftUI

private enum TradeRecordFilter: String, CaseIterable, Identifiable {
    case all
    case buy
    case sell
    case conversion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
        case .conversion:
            "转换"
        }
    }

    func matches(_ record: FundTradeRecord) -> Bool {
        switch self {
        case .all:
            true
        case .buy:
            record.kind == .buy || record.kind == .newFund
        case .sell:
            record.kind == .sell
        case .conversion:
            record.kind == .conversionOut || record.kind == .conversionIn
        }
    }
}

struct FundTradeRecordsPanelView: View {
    let store: PortfolioStore
    let fundCode: String
    let onEdit: (FundTradeRecord) -> Void
    let onDelete: (FundTradeRecord) async -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: TradeRecordFilter = .all
    @State private var deletingRecord: FundTradeRecord?

    private var fund: FundPosition {
        store.snapshot.funds.first { $0.code == fundCode } ?? unavailableRoutedFund(code: fundCode)
    }

    private var tradeRecords: [FundTradeRecord] {
        store.snapshot.tradeRecords ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "clock.arrow.circlepath",
                title: "交易记录",
                subtitle: tradeRecordsHeaderSubtitle,
                subtitleWeight: .semibold,
                onClose: onClose
            )

            filterBar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredTradeRecords.isEmpty {
                        ContentUnavailableView(emptyTitle, systemImage: "tray")
                            .frame(height: 320)
                    } else {
                        ForEach(filteredTradeRecords) { record in
                            tradeRecordRow(record)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(PanelDesign.panelBackground)
        .alert("删除交易记录", isPresented: deleteConfirmationBinding, presenting: deletingRecord) { record in
            Button("取消", role: .cancel) {
                deletingRecord = nil
            }
            Button("删除记录", role: .destructive) {
                Task {
                    await onDelete(record)
                    deletingRecord = nil
                }
            }
        } message: { record in
            Text(deleteTradeRecordConfirmationMessage(for: record))
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(visibleTradeRecordFilters) { value in
                Button {
                    filter = value
                } label: {
                    Text(filterTitle(value))
                        .font(.system(size: 11, weight: filter == value ? .semibold : .medium))
                        .foregroundStyle(filter == value ? Color.blue : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(
                            filter == value ? Color.blue.opacity(0.11) : PanelDesign.selectorBackground.opacity(0.72),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(filter == value ? Color.blue.opacity(0.16) : Color.clear, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }

    private var recentTradeRecords: [FundTradeRecord] {
        let actualRecords = tradeRecords.filter { $0.code == fund.code }
        let records = actualRecords.contains { $0.kind == .newFund }
            ? actualRecords
            : actualRecords + (inferredInitialTradeRecord(for: fund).map { [$0] } ?? [])
        return records.sorted(by: tradeRecordTimeDescending)
    }

    private var filteredTradeRecords: [FundTradeRecord] {
        recentTradeRecords.filter(filter.matches)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingRecord != nil },
            set: { isPresented in
                if !isPresented {
                    deletingRecord = nil
                }
            }
        )
    }

    private var emptyTitle: String {
        filter == .all ? "暂无交易记录" : "暂无\(filterTitle(filter))记录"
    }

    private var visibleTradeRecordFilters: [TradeRecordFilter] {
        store.accountKind == .onExchange ? [.all, .buy, .sell] : Array(TradeRecordFilter.allCases)
    }

    private func filterTitle(_ filter: TradeRecordFilter) -> String {
        guard store.accountKind == .onExchange else { return filter.title }
        return switch filter {
        case .all:
            "全部"
        case .buy:
            "买入"
        case .sell:
            "卖出"
        case .conversion:
            "转换"
        }
    }

    private var tradeRecordsHeaderSubtitle: String {
        let code = FundCodeFormatter.display(fund.code)
        let name = fund.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? code : "\(code) · \(name)"
    }

    private func deleteTradeRecordConfirmationMessage(for record: FundTradeRecord) -> String {
        "确定删除 \(tradeDateTimeText(record)) 的\(recordKindTitle(record.kind))记录（\(tradeRecordAmountText(record))）吗？删除后会重新计算这只基金的持仓金额、持仓份额和成本，且无法撤销。"
    }

    private func tradeRecordRow(_ record: FundTradeRecord) -> some View {
        let kindColor = tradeKindColor(record.kind)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    recordKindBadge(record.kind)

                    Text(tradeDateTimeText(record))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                Text(tradeRecordAmountText(record))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(kindColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .frame(height: 22, alignment: .center)

            HStack(alignment: .center, spacing: 8) {
                Text(recordConfirmationText(record))
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 19, alignment: .center)

                Spacer(minLength: 4)

                recordStatusBadge(record)
            }
            .frame(height: 22, alignment: .center)

            HStack(alignment: .center, spacing: 8) {
                recordPriceShareLine(record, color: kindColor)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                recordActionStack(record)
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(height: 22, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 88)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(recordCardBackground(record.kind))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kindColor.opacity(colorScheme == .dark ? 0.24 : 0.16), lineWidth: 0.8)
        }
    }

    private func recordActionButton(
        systemName: String,
        title: String,
        color: Color = .secondary,
        backgroundOpacity: Double = 0.06,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(title)
    }

    private func canEdit(_ record: FundTradeRecord) -> Bool {
        !isInferredInitialTradeRecord(record)
    }

    private func recordActionStack(_ record: FundTradeRecord) -> some View {
        HStack(spacing: 5) {
            if canEdit(record) {
                recordActionButton(systemName: "pencil", title: "编辑") {
                    onEdit(record)
                }
            }
            if !isInferredInitialTradeRecord(record) {
                recordActionButton(systemName: "trash", title: "删除", color: .red, backgroundOpacity: 0.08) {
                    deletingRecord = record
                }
            }
        }
    }

    private func recordKindBadge(_ kind: FundTradeKind) -> some View {
        let color = tradeKindColor(kind)
        return Text(recordKindTitle(kind))
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 0.6)
            )
    }

    private func recordStatusBadge(_ record: FundTradeRecord) -> some View {
        let title = recordStatusTitle(record)
        let color = tradeStatusColor(record.status)
        return Text(title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(minWidth: 50)
            .frame(height: 19)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 0.6)
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
    }

    private func recordTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func recordKindTitle(_ kind: FundTradeKind) -> String {
        if store.accountKind == .onExchange {
            switch kind {
            case .newFund:
                return "基线"
            case .buy:
                return "买入"
            case .sell:
                return "卖出"
            case .conversionOut:
                return "转出"
            case .conversionIn:
                return "转入"
            }
        }
        return switch kind {
        case .newFund:
            "新增"
        case .buy:
            "加仓"
        case .sell:
            "减仓"
        case .conversionOut:
            "转出"
        case .conversionIn:
            "转入"
        }
    }

    private func tradeDateTimeText(_ record: FundTradeRecord) -> String {
        if store.accountKind == .onExchange {
            return record.tradeDate
        }
        if record.kind == .newFund, record.mode == .amount {
            return "首次录入"
        }
        return "\(record.tradeDate) \(record.tradeTimeType.title)"
    }

    private func recordConfirmationText(_ record: FundTradeRecord) -> String {
        if store.accountKind == .onExchange {
            return record.kind == .newFund ? "持仓基线 \(record.acceptedDate)" : "成交 \(record.acceptedDate)"
        }
        if record.status == .pending,
           isConversionRecord(record),
           record.amount != nil,
           let executionDate = TradingCalendar.nextFundTradingDate(after: record.acceptedDate) {
            return "执行 \(executionDate) 00:00后"
        }
        return "确认 \(record.acceptedDate)"
    }

    private func recordStatusTitle(_ record: FundTradeRecord) -> String {
        if store.accountKind == .onExchange, record.status == .confirmed {
            return record.kind == .newFund ? "已录入" : "已成交"
        }
        if record.status == .pending,
           isConversionRecord(record),
           record.amount != nil {
            return "待执行"
        }
        if record.status == .pending,
           isConversionRecord(record) {
            return "待净值"
        }
        return record.status.title
    }

    private func isConversionRecord(_ record: FundTradeRecord) -> Bool {
        record.kind == .conversionOut || record.kind == .conversionIn
    }

    @ViewBuilder
    private func recordPriceShareLine(_ record: FundTradeRecord, color: Color) -> some View {
        let priceText = record.price.map { numberText($0, places: 4) }
        let sharesText = (record.confirmedShares ?? record.shares).map { "\(numberText($0, places: 2))份" }

        if priceText == nil && sharesText == nil {
            Text(record.kind == .newFund && record.mode == .amount ? "手工录入" : (store.accountKind == .onExchange ? "暂无成交数据" : "待确认净值和份额"))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            HStack(spacing: 8) {
                if let priceText {
                    recordMetricText(
                        label: store.accountKind == .onExchange
                            ? (record.kind == .newFund ? "成本价" : "成交价")
                            : (record.kind == .newFund && record.mode == .amount ? "参考净值" : "净值"),
                        value: priceText,
                        color: color
                    )
                }

                if let sharesText {
                    recordMetricText(label: "份额", value: sharesText, color: color)
                }

                if store.accountKind == .onExchange,
                   let feeAmount = record.feeAmount,
                   feeAmount > 0 {
                    recordMetricText(
                        label: "费用",
                        value: MoneyFormatter.plainMoney(feeAmount),
                        color: color
                    )
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
        }
    }

    private func recordMetricText(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary.opacity(colorScheme == .dark ? 0.82 : 0.70))
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color.opacity(colorScheme == .dark ? 0.95 : 0.82))
        }
        .monospacedDigit()
    }

    private func tradeRecordAmountText(_ record: FundTradeRecord) -> String {
        if let amount = record.amount {
            return MoneyFormatter.plainMoney(amount)
        }
        if let shares = record.shares ?? record.confirmedShares {
            return "\(numberText(shares, places: 2))份"
        }
        return "--"
    }

    private func tradeKindColor(_ kind: FundTradeKind) -> Color {
        switch kind {
        case .newFund:
            Color(nsColor: .systemBlue)
        case .buy:
            Color(nsColor: .systemRed)
        case .sell, .conversionOut:
            .fundPulseGreen
        case .conversionIn:
            Color(nsColor: .systemRed)
        }
    }

    private func recordCardBackground(_ kind: FundTradeKind) -> LinearGradient {
        let color = tradeKindColor(kind)
        return LinearGradient(
            colors: [
                color.opacity(colorScheme == .dark ? 0.18 : 0.10),
                color.opacity(colorScheme == .dark ? 0.10 : 0.055),
                PanelDesign.cardBackground.opacity(colorScheme == .dark ? 0.82 : 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func tradeStatusColor(_ status: FundTradeRecordStatus) -> Color {
        switch status {
        case .pending:
            .orange
        case .confirmed:
            .blue
        case .failed:
            .red
        }
    }

    private func numberText(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }
}

