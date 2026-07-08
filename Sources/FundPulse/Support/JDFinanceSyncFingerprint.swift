import Foundation

enum JDFinanceSyncFingerprint {
    static func tradeDraft(_ draft: FundTradeDraft) -> String {
        [
            "trade",
            draft.action.rawValue,
            normalizedCode(draft.code),
            draft.tradeDate,
            draft.tradeTimeType.rawValue,
            moneyPart(draft.amount),
            sharesPart(draft.shares)
        ].joined(separator: "|")
    }

    static func conversionDraft(_ draft: FundConversionDraft) -> String {
        [
            "conversion",
            normalizedCode(draft.fromCode),
            normalizedCode(draft.toCode),
            draft.tradeDate,
            draft.tradeTimeType.rawValue,
            sharesPart(draft.shares)
        ].joined(separator: "|")
    }

    static func tradeOrderRecord(_ record: JDFinanceTradeOrderRecord, fallbackCode: String? = nil) -> String {
        [
            "order",
            record.action?.rawValue ?? "unknown",
            normalizedCode(record.code ?? fallbackCode ?? ""),
            normalizedCode(record.conversionTargetCode ?? ""),
            record.tradeDate ?? "",
            record.tradeTimeType?.rawValue ?? "",
            moneyPart(record.amount),
            sharesPart(record.shares)
        ].joined(separator: "|")
    }

    private static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func moneyPart(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", (value * 100).rounded() / 100)
    }

    private static func sharesPart(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", (value * 1_000_000).rounded() / 1_000_000)
    }
}
